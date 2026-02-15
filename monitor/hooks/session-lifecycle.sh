#!/bin/bash
# TaskPlex Monitor — SessionStart/SessionEnd hook
# Captures Claude Code session lifecycle events.
# The event type is passed as the first argument by hooks.json.

EVENT_TYPE="${1:-session.start}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/send-event.sh" "$EVENT_TYPE"
