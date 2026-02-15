#!/bin/bash
# TaskPlex Monitor — Start server and open dashboard
# Usage: start-monitor.sh [--no-open] [--port PORT]
#
# Starts the Bun server, builds the client if needed, and opens the browser.
# Stores PID in .claude/taskplex-monitor.pid for lifecycle management.

set -e

MONITOR_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${TASKPLEX_MONITOR_PORT:-4444}"
OPEN_BROWSER=true
PID_FILE=".claude/taskplex-monitor.pid"

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --no-open) OPEN_BROWSER=false; shift ;;
    --port) PORT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Check if already running
if [ -f "$PID_FILE" ]; then
  EXISTING_PID=$(cat "$PID_FILE")
  if kill -0 "$EXISTING_PID" 2>/dev/null; then
    echo "[MONITOR] Already running (PID: $EXISTING_PID) on port $PORT" >&2
    echo "$PORT"
    exit 0
  else
    rm -f "$PID_FILE"
  fi
fi

# Check bun is available
if ! command -v bun &>/dev/null; then
  echo "[MONITOR] Error: bun is required but not found. Install from https://bun.sh" >&2
  exit 1
fi

# Install dependencies if needed
if [ ! -d "$MONITOR_DIR/node_modules" ]; then
  echo "[MONITOR] Installing dependencies..." >&2
  (cd "$MONITOR_DIR" && bun install --frozen-lockfile 2>/dev/null || bun install) >&2
fi

# Build client if dist doesn't exist
if [ ! -d "$MONITOR_DIR/client/dist" ]; then
  echo "[MONITOR] Building client..." >&2
  (cd "$MONITOR_DIR/client" && bun run build) >&2
fi

# Ensure PID directory exists
mkdir -p "$(dirname "$PID_FILE")"

# Start server in background
TASKPLEX_MONITOR_PORT="$PORT" \
TASKPLEX_MONITOR_DB="${TASKPLEX_MONITOR_DB:-.claude/taskplex-monitor.db}" \
SERVE_CLIENT=true \
  nohup bun run "$MONITOR_DIR/server/index.ts" > .claude/taskplex-monitor.log 2>&1 &

SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

# Wait for server to be ready (max 5 seconds)
for i in $(seq 1 50); do
  if curl -s --connect-timeout 1 "http://localhost:${PORT}/health" > /dev/null 2>&1; then
    echo "[MONITOR] Server started (PID: $SERVER_PID) on http://localhost:${PORT}" >&2

    # Open browser if requested
    if [ "$OPEN_BROWSER" = true ]; then
      if command -v open &>/dev/null; then
        open "http://localhost:${PORT}"
      elif command -v xdg-open &>/dev/null; then
        xdg-open "http://localhost:${PORT}"
      fi
    fi

    # Output port for taskplex.sh to capture
    echo "$PORT"
    exit 0
  fi
  sleep 0.1
done

echo "[MONITOR] Error: Server failed to start within 5 seconds" >&2
kill "$SERVER_PID" 2>/dev/null || true
rm -f "$PID_FILE"
exit 1
