#!/bin/bash
#
# 巢记（ezBookkeeping）自动部署脚本（NAS 上运行）
#
# 原理：每 10 分钟（crontab）查询 Docker Hub 上 latest-snapshot tag 的
# manifest digest，与本地记录的基线对比；有新镜像就自动执行 deploy.sh
# 拉取重建。GitHub Actions 每次成功构建都会重推该 tag → digest 变化。
#
# 特性：
#   - 零凭据：不涉及任何 SSH/GitHub 密码，只读 Docker Hub 公开 API
#   - 首次运行只记录基线，不触发部署
#   - 网络查询失败静默跳过，下轮重试；deploy 失败不更新基线，下轮自动重试
#   - 与手动部署（nas_deploy.py）互不冲突：同一个 deploy.sh，幂等
#
# 手动检查：bash /volume2/docker/ezbk/ezbk_autodeploy.sh && tail autodeploy.log
#
set -u

TAG_URL="https://hub.docker.com/v2/repositories/hhxxc/ezbookkeeping/tags/latest-snapshot"
STATE_DIR="/volume2/docker/ezbk"
DEPLOY="$STATE_DIR/deploy.sh"
DIGEST_FILE="$STATE_DIR/.autodeploy_last_digest"
LOG="$STATE_DIR/autodeploy.log"
LOCK="$STATE_DIR/.autodeploy.lock"

ts() { date +"%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $1" >> "$LOG"; }

if ! mkdir "$LOCK" 2>/dev/null; then
    log "已有实例在运行，跳过"
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

if [ ! -x "$DEPLOY" ]; then
    log "ERROR: 找不到 $DEPLOY"
    exit 1
fi

# 1. 查远端 digest（网络失败静默跳过，下轮再试）
REMOTE=$(curl -sf --max-time 20 "$TAG_URL" | grep -o '"digest":"sha256:[a-f0-9]*"' | head -1 | cut -d'"' -f4)
if [ -z "$REMOTE" ]; then
    log "WARN: 查询 Docker Hub 失败，跳过本次"
    exit 0
fi

LAST=""
[ -f "$DIGEST_FILE" ] && LAST=$(cat "$DIGEST_FILE")

# 无更新：静默退出（不打日志避免刷屏）
if [ "$REMOTE" = "$LAST" ]; then
    exit 0
fi

# 首次运行：只记基线，不部署
if [ -z "$LAST" ]; then
    echo "$REMOTE" > "$DIGEST_FILE"
    log "初始化 digest 基线：$REMOTE"
    exit 0
fi

# 2. 有新镜像：部署
log "发现新镜像 digest：$REMOTE（旧：$LAST），开始部署"
if bash "$DEPLOY" >> "$LOG" 2>&1; then
    echo "$REMOTE" > "$DIGEST_FILE"
    log "部署完成，已更新基线"
else
    log "ERROR: deploy.sh 失败（详见上方日志），基线未更新，下轮重试"
fi

# 日志只留最近 500 行
tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
