#!/bin/bash
# validate-result.sh — SubagentStop hook
# Runs inline validation (typecheck/build/test) after implementer finishes.
# If validation fails, blocks agent with error details so it can self-heal.
#
# Input: JSON on stdin with agent_id, agent_type, agent_transcript_path, stop_hook_active, last_assistant_message
# Output: JSON on stdout with decision:"block" and reason (if failing)
# Exit 0 = allow agent to stop normally
# Exit 2 = block agent, inject reason (agent continues fixing)
# NOTE: set -e intentionally omitted — hook requires explicit exit code control

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract fields
AGENT_TYPE=$(echo "$HOOK_INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)

# Prevent infinite validation loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Only validate implementer agents
if [ "$AGENT_TYPE" != "implementer" ]; then
  exit 0
fi

# Find project config
PROJECT_DIR="$(pwd)"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"

# Check if validation is enabled
if [ -f "$CONFIG_FILE" ]; then
  VALIDATE_ON_STOP=$(jq -r 'if .validate_on_stop == false then "false" elif .validate_on_stop == true then "true" else "true" end' "$CONFIG_FILE" 2>/dev/null)
  if [ "$VALIDATE_ON_STOP" = "false" ]; then
    exit 0
  fi
fi

# Read validation commands from config
TYPECHECK_CMD=""
BUILD_CMD=""
TEST_CMD=""

if [ -f "$CONFIG_FILE" ]; then
  TYPECHECK_CMD=$(jq -r '.typecheck_command // ""' "$CONFIG_FILE" 2>/dev/null)
  BUILD_CMD=$(jq -r '.build_command // ""' "$CONFIG_FILE" 2>/dev/null)
  TEST_CMD=$(jq -r '.test_command // ""' "$CONFIG_FILE" 2>/dev/null)
fi

# If no validation commands configured, pass through
if [ -z "$TYPECHECK_CMD" ] && [ -z "$BUILD_CMD" ] && [ -z "$TEST_CMD" ]; then
  exit 0
fi

# Run validation commands and collect failures
FAILURES=""

if [ -n "$TYPECHECK_CMD" ]; then
  TYPECHECK_OUTPUT=$(eval "$TYPECHECK_CMD" 2>&1)
  TYPECHECK_EXIT=$?
  if [ $TYPECHECK_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Typecheck failed (exit $TYPECHECK_EXIT):
${TYPECHECK_OUTPUT}

"
  fi
fi

if [ -n "$BUILD_CMD" ]; then
  BUILD_OUTPUT=$(eval "$BUILD_CMD" 2>&1)
  BUILD_EXIT=$?
  if [ $BUILD_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Build failed (exit $BUILD_EXIT):
${BUILD_OUTPUT}

"
  fi
fi

if [ -n "$TEST_CMD" ]; then
  TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
  TEST_EXIT=$?
  if [ $TEST_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Tests failed (exit $TEST_EXIT):
${TEST_OUTPUT}

"
  fi
fi

# Extract learnings from last_assistant_message and save to SQLite (best-effort)
# Since CLI 2.1.47, SubagentStop provides last_assistant_message directly —
# no need to parse the transcript file.
LAST_MESSAGE=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)

if [ -n "$LAST_MESSAGE" ]; then
  source "$SCRIPT_DIR/scripts/knowledge-db.sh" 2>/dev/null || true

  PRD_FILE="$PROJECT_DIR/prd.json"
  KNOWLEDGE_DB="$PROJECT_DIR/knowledge.db"
  if [ -f "$CONFIG_FILE" ]; then
    CONFIGURED_DB=$(jq -r '.knowledge_db // ""' "$CONFIG_FILE" 2>/dev/null)
    [ -n "$CONFIGURED_DB" ] && KNOWLEDGE_DB="$PROJECT_DIR/$CONFIGURED_DB"
  fi

  if [ -f "$KNOWLEDGE_DB" ] && [ -f "$PRD_FILE" ]; then
    STORY_ID=$(jq -r '.userStories[] | select(.status == "in_progress") | .id' "$PRD_FILE" 2>/dev/null | head -1)
    RUN_ID="${TASKPLEX_RUN_ID:-unknown}"

    # Extract learnings from the implementer's final response.
    # Try jq parsing first (structured JSON), fall back to regex extraction.
    LEARNINGS=$(echo "$LAST_MESSAGE" | jq -r '
      (if type == "string" then (try fromjson catch {}) else . end) |
      .learnings // [] | .[]
    ' 2>/dev/null || true)
    if [ -z "$LEARNINGS" ]; then
      # Fallback: extract JSON object containing learnings, then parse
      LEARNINGS=$(echo "$LAST_MESSAGE" | grep -o '{[^{}]*"learnings"[^{}]*}' 2>/dev/null | tail -1 | jq -r '.learnings // [] | .[]' 2>/dev/null || true)
    fi

    if [ -n "$LEARNINGS" ] && [ -n "$STORY_ID" ]; then
      while IFS= read -r learning; do
        if [ -n "$learning" ]; then
          insert_learning "$KNOWLEDGE_DB" "$STORY_ID" "$RUN_ID" "$learning" 2>/dev/null || true
        fi
      done <<< "$LEARNINGS"
    fi
  fi
fi

# If all validations passed, allow agent to stop
if [ -z "$FAILURES" ]; then
  exit 0
fi

# Validation failed — block agent with error details
# Truncate to avoid overwhelming the agent
TRUNCATED_FAILURES=$(echo "$FAILURES" | head -c 2000)

# Escape for JSON
ESCAPED_REASON=$(echo "$TRUNCATED_FAILURES" | jq -Rs '.' 2>/dev/null)

cat <<BLOCK_OUTPUT
{
  "decision": "block",
  "reason": ${ESCAPED_REASON}
}
BLOCK_OUTPUT

exit 2
