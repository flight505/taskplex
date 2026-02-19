#!/bin/bash
# TaskPlex Monitor — PostToolUseFailure hook
# Captures tool failures for error pattern analysis in the dashboard.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/send-event.sh" "tool.failure"
