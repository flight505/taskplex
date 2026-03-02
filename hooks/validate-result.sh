#!/bin/bash
# validate-result.sh — SubagentStop hook
# Runs inline validation (typecheck/build/test) after implementer finishes.
# If validation fails, blocks agent with error details so it can self-heal.
#
# Input: JSON on stdin with agent_type, stop_hook_active
# Exit 0 = allow agent to stop normally
# Exit 2 = block agent, inject reason via stderr (agent continues fixing)
# NOTE: set -e intentionally omitted — hook requires explicit exit code control

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract fields — validate jq parse succeeded
AGENT_TYPE=$(echo "$HOOK_INPUT" | jq -r '.agent_type // ""' 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$AGENT_TYPE" ]; then
  # Malformed input or missing agent_type — allow through
  exit 0
fi

STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // "false"' 2>/dev/null)
LAST_MESSAGE=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)

# Prevent infinite validation loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Only validate implementer agents
if [ "$AGENT_TYPE" != "implementer" ]; then
  exit 0
fi

# Extract structured output from implementer's last message
# Look for the JSON block with status field
IMPL_STATUS=""
RETRY_HINT=""
if [ -n "$LAST_MESSAGE" ]; then
  # Extract JSON block from the message (last ```json ... ``` block)
  JSON_BLOCK=$(echo "$LAST_MESSAGE" | sed -n '/```json/,/```/p' | sed '1d;$d' | tail -n +1)
  if [ -n "$JSON_BLOCK" ]; then
    IMPL_STATUS=$(echo "$JSON_BLOCK" | jq -r '.status // ""' 2>/dev/null) || IMPL_STATUS=""
    RETRY_HINT=$(echo "$JSON_BLOCK" | jq -r '.retry_hint // ""' 2>/dev/null) || RETRY_HINT=""
  fi
fi

# Skip validation if implementer reported story as skipped (already implemented)
if [ "$IMPL_STATUS" = "skipped" ]; then
  exit 0
fi

# Find project config
PROJECT_DIR="$(pwd)"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"

# Read validation commands from config
TYPECHECK_CMD=""
BUILD_CMD=""
TEST_CMD=""

if [ -f "$CONFIG_FILE" ]; then
  TYPECHECK_CMD=$(jq -r '.typecheck_command // ""' "$CONFIG_FILE" 2>/dev/null) || TYPECHECK_CMD=""
  BUILD_CMD=$(jq -r '.build_command // ""' "$CONFIG_FILE" 2>/dev/null) || BUILD_CMD=""
  TEST_CMD=$(jq -r '.test_command // ""' "$CONFIG_FILE" 2>/dev/null) || TEST_CMD=""
fi

# If no validation commands configured, pass through
if [ -z "$TYPECHECK_CMD" ] && [ -z "$BUILD_CMD" ] && [ -z "$TEST_CMD" ]; then
  exit 0
fi

# Run validation commands and collect failures
# Uses bash -c instead of eval to avoid command injection
FAILURES=""

if [ -n "$TYPECHECK_CMD" ]; then
  TYPECHECK_OUTPUT=$(bash -c "$TYPECHECK_CMD" 2>&1)
  TYPECHECK_EXIT=$?
  if [ $TYPECHECK_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Typecheck failed (exit $TYPECHECK_EXIT):
${TYPECHECK_OUTPUT}

"
  fi
fi

if [ -n "$BUILD_CMD" ]; then
  BUILD_OUTPUT=$(bash -c "$BUILD_CMD" 2>&1)
  BUILD_EXIT=$?
  if [ $BUILD_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Build failed (exit $BUILD_EXIT):
${BUILD_OUTPUT}

"
  fi
fi

if [ -n "$TEST_CMD" ]; then
  TEST_OUTPUT=$(bash -c "$TEST_CMD" 2>&1)
  TEST_EXIT=$?
  if [ $TEST_EXIT -ne 0 ]; then
    FAILURES="${FAILURES}Tests failed (exit $TEST_EXIT):
${TEST_OUTPUT}

"
  fi
fi

# If all validations passed, allow agent to stop
if [ -z "$FAILURES" ]; then
  exit 0
fi

# Validation failed — block agent with error details
# Include retry_hint from implementer's structured output if available
if [ -n "$RETRY_HINT" ]; then
  FAILURES="${FAILURES}Implementer's retry hint: ${RETRY_HINT}
"
fi

# Truncate to 4000 chars (enough for meaningful diagnostics without overwhelming)
TRUNCATED_FAILURES=$(echo "$FAILURES" | head -c 4000)

# Exit 2 blocks the agent; reason goes to stderr per hook convention
echo "$TRUNCATED_FAILURES" >&2
exit 2
