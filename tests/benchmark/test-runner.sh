#!/usr/bin/env bash
# test-runner.sh — Tests for run-benchmark.sh
#
# Tests the runner in --dry-run mode to validate:
# - CLI parsing and story filtering
# - Worktree creation/cleanup
# - Trace and result generation
# - Score computation
# - Summary generation
#
# Usage: bash tests/benchmark/test-runner.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER="$SCRIPT_DIR/run-benchmark.sh"

PASS=0
FAIL=0

# ─── Helpers ────────────────────────────────

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [ -f "$path" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_dir_exists() {
  local label="$1" path="$2"
  if [ -d "$path" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (directory not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local label="$1" file="$2" query="$3" expected="$4"
  local actual
  actual=$(jq -r "$query" "$file" 2>/dev/null || echo "PARSE_ERROR")
  if [ "$actual" = "$expected" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_gt() {
  local label="$1" file="$2" query="$3" threshold="$4"
  local actual
  actual=$(jq -r "$query" "$file" 2>/dev/null || echo "0")
  local cmp
  cmp=$(echo "$actual > $threshold" | bc 2>/dev/null || echo "0")
  if [ "$cmp" -eq 1 ]; then
    echo "  PASS: $label ($actual > $threshold)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label ($actual not > $threshold)"
    FAIL=$((FAIL + 1))
  fi
}

cleanup() {
  if [ -n "${TEST_OUTPUT:-}" ] && [ -d "$TEST_OUTPUT" ]; then
    rm -rf "$TEST_OUTPUT"
  fi
}

trap cleanup EXIT

# ─── Test 1: Dry run with all stories ───────

echo "Test 1: Dry run — all stories, taskplex only"

TEST_OUTPUT="${TMPDIR:-/tmp}/benchmark-test-$$-all"
bash "$RUNNER" --dry-run --plugins taskplex --output "$TEST_OUTPUT" 2>&1 | tail -5

assert_dir_exists "Output directory created" "$TEST_OUTPUT"
assert_file_exists "meta.json created" "$TEST_OUTPUT/meta.json"
assert_json_field "meta: dry_run is true" "$TEST_OUTPUT/meta.json" '.dry_run' 'true'
assert_json_field "meta: plugins includes taskplex" "$TEST_OUTPUT/meta.json" '.plugins[0]' 'taskplex'

# Count trace files
trace_count=$(ls "$TEST_OUTPUT/traces/"*-taskplex-trace.json 2>/dev/null | wc -l | tr -d ' ')
assert_eq "30 trace files generated" "30" "$trace_count"

# Count result files
result_count=$(ls "$TEST_OUTPUT/results/"*-taskplex-result.json 2>/dev/null | wc -l | tr -d ' ')
assert_eq "30 result files generated" "30" "$result_count"

# Count score files
score_count=$(ls "$TEST_OUTPUT/scores/"*-taskplex-score.json 2>/dev/null | wc -l | tr -d ' ')
assert_eq "30 score files generated" "30" "$score_count"

# Verify summary exists
assert_file_exists "summary.json created" "$TEST_OUTPUT/summary.json"
assert_json_field "summary: has taskplex stats" "$TEST_OUTPUT/summary.json" '.plugins.taskplex.stories_scored' '30'

rm -rf "$TEST_OUTPUT"

# ─── Test 2: Story ID filtering ─────────────

echo ""
echo "Test 2: Dry run — filtered by story IDs"

TEST_OUTPUT="${TMPDIR:-/tmp}/benchmark-test-$$-filter"
bash "$RUNNER" --dry-run --plugins taskplex --story-ids "S001,S002,S003" --output "$TEST_OUTPUT" 2>&1 | tail -3

filtered_count=$(ls "$TEST_OUTPUT/traces/"*-trace.json 2>/dev/null | wc -l | tr -d ' ')
assert_eq "3 traces for filtered stories" "3" "$filtered_count"

assert_file_exists "S001 trace exists" "$TEST_OUTPUT/traces/S001-taskplex-trace.json"
assert_file_exists "S002 trace exists" "$TEST_OUTPUT/traces/S002-taskplex-trace.json"
assert_file_exists "S003 trace exists" "$TEST_OUTPUT/traces/S003-taskplex-trace.json"

rm -rf "$TEST_OUTPUT"

# ─── Test 3: Tier filtering ─────────────────

echo ""
echo "Test 3: Dry run — filtered by tier T1"

TEST_OUTPUT="${TMPDIR:-/tmp}/benchmark-test-$$-tier"
bash "$RUNNER" --dry-run --plugins taskplex --tiers "T1" --output "$TEST_OUTPUT" 2>&1 | tail -3

# T1 has 6 stories (S001-S006)
t1_count=$(ls "$TEST_OUTPUT/traces/"*-trace.json 2>/dev/null | wc -l | tr -d ' ')
assert_eq "6 traces for T1 tier" "6" "$t1_count"

rm -rf "$TEST_OUTPUT"

# ─── Test 4: Dual plugin dry run ────────────

echo ""
echo "Test 4: Dry run — two plugins, single story"

TEST_OUTPUT="${TMPDIR:-/tmp}/benchmark-test-$$-dual"
bash "$RUNNER" --dry-run --plugins taskplex,superpowers --story-ids "S001" --output "$TEST_OUTPUT" 2>&1 | tail -5

assert_file_exists "taskplex trace" "$TEST_OUTPUT/traces/S001-taskplex-trace.json"
assert_file_exists "superpowers trace" "$TEST_OUTPUT/traces/S001-superpowers-trace.json"
assert_file_exists "taskplex result" "$TEST_OUTPUT/results/S001-taskplex-result.json"
assert_file_exists "superpowers result" "$TEST_OUTPUT/results/S001-superpowers-result.json"

# Verify dry_run flag in trace
assert_json_field "taskplex trace has dry_run" "$TEST_OUTPUT/traces/S001-taskplex-trace.json" '.dry_run' 'true'

rm -rf "$TEST_OUTPUT"

# ─── Test 5: Score file structure ────────────

echo ""
echo "Test 5: Score file structure validation"

TEST_OUTPUT="${TMPDIR:-/tmp}/benchmark-test-$$-score"
bash "$RUNNER" --dry-run --plugins taskplex --story-ids "S001" --output "$TEST_OUTPUT" 2>&1 | tail -2

SCORE_FILE="$TEST_OUTPUT/scores/S001-taskplex-score.json"
assert_file_exists "Score file exists" "$SCORE_FILE"

if [ -f "$SCORE_FILE" ]; then
  # Validate score structure
  assert_json_field "has story_id" "$SCORE_FILE" '.story_id' 'S001'
  assert_json_field "has plugin" "$SCORE_FILE" '.plugin' 'taskplex'

  # Validate dimensions are present (even if 0 for dry run)
  d_val=$(jq '.scores.discipline' "$SCORE_FILE")
  c_val=$(jq '.scores.correctness' "$SCORE_FILE")
  a_val=$(jq '.scores.autonomy' "$SCORE_FILE")
  e_val=$(jq '.scores.efficiency' "$SCORE_FILE")
  dq_val=$(jq '.scores.dq' "$SCORE_FILE")

  # In dry-run mode scores will be low but should be valid numbers
  for field in "$d_val" "$c_val" "$a_val" "$e_val" "$dq_val"; do
    if echo "$field" | grep -qE '^[0-9]'; then
      true  # valid number
    else
      echo "  FAIL: Score field is not a number: $field"
      FAIL=$((FAIL + 1))
    fi
  done
  echo "  PASS: All score dimensions are valid numbers"
  PASS=$((PASS + 1))
fi

rm -rf "$TEST_OUTPUT"

# ─── Test 6: Result file metrics ────────────

echo ""
echo "Test 6: Result file metrics structure"

TEST_OUTPUT="${TMPDIR:-/tmp}/benchmark-test-$$-result"
bash "$RUNNER" --dry-run --plugins taskplex --story-ids "S002" --output "$TEST_OUTPUT" 2>&1 | tail -2

RESULT_FILE="$TEST_OUTPUT/results/S002-taskplex-result.json"
assert_file_exists "Result file exists" "$RESULT_FILE"

if [ -f "$RESULT_FILE" ]; then
  assert_json_field "result: story_id" "$RESULT_FILE" '.story_id' 'S002'
  assert_json_field "result: tier" "$RESULT_FILE" '.tier' 'T1'
  assert_json_field "result: plugin" "$RESULT_FILE" '.plugin' 'taskplex'
  assert_json_field "result: dry_run" "$RESULT_FILE" '.dry_run' 'true'
  assert_json_field "result: has metrics" "$RESULT_FILE" '.metrics | type' 'object'
  assert_json_field "result: has tests_pass" "$RESULT_FILE" '.metrics.tests_pass | type' 'boolean'
  assert_json_field "result: has tdd_applicable" "$RESULT_FILE" '.metrics.tdd_applicable | type' 'boolean'
fi

rm -rf "$TEST_OUTPUT"

# ─── Summary ────────────────────────────────

echo ""
echo "═══════════════════════════════════════"
echo "  Runner tests: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════"

exit "$FAIL"
