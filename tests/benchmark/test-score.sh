#!/usr/bin/env bash
# test-score.sh — Validate the scoring engine with synthetic data
#
# Usage: ./tests/benchmark/test-score.sh
# Runs from project root (taskplex/)
#
# Creates synthetic trace + result files, runs score.sh, verifies output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCORE_SH="$SCRIPT_DIR/score.sh"
TMPDIR_TEST=$(mktemp -d "${TMPDIR:-/tmp}/benchmark-test.XXXXXX")

pass_count=0
fail_count=0
total_count=0

# ─────────────────────────────────────────────
# Test helpers
# ─────────────────────────────────────────────

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  total_count=$((total_count + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (expected=$expected, actual=$actual)"
    fail_count=$((fail_count + 1))
  fi
}

# Numeric equality with tolerance (handles bc formatting differences)
assert_numeq() {
  local label="$1" expected="$2" actual="$3" tolerance="${4:-0.001}"
  total_count=$((total_count + 1))
  local diff
  diff=$(echo "scale=6; d=$actual - $expected; if (d < 0) -1*d else d" | bc 2>/dev/null || echo "999")
  local ok
  ok=$(echo "$diff <= $tolerance" | bc)
  if [ "$ok" -eq 1 ]; then
    echo "  PASS: $label ($actual ≈ $expected)"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label (expected≈$expected, actual=$actual, diff=$diff)"
    fail_count=$((fail_count + 1))
  fi
}

assert_range() {
  local label="$1" min="$2" max="$3" actual="$4"
  total_count=$((total_count + 1))
  local in_range
  in_range=$(echo "$actual >= $min && $actual <= $max" | bc -l)
  if [ "$in_range" -eq 1 ]; then
    echo "  PASS: $label ($actual in [$min, $max])"
    pass_count=$((pass_count + 1))
  else
    echo "  FAIL: $label ($actual NOT in [$min, $max])"
    fail_count=$((fail_count + 1))
  fi
}

# ─────────────────────────────────────────────
# Test 1: Perfect TaskPlex run (all metrics pass)
# ─────────────────────────────────────────────

test_perfect_taskplex() {
  echo "Test 1: Perfect TaskPlex run"

  local trace="$TMPDIR_TEST/trace-perfect.json"
  local result="$TMPDIR_TEST/result-perfect.json"

  # Create perfect trace (all events fire correctly)
  cat > "$trace" <<'EOF'
{
  "story_id": "S001",
  "plugin": "taskplex",
  "events": [
    {"event": "skill_invoked", "skill": "using-taskplex", "phase": "startup"},
    {"event": "skill_invoked", "skill": "taskplex-tdd", "phase": "execution"},
    {"event": "agent_dispatched", "agent": "implementer", "for_story": "S001"},
    {"event": "commit_created", "message": "test: add tests for config validation", "files_changed": 1},
    {"event": "commit_created", "message": "feat: add config validation", "files_changed": 2},
    {"event": "test_executed", "command": "npm test", "pass": true, "phase": "pre_completion"},
    {"event": "skill_invoked", "skill": "taskplex-verify", "phase": "pre_completion"},
    {"event": "skill_invoked", "skill": "requesting-code-review", "phase": "review"},
    {"event": "agent_dispatched", "agent": "spec-reviewer", "for_story": "S001"},
    {"event": "hook_fired", "hook": "session-context", "result": "ok", "hook_event": "SessionStart"},
    {"event": "completion_claimed", "verified": true}
  ]
}
EOF

  # Create perfect result
  cat > "$result" <<'EOF'
{
  "story_id": "S001",
  "plugin": "taskplex",
  "plugin_version": "3.1.0",
  "tier": "T2",
  "metrics": {
    "tdd_applicable": true,
    "tdd_sequence_observed": true,
    "turns": 35,
    "tokens_used": 80000,
    "wall_clock_seconds": 120,
    "retries": 0
  },
  "budgets": {
    "max_turns": 200,
    "token_budget": 500000,
    "timeout_seconds": 900,
    "max_retries": 3
  },
  "commands": {
    "test_command": "npm test",
    "build_command": "npm run build",
    "typecheck_command": "tsc --noEmit"
  },
  "results": {
    "tests_pass": true,
    "build_pass": true,
    "typecheck_pass": true,
    "acceptance_criteria_total": 4,
    "acceptance_criteria_met": 4,
    "regressions": 0,
    "syntax_errors": 0,
    "fully_autonomous": true
  }
}
EOF

  local output
  output=$(bash "$SCORE_SH" "$trace" "$result")

  # Verify composite DQ is high (should be close to 1.0)
  local dq
  dq=$(echo "$output" | jq -r '.scores.dq')
  assert_range "DQ score is high" "0.85" "1.0" "$dq"

  # Verify all dimensions are high
  local d c a e
  d=$(echo "$output" | jq -r '.scores.discipline')
  c=$(echo "$output" | jq -r '.scores.correctness')
  a=$(echo "$output" | jq -r '.scores.autonomy')
  e=$(echo "$output" | jq -r '.scores.efficiency')

  assert_range "Discipline high" "0.8" "1.0" "$d"
  assert_range "Correctness high" "0.9" "1.0" "$c"
  assert_range "Autonomy high" "0.9" "1.0" "$a"
  assert_range "Efficiency high" "0.7" "1.0" "$e"

  # Verify metadata
  assert_eq "Plugin is taskplex" "taskplex" "$(echo "$output" | jq -r '.plugin')"
  assert_eq "Story is S001" "S001" "$(echo "$output" | jq -r '.story_id')"
}

# ─────────────────────────────────────────────
# Test 2: Minimal Superpowers run (fewer metrics pass)
# ─────────────────────────────────────────────

test_minimal_superpowers() {
  echo "Test 2: Minimal Superpowers run"

  local trace="$TMPDIR_TEST/trace-minimal.json"
  local result="$TMPDIR_TEST/result-minimal.json"

  # Superpowers trace: no spec review, no stop guard, no TDD sequence
  cat > "$trace" <<'EOF'
{
  "story_id": "S002",
  "plugin": "superpowers",
  "events": [
    {"event": "skill_invoked", "skill": "using-superpowers", "phase": "startup"},
    {"event": "commit_created", "message": "feat: add config validation", "files_changed": 3},
    {"event": "test_executed", "command": "npm test", "pass": true, "phase": "post_completion"},
    {"event": "human_intervention", "reason": "user provided clarification"},
    {"event": "completion_claimed", "verified": false}
  ]
}
EOF

  cat > "$result" <<'EOF'
{
  "story_id": "S002",
  "plugin": "superpowers",
  "plugin_version": "4.3.1",
  "tier": "T2",
  "metrics": {
    "tdd_applicable": true,
    "tdd_sequence_observed": false,
    "turns": 85,
    "tokens_used": 250000,
    "wall_clock_seconds": 400,
    "retries": 2
  },
  "budgets": {
    "max_turns": 200,
    "token_budget": 500000,
    "timeout_seconds": 900,
    "max_retries": 3
  },
  "commands": {
    "test_command": "npm test",
    "build_command": "npm run build",
    "typecheck_command": "tsc --noEmit"
  },
  "results": {
    "tests_pass": true,
    "build_pass": true,
    "typecheck_pass": false,
    "acceptance_criteria_total": 4,
    "acceptance_criteria_met": 3,
    "regressions": 0,
    "syntax_errors": 0,
    "fully_autonomous": false
  }
}
EOF

  local output
  output=$(bash "$SCORE_SH" "$trace" "$result")

  local dq d c a e
  dq=$(echo "$output" | jq -r '.scores.dq')
  d=$(echo "$output" | jq -r '.scores.discipline')
  c=$(echo "$output" | jq -r '.scores.correctness')
  a=$(echo "$output" | jq -r '.scores.autonomy')
  e=$(echo "$output" | jq -r '.scores.efficiency')

  # Should be lower than perfect run
  assert_range "DQ score moderate" "0.30" "0.70" "$dq"
  assert_range "Discipline low (no TDD, no review, no pre-completion verification)" "0.1" "0.5" "$d"
  assert_range "Correctness moderate (typecheck failed)" "0.6" "0.9" "$c"
  assert_range "Autonomy low (human intervention)" "0.0" "0.5" "$a"
  assert_range "Efficiency moderate" "0.3" "0.7" "$e"

  # Verify D4 and D5 are null (Superpowers doesn't have these)
  local d4 d5
  d4=$(echo "$output" | jq -r '.dimensions.discipline.metrics.D4_spec_review')
  d5=$(echo "$output" | jq -r '.dimensions.discipline.metrics.D5_stop_guard')
  assert_eq "D4 is null for Superpowers" "null" "$d4"
  assert_eq "D5 is null for Superpowers" "null" "$d5"
}

# ─────────────────────────────────────────────
# Test 3: Error recovery scenario
# ─────────────────────────────────────────────

test_error_recovery() {
  echo "Test 3: Error recovery scenario"

  local trace="$TMPDIR_TEST/trace-recovery.json"
  local result="$TMPDIR_TEST/result-recovery.json"

  cat > "$trace" <<'EOF'
{
  "story_id": "S003",
  "plugin": "taskplex",
  "events": [
    {"event": "skill_invoked", "skill": "using-taskplex", "phase": "startup"},
    {"event": "skill_invoked", "skill": "taskplex-tdd", "phase": "execution"},
    {"event": "error_occurred", "error_type": "test_failure", "message": "TypeError: cannot read property"},
    {"event": "skill_invoked", "skill": "systematic-debugging", "phase": "debug"},
    {"event": "error_recovered", "error_type": "test_failure", "strategy": "fix_and_retry"},
    {"event": "error_occurred", "error_type": "build_failure", "message": "Module not found"},
    {"event": "error_recovered", "error_type": "build_failure", "strategy": "install_deps"},
    {"event": "test_executed", "command": "npm test", "pass": true, "phase": "pre_completion"},
    {"event": "skill_invoked", "skill": "taskplex-verify", "phase": "pre_completion"},
    {"event": "skill_invoked", "skill": "requesting-code-review", "phase": "review"},
    {"event": "agent_dispatched", "agent": "spec-reviewer", "for_story": "S003"},
    {"event": "completion_claimed", "verified": true}
  ]
}
EOF

  cat > "$result" <<'EOF'
{
  "story_id": "S003",
  "plugin": "taskplex",
  "plugin_version": "3.1.0",
  "tier": "T3",
  "metrics": {
    "tdd_applicable": true,
    "tdd_sequence_observed": true,
    "turns": 95,
    "tokens_used": 200000,
    "wall_clock_seconds": 350,
    "retries": 2
  },
  "budgets": {
    "max_turns": 200,
    "token_budget": 500000,
    "timeout_seconds": 900,
    "max_retries": 3
  },
  "commands": {
    "test_command": "npm test",
    "build_command": "npm run build",
    "typecheck_command": "tsc --noEmit"
  },
  "results": {
    "tests_pass": true,
    "build_pass": true,
    "typecheck_pass": true,
    "acceptance_criteria_total": 7,
    "acceptance_criteria_met": 7,
    "regressions": 0,
    "syntax_errors": 0,
    "fully_autonomous": true
  }
}
EOF

  local output
  output=$(bash "$SCORE_SH" "$trace" "$result")

  local dq a2
  dq=$(echo "$output" | jq -r '.scores.dq')
  a2=$(echo "$output" | jq -r '.dimensions.autonomy.metrics.A2_error_recovery_rate')

  # Despite errors, should score well due to recovery
  assert_range "DQ good despite errors" "0.70" "1.0" "$dq"
  assert_numeq "Full error recovery (2/2)" "1" "$a2"

  # D7: debugging before fix should be true
  local d7
  d7=$(echo "$output" | jq -r '.dimensions.discipline.metrics.D7_debug_before_fix')
  assert_eq "D7 debug-before-fix true" "true" "$d7"
}

# ─────────────────────────────────────────────
# Test 4: Head-to-head comparison math
# ─────────────────────────────────────────────

test_comparison_math() {
  echo "Test 4: DQ weight math verification"

  # DQ = 0.35*D + 0.35*C + 0.20*A + 0.10*E
  # With D=1.0, C=1.0, A=1.0, E=1.0 → DQ should = 1.0
  # With D=0.5, C=0.5, A=0.5, E=0.5 → DQ should = 0.5

  local trace="$TMPDIR_TEST/trace-math.json"
  local result="$TMPDIR_TEST/result-math.json"

  # Create a trace that gives D=1.0 (all discipline metrics pass for Superpowers)
  cat > "$trace" <<'EOF'
{
  "story_id": "S010",
  "plugin": "superpowers",
  "events": [
    {"event": "skill_invoked", "skill": "using-superpowers", "phase": "startup"},
    {"event": "skill_invoked", "skill": "test-driven-development", "phase": "execution"},
    {"event": "test_executed", "command": "npm test", "pass": true, "phase": "pre_completion"},
    {"event": "skill_invoked", "skill": "requesting-code-review", "phase": "review"},
    {"event": "completion_claimed", "verified": true}
  ]
}
EOF

  cat > "$result" <<'EOF'
{
  "story_id": "S010",
  "plugin": "superpowers",
  "plugin_version": "4.3.1",
  "tier": "T1",
  "metrics": {
    "tdd_applicable": true,
    "tdd_sequence_observed": true,
    "turns": 10,
    "tokens_used": 20000,
    "wall_clock_seconds": 30,
    "retries": 0
  },
  "budgets": {
    "max_turns": 200,
    "token_budget": 500000,
    "timeout_seconds": 900,
    "max_retries": 3
  },
  "commands": {
    "test_command": "npm test",
    "build_command": "npm run build",
    "typecheck_command": "tsc --noEmit"
  },
  "results": {
    "tests_pass": true,
    "build_pass": true,
    "typecheck_pass": true,
    "acceptance_criteria_total": 2,
    "acceptance_criteria_met": 2,
    "regressions": 0,
    "syntax_errors": 0,
    "fully_autonomous": true
  }
}
EOF

  local output
  output=$(bash "$SCORE_SH" "$trace" "$result")

  local dq d c a e
  dq=$(echo "$output" | jq -r '.scores.dq')
  d=$(echo "$output" | jq -r '.scores.discipline')
  c=$(echo "$output" | jq -r '.scores.correctness')
  a=$(echo "$output" | jq -r '.scores.autonomy')
  e=$(echo "$output" | jq -r '.scores.efficiency')

  # Verify the weighted formula
  local expected_dq
  expected_dq=$(echo "scale=4; 0.35 * $d + 0.35 * $c + 0.20 * $a + 0.10 * $e" | bc)
  assert_numeq "DQ matches weighted formula" "$expected_dq" "$dq"

  # Verify weights are in output
  assert_numeq "Weight discipline" "0.35" "$(echo "$output" | jq -r '.weights.discipline')"
  assert_numeq "Weight correctness" "0.35" "$(echo "$output" | jq -r '.weights.correctness')"
  assert_numeq "Weight autonomy" "0.20" "$(echo "$output" | jq -r '.weights.autonomy')"
  assert_numeq "Weight efficiency" "0.10" "$(echo "$output" | jq -r '.weights.efficiency')"
}

# ─────────────────────────────────────────────
# Run all tests
# ─────────────────────────────────────────────

echo "═══════════════════════════════════════════"
echo "  Benchmark Scoring Engine — Test Suite"
echo "═══════════════════════════════════════════"
echo ""

test_perfect_taskplex
echo ""
test_minimal_superpowers
echo ""
test_error_recovery
echo ""
test_comparison_math

echo ""
echo "═══════════════════════════════════════════"
echo "  Results: $pass_count passed, $fail_count failed, $total_count total"
echo "═══════════════════════════════════════════"

# Clean up
rm -rf "$TMPDIR_TEST"

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
