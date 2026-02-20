#!/bin/bash
# stop-guard.sh — Stop hook
# Prevents Claude from stopping prematurely when TaskPlex stories are in progress.
# Exit 0 = allow stop
# Exit 2 = block stop (with reason on stdout as JSON)

HOOK_INPUT=$(cat)

# Prevent infinite loops — if we already blocked once, let it go
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Check if prd.json exists with in_progress or pending stories
PRD_FILE="$(pwd)/prd.json"
if [ ! -f "$PRD_FILE" ]; then
  exit 0
fi

IN_PROGRESS=$(jq '[.userStories[] | select(.status == "in_progress")] | length' "$PRD_FILE" 2>/dev/null || echo "0")
PENDING=$(jq '[.userStories[] | select(.passes == false and (.status == null or .status == "pending"))] | length' "$PRD_FILE" 2>/dev/null || echo "0")

if [ "$IN_PROGRESS" -gt 0 ] || [ "$PENDING" -gt 0 ]; then
  cat <<'BLOCK_JSON'
{
  "decision": "block",
  "reason": "TaskPlex run still active. There are stories in progress or pending. Continue working on the next story from prd.json, or explicitly mark remaining stories as skipped if you cannot proceed."
}
BLOCK_JSON
  exit 2
fi

exit 0
