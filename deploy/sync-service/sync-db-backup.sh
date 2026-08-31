#!/usr/bin/env bash
# Nightly backup of shaddai-sync's SQLite database. This is the one
# service on this server holding data no other app has a copy of (unlike
# Komga/Kavita/Suwayomi, which can be re-derived or re-imported from the
# actual comic files), so losing it silently is a real loss, not just an
# inconvenience - mirrors the precedent that actually saved data during
# the 2026-08-25 mergerfs incident (Kavita's own 02:00 automated backup).

set -u

DB_PATH="/home/server/docker/sync-service/data/sync.db"
BACKUP_DIR="/home/server/docker/sync-service/backups"
KEEP_DAYS=14

mkdir -p "$BACKUP_DIR"

if [ ! -f "$DB_PATH" ]; then
  echo "$(date -Iseconds): $DB_PATH does not exist yet - nothing to back up"
  exit 0
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$BACKUP_DIR/sync-$STAMP.db"

# sqlite3's own online backup would be ideal, but this container is
# minimal (no sqlite3 CLI installed) - a plain file copy is safe here
# because the app runs in WAL mode and this timer runs at 02:00, a quiet
# hour, not because a raw copy is generally safe against concurrent
# writers.
cp "$DB_PATH" "$DEST"
echo "$(date -Iseconds): backed up to $DEST"

find "$BACKUP_DIR" -name 'sync-*.db' -mtime "+$KEEP_DAYS" -delete
