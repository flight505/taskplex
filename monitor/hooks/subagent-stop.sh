#!/bin/bash
# TaskPlex Monitor — SubagentStop hook
# Captures when agents complete, including duration and exit status.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/send-event.sh" "subagent.stop"
