#!/bin/bash
# TaskPlex Monitor — PostToolUse hook
# Captures tool usage (Bash, Edit, Write, Read, etc.) for agent behavior analysis.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/send-event.sh" "tool.use"
