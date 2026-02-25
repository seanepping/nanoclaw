#!/bin/bash
set -euo pipefail

# Start the nanoclaw service. Mirrors platform detection from stop-service.sh.

PLATFORM="unknown"
SERVICE_MANAGER="${1:-auto}"

case "$(uname -s)" in
  Darwin*) PLATFORM="macos" ;;
  Linux*)  PLATFORM="linux" ;;
esac

# Auto-detect service manager if not specified
if [ "$SERVICE_MANAGER" = "auto" ]; then
  if [ "$PLATFORM" = "macos" ]; then
    SERVICE_MANAGER="launchd"
  elif [ "$PLATFORM" = "linux" ]; then
    if systemctl --user list-unit-files 2>/dev/null | grep -q "nanoclaw"; then
      SERVICE_MANAGER="systemd-user"
    elif systemctl list-unit-files 2>/dev/null | grep -q "nanoclaw"; then
      SERVICE_MANAGER="systemd-system"
    else
      SERVICE_MANAGER="nohup"
    fi
  fi
fi

SERVICE_STARTED="false"

case "$SERVICE_MANAGER" in
  launchd)
    launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist 2>/dev/null || true
    ;;
  systemd-user)
    systemctl --user start nanoclaw 2>/dev/null || true
    ;;
  systemd-system)
    sudo systemctl start nanoclaw 2>/dev/null || true
    ;;
  nohup)
    if [ -f start-nanoclaw.sh ]; then
      bash start-nanoclaw.sh
    else
      nohup node dist/index.js >> logs/nanoclaw.log 2>> logs/nanoclaw.error.log &
      echo $! > nanoclaw.pid
    fi
    ;;
esac

# Wait up to 15 seconds for process to start
for i in $(seq 1 15); do
  if pgrep -f 'dist/index\.js' >/dev/null 2>&1; then
    SERVICE_STARTED="true"
    break
  fi
  sleep 1
done

cat <<EOF
<<< STATUS
PLATFORM=$PLATFORM
SERVICE_MANAGER=$SERVICE_MANAGER
SERVICE_STARTED=$SERVICE_STARTED
STATUS=success
STATUS >>>
EOF
