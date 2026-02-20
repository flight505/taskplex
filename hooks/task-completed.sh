#!/bin/bash
# task-completed.sh — TaskCompleted hook
# Validates that tests pass before allowing a task to be marked complete.
# Exit 0 = allow completion
# Exit 2 = block completion (stderr message fed back to agent)

PROJECT_DIR="$(pwd)"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"

# Read test command from config
TEST_CMD=""
if [ -f "$CONFIG_FILE" ]; then
  TEST_CMD=$(jq -r '.test_command // ""' "$CONFIG_FILE" 2>/dev/null)
fi

# No test command configured — allow completion
if [ -z "$TEST_CMD" ]; then
  exit 0
fi

# Run tests
TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
TEST_EXIT=$?

if [ $TEST_EXIT -eq 0 ]; then
  exit 0
fi

# Tests failed — block completion
echo "Tests failed (exit $TEST_EXIT). Fix the failing tests before marking this task complete:" >&2
echo "$TEST_OUTPUT" | head -c 1500 >&2
exit 2
