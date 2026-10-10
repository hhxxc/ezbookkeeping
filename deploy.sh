#!/bin/bash
#
# 巢记（ezBookkeeping）NAS 部署 / 更新脚本
#
# 用法（在 NAS 上执行）：
#     ./deploy.sh                 # 拉取最新镜像并重建容器
#     ./deploy.sh --no-pull       # 只用本地已有镜像重建容器（改配置时用）
#
# 设计说明：
#   - Web 前端（Vue 应用）由这个容器提供。iOS 上的「巢记」IPA 只是一个启动壳，
#     它每次启动都会从本容器加载前端，所以**前端有任何更新，只需要在本机重跑本脚本**，
#     IPA 不用重新打包、也不用重装。
#   - 本脚本是幂等的：重复执行只会重建同名容器，不会产生重复容器或丢数据
#     （数据在宿主机数据目录里，容器只是挂载它）。
#
# ⚠️ 部署你自己的实例前，请先完成两件事（默认值是作者的私人环境，勿直接照搬）：
#   1. LLM API Key（AI 识图/语音记账用）：到硅基流动 https://siliconflow.cn
#      等平台注册并申请，存成一个只读文件，然后用环境变量或 deploy.local.sh
#      指定 KEY_FILE=<你的 key 文件路径>
#   2. 个人覆盖配置：把本脚本同目录放一个 deploy.local.sh（已 gitignore），
#      内容是普通 shell 变量赋值，会覆盖下方所有默认值。例如：
#        DATA_DIR="/volume1/docker/ezbookkeeping"
#        KEY_FILE="/volume1/docker/my_llm_key.txt"
#        SHELL_BASE_URL="https://your-domain.example.com"
#      没有外网域名的话 SHELL_BASE_URL 留空即可（只显示局域网地址）。
#
set -u

# 同目录的个人覆盖配置（可选）：deploy.local.sh
LOCAL_OVERRIDE="$(cd "$(dirname "$0")" && pwd)/deploy.local.sh"
if [ -f "$LOCAL_OVERRIDE" ]; then
    # shellcheck disable=SC1090
    . "$LOCAL_OVERRIDE"
    echo "==> 已加载个人覆盖配置：$LOCAL_OVERRIDE"
fi

# 镜像：默认拉作者的快照镜像；自己 fork 的仓库请改成你自己的镜像名
# （或用仓库根的 Dockerfile 自行构建后本地导入）
IMAGE_NAME="${IMAGE_NAME:-hhxxc/ezbookkeeping:latest-snapshot}"
CONTAINER_NAME="${CONTAINER_NAME:-ezbookkeeping}"
HOST_PORT="${HOST_PORT:-9180}"
CONTAINER_PORT="${CONTAINER_PORT:-15080}"
DATA_DIR="${DATA_DIR:-/volume2/docker/ezbk}"
# LLM API Key 文件（纯文本，内容是 key 本身）。必须自行提供，见文件头说明
KEY_FILE="${KEY_FILE:-}"
RESTART_POLICY="${RESTART_POLICY:-no}"
# 外网入口（反代/隧道域名），留空则只输出局域网地址
SHELL_BASE_URL="${SHELL_BASE_URL:-}"

# 识图大模型：主模型 + 备用模型（按轮询顺序自动故障切换）
LLM_PROVIDER="${LLM_PROVIDER:-openai_compatible}"
LLM_BASE_URL="${LLM_BASE_URL:-https://api.siliconflow.cn/v1}"
LLM_MODEL_ID="${LLM_MODEL_ID:-Qwen/Qwen3-VL-8B-Instruct}"
LLM_FALLBACK_MODELS="${LLM_FALLBACK_MODELS:-model=Qwen/Qwen3-VL-30B-A3B-Instruct;model=Qwen/Qwen3-VL-32B-Instruct}"
LLM_REQUEST_TIMEOUT="${LLM_REQUEST_TIMEOUT:-60000}"
LLM_REQUEST_TIMEOUT_PER_MODEL="${LLM_REQUEST_TIMEOUT_PER_MODEL:-45000}"
LLM_ROTATE_MODELS="${LLM_ROTATE_MODELS:-true}"

# 尝试的镜像代理源（按顺序），国内网络下 docker hub 直连经常失败
MIRRORS=(
    "docker.m.daocloud.io"
    "dockerhub.icu"
    "dockerpull.org"
    "docker.1panel.live"
)

DO_PULL=1

for arg in "$@"; do
    case "$arg" in
        --no-pull) DO_PULL=0 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "unknown argument: $arg"
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------- docker 命令
# Synology DSM 上 docker 装在 /usr/local/bin，但非交互式 shell 的 PATH（尤其是 root 的）
# 不一定包含它，所以这里显式解析可执行文件路径
DOCKER_BIN=""

for candidate in "$(command -v docker 2>/dev/null)" /usr/local/bin/docker /var/packages/Docker/target/usr/bin/docker /usr/bin/docker; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        DOCKER_BIN="$candidate"
        break
    fi
done

if [ -z "$DOCKER_BIN" ]; then
    echo "ERROR: 找不到 docker 命令，请确认 NAS 上已安装 Docker 套件"
    exit 1
fi

if [ "$(id -u)" = "0" ]; then
    DOCKER="$DOCKER_BIN"
elif "$DOCKER_BIN" ps >/dev/null 2>&1; then
    DOCKER="$DOCKER_BIN"
else
    DOCKER="sudo $DOCKER_BIN"
    echo "当前用户不能直接访问 docker，将使用 sudo（可能需要输入密码）"
fi

echo "使用 docker: $DOCKER_BIN"

# ------------------------------------------------------------------ 前置检查
if [ -z "$KEY_FILE" ]; then
    echo "ERROR: 未配置 LLM API Key 文件（KEY_FILE）"
    echo "  AI 识图/语音记账需要一个大模型 API Key，请自行申请（如硅基流动 https://siliconflow.cn），"
    echo "  把 key 存成只读文本文件后设置：KEY_FILE=/path/to/your_key.txt ./deploy.sh"
    echo "  （推荐写入同目录 deploy.local.sh，避免每次输入；不需要 AI 功能可临时"
    echo "   创建一个空文件占位，之后在 NAS 的管理后台关闭 AI 功能）"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "ERROR: 找不到 API Key 文件 $KEY_FILE"
    exit 1
fi

if [ ! -d "$DATA_DIR" ]; then
    echo "ERROR: 找不到数据目录 $DATA_DIR"
    exit 1
fi

# -------------------------------------------------------------------- 拉镜像
if [ "$DO_PULL" = "1" ]; then
    echo "==> 拉取镜像 $IMAGE_NAME"

    if $DOCKER pull "$IMAGE_NAME"; then
        echo "    从官方源拉取成功"
    else
        echo "    官方源失败，尝试镜像代理..."

        PULLED=0

        for mirror in "${MIRRORS[@]}"; do
            echo "    尝试 $mirror"

            if $DOCKER pull "$mirror/$IMAGE_NAME"; then
                $DOCKER tag "$mirror/$IMAGE_NAME" "$IMAGE_NAME"
                $DOCKER rmi "$mirror/$IMAGE_NAME" >/dev/null 2>&1
                PULLED=1
                echo "    从 $mirror 拉取成功"
                break
            fi
        done

        if [ "$PULLED" != "1" ]; then
            echo "ERROR: 所有镜像源都拉取失败"
            exit 1
        fi
    fi
fi

if ! $DOCKER image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "ERROR: 本地没有镜像 $IMAGE_NAME"
    exit 1
fi

IMAGE_VERSION=$($DOCKER image inspect "$IMAGE_NAME" --format '{{ index .Config.Labels "org.opencontainers.image.version" }}' 2>/dev/null)
IMAGE_CREATED=$($DOCKER image inspect "$IMAGE_NAME" --format '{{.Created}}' 2>/dev/null)
echo "==> 使用镜像 $IMAGE_NAME (created: ${IMAGE_CREATED:-unknown} ${IMAGE_VERSION:-})"

# -------------------------------------------------------------- 重建容器
echo "==> 停止并删除旧容器 $CONTAINER_NAME"
# 用 rm -f 一次性强制停止并删除（stop + rm 分开时，若容器处于 restarting/停止超时等
# 异常态，plain rm 会因「容器仍在运行」而失败且被静默吞掉，导致下一步 run 报 name 冲突）
$DOCKER rm -f "$CONTAINER_NAME" >/dev/null 2>&1

# 确保 storage 目录存在且权限正确（容器以 user 1000 运行）
mkdir -p "${DATA_DIR}/storage"
chown -R 1000:1000 "${DATA_DIR}/storage" 2>/dev/null || true

echo "==> 启动新容器"

$DOCKER run -d \
    --name "$CONTAINER_NAME" \
    --user "1000:1000" \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    -e EBK_GLOBAL_MODE=production \
    -e EBK_SERVER_ENABLE_GZIP=true \
    -e EBK_SERVER_ROOT_URL="${SHELL_BASE_URL}/" \
    -e EBK_LLM_TRANSACTION_FROM_AI_IMAGE_RECOGNITION=true \
    -e EBK_LLM_IMAGE_RECOGNITION_LLM_PROVIDER="$LLM_PROVIDER" \
    -e EBK_LLM_IMAGE_RECOGNITION_OPENAI_COMPATIBLE_BASE_URL="$LLM_BASE_URL" \
    -e EBK_LLM_IMAGE_RECOGNITION_OPENAI_COMPATIBLE_MODEL_ID="$LLM_MODEL_ID" \
    -e EBK_LLM_IMAGE_RECOGNITION_FALLBACK_MODELS="$LLM_FALLBACK_MODELS" \
    -e EBK_LLM_IMAGE_RECOGNITION_REQUEST_TIMEOUT="$LLM_REQUEST_TIMEOUT" \
    -e EBK_LLM_IMAGE_RECOGNITION_REQUEST_TIMEOUT_PER_MODEL="$LLM_REQUEST_TIMEOUT_PER_MODEL" \
    -e EBK_LLM_IMAGE_RECOGNITION_ROTATE_MODELS="$LLM_ROTATE_MODELS" \
    -e EBKCFP_LLM_IMAGE_RECOGNITION_OPENAI_COMPATIBLE_API_KEY="$KEY_FILE" \
    -v "${DATA_DIR}:/ezbookkeeping/data" \
    -v "${DATA_DIR}/storage:/ezbookkeeping/storage" \
    -v "${KEY_FILE}:${KEY_FILE}:ro" \
    --restart="$RESTART_POLICY" \
    --log-driver=json-file \
    --log-opt max-size=10m \
    --log-opt max-file=3 \
    "$IMAGE_NAME" >/dev/null

if [ $? -ne 0 ]; then
    echo "ERROR: 容器启动失败"
    exit 1
fi

# ---------------------------------------------------------------- 健康检查
echo "==> 等待服务就绪"
HEALTH=""

for i in $(seq 1 30); do
    HEALTH=$(curl -s --max-time 3 "http://127.0.0.1:${HOST_PORT}/healthz.json" 2>/dev/null)

    if echo "$HEALTH" | grep -q '"status":"ok"'; then
        break
    fi

    sleep 1
done

echo
echo "容器状态："
$DOCKER ps -f "name=$CONTAINER_NAME" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

if echo "$HEALTH" | grep -q '"status":"ok"'; then
    LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") print $(i + 1)}' | head -1)

    if [ -z "$LAN_IP" ]; then
        LAN_IP=$(hostname -i 2>/dev/null | awk '{print $1}')
    fi

    echo
    echo "服务已就绪：$HEALTH"
    echo
    echo "访问地址（保持不变的入口）："

    if [ -n "$LAN_IP" ] && [ "$LAN_IP" != "::1" ]; then
        echo "  - 局域网   http://${LAN_IP}:${HOST_PORT}/"
    fi

    if [ -n "$SHELL_BASE_URL" ]; then
        echo "  - 外网     ${SHELL_BASE_URL}/"
    fi
else
    echo
    echo "WARNING: 服务在 30 秒内没有就绪，最近日志："
    $DOCKER logs --tail 40 "$CONTAINER_NAME" 2>&1
    exit 1
fi
