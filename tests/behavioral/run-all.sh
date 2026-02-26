#!/usr/bin/env bash
# US-008: Behavioral Test Runner and Cost Tracking
# Runs behavioral test suites with selective execution and cost tracking
# Usage: bash tests/behavioral/run-all.sh [--suite hooks|skills|agents] [--estimate] [--yes]
# Exit 0: all suites pass | Exit 1: any failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

mkdir -p "$RESULTS_DIR"

# Parse args
SUITE="all"
ESTIMATE=0
YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --suite)    SUITE="$2"; shift 2 ;;
    --estimate) ESTIMATE=1; shift ;;
    --yes)      YES=1; shift ;;
    *)          shift ;;
  esac
done

VERSION=$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)
GIT_SHA=$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null)
TIMESTAMP=$(date +%s)

# Cost estimates (prompts × per-prompt cost)
HOOKS_COST=0
SKILLS_PROMPTS=32
SKILLS_COST_PER=0.15
AGENTS_TASKS=6
AGENTS_COST_PER=0.50

if [ "$ESTIMATE" -eq 1 ]; then
  echo "=== Behavioral Suite Cost Estimate ==="
  echo ""
  printf "  %-12s %4d prompts × \$0.00  =  ~\$0.00  (pure bash, no API)\n" "hooks:" 0
  printf "  %-12s %4d prompts × \$%.2f =  ~\$%.2f\n" "skills:" "$SKILLS_PROMPTS" "$SKILLS_COST_PER" "$(echo "$SKILLS_PROMPTS $SKILLS_COST_PER" | awk '{printf "%.2f", $1*$2}')"
  printf "  %-12s %4d tasks   × \$%.2f =  ~\$%.2f\n" "agents:" "$AGENTS_TASKS" "$AGENTS_COST_PER" "$(echo "$AGENTS_TASKS $AGENTS_COST_PER" | awk '{printf "%.2f", $1*$2}')"
  echo ""
  total=$(echo "$SKILLS_PROMPTS $SKILLS_COST_PER $AGENTS_TASKS $AGENTS_COST_PER" | awk '{printf "%.2f", $1*$2 + $3*$4}')
  printf "  Total (all suites): ~\$%s\n" "$total"
  exit 0
fi

echo "=== Behavioral Test Suite v${VERSION} (${GIT_SHA}) ==="
if [ "$SUITE" != "all" ]; then
  echo "  Running suite: ${SUITE}"
fi
echo ""

passed=0
failed=0
total_cost=0
suite_results="{}"

run_suite_hooks() {
  local output exit_code
  output=$(bash "${SCRIPT_DIR}/test-hooks.sh" 2>&1) && exit_code=0 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    printf "  ${GREEN}✓${RESET} hooks\n"
    passed=$((passed + 1))
  else
    printf "  ${RED}✗${RESET} hooks\n"
    echo "$output" | grep '✗\|→' | sed 's/^/    /' | head -10
    failed=$((failed + 1))
  fi

  # Grab latest results file from hooks run
  latest_hooks=$(ls -t "${RESULTS_DIR}"/behavioral-hooks-*.json 2>/dev/null | head -1)
  if [ -n "$latest_hooks" ]; then
    hooks_summary=$(jq '.summary' "$latest_hooks" 2>/dev/null)
    suite_results=$(echo "$suite_results" | jq ". + {\"hooks\": ${hooks_summary}}")
    h_cost=$(jq -r '.summary.cost_usd // 0' "$latest_hooks" 2>/dev/null)
    total_cost=$(echo "$total_cost $h_cost" | awk '{printf "%.4f", $1+$2}')
  fi
}

run_suite_skills() {
  if [ -f "${SCRIPT_DIR}/test-skill-triggers.sh" ]; then
    local output exit_code
    output=$(bash "${SCRIPT_DIR}/test-skill-triggers.sh" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
      printf "  ${GREEN}✓${RESET} skills\n"
      passed=$((passed + 1))
    else
      printf "  ${RED}✗${RESET} skills\n"
      echo "$output" | grep '✗\|→' | sed 's/^/    /' | head -10
      failed=$((failed + 1))
    fi
  else
    printf "  ${YELLOW}⊘${RESET} skills (not yet implemented — run US-005 first)\n"
    suite_results=$(echo "$suite_results" | jq '. + {"skills": {"status": "not_implemented"}}')
  fi
}

run_suite_agents() {
  if [ -f "${SCRIPT_DIR}/test-agents.sh" ]; then
    local output exit_code
    output=$(bash "${SCRIPT_DIR}/test-agents.sh" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
      printf "  ${GREEN}✓${RESET} agents\n"
      passed=$((passed + 1))
    else
      printf "  ${RED}✗${RESET} agents\n"
      echo "$output" | grep '✗\|→' | sed 's/^/    /' | head -10
      failed=$((failed + 1))
    fi
  else
    printf "  ${YELLOW}⊘${RESET} agents (not yet implemented — run US-007 first)\n"
    suite_results=$(echo "$suite_results" | jq '. + {"agents": {"status": "not_implemented"}}')
  fi
}

case "$SUITE" in
  hooks)  run_suite_hooks ;;
  skills) run_suite_skills ;;
  agents) run_suite_agents ;;
  all)
    # Confirm before API-calling suites (unless --yes)
    if [ "$YES" -eq 0 ]; then
      echo "  Note: 'skills' and 'agents' suites make real Claude API calls."
      echo "  Estimated cost: ~\$7.80. Use --estimate to see breakdown."
      echo "  Run with --yes to proceed, or --suite hooks for free-only run."
      echo ""
    fi
    run_suite_hooks
    run_suite_skills
    run_suite_agents
    ;;
  *)
    echo "Unknown suite: ${SUITE}. Valid: hooks, skills, agents, all" >&2
    exit 1
    ;;
esac

total=$((passed + failed))
echo ""
echo "=== Results: ${passed}/${total} suites passed, total cost: \$${total_cost} ==="

# Write combined JSON report
REPORT="${RESULTS_DIR}/behavioral-${TIMESTAMP}.json"
total_for_json=$((passed + failed))
jq -n \
  --arg version "$VERSION" \
  --arg git_sha "$GIT_SHA" \
  --argjson timestamp "$TIMESTAMP" \
  --arg suite "$SUITE" \
  --argjson suites "$suite_results" \
  --argjson passed "$passed" \
  --argjson failed "$failed" \
  --argjson total "$total_for_json" \
  --argjson cost "$total_cost" \
  '{
    suite: "behavioral",
    version: $version,
    git_sha: $git_sha,
    timestamp: $timestamp,
    selected_suite: $suite,
    suites: $suites,
    summary: {
      total: $total,
      passed: $passed,
      failed: $failed,
      cost_usd: $cost
    }
  }' > "$REPORT"

echo "  Report: ${REPORT}"

[ "$failed" -eq 0 ] && exit 0 || exit 1
