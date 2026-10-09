#!/bin/bash
#
# 巢记（ezBookkeeping）数据库定时备份脚本（NAS 上运行）
#
# 用法：
#     /volume2/docker/ezbk/ezbk_backup.sh            # 手动执行
#     crontab 里每天自动调用（见仓库 AGENTS.md 或 /etc/crontab）
#
# 流程：
#   1. sqlite3 .backup 在线备份（一致性好副本，不需要停容器）
#   2. PRAGMA quick_check 完整性校验，不合格直接报错丢弃
#   3. gzip 压缩，latest.db.gz 软链指向最新一份
#   4. storage 目录（交易图片/头像）打 tar 快照，量小一起备
#   5. 清理 30 天前的旧备份（无论多旧至少保留最近 3 份）
#
# 恢复方法（停止/重建容器前把备份放回去）：
#     gunzip -c /volume2/docker/ezbk/backups/latest.db.gz > /volume2/docker/ezbk/ezbookkeeping.db
#     tar -xzf /volume2/docker/ezbk/backups/storage-<日期>.tar.gz -C /volume2/docker/ezbk
#     bash /volume2/docker/ezbk/deploy.sh --no-pull
#
set -u

DB="/volume2/docker/ezbk/ezbookkeeping.db"
BACKUP_DIR="/volume2/docker/ezbk/backups"
KEEP_DAYS=30
MIN_KEEP=3
LOG="$BACKUP_DIR/backup.log"
LOCK="$BACKUP_DIR/.lock"

ts() { date +"%Y-%m-%d %H:%M:%S"; }

mkdir -p "$BACKUP_DIR"

# 防重叠执行（上次没跑完又到点时直接跳过本次）
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "[$(ts)] 已有备份在运行，跳过本次"
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

log() { echo "[$(ts)] $1" | tee -a "$LOG"; }

if [ ! -f "$DB" ]; then
    log "ERROR: 数据库不存在 $DB"
    exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
RAW="$BACKUP_DIR/ezbk-$STAMP.db"

# 1. 在线备份
if ! sqlite3 "$DB" ".backup '$RAW'"; then
    log "ERROR: sqlite3 .backup 失败"
    rm -f "$RAW"
    exit 1
fi

# 2. 完整性校验
CHECK=$(sqlite3 "$RAW" "PRAGMA quick_check;" 2>&1)
if [ "$CHECK" != "ok" ]; then
    log "ERROR: 备份完整性校验失败：$CHECK"
    rm -f "$RAW"
    exit 1
fi

# 3. 压缩（校验通过后原始 .db 即删，只留 gz）
if ! gzip -f "$RAW"; then
    log "ERROR: gzip 失败"
    exit 1
fi
GZ="$RAW.gz"
SIZE=$(du -h "$GZ" | cut -f1)
log "OK: $GZ ($SIZE)"

# latest 软链，方便恢复
ln -sf "$(basename "$GZ")" "$BACKUP_DIR/latest.db.gz"

# 4. storage 目录快照（交易图片/头像等；量小，跟库一起备恢复才完整）
STORAGE_DIR="/volume2/docker/ezbk/storage"

if [ -d "$STORAGE_DIR" ]; then
    STORAGE_TAR="$BACKUP_DIR/storage-$STAMP.tar.gz"

    if tar -czf "$STORAGE_TAR" -C /volume2/docker/ezbk storage 2>/dev/null; then
        SSIZE=$(du -h "$STORAGE_TAR" | cut -f1)
        log "OK: $STORAGE_TAR ($SSIZE)"
    else
        log "WARN: storage 快照失败（不影响数据库备份）"
        rm -f "$STORAGE_TAR"
    fi
fi

# 5. 清理旧备份：30 天前且不占用最近 MIN_KEEP 个名额的才删
for pattern in "ezbk-*.db.gz" "storage-*.tar.gz"; do
    ls -1t "$BACKUP_DIR"/$pattern 2>/dev/null | tail -n +$((MIN_KEEP + 1)) | while IFS= read -r f; do
        if [ -n "$(find "$f" -mtime +"$KEEP_DAYS")" ]; then
            rm -f "$f"
            log "清理过期备份：$(basename "$f")"
        fi
    done
done

# 日志只留最近 300 行
tail -n 300 "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"

log "完成"
