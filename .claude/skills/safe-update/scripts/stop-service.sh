#!/bin/bash
set -euo pipefail

# Detect platform and stop the nanoclaw service.
# Idempotent — safe to run if already stopped.

PLATFORM="unknown"
SERVICE_MANAGER="none"
SERVICE_WAS_RUNNING="false"
SERVICE_STOPPED="true"

case "$(uname -s)" in
  Darwin*) PLATFORM="macos" ;;
  Linux*)  PLATFORM="linux" ;;
esac

# Detect service manager and check if running
if [ "$PLATFORM" = "macos" ]; then
  SERVICE_MANAGER="launchd"
  if launchctl list 2>/dev/null | grep -q "com.nanoclaw"; then
    PID_FIELD=$(launchctl list 2>/dev/null | grep "com.nanoclaw" | awk '{print $1}')
    if [ "$PID_FIELD" != "-" ] && [ -n "$PID_FIELD" ]; then
      SERVICE_WAS_RUNNING="true"
    fi
  fi
elif [ "$PLATFORM" = "linux" ]; then
  if systemctl --user is-active nanoclaw >/dev/null 2>&1; then
    SERVICE_MANAGER="systemd-user"
    SERVICE_WAS_RUNNING="true"
  elif systemctl is-active nanoclaw >/dev/null 2>&1; then
    SERVICE_MANAGER="systemd-system"
    SERVICE_WAS_RUNNING="true"
  elif pgrep -f 'dist/index\.js' >/dev/null 2>&1; then
    SERVICE_MANAGER="nohup"
    SERVICE_WAS_RUNNING="true"
  else
    # Check if systemd unit exists but isn't active
    if systemctl --user list-unit-files 2>/dev/null | grep -q "nanoclaw"; then
      SERVICE_MANAGER="systemd-user"
    fi
  fi
fi

# Stop service
if [ "$SERVICE_WAS_RUNNING" = "true" ]; then
  case "$SERVICE_MANAGER" in
    launchd)
      launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist 2>/dev/null || true
      ;;
    systemd-user)
      systemctl --user stop nanoclaw 2>/dev/null || true
      ;;
    systemd-system)
      sudo systemctl stop nanoclaw 2>/dev/null || true
      ;;
    nohup)
      pkill -f 'dist/index\.js' 2>/dev/null || true
      ;;
  esac

  # Wait up to 10 seconds for process to stop
  for i in $(seq 1 10); do
    if ! pgrep -f 'dist/index\.js' >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if pgrep -f 'dist/index\.js' >/dev/null 2>&1; then
    SERVICE_STOPPED="false"
  fi
fi

cat <<EOF
<<< STATUS
PLATFORM=$PLATFORM
SERVICE_MANAGER=$SERVICE_MANAGER
SERVICE_WAS_RUNNING=$SERVICE_WAS_RUNNING
SERVICE_STOPPED=$SERVICE_STOPPED
STATUS=success
STATUS >>>
EOF
