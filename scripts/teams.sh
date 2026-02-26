#!/bin/bash
# teams.sh — Agent Teams execution mode for TaskPlex
# Creates a team with orchestrator, implementer(s), and reviewer roles.
# Triggered by execution_mode: "teams" in config or wizard selection.
#
# Usage: ./teams.sh [max_iterations]
# Requires: claude CLI with Agent Teams support, prd.json, jq

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(pwd)"
PRD_FILE="$PROJECT_DIR/prd.json"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"
MAX_ITERATIONS=${1:-10}

# Source dependencies
source "$SCRIPT_DIR/knowledge-db.sh" 2>/dev/null || true

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%S)] [TEAMS-$1] $2" >&2
}

# Validate prerequisites
if [ ! -f "$PRD_FILE" ]; then
  log "ERROR" "prd.json not found. Run /taskplex:start first."
  exit 1
fi

if ! jq empty "$PRD_FILE" 2>/dev/null; then
  log "ERROR" "prd.json is invalid JSON."
  exit 1
fi

# Read config
MAX_PARALLEL=3
EXECUTION_MODEL="sonnet"
MERGE_ON_COMPLETE=false
TEST_COMMAND=""
BUILD_COMMAND=""
TYPECHECK_COMMAND=""

if [ -f "$CONFIG_FILE" ]; then
  MAX_PARALLEL=$(jq -r '.max_parallel // 3' "$CONFIG_FILE")
  EXECUTION_MODEL=$(jq -r '.execution_model // "sonnet"' "$CONFIG_FILE")
  MERGE_ON_COMPLETE=$(jq -r '.merge_on_complete // false' "$CONFIG_FILE")
  TEST_COMMAND=$(jq -r '.test_command // ""' "$CONFIG_FILE")
  BUILD_COMMAND=$(jq -r '.build_command // ""' "$CONFIG_FILE")
  TYPECHECK_COMMAND=$(jq -r '.typecheck_command // ""' "$CONFIG_FILE")
fi

# Count stories
TOTAL_STORIES=$(jq '.userStories | length' "$PRD_FILE")
PENDING_STORIES=$(jq '[.userStories[] | select(.passes == false and .status != "skipped")] | length' "$PRD_FILE")

log "INIT" "Team execution mode: $TOTAL_STORIES total stories, $PENDING_STORIES pending"
log "INIT" "Max concurrent implementers: $MAX_PARALLEL"

# Build team prompt for orchestrator
ORCHESTRATOR_PROMPT="You are the TaskPlex orchestrator managing a team of implementers.

## Your Role
- Read prd.json to understand the project and remaining stories
- Assign stories to teammates based on dependency order
- Monitor progress and handle failures
- Ensure each story is validated before marking complete

## Project
$(jq '{project, branchName, description}' "$PRD_FILE")

## Stories Summary
$(jq '[.userStories[] | {id, title, status: (if .passes then "completed" elif .status == "skipped" then "skipped" else .status // "pending" end), deps: (.depends_on // [])}]' "$PRD_FILE")

## Rules
1. Only assign stories whose dependencies are ALL completed
2. Each teammate implements ONE story at a time
3. After a teammate completes a story, run validation: ${TEST_COMMAND:-echo 'No test command configured'}
4. If validation fails, ask the teammate to fix the issue
5. When all stories are complete, output <promise>COMPLETE</promise>

## Available Validation Commands
- Test: ${TEST_COMMAND:-not configured}
- Build: ${BUILD_COMMAND:-not configured}
- Typecheck: ${TYPECHECK_COMMAND:-not configured}
"

# Check if claude teams is available
if ! claude --help 2>&1 | grep -q "team\|teams"; then
  log "WARN" "Agent Teams may not be available in your Claude CLI version."
  log "WARN" "Falling back to sequential mode."
  exec "$SCRIPT_DIR/taskplex.sh" "$MAX_ITERATIONS"
fi

# Launch team with orchestrator prompt
log "START" "Launching Agent Team..."

env -u CLAUDECODE claude -p "$ORCHESTRATOR_PROMPT" \
  --model "$EXECUTION_MODEL" \
  --output-format json \
  --dangerously-skip-permissions \
  --max-turns "$((MAX_ITERATIONS * 10))" \
  --no-session-persistence

TEAM_EXIT=$?

if [ $TEAM_EXIT -eq 0 ]; then
  log "DONE" "Team execution completed successfully"
else
  log "ERROR" "Team execution failed with exit code $TEAM_EXIT"
fi

# Check final status
COMPLETED=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
SKIPPED=$(jq '[.userStories[] | select(.status == "skipped")] | length' "$PRD_FILE")

echo ""
echo "Team Execution Results:"
echo "  Completed: $COMPLETED / $TOTAL_STORIES"
echo "  Skipped: $SKIPPED"
echo "  Remaining: $((TOTAL_STORIES - COMPLETED - SKIPPED))"

exit $TEAM_EXIT
