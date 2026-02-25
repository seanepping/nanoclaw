#!/bin/bash
set -euo pipefail

# Post-update health check: process running, DB intact, auth present.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

PROCESS_RUNNING="false"
DB_INTEGRITY="unknown"
AUTH_PRESENT="false"
RECENT_ERRORS=""

# Check process
if pgrep -f 'dist/index\.js' >/dev/null 2>&1; then
  PROCESS_RUNNING="true"
fi

# Check DB integrity
DB_PATH="$PROJECT_ROOT/store/messages.db"
if [ -f "$DB_PATH" ] && command -v sqlite3 >/dev/null 2>&1; then
  RESULT=$(sqlite3 "$DB_PATH" "PRAGMA integrity_check;" 2>&1 || echo "error")
  if [ "$RESULT" = "ok" ]; then
    DB_INTEGRITY="ok"
  else
    DB_INTEGRITY="error: $RESULT"
  fi
elif [ -f "$DB_PATH" ]; then
  DB_INTEGRITY="exists_unchecked"
else
  DB_INTEGRITY="missing"
fi

# Check auth
if [ -f "$PROJECT_ROOT/store/auth/creds.json" ]; then
  AUTH_PRESENT="true"
fi

# Check recent errors
ERROR_LOG="$PROJECT_ROOT/logs/nanoclaw.error.log"
if [ -f "$ERROR_LOG" ]; then
  RECENT_ERRORS=$(tail -5 "$ERROR_LOG" 2>/dev/null | head -5 || echo "")
fi

# Overall status
STATUS="success"
if [ "$PROCESS_RUNNING" = "false" ] || [ "$DB_INTEGRITY" != "ok" ] && [ "$DB_INTEGRITY" != "exists_unchecked" ]; then
  STATUS="warning"
fi

cat <<EOF
<<< STATUS
PROCESS_RUNNING=$PROCESS_RUNNING
DB_INTEGRITY=$DB_INTEGRITY
AUTH_PRESENT=$AUTH_PRESENT
STATUS=$STATUS
STATUS >>>
EOF

if [ -n "$RECENT_ERRORS" ]; then
  echo "RECENT_ERRORS:"
  echo "$RECENT_ERRORS"
fi
