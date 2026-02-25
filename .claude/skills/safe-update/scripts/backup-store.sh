#!/bin/bash
set -euo pipefail

# Back up runtime state: SQLite database and WhatsApp auth credentials.
# Uses sqlite3 .backup for a consistent DB copy when available.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$PROJECT_ROOT/.nanoclaw/safe-update-backup/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

DB_BACKED_UP="false"
AUTH_BACKED_UP="false"

# Back up SQLite database
DB_PATH="$PROJECT_ROOT/store/messages.db"
if [ -f "$DB_PATH" ]; then
  if command -v sqlite3 >/dev/null 2>&1; then
    # Use SQLite .backup for WAL-safe consistent copy
    sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/messages.db'"
  else
    # Service is stopped so direct copy is safe
    cp "$DB_PATH" "$BACKUP_DIR/messages.db"
  fi
  DB_BACKED_UP="true"
fi

# Back up WhatsApp auth
AUTH_DIR="$PROJECT_ROOT/store/auth"
if [ -d "$AUTH_DIR" ] && [ "$(ls -A "$AUTH_DIR" 2>/dev/null)" ]; then
  cp -r "$AUTH_DIR" "$BACKUP_DIR/auth"
  AUTH_BACKED_UP="true"
fi

# Update latest symlink
LATEST_LINK="$PROJECT_ROOT/.nanoclaw/safe-update-backup/latest"
rm -f "$LATEST_LINK"
ln -s "$BACKUP_DIR" "$LATEST_LINK"

# Calculate backup size
BACKUP_SIZE_KB=$(du -sk "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
BACKUP_SIZE_MB=$(echo "scale=1; $BACKUP_SIZE_KB / 1024" | bc 2>/dev/null || echo "0")

cat <<EOF
<<< STATUS
BACKUP_DIR=$BACKUP_DIR
DB_BACKED_UP=$DB_BACKED_UP
AUTH_BACKED_UP=$AUTH_BACKED_UP
BACKUP_SIZE_MB=$BACKUP_SIZE_MB
STATUS=success
STATUS >>>
EOF
