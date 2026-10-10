#!/bin/bash
#
# NestKeep 原生 App 自动跟版脚本（NAS 上运行）
#
# 原理：每 10 分钟（crontab）查询 Docker Hub 上 hhxxc/nestkeep-release:latest
# 的 manifest digest，与本地基线对比；有变化就 docker pull 该镜像并解包出
# IPA 与更新清单（latest-<flavor>.json）到 data/nestkeep 发布目录。
#
# 为什么走 Docker Hub 而不是 GitHub Releases：NAS 家宽直连 github.com /
# release-assets 被墙（实测 ~11s 失败），镜像站也不稳；而 Docker Hub 拉取
# 链路已被 ezbk_autodeploy.sh 长期验证可用。CI（build-native-ios.yml 的
# publish-release-image job）每次发语义版本 Release 都会重推该镜像 → digest 变化。
#
# 特性：
#   - 零凭据：只读 Docker Hub 公开 API + docker pull 公开镜像
#   - 首次运行只记录基线，不解包
#   - 网络查询失败静默跳过，下轮重试；解包失败不更新基线，下轮自动重试
#   - 与手动发版脚本 nas_publish_nestkeep.py 不冲突：同目录、按文件覆盖
#
# 手动检查：bash /volume2/docker/ezbk/nestkeep_autosync.sh && tail nk_autosync.log
#
set -u

# 个人覆盖：同目录 nas.local.sh（已 gitignore）可定义 RELEASE_IMAGE / NK_DATA_DIR 等
LOCAL_OVERRIDE="$(cd "$(dirname "$0")" && pwd)/nas.local.sh"
[ -f "$LOCAL_OVERRIDE" ] && . "$LOCAL_OVERRIDE"

RELEASE_IMAGE="${RELEASE_IMAGE:-hhxxc/nestkeep-release}"
TAG_URL="${NK_TAG_URL:-https://hub.docker.com/v2/repositories/${RELEASE_IMAGE}/tags/latest}"
DATA_DIR="${NK_DATA_DIR:-/volume2/docker/ezbk/nestkeep}"
STATE_DIR="${NK_STATE_DIR:-/volume2/docker/ezbk}"
DIGEST_FILE="$STATE_DIR/.nk_autosync_last_digest"
LOG="$STATE_DIR/nk_autosync.log"
LOCK="$STATE_DIR/.nk_autosync.lock"

# docker 路径：群晖 cron 环境下 PATH 不含 /usr/local/bin，逐个探测
DOCKER_BIN="docker"
command -v docker >/dev/null 2>&1 || DOCKER_BIN="/usr/local/bin/docker"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $1" >> "$LOG"; }

if ! mkdir "$LOCK" 2>/dev/null; then
    # 锁目录残留（断电/被杀）超过 30 分钟视为陈旧，清掉重试
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
        log "WARN: 清理陈旧锁（>30 分钟，疑似上次异常退出残留）"
        rm -rf "$LOCK"
        if ! mkdir "$LOCK" 2>/dev/null; then
            log "ERROR: 陈旧锁清理后仍无法获取锁"
            exit 1
        fi
    else
        log "已有实例在运行，跳过"
        exit 0
    fi
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# 1. 查远端 digest（网络失败静默跳过，下轮再试）
REMOTE=$(curl -sf --max-time 20 "$TAG_URL" | grep -o '"digest":"sha256:[a-f0-9]*"' | head -1 | cut -d'"' -f4)
if [ -z "$REMOTE" ]; then
    log "WARN: 查询 Docker Hub 失败，跳过本次"
    exit 0
fi

LAST=""
[ -f "$DIGEST_FILE" ] && LAST=$(cat "$DIGEST_FILE")

# 无更新：静默退出
if [ "$REMOTE" = "$LAST" ]; then
    exit 0
fi

# 首次运行：只记基线，不解包
if [ -z "$LAST" ]; then
    echo "$REMOTE" > "$DIGEST_FILE"
    log "初始化 digest 基线：$REMOTE"
    exit 0
fi

# 2. 有新镜像：拉取并解包。
# 国内家宽直连 registry-1.docker.io 常超时（hub.docker.com 的 API 反而可达），
# 与 deploy.sh 相同策略：直连失败依次回退镜像站，成功后改回标准 tag。
PULL_MIRRORS="${NK_PULL_MIRRORS:-docker.m.daocloud.io dockerpull.org docker.1panel.live}"

do_pull() {
    if "$DOCKER_BIN" pull -q "$RELEASE_IMAGE:latest" >> "$LOG" 2>&1; then
        return 0
    fi
    log "WARN: 直连拉取失败，尝试镜像站"
    for mirror in $PULL_MIRRORS; do
        if "$DOCKER_BIN" pull -q "$mirror/$RELEASE_IMAGE:latest" >> "$LOG" 2>&1; then
            "$DOCKER_BIN" tag "$mirror/$RELEASE_IMAGE:latest" "$RELEASE_IMAGE:latest" >> "$LOG" 2>&1
            "$DOCKER_BIN" rmi "$mirror/$RELEASE_IMAGE:latest" >/dev/null 2>&1
            log "从镜像站 $mirror 拉取成功"
            return 0
        fi
    done
    return 1
}

log "发现新发版镜像 digest：$REMOTE（旧：$LAST），开始同步"
if ! do_pull; then
    log "ERROR: 所有源拉取失败，基线未更新，下轮重试"
    exit 1
fi

# scratch 镜像无 CMD，create 需显式 entrypoint（仅创建容器不执行，任何值都可）
CID=$("$DOCKER_BIN" create --entrypoint /bin/true "$RELEASE_IMAGE:latest" 2>> "$LOG")
if [ -z "$CID" ]; then
    log "ERROR: docker create 失败，基线未更新，下轮重试"
    exit 1
fi

mkdir -p "$DATA_DIR"
"$DOCKER_BIN" cp "$CID":/data/. "$DATA_DIR/" >> "$LOG" 2>&1
"$DOCKER_BIN" rm "$CID" >/dev/null 2>&1
# docker cp 以 root 执行后文件属主变 root，会挡住以后 hhxxc 手动发版脚本的覆盖写；
# 归还成发布目录原有的属主（失败不致命，忽略）
DATA_OWNER=$(stat -c '%U:%G' "$DATA_DIR" 2>/dev/null)
if [ -n "$DATA_OWNER" ]; then
    chown -R "$DATA_OWNER" "$DATA_DIR" 2>/dev/null
fi

# 3. 校验：至少一份清单 + 最新 IPA 是 zip 头（防镜像/解包异常污染发布目录）
if ! ls "$DATA_DIR"/latest-*.json >/dev/null 2>&1; then
    log "ERROR: 解包后找不到 latest-*.json，基线未更新，下轮重试"
    exit 1
fi

NEWEST_IPA=$(ls -t "$DATA_DIR"/*.ipa 2>/dev/null | head -1)
if [ -n "$NEWEST_IPA" ]; then
    if ! head -c 2 "$NEWEST_IPA" | grep -q "PK"; then
        log "ERROR: IPA 文件头校验失败（$NEWEST_IPA），基线未更新，下轮重试"
        exit 1
    fi
fi

# 4. 清理旧 IPA：按修改时间只保留最近 5 个（每个 ~2-5MB）
ls -t "$DATA_DIR"/*.ipa 2>/dev/null | tail -n +6 | xargs -r rm -f

echo "$REMOTE" > "$DIGEST_FILE"
VERSIONS=$(grep -h -o '"version": *"[^"]*"' "$DATA_DIR"/latest-*.json 2>/dev/null | tr '\n' ' ')
log "同步完成，已更新基线。当前清单版本：$VERSIONS"

# 日志只留最近 500 行
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
