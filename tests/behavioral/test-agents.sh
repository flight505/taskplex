#!/usr/bin/env bash
# US-007: Behavioral Test Harness — Agent Completion
# Tests that each agent can complete a minimal controlled task
# Usage: bash tests/behavioral/test-agents.sh [--agent <name>] [--dry-run] [--all]
# MUST run from terminal or CI — NOT from within Claude Code (nested claude hangs)
# Exit 0: agent completed task | Exit 1: failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures/agent-tasks.json"
RESULTS_DIR="${SCRIPT_DIR}/results"
TIMEOUT=300  # 5 minutes per agent

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

mkdir -p "$RESULTS_DIR"

# Parse args
DRY_RUN=0
TARGET_AGENT=""
RUN_ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --agent)   TARGET_AGENT="$2"; shift 2 ;;
    --all)     RUN_ALL=1; shift ;;
    *)         shift ;;
  esac
done

# ─────────────────────────────────────────────
# Validate fixture
# ─────────────────────────────────────────────
validate_fixture() {
  if [ ! -f "$FIXTURES" ]; then
    echo "ERROR: fixtures/agent-tasks.json not found" >&2
    exit 1
  fi
  if ! jq . "$FIXTURES" > /dev/null 2>&1; then
    echo "ERROR: fixtures/agent-tasks.json has invalid JSON" >&2
    exit 1
  fi
  local count
  count=$(jq '.agents | length' "$FIXTURES")
  if [ "$count" -ne 6 ]; then
    echo "ERROR: expected 6 agents in fixture, got ${count}" >&2
    exit 1
  fi
  echo "Fixture: ${count} agents validated"
}

# ─────────────────────────────────────────────
# Dry-run mode: show what would be tested
# ─────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ] && [ -z "$TARGET_AGENT" ] && [ "$RUN_ALL" -eq 0 ]; then
  echo "=== US-007: Agent Completion Tests (DRY RUN) ==="
  echo ""
  validate_fixture
  echo ""
  jq -r '.agents[] | "  \(.name) (model: \(.model), maxTurns: \(.maxTurns), perm: \(.permissionMode))\n    Task: \(.task_prompt[:80])..."' "$FIXTURES"
  echo ""
  echo "Estimated cost: ~\$3.00 total (haiku×3 + sonnet×2 + implementer×1)"
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ] && [ -n "$TARGET_AGENT" ]; then
  validate_fixture
  echo "=== Agent: ${TARGET_AGENT} (dry run) ==="
  jq -r --arg n "$TARGET_AGENT" '.agents[] | select(.name==$n) | "Model: \(.model)\nPermission: \(.permissionMode)\nMax turns: \(.maxTurns)\nTask: \(.task_prompt)"' "$FIXTURES"
  exit 0
fi

# Guard: cannot run inside active Claude Code session
if [ -n "$CLAUDECODE" ]; then
  echo "ERROR: Cannot run agent tests from within an active Claude Code session." >&2
  echo "       The nested claude -p call will hang indefinitely." >&2
  echo "       Run from a terminal: bash tests/behavioral/test-agents.sh --agent validator" >&2
  echo "       Or in CI: GitHub Actions provides the correct environment." >&2
  exit 1
fi

if ! command -v claude > /dev/null 2>&1; then
  echo "ERROR: claude CLI not found" >&2
  exit 1
fi

validate_fixture

# ─────────────────────────────────────────────
# Ensure sample project has dependencies installed
# ─────────────────────────────────────────────
SAMPLE_PROJECT="${PLUGIN_ROOT}/tests/benchmark/projects/sample-ts-api"
if [ -d "$SAMPLE_PROJECT" ] && [ ! -d "${SAMPLE_PROJECT}/node_modules" ]; then
  echo "Installing sample project dependencies..." >&2
  (cd "$SAMPLE_PROJECT" && npm install --silent 2>/dev/null) || {
    echo "WARNING: Failed to install sample project deps — some agent tests may fail" >&2
  }
fi

# ─────────────────────────────────────────────
# Run a single agent test
# ─────────────────────────────────────────────
test_agent() {
  local agent_name="$1"

  # Load agent config from fixture
  if ! jq -e --arg n "$agent_name" '.agents[] | select(.name==$n)' "$FIXTURES" > /dev/null 2>&1; then
    echo "ERROR: agent '${agent_name}' not found in fixture" >&2
    return 1
  fi

  local model task_prompt target_project max_turns perm_mode
  model=$(jq -r --arg n "$agent_name" '.agents[] | select(.name==$n) | .model' "$FIXTURES")
  task_prompt=$(jq -r --arg n "$agent_name" '.agents[] | select(.name==$n) | .task_prompt' "$FIXTURES")
  target_project=$(jq -r --arg n "$agent_name" '.agents[] | select(.name==$n) | .target_project' "$FIXTURES")
  max_turns=$(jq -r --arg n "$agent_name" '.agents[] | select(.name==$n) | .maxTurns' "$FIXTURES")
  perm_mode=$(jq -r --arg n "$agent_name" '.agents[] | select(.name==$n) | .permissionMode' "$FIXTURES")

  local project_path="${PLUGIN_ROOT}/${target_project}"
  if [ ! -d "$project_path" ]; then
    echo "ERROR: target project not found: ${project_path}" >&2
    return 1
  fi

  # Resolve model (inherit = haiku for test purposes)
  local resolved_model="$model"
  [ "$resolved_model" = "inherit" ] && resolved_model="haiku"

  local tmp_output
  tmp_output=$(mktemp /tmp/agent-test-XXXXXX.json)
  local start_time
  start_time=$(date +%s)
  local exit_code=0

  # Build permission flags
  local perm_flags="--dangerously-skip-permissions"

  env -u CLAUDECODE timeout "$TIMEOUT" claude -p "$task_prompt" \
    --cwd "$project_path" \
    --plugin-dir "$PLUGIN_ROOT" \
    --model "$resolved_model" \
    "$perm_flags" \
    --output-format json \
    2>/dev/null > "$tmp_output" || exit_code=$?

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))

  # Parse completion from output
  local task_completed=false
  local turns_used=0
  local permission_blocks="[]"
  local cost=0

  if [ -f "$tmp_output" ] && [ -s "$tmp_output" ]; then
    # Check if result contains completion indicators (not empty, not error-only)
    if grep -q '"type":"result"' "$tmp_output" 2>/dev/null; then
      task_completed=true
    elif [ "$exit_code" -eq 0 ]; then
      task_completed=true
    fi

    # Extract cost if available
    cost=$(grep -o '"total_cost_usd":[0-9.]*' "$tmp_output" 2>/dev/null | head -1 | cut -d: -f2 || echo "0")

    # Check for permission blocks (exit code 5 = permission denied)
    if [ "$exit_code" -eq 5 ]; then
      permission_blocks='["permission_denied"]'
      task_completed=false
    fi
  fi

  local within_budget=false
  [ "$turns_used" -le "$max_turns" ] && within_budget=true

  rm -f "$tmp_output"

  local result
  result=$(jq -n \
    --arg agent "$agent_name" \
    --argjson completed "$task_completed" \
    --argjson turns "$turns_used" \
    --argjson max "$max_turns" \
    --argjson budget "$within_budget" \
    --argjson blocks "$permission_blocks" \
    --argjson duration "$duration" \
    --argjson cost "$cost" \
    '{
      agent: $agent,
      task_completed: $completed,
      turns_used: $turns,
      max_turns: $max,
      within_budget: $budget,
      permission_blocks: $blocks,
      duration_seconds: $duration,
      cost_usd: $cost
    }')

  if [ "$task_completed" = "true" ]; then
    printf "  ${GREEN}✓${RESET} %s completed (%ds, \$%s)\n" "$agent_name" "$duration" "$cost" >&2
  else
    printf "  ${RED}✗${RESET} %s did not complete (exit=%d, %ds)\n" "$agent_name" "$exit_code" "$duration" >&2
  fi

  echo "$result"
}

# ─────────────────────────────────────────────
# Main execution
# ─────────────────────────────────────────────
TIMESTAMP=$(date +%s)
VERSION=$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)
GIT_SHA=$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null)

echo "=== US-007: Agent Completion Tests v${VERSION} ==="
echo ""

all_results="[]"
total=0
completed=0

if [ "$RUN_ALL" -eq 1 ]; then
  AGENTS=$(jq -r '.agents[].name' "$FIXTURES")
elif [ -n "$TARGET_AGENT" ]; then
  AGENTS="$TARGET_AGENT"
else
  echo "Usage: $0 --dry-run | --agent <name> | --all" >&2
  exit 1
fi

while IFS= read -r agent_name; do
  [ -z "$agent_name" ] && continue
  echo "Testing agent: ${agent_name}" >&2

  result=$(test_agent "$agent_name" || echo '{"error":"test_failed"}')
  all_results=$(echo "$all_results" | jq --argjson r "$result" '. + [$r]')
  total=$((total + 1))

  if echo "$result" | jq -e '.task_completed == true' > /dev/null 2>&1; then
    completed=$((completed + 1))
  fi
  echo "" >&2
done <<EOF
$AGENTS
EOF

echo "=== Results: ${completed}/${total} agents completed ==="

# Write results JSON
REPORT="${RESULTS_DIR}/agent-completion-${TIMESTAMP}.json"
completion_rate=0
if [ "$total" -gt 0 ]; then
  completion_rate=$(echo "$completed $total" | awk '{printf "%.2f", $1/$2}')
fi

jq -n \
  --arg version "$VERSION" \
  --arg git_sha "$GIT_SHA" \
  --argjson timestamp "$TIMESTAMP" \
  --argjson results "$all_results" \
  --argjson total "$total" \
  --argjson completed "$completed" \
  --argjson rate "$completion_rate" \
  '{
    suite: "agent-completion",
    version: $version,
    git_sha: $git_sha,
    timestamp: $timestamp,
    results: $results,
    summary: {
      total_agents: $total,
      completed: $completed,
      completion_rate: $rate
    }
  }' > "$REPORT"

echo "  Report: ${REPORT}"

[ "$completed" -eq "$total" ] && exit 0 || exit 1
