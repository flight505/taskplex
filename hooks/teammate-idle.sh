#!/bin/bash
# teammate-idle.sh — TeammateIdle hook
# Assigns next ready story (deps satisfied) to idle teammate from prd.json.
#
# Input: JSON on stdin with teammate_id, teammate_name
# Output: JSON on stdout with task assignment
# Exit 0 always

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Read hook input from stdin
HOOK_INPUT=$(cat)

TEAMMATE_ID=$(echo "$HOOK_INPUT" | jq -r '.teammate_id // ""' 2>/dev/null)
TEAMMATE_NAME=$(echo "$HOOK_INPUT" | jq -r '.teammate_name // ""' 2>/dev/null)

# Find project root (look for prd.json)
PROJECT_DIR="$(pwd)"
PRD_FILE="$PROJECT_DIR/prd.json"

if [ ! -f "$PRD_FILE" ]; then
  echo '{}'
  exit 0
fi

# Find next eligible story with all dependencies satisfied
NEXT_STORY=$(jq -r '
  .userStories as $all |
  .userStories[] |
  select(.passes == false and .status != "skipped" and .status != "in_progress" and .status != "rewritten") |
  select(
    (.depends_on == null) or
    (.depends_on | length == 0) or
    (.depends_on | all(. as $dep | $all | map(select(.id == $dep and .passes == true)) | length > 0))
  ) |
  {id: .id, priority: .priority}
' "$PRD_FILE" | jq -rs 'sort_by(.priority) | .[0].id // empty' 2>/dev/null)

if [ -z "$NEXT_STORY" ]; then
  echo '{}'
  exit 0
fi

# Mark story as in_progress in prd.json
TEMP_PRD=$(mktemp)
jq --arg id "$NEXT_STORY" --arg mate "$TEAMMATE_NAME" '
  .userStories |= map(
    if .id == $id then .status = "in_progress" | .assigned_to = $mate else . end
  )
' "$PRD_FILE" > "$TEMP_PRD" && mv "$TEMP_PRD" "$PRD_FILE"

# Get story details for context
STORY_TITLE=$(jq -r --arg id "$NEXT_STORY" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE" 2>/dev/null)
STORY_CRITERIA=$(jq -r --arg id "$NEXT_STORY" '.userStories[] | select(.id == $id) | .acceptanceCriteria | join("; ")' "$PRD_FILE" 2>/dev/null)

# Return assignment context
ESCAPED_CONTEXT=$(cat <<TASK_CONTEXT | jq -Rs '.'
## Assigned Story: ${NEXT_STORY}
**Title:** ${STORY_TITLE}
**Criteria:** ${STORY_CRITERIA}

Implement this story following TDD discipline. When complete, output <promise>COMPLETE</promise>.
TASK_CONTEXT
)

cat <<HOOK_OUTPUT
{
  "hookSpecificOutput": {
    "hookEventName": "TeammateIdle",
    "additionalContext": ${ESCAPED_CONTEXT}
  }
}
HOOK_OUTPUT

exit 0
