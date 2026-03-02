#!/bin/bash
# task-completed.sh — TaskCompleted hook
# Validates that story tasks have been properly reviewed before completion.
# Prevents advancing past a story when review was skipped.
#
# Input: JSON on stdin with task_id, task_subject, task_description
# Exit 0 = allow task completion
# Exit 2 = block completion, inject reason via stderr
# NOTE: set -e intentionally omitted — hook requires explicit exit code control

# Read hook input from stdin
HOOK_INPUT=$(cat)

# Extract fields
TASK_SUBJECT=$(echo "$HOOK_INPUT" | jq -r '.task_subject // ""' 2>/dev/null)
TASK_DESCRIPTION=$(echo "$HOOK_INPUT" | jq -r '.task_description // ""' 2>/dev/null)

# If no task subject or jq failed, allow through
if [ -z "$TASK_SUBJECT" ]; then
  exit 0
fi

# Only gate story tasks (those matching US-XXX pattern)
if ! echo "$TASK_SUBJECT" | grep -qE 'US-[0-9]+'; then
  exit 0
fi

# Check if prd.json exists
PROJECT_DIR="$(pwd)"
PRD_FILE="$PROJECT_DIR/prd.json"

if [ ! -f "$PRD_FILE" ]; then
  exit 0
fi

# Extract story ID from task subject
STORY_ID=$(echo "$TASK_SUBJECT" | grep -oE 'US-[0-9]+' | head -1)

if [ -z "$STORY_ID" ]; then
  exit 0
fi

# Check story status in prd.json — verify it's been reviewed
STORY_STATUS=$(jq -r --arg id "$STORY_ID" '.stories[]? | select(.id == $id) | .status // ""' "$PRD_FILE" 2>/dev/null) || STORY_STATUS=""

# If story is still in_progress (not reviewed), block completion
if [ "$STORY_STATUS" = "in_progress" ]; then
  echo "Story $STORY_ID has not been reviewed yet. Run the reviewer agent before marking this task complete." >&2
  exit 2
fi

# Check if validation commands are configured and test suite passes
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"
TEST_CMD=""

if [ -f "$CONFIG_FILE" ]; then
  TEST_CMD=$(jq -r '.test_command // ""' "$CONFIG_FILE" 2>/dev/null) || TEST_CMD=""
fi

if [ -n "$TEST_CMD" ]; then
  TEST_OUTPUT=$(bash -c "$TEST_CMD" 2>&1)
  TEST_EXIT=$?
  if [ $TEST_EXIT -ne 0 ]; then
    TRUNCATED=$(echo "$TEST_OUTPUT" | head -c 2000)
    echo "Tests failing for $STORY_ID. Fix tests before completing task:
$TRUNCATED" >&2
    exit 2
  fi
fi

exit 0
