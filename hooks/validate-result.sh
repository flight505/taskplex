#!/bin/bash
# validate-result.sh — SubagentStop hook
# Runs inline validation (typecheck/build/test) after implementer finishes.
# If validation fails, blocks agent with error details so it can self-heal.
#
# Input: JSON on stdin with agent_type, stop_hook_active
# Exit 0 = allow agent to stop normally
# Exit 2 = block agent, inject reason (agent continues fixing)
# NOTE: set -e intentionally omitted — hook requires explicit exit code control

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

# If all validations passed, allow agent to stop
if [ -z "$FAILURES" ]; then
  exit 0
fi

# Validation failed — block agent with error details
TRUNCATED_FAILURES=$(echo "$FAILURES" | head -c 2000)
ESCAPED_REASON=$(echo "$TRUNCATED_FAILURES" | jq -Rs '.' 2>/dev/null)

cat <<BLOCK_OUTPUT
{
  "decision": "block",
  "reason": ${ESCAPED_REASON}
}
BLOCK_OUTPUT

exit 2
