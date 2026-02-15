#!/bin/bash
# TaskPlex Monitor — SubagentStart hook
# Captures when implementer/validator/reviewer/merger agents spawn.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/send-event.sh" "subagent.start"
