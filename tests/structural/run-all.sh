#!/usr/bin/env bash
# US-004: Structural Test Runner and Reporting
# Runs all structural validators and produces terminal + JSON output
# Usage: bash tests/structural/run-all.sh
# Exit 0: all tests pass | Exit 1: any failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/results"

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

mkdir -p "$RESULTS_DIR"

VERSION=$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)
GIT_SHA=$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null)
TIMESTAMP=$(date +%s)

echo "=== Structural Test Suite v${VERSION} (${GIT_SHA}) ==="
echo ""

# Run each validator; capture output and exit code
run_test() {
  local name="$1" script="$2"
  local output exit_code

  # Run silently, capture output and exit code
  output=$(bash "$script" 2>&1) && exit_code=0 || exit_code=$?

  if [ "$exit_code" -eq 0 ]; then
    printf "  ${GREEN}✓${RESET} %s\n" "$name"
  else
    printf "  ${RED}✗${RESET} %s\n" "$name"
    # Indent failures from the test output
    echo "$output" | grep '✗\|→\|FAIL\|Error\|failed' | sed 's/^/    /' | head -10
  fi

  echo "$exit_code"
}

# Tests to run (name|script pairs)
tests="cross-refs|${SCRIPT_DIR}/test-cross-refs.sh"

passed=0
failed=0
tests_json="[]"

while IFS='|' read -r test_name test_script; do
  [ -z "$test_name" ] && continue

  if [ ! -f "$test_script" ]; then
    printf "  ${RED}✗${RESET} %s (script not found)\n" "$test_name"
    tests_json=$(echo "$tests_json" | jq ". + [{\"name\":\"${test_name}\",\"status\":\"error\",\"failures\":[\"script not found\"]}]")
    failed=$((failed + 1))
    continue
  fi

  # Capture output for JSON extraction
  raw_output=$(bash "$test_script" 2>&1) && ec=0 || ec=$?

  if [ "$ec" -eq 0 ]; then
    printf "  ${GREEN}✓${RESET} %s\n" "$test_name"
    passed=$((passed + 1))
    tests_json=$(echo "$tests_json" | jq ". + [{\"name\":\"${test_name}\",\"status\":\"pass\",\"failures\":[]}]")
  else
    printf "  ${RED}✗${RESET} %s\n" "$test_name"
    failed=$((failed + 1))
    # Extract failure lines (lines with ✗ marker)
    failure_lines=$(echo "$raw_output" | grep '✗' | sed 's/.*✗[[:space:]]*//' | head -20)
    failures_arr=$(echo "$failure_lines" | jq -R . | jq -s .)
    tests_json=$(echo "$tests_json" | jq ". + [{\"name\":\"${test_name}\",\"status\":\"fail\",\"failures\":${failures_arr}}]")
    # Show failures indented
    echo "$raw_output" | grep '✗\|→' | sed 's/^/    /' | head -15
  fi
done <<EOF
$tests
EOF

total=$((passed + failed))
echo ""
echo "=== Results: ${passed}/${total} passed ==="

# Write JSON report
REPORT="${RESULTS_DIR}/structural-${TIMESTAMP}.json"
jq -n \
  --arg version "$VERSION" \
  --arg git_sha "$GIT_SHA" \
  --argjson timestamp "$TIMESTAMP" \
  --argjson tests "$tests_json" \
  --arg suite "structural" \
  --argjson passed "$passed" \
  --argjson failed "$failed" \
  --argjson total "$total" \
  '{
    suite: $suite,
    version: $version,
    git_sha: $git_sha,
    timestamp: $timestamp,
    tests: $tests,
    summary: {
      total: $total,
      passed: $passed,
      failed: $failed
    }
  }' > "$REPORT"

echo "  Report: ${REPORT}"

[ "$failed" -eq 0 ] && exit 0 || exit 1
