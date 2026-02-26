#!/usr/bin/env bash
# score.sh — Scoring engine for TaskPlex benchmark
# Reads a trace file + result metadata, outputs DQ score JSON
#
# Usage: ./score.sh <trace-file> <result-file>
# Output: JSON with per-dimension scores and composite DQ
#
# Dependencies: jq, bash 3.2+

set -euo pipefail

TRACE_FILE="${1:?Usage: score.sh <trace-file> <result-file>}"
RESULT_FILE="${2:?Usage: score.sh <trace-file> <result-file>}"

# Weights
W_DISCIPLINE=0.35
W_CORRECTNESS=0.35
W_AUTONOMY=0.20
W_EFFICIENCY=0.10

# ─────────────────────────────────────────────
# Dimension 1: Discipline Compliance (D)
# ─────────────────────────────────────────────

score_discipline() {
  local trace="$1"
  local result="$2"
  local plugin
  plugin=$(jq -r '.plugin' "$result")

  local passed=0
  local applicable=0

  # D1: TDD sequence — test commit before implementation commit
  local d1="null"
  if jq -e '.metrics.tdd_applicable' "$result" >/dev/null 2>&1; then
    applicable=$((applicable + 1))
    if jq -e '.metrics.tdd_sequence_observed == true' "$result" >/dev/null 2>&1; then
      d1="true"
      passed=$((passed + 1))
    else
      d1="false"
    fi
  fi

  # D2: Verification before completion
  local d2="null"
  applicable=$((applicable + 1))
  if jq -e '[.events[] | select(.event == "test_executed" and .phase == "pre_completion")] | length > 0' "$trace" >/dev/null 2>&1; then
    d2="true"
    passed=$((passed + 1))
  else
    d2="false"
  fi

  # D3: Code review executed
  local d3="null"
  applicable=$((applicable + 1))
  local review_count
  review_count=$(jq '[.events[] | select(.event == "skill_invoked" and (.skill | test("code.review|requesting-code-review")))] | length' "$trace" 2>/dev/null || echo "0")
  if [ "$review_count" -gt 0 ]; then
    d3="true"
    passed=$((passed + 1))
  else
    d3="false"
  fi

  # D4: Spec review (TaskPlex-specific)
  local d4="null"
  if [ "$plugin" = "taskplex" ]; then
    applicable=$((applicable + 1))
    local spec_count
    spec_count=$(jq '[.events[] | select(.event == "agent_dispatched" and .agent == "spec-reviewer")] | length' "$trace" 2>/dev/null || echo "0")
    if [ "$spec_count" -gt 0 ]; then
      d4="true"
      passed=$((passed + 1))
    else
      d4="false"
    fi
  fi

  # D5: Stop guard respected (TaskPlex-specific)
  local d5="null"
  if [ "$plugin" = "taskplex" ]; then
    applicable=$((applicable + 1))
    local premature_stops
    premature_stops=$(jq '[.events[] | select(.event == "hook_fired" and .hook == "stop-guard" and .result == "blocked")] | length' "$trace" 2>/dev/null || echo "0")
    # If stop guard never had to block, that's also good (agent didn't try to exit early)
    local stop_attempts
    stop_attempts=$(jq '[.events[] | select(.event == "hook_fired" and .hook == "stop-guard")] | length' "$trace" 2>/dev/null || echo "0")
    if [ "$stop_attempts" -eq 0 ] || [ "$premature_stops" -gt 0 ]; then
      d5="true"
      passed=$((passed + 1))
    else
      d5="false"
    fi
  fi

  # D6: Skill routing gate fired
  local d6="null"
  applicable=$((applicable + 1))
  local gate_count
  gate_count=$(jq '[.events[] | select(.event == "skill_invoked" and (.skill | test("using-taskplex|using-superpowers")))] | length' "$trace" 2>/dev/null || echo "0")
  if [ "$gate_count" -gt 0 ]; then
    d6="true"
    passed=$((passed + 1))
  else
    d6="false"
  fi

  # D7: Debugging before fix (only if errors occurred)
  local d7="null"
  local error_count
  error_count=$(jq '[.events[] | select(.event == "error_occurred")] | length' "$trace" 2>/dev/null || echo "0")
  if [ "$error_count" -gt 0 ]; then
    applicable=$((applicable + 1))
    local debug_before_fix
    debug_before_fix=$(jq '[.events[] | select(.event == "skill_invoked" and (.skill | test("systematic-debugging|debugging")))] | length' "$trace" 2>/dev/null || echo "0")
    if [ "$debug_before_fix" -gt 0 ]; then
      d7="true"
      passed=$((passed + 1))
    else
      d7="false"
    fi
  fi

  # Calculate score
  local score="0"
  if [ "$applicable" -gt 0 ]; then
    score=$(echo "scale=4; $passed / $applicable" | bc)
  fi

  # Output JSON fragment
  cat <<EOF
{
  "score": $score,
  "passed": $passed,
  "applicable": $applicable,
  "metrics": {
    "D1_tdd_sequence": $d1,
    "D2_verification": $d2,
    "D3_code_review": $d3,
    "D4_spec_review": $d4,
    "D5_stop_guard": $d5,
    "D6_skill_routing": $d6,
    "D7_debug_before_fix": $d7
  }
}
EOF
}

# ─────────────────────────────────────────────
# Dimension 2: Output Correctness (C)
# ─────────────────────────────────────────────

score_correctness() {
  local result="$1"

  # Use bc for all arithmetic since C4 introduces fractions
  local passed="0"
  local applicable=0

  # C1: Tests pass
  local c1="null"
  if jq -e '.commands.test_command != ""' "$result" >/dev/null 2>&1; then
    applicable=$((applicable + 1))
    if jq -e '.results.tests_pass == true' "$result" >/dev/null 2>&1; then
      c1="true"
      passed=$(echo "scale=4; $passed + 1" | bc)
    else
      c1="false"
    fi
  fi

  # C2: Build succeeds
  local c2="null"
  if jq -e '.commands.build_command != ""' "$result" >/dev/null 2>&1; then
    applicable=$((applicable + 1))
    if jq -e '.results.build_pass == true' "$result" >/dev/null 2>&1; then
      c2="true"
      passed=$(echo "scale=4; $passed + 1" | bc)
    else
      c2="false"
    fi
  fi

  # C3: Typecheck passes
  local c3="null"
  if jq -e '.commands.typecheck_command != ""' "$result" >/dev/null 2>&1; then
    applicable=$((applicable + 1))
    if jq -e '.results.typecheck_pass == true' "$result" >/dev/null 2>&1; then
      c3="true"
      passed=$(echo "scale=4; $passed + 1" | bc)
    else
      c3="false"
    fi
  fi

  # C4: Acceptance criteria met (fraction)
  local c4="null"
  local ac_total
  ac_total=$(jq '.results.acceptance_criteria_total // 0' "$result" 2>/dev/null)
  if [ "$ac_total" -gt 0 ]; then
    applicable=$((applicable + 1))
    local ac_met
    ac_met=$(jq '.results.acceptance_criteria_met // 0' "$result" 2>/dev/null)
    c4=$(echo "scale=4; $ac_met / $ac_total" | bc)
    passed=$(echo "scale=4; $passed + $c4" | bc)
  fi

  # C5: No regressions
  local c5="null"
  applicable=$((applicable + 1))
  if jq -e '.results.regressions == 0' "$result" >/dev/null 2>&1; then
    c5="true"
    passed=$(echo "scale=4; $passed + 1" | bc)
  else
    c5="false"
  fi

  # C6: Code compiles
  local c6="null"
  applicable=$((applicable + 1))
  if jq -e '.results.syntax_errors == 0' "$result" >/dev/null 2>&1; then
    c6="true"
    passed=$(echo "scale=4; $passed + 1" | bc)
  else
    c6="false"
  fi

  local score="0"
  if [ "$applicable" -gt 0 ]; then
    score=$(echo "scale=4; $passed / $applicable" | bc)
  fi

  cat <<EOF
{
  "score": $score,
  "passed": $passed,
  "applicable": $applicable,
  "metrics": {
    "C1_tests_pass": $c1,
    "C2_build_succeeds": $c2,
    "C3_typecheck_passes": $c3,
    "C4_acceptance_criteria": $c4,
    "C5_no_regressions": $c5,
    "C6_code_compiles": $c6
  }
}
EOF
}

# ─────────────────────────────────────────────
# Dimension 3: Autonomy Rate (A)
# ─────────────────────────────────────────────

score_autonomy() {
  local trace="$1"
  local result="$2"

  local passed=0

  # A1: No human intervention
  local a1="false"
  local human_count
  human_count=$(jq '[.events[] | select(.event == "human_intervention")] | length' "$trace" 2>/dev/null || echo "0")
  if [ "$human_count" -eq 0 ]; then
    a1="true"
    passed=$((passed + 1))
  fi

  # A2: Error self-recovery rate
  local a2="0"
  local errors
  errors=$(jq '[.events[] | select(.event == "error_occurred")] | length' "$trace" 2>/dev/null || echo "0")
  if [ "$errors" -eq 0 ]; then
    a2="1"
    passed=$(echo "scale=4; $passed + 1" | bc)
  else
    local recovered
    recovered=$(jq '[.events[] | select(.event == "error_recovered")] | length' "$trace" 2>/dev/null || echo "0")
    a2=$(echo "scale=4; $recovered / $errors" | bc)
    passed=$(echo "scale=4; $passed + $a2" | bc)
  fi

  # A3: No permission blocks
  local a3="false"
  local perm_blocks
  perm_blocks=$(jq '[.events[] | select(.event == "permission_blocked")] | length' "$trace" 2>/dev/null || echo "0")
  if [ "$perm_blocks" -eq 0 ]; then
    a3="true"
    passed=$(echo "scale=4; $passed + 1" | bc)
  fi

  # A4: Fully autonomous story
  local a4="false"
  if jq -e '.results.fully_autonomous == true' "$result" >/dev/null 2>&1; then
    a4="true"
    passed=$(echo "scale=4; $passed + 1" | bc)
  fi

  local score
  score=$(echo "scale=4; $passed / 4" | bc)

  cat <<EOF
{
  "score": $score,
  "metrics": {
    "A1_no_human_input": $a1,
    "A2_error_recovery_rate": $a2,
    "A3_no_permission_blocks": $a3,
    "A4_fully_autonomous": $a4
  }
}
EOF
}

# ─────────────────────────────────────────────
# Dimension 4: Efficiency (E)
# ─────────────────────────────────────────────

score_efficiency() {
  local result="$1"

  # Read budgets and actuals
  local turns
  turns=$(jq '.metrics.turns // 0' "$result" 2>/dev/null)
  local max_turns
  max_turns=$(jq '.budgets.max_turns // 200' "$result" 2>/dev/null)
  local tokens
  tokens=$(jq '.metrics.tokens_used // 0' "$result" 2>/dev/null)
  local token_budget
  token_budget=$(jq '.budgets.token_budget // 500000' "$result" 2>/dev/null)
  local seconds
  seconds=$(jq '.metrics.wall_clock_seconds // 0' "$result" 2>/dev/null)
  local timeout
  timeout=$(jq '.budgets.timeout_seconds // 900' "$result" 2>/dev/null)
  local retries
  retries=$(jq '.metrics.retries // 0' "$result" 2>/dev/null)
  local max_retries
  max_retries=$(jq '.budgets.max_retries // 3' "$result" 2>/dev/null)

  # Normalize: 1 - min(actual/budget, 1)
  # Higher is better (fewer resources used)
  local e1 e2 e3 e4

  _clamp_efficiency() {
    local actual="$1" budget="$2"
    local ratio
    ratio=$(echo "scale=4; $actual / $budget" | bc)
    # Clamp ratio to [0, 1]
    local over
    over=$(echo "$ratio > 1" | bc)
    if [ "$over" -eq 1 ]; then
      ratio="1"
    fi
    echo "scale=4; 1 - $ratio" | bc
  }

  if [ "$max_turns" -gt 0 ]; then
    e1=$(_clamp_efficiency "$turns" "$max_turns")
  else
    e1="1"
  fi

  if [ "$token_budget" -gt 0 ]; then
    e2=$(_clamp_efficiency "$tokens" "$token_budget")
  else
    e2="1"
  fi

  if [ "$timeout" -gt 0 ]; then
    e3=$(_clamp_efficiency "$seconds" "$timeout")
  else
    e3="1"
  fi

  if [ "$max_retries" -gt 0 ]; then
    e4=$(_clamp_efficiency "$retries" "$max_retries")
  else
    e4="1"
  fi

  local score
  score=$(echo "scale=4; ($e1 + $e2 + $e3 + $e4) / 4" | bc)

  cat <<EOF
{
  "score": $score,
  "metrics": {
    "E1_turn_efficiency": $e1,
    "E2_token_efficiency": $e2,
    "E3_time_efficiency": $e3,
    "E4_retry_efficiency": $e4
  },
  "raw": {
    "turns": $turns,
    "max_turns": $max_turns,
    "tokens": $tokens,
    "token_budget": $token_budget,
    "seconds": $seconds,
    "timeout": $timeout,
    "retries": $retries,
    "max_retries": $max_retries
  }
}
EOF
}

# ─────────────────────────────────────────────
# Main: Compute composite DQ score
# ─────────────────────────────────────────────

main() {
  if [ ! -f "$TRACE_FILE" ]; then
    echo "Error: trace file not found: $TRACE_FILE" >&2
    exit 1
  fi
  if [ ! -f "$RESULT_FILE" ]; then
    echo "Error: result file not found: $RESULT_FILE" >&2
    exit 1
  fi

  local d_json c_json a_json e_json
  d_json=$(score_discipline "$TRACE_FILE" "$RESULT_FILE")
  c_json=$(score_correctness "$RESULT_FILE")
  a_json=$(score_autonomy "$TRACE_FILE" "$RESULT_FILE")
  e_json=$(score_efficiency "$RESULT_FILE")

  local d_score c_score a_score e_score
  d_score=$(echo "$d_json" | jq -r '.score')
  c_score=$(echo "$c_json" | jq -r '.score')
  a_score=$(echo "$a_json" | jq -r '.score')
  e_score=$(echo "$e_json" | jq -r '.score')

  local dq
  dq=$(echo "scale=4; $W_DISCIPLINE * $d_score + $W_CORRECTNESS * $c_score + $W_AUTONOMY * $a_score + $W_EFFICIENCY * $e_score" | bc)

  # Read metadata from result file
  local story_id plugin plugin_version tier
  story_id=$(jq -r '.story_id' "$RESULT_FILE")
  plugin=$(jq -r '.plugin' "$RESULT_FILE")
  plugin_version=$(jq -r '.plugin_version' "$RESULT_FILE")
  tier=$(jq -r '.tier' "$RESULT_FILE")

  # Assemble final output
  jq -n \
    --arg story_id "$story_id" \
    --arg plugin "$plugin" \
    --arg plugin_version "$plugin_version" \
    --arg tier "$tier" \
    --argjson discipline "$d_json" \
    --argjson correctness "$c_json" \
    --argjson autonomy "$a_json" \
    --argjson efficiency "$e_json" \
    --argjson dq "$dq" \
    --argjson d_score "$d_score" \
    --argjson c_score "$c_score" \
    --argjson a_score "$a_score" \
    --argjson e_score "$e_score" \
    '{
      story_id: $story_id,
      plugin: $plugin,
      plugin_version: $plugin_version,
      tier: $tier,
      scores: {
        discipline: $d_score,
        correctness: $c_score,
        autonomy: $a_score,
        efficiency: $e_score,
        dq: $dq
      },
      weights: {
        discipline: 0.35,
        correctness: 0.35,
        autonomy: 0.20,
        efficiency: 0.10
      },
      dimensions: {
        discipline: $discipline,
        correctness: $correctness,
        autonomy: $autonomy,
        efficiency: $efficiency
      }
    }'
}

main
