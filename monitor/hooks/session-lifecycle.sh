#!/bin/bash
# TaskPlex Monitor — SessionStart/SessionEnd hook
# Captures Claude Code session lifecycle events.
# Also persists TaskPlex env vars via CLAUDE_ENV_FILE on session start.
# The event type is passed as the first argument by hooks.json.

EVENT_TYPE="${1:-session.start}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Persist TaskPlex environment variables for all subsequent Bash commands
if [ "$EVENT_TYPE" = "session.start" ] && [ -n "$CLAUDE_ENV_FILE" ]; then
  # Detect monitor port from PID file or env
  MONITOR_PORT="${TASKPLEX_MONITOR_PORT:-}"
  if [ -z "$MONITOR_PORT" ]; then
    PID_FILE="$(pwd)/.claude/taskplex-monitor.pid"
    if [ -f "$PID_FILE" ]; then
      MONITOR_PORT=$(head -2 "$PID_FILE" | tail -1 2>/dev/null || echo "")
    fi
  fi
  [ -n "$MONITOR_PORT" ] && echo "export TASKPLEX_MONITOR_PORT=\"$MONITOR_PORT\"" >> "$CLAUDE_ENV_FILE"

  # Persist run ID if set
  [ -n "$TASKPLEX_RUN_ID" ] && echo "export TASKPLEX_RUN_ID=\"$TASKPLEX_RUN_ID\"" >> "$CLAUDE_ENV_FILE"
fi

exec "$SCRIPT_DIR/send-event.sh" "$EVENT_TYPE"
