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

# Mark story as in_progress in prd.json — with safe temp file handling
TEMP_PRD=$(mktemp) || { echo '{}'; exit 0; }
trap 'rm -f "$TEMP_PRD"' EXIT

if ! jq --arg id "$NEXT_STORY" --arg mate "$TEAMMATE_NAME" '
  .userStories |= map(
    if .id == $id then .status = "in_progress" | .assigned_to = $mate else . end
  )
' "$PRD_FILE" > "$TEMP_PRD"; then
  # jq failed — don't corrupt prd.json
  echo '{}' >&2
  exit 0
fi

# Verify the temp file has content before overwriting
if [ ! -s "$TEMP_PRD" ]; then
  echo '{}' >&2
  exit 0
fi

if ! mv "$TEMP_PRD" "$PRD_FILE"; then
  echo '{}' >&2
  exit 0
fi
trap - EXIT

# Get story details for context
STORY_TITLE=$(jq -r --arg id "$NEXT_STORY" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE" 2>/dev/null)
STORY_CRITERIA=$(jq -r --arg id "$NEXT_STORY" '.userStories[] | select(.id == $id) | .acceptanceCriteria | join("; ")' "$PRD_FILE" 2>/dev/null)

# Return assignment context — use jq --arg to safely handle special characters
jq -n \
  --arg id "$NEXT_STORY" \
  --arg title "$STORY_TITLE" \
  --arg criteria "$STORY_CRITERIA" \
  '{
    hookSpecificOutput: {
      hookEventName: "TeammateIdle",
      additionalContext: ("## Assigned Story: " + $id + "\n**Title:** " + $title + "\n**Criteria:** " + $criteria + "\n\nImplement this story following TDD discipline. When complete, output <promise>COMPLETE</promise>.")
    }
  }'

exit 0
