#!/bin/bash
set -euo pipefail

# Restore runtime state from a backup directory.
# Usage: restore-store.sh <backup-dir>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

BACKUP_DIR="${1:?Usage: restore-store.sh <backup-dir>}"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "<<< STATUS"
  echo "ERROR=backup_not_found"
  echo "STATUS=error"
  echo "STATUS >>>"
  exit 1
fi

DB_RESTORED="false"
AUTH_RESTORED="false"

# Restore SQLite database
if [ -f "$BACKUP_DIR/messages.db" ]; then
  cp "$BACKUP_DIR/messages.db" "$PROJECT_ROOT/store/messages.db"
  # Remove stale WAL/SHM files from the failed update
  rm -f "$PROJECT_ROOT/store/messages.db-shm" "$PROJECT_ROOT/store/messages.db-wal"
  DB_RESTORED="true"
fi

# Restore WhatsApp auth
if [ -d "$BACKUP_DIR/auth" ]; then
  rm -rf "$PROJECT_ROOT/store/auth"
  cp -r "$BACKUP_DIR/auth" "$PROJECT_ROOT/store/auth"
  AUTH_RESTORED="true"
fi

cat <<EOF
<<< STATUS
BACKUP_DIR=$BACKUP_DIR
DB_RESTORED=$DB_RESTORED
AUTH_RESTORED=$AUTH_RESTORED
STATUS=success
STATUS >>>
EOF
