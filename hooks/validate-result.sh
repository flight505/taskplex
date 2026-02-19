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

    # === Transcript mining: extract implicit learnings from prose ===
    # The agent's final message often contains useful patterns and environment
    # observations buried in prose that aren't in the structured JSON output.
    # Mine these by looking for specific signal patterns.
    mine_implicit_learnings "$KNOWLEDGE_DB" "$STORY_ID" "$RUN_ID" "$LAST_MESSAGE" 2>/dev/null || true
  fi
fi

# === Scope drift detection ===
# Compare git diff against expected files from story context.
# Informational only — logs a warning but never blocks the agent.
SCOPE_DRIFT=""
if [ -f "$PRD_FILE" ]; then
  STORY_ID_DRIFT=$(jq -r '.userStories[] | select(.status == "in_progress") | .id' "$PRD_FILE" 2>/dev/null | head -1)

  if [ -n "$STORY_ID_DRIFT" ]; then
    # Get expected files from story hints and related_to context
    EXPECTED_DIRS=$(jq -r --arg id "$STORY_ID_DRIFT" '
      .userStories[] | select(.id == $id) |
      ([.implementation_hint // ""] + [.related_to // [] | .[]] + [.title // ""]) | join(" ")
    ' "$PRD_FILE" 2>/dev/null)

    # Get actual files changed (uncommitted + last commit by this agent)
    ACTUAL_FILES=$(git diff --name-only HEAD 2>/dev/null; git diff --cached --name-only 2>/dev/null)
    ACTUAL_FILE_COUNT=$(echo "$ACTUAL_FILES" | grep -c . 2>/dev/null || echo "0")

    # Flag if more than 15 files changed (likely scope creep)
    if [ "$ACTUAL_FILE_COUNT" -gt 15 ]; then
      SCOPE_DRIFT="[scope-drift] Agent modified $ACTUAL_FILE_COUNT files (threshold: 15). Review for scope creep."
    fi

    # Flag if files outside the expected directories were touched
    # Extract directory patterns from implementation_hint
    HINT_DIRS=$(jq -r --arg id "$STORY_ID_DRIFT" '
      .userStories[] | select(.id == $id) |
      .implementation_hint // "" | split(" ") | map(select(contains("/"))) | .[]
    ' "$PRD_FILE" 2>/dev/null)

    if [ -n "$HINT_DIRS" ] && [ -n "$ACTUAL_FILES" ]; then
      UNEXPECTED_FILES=""
      while IFS= read -r f; do
        [ -z "$f" ] && continue
        matched=0
        while IFS= read -r hint_dir; do
          [ -z "$hint_dir" ] && continue
          if echo "$f" | grep -q "$hint_dir" 2>/dev/null; then
            matched=1
            break
          fi
        done <<< "$HINT_DIRS"
        if [ "$matched" -eq 0 ]; then
          UNEXPECTED_FILES="${UNEXPECTED_FILES}${f}\n"
        fi
      done <<< "$ACTUAL_FILES"

      UNEXPECTED_COUNT=$(echo -e "$UNEXPECTED_FILES" | grep -c . 2>/dev/null || echo "0")
      if [ "$UNEXPECTED_COUNT" -gt 5 ]; then
        SCOPE_DRIFT="${SCOPE_DRIFT}[scope-drift] $UNEXPECTED_COUNT files outside expected scope."
      fi
    fi

    # Log scope drift to SQLite as a low-confidence learning (informational)
    if [ -n "$SCOPE_DRIFT" ] && [ -f "$KNOWLEDGE_DB" ]; then
      source "$SCRIPT_DIR/scripts/knowledge-db.sh" 2>/dev/null || true
      ESCAPED_DRIFT=$(echo "$SCOPE_DRIFT" | sed "s/'/''/g" | head -c 500)
      sqlite3 "$KNOWLEDGE_DB" "INSERT INTO learnings (story_id, run_id, content, confidence, tags, source) VALUES ('$STORY_ID_DRIFT', '${TASKPLEX_RUN_ID:-unknown}', '$ESCAPED_DRIFT', 0.5, 'scope-drift', 'validate-result');" 2>/dev/null || true
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
