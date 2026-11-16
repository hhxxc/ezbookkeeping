#!/bin/bash
#
# 巢记（ezBookkeeping）自动部署脚本（NAS 上运行）
#
# 原理：每 10 分钟（crontab）从镜像站拉取 latest-snapshot 的 manifest，
# 读取镜像内置的 commit 标签（org.opencontainers.image.revision），
# 与本地记录的基线对比；不同就执行 deploy.sh 拉取重建。
#
# 为什么不用 Docker Hub 公开 API：NAS 在墙内，hub.docker.com 长期超时
# （历史日志里连续出现「查询 Docker Hub 失败」），导致自动部署静默失效。
# 镜像站（docker.1ms.run 等）可直连，且未更新时 pull 只走 manifest，几秒返回。
#
# 特性：
#   - 零凭据：只读公开镜像，不涉及任何密码
#   - 首次运行只记录基线，不触发部署
#   - 拉取失败静默跳过，下轮重试；deploy 失败不更新基线，下轮自动重试
#   - 与手动部署（nas_deploy.py）互不冲突：同一个 deploy.sh，幂等
#
# 手动检查：bash /volume2/docker/ezbk/ezbk_autodeploy.sh && tail autodeploy.log
#
set -u

# 个人覆盖：同目录放 nas.local.sh（已 gitignore）定义 IMAGE_REPO / DATA_DIR 等
LOCAL_OVERRIDE="$(cd "$(dirname "$0")" && pwd)/nas.local.sh"
[ -f "$LOCAL_OVERRIDE" ] && . "$LOCAL_OVERRIDE"

# 镜像仓库：自己 fork 的请改成你的 Docker Hub 仓库名
IMAGE_REPO="${IMAGE_REPO:-hhxxc/ezbookkeeping}"
# 拉取走的镜像站（官方 registry 在墙内直连超时）
MIRROR="${MIRROR:-docker.1ms.run}"
STATE_DIR="${STATE_DIR:-/volume2/docker/ezbk}"
DEPLOY="$STATE_DIR/deploy.sh"
LEVEL_FILE="$STATE_DIR/.autodeploy_last_revision"
LEGACY_DIGEST_FILE="$STATE_DIR/.autodeploy_last_digest"
LOG="$STATE_DIR/autodeploy.log"
LOCK="$STATE_DIR/.autodeploy.lock"
DOCKER_BIN="/usr/local/bin/docker"

# 告警：走 NAS 本机 Apprise API（渠道配置在容器 data 里，脚本零凭据）。
# 仅在「连续失败达阈值」与「恢复」时发送，通知本身失败静默（不影响主流程）。
APPRISE_URL="${AUTODEPLOY_APPRISE_URL:-http://localhost:8082/notify/8b}"
FAIL_FILE="$STATE_DIR/.autodeploy_failcount"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $1" >> "$LOG"; }

# $1=标题 $2=正文 $3=类型(warning|info)；payload 用临时文件避开引号/JSON 转义坑
notify() {
    [ -n "$APPRISE_URL" ] || return 0
    local tmp
    tmp=$(mktemp)
    printf '{"title":"%s","body":"%s","type":"%s","format":"text"}' "$1" "$2" "${3:-warning}" > "$tmp"
    curl -s -m 30 -X POST "$APPRISE_URL" -H "Content-Type: application/json" -d @"$tmp" >/dev/null 2>&1
    rm -f "$tmp"
}

# 连续失败计数：第 3 次与之后每满 30 次发一次告警（每 10 分钟重试）
mark_fail() { # $1=固定措辞的失败原因（不含引号/反斜杠，保证 JSON 安全）
    local count=0
    [ -f "$FAIL_FILE" ] && count=$(cat "$FAIL_FILE" 2>/dev/null)
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    count=$((count + 1))
    echo "$count" > "$FAIL_FILE"
    if [ "$count" -eq 3 ] || [ $((count % 30)) -eq 0 ]; then
        notify "巢记自动部署失败" "Web 服务端自动部署已连续失败 $count 次（每 10 分钟自动重试）。原因：$1" 
        log "WARN: 已发送告警（连续失败 $count 次）"
    fi
}

mark_ok() {
    if [ -f "$FAIL_FILE" ]; then
        local count
        count=$(cat "$FAIL_FILE" 2>/dev/null)
        rm -f "$FAIL_FILE"
        case "$count" in ''|*[!0-9]*) count=0 ;; esac
        if [ "$count" -ge 3 ]; then
            notify "巢记自动部署恢复" "此前连续失败 $count 次，现已恢复正常。" info
            log "已发送恢复通知（此前失败 $count 次）"
        fi
    fi
}

# cron 里以 root 运行，手动执行时是普通用户（hhxxc 有 sudo 免密）
dk() {
    if [ "$(id -u)" = "0" ]; then
        "$DOCKER_BIN" "$@"
    else
        sudo -n "$DOCKER_BIN" "$@"
    fi
}

if ! mkdir "$LOCK" 2>/dev/null; then
    # 锁目录可能因断电/进程被杀（trap 未执行）残留：超过 30 分钟视为陈旧，
    # 清掉重试一次；否则若不清理，自动部署会从此静默失效
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

if [ ! -x "$DEPLOY" ]; then
    log "ERROR: 找不到 $DEPLOY"
    exit 1
fi

# 1. 从镜像站拉取（未更新时代价极小），再读镜像内置 commit
PROBE_IMAGE="${MIRROR}/${IMAGE_REPO}:latest-snapshot"

if ! dk pull -q "$PROBE_IMAGE" > /dev/null 2>&1; then
    log "WARN: 从镜像站 $MIRROR 拉取失败，跳过本次"
    mark_fail "从镜像站拉取镜像失败"
    exit 0
fi

REMOTE=$(dk inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$PROBE_IMAGE" 2>/dev/null)

if [ -z "$REMOTE" ] || [ "$REMOTE" = "<no value>" ]; then
    log "WARN: 读取镜像 commit 标签失败，跳过本次"
    mark_fail "读取镜像 commit 标签失败"
    exit 0
fi

LAST=""
[ -f "$LEVEL_FILE" ] && LAST=$(cat "$LEVEL_FILE")

# 无更新：静默退出（不打日志避免刷屏）
if [ "$REMOTE" = "$LAST" ]; then
    mark_ok
    exit 0
fi

# 首次运行（或从旧的 digest 基线迁移）：只记基线，不部署
if [ -z "$LAST" ]; then
    echo "$REMOTE" > "$LEVEL_FILE"
    if [ -f "$LEGACY_DIGEST_FILE" ]; then
        log "迁移基线：digest 检测改为 commit 检测，当前镜像 commit：$REMOTE"
        rm -f "$LEGACY_DIGEST_FILE"
    else
        log "初始化 commit 基线：$REMOTE"
    fi
    mark_ok
    exit 0
fi

# 2. 有新镜像：部署
log "发现新镜像 commit：$REMOTE（旧：$LAST），开始部署"
if bash "$DEPLOY" >> "$LOG" 2>&1; then
    echo "$REMOTE" > "$LEVEL_FILE"
    log "部署完成，已更新基线"
    mark_ok
else
    log "ERROR: deploy.sh 失败（详见上方日志），基线未更新，下轮重试"
    mark_fail "deploy.sh 执行失败"
fi

# 日志只留最近 500 行
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
