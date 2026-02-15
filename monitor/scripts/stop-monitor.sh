#!/bin/bash
# TaskPlex Monitor — Stop server gracefully
# Usage: stop-monitor.sh
#
# Reads PID from .claude/taskplex-monitor.pid and sends SIGTERM.

PID_FILE=".claude/taskplex-monitor.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "[MONITOR] Not running (no PID file)" >&2
  exit 0
fi

PID=$(cat "$PID_FILE")

if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null
  # Wait up to 3 seconds for graceful shutdown
  for i in $(seq 1 30); do
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "[MONITOR] Server stopped (PID: $PID)" >&2
      rm -f "$PID_FILE"
      exit 0
    fi
    sleep 0.1
  done
  # Force kill if still running
  kill -9 "$PID" 2>/dev/null || true
  echo "[MONITOR] Server force-killed (PID: $PID)" >&2
else
  echo "[MONITOR] Server already stopped" >&2
fi

rm -f "$PID_FILE"
exit 0
