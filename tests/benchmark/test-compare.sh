#!/usr/bin/env bash
# test-compare.sh — Validate the comparison report with synthetic scored data
#
# Usage: ./tests/benchmark/test-compare.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCORE_SH="$SCRIPT_DIR/score.sh"
COMPARE_SH="$SCRIPT_DIR/compare.sh"
TMPDIR_TEST=$(mktemp -d "${TMPDIR:-/tmp}/benchmark-compare-test.XXXXXX")

SCORES_TASKPLEX="$TMPDIR_TEST/taskplex"
SCORES_SUPERPOWERS="$TMPDIR_TEST/superpowers"
mkdir -p "$SCORES_TASKPLEX" "$SCORES_SUPERPOWERS"

echo "═══════════════════════════════════════════"
echo "  Comparison Report — Integration Test"
echo "═══════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────
# Generate 3 synthetic paired scores
# ─────────────────────────────────────────────

# Story 1 — TaskPlex does great, Superpowers does okay
cat > "$TMPDIR_TEST/trace-tp1.json" <<'EOF'
{"story_id":"S001","plugin":"taskplex","events":[
  {"event":"skill_invoked","skill":"using-taskplex"},
  {"event":"skill_invoked","skill":"taskplex-tdd"},
  {"event":"test_executed","command":"npm test","pass":true,"phase":"pre_completion"},
  {"event":"skill_invoked","skill":"requesting-code-review"},
  {"event":"agent_dispatched","agent":"spec-reviewer","for_story":"S001"}
]}
EOF
cat > "$TMPDIR_TEST/result-tp1.json" <<'EOF'
{"story_id":"S001","plugin":"taskplex","plugin_version":"3.1.0","tier":"T2",
 "metrics":{"tdd_applicable":true,"tdd_sequence_observed":true,"turns":30,"tokens_used":70000,"wall_clock_seconds":100,"retries":0},
 "budgets":{"max_turns":200,"token_budget":500000,"timeout_seconds":900,"max_retries":3},
 "commands":{"test_command":"npm test","build_command":"npm run build","typecheck_command":"tsc --noEmit"},
 "results":{"tests_pass":true,"build_pass":true,"typecheck_pass":true,"acceptance_criteria_total":3,"acceptance_criteria_met":3,"regressions":0,"syntax_errors":0,"fully_autonomous":true}}
EOF

cat > "$TMPDIR_TEST/trace-sp1.json" <<'EOF'
{"story_id":"S001","plugin":"superpowers","events":[
  {"event":"skill_invoked","skill":"using-superpowers"},
  {"event":"test_executed","command":"npm test","pass":true,"phase":"post_completion"}
]}
EOF
cat > "$TMPDIR_TEST/result-sp1.json" <<'EOF'
{"story_id":"S001","plugin":"superpowers","plugin_version":"4.3.1","tier":"T2",
 "metrics":{"tdd_applicable":true,"tdd_sequence_observed":false,"turns":60,"tokens_used":180000,"wall_clock_seconds":280,"retries":1},
 "budgets":{"max_turns":200,"token_budget":500000,"timeout_seconds":900,"max_retries":3},
 "commands":{"test_command":"npm test","build_command":"npm run build","typecheck_command":"tsc --noEmit"},
 "results":{"tests_pass":true,"build_pass":true,"typecheck_pass":true,"acceptance_criteria_total":3,"acceptance_criteria_met":2,"regressions":0,"syntax_errors":0,"fully_autonomous":false}}
EOF

# Story 2 — Both do well
cat > "$TMPDIR_TEST/trace-tp2.json" <<'EOF'
{"story_id":"S002","plugin":"taskplex","events":[
  {"event":"skill_invoked","skill":"using-taskplex"},
  {"event":"skill_invoked","skill":"taskplex-tdd"},
  {"event":"test_executed","command":"npm test","pass":true,"phase":"pre_completion"},
  {"event":"skill_invoked","skill":"requesting-code-review"},
  {"event":"agent_dispatched","agent":"spec-reviewer","for_story":"S002"}
]}
EOF
cat > "$TMPDIR_TEST/result-tp2.json" <<'EOF'
{"story_id":"S002","plugin":"taskplex","plugin_version":"3.1.0","tier":"T1",
 "metrics":{"tdd_applicable":true,"tdd_sequence_observed":true,"turns":12,"tokens_used":25000,"wall_clock_seconds":40,"retries":0},
 "budgets":{"max_turns":200,"token_budget":500000,"timeout_seconds":900,"max_retries":3},
 "commands":{"test_command":"npm test","build_command":"npm run build","typecheck_command":"tsc --noEmit"},
 "results":{"tests_pass":true,"build_pass":true,"typecheck_pass":true,"acceptance_criteria_total":2,"acceptance_criteria_met":2,"regressions":0,"syntax_errors":0,"fully_autonomous":true}}
EOF

cat > "$TMPDIR_TEST/trace-sp2.json" <<'EOF'
{"story_id":"S002","plugin":"superpowers","events":[
  {"event":"skill_invoked","skill":"using-superpowers"},
  {"event":"skill_invoked","skill":"test-driven-development"},
  {"event":"test_executed","command":"npm test","pass":true,"phase":"pre_completion"},
  {"event":"skill_invoked","skill":"requesting-code-review"}
]}
EOF
cat > "$TMPDIR_TEST/result-sp2.json" <<'EOF'
{"story_id":"S002","plugin":"superpowers","plugin_version":"4.3.1","tier":"T1",
 "metrics":{"tdd_applicable":true,"tdd_sequence_observed":true,"turns":15,"tokens_used":30000,"wall_clock_seconds":50,"retries":0},
 "budgets":{"max_turns":200,"token_budget":500000,"timeout_seconds":900,"max_retries":3},
 "commands":{"test_command":"npm test","build_command":"npm run build","typecheck_command":"tsc --noEmit"},
 "results":{"tests_pass":true,"build_pass":true,"typecheck_pass":true,"acceptance_criteria_total":2,"acceptance_criteria_met":2,"regressions":0,"syntax_errors":0,"fully_autonomous":true}}
EOF

# Story 3 — TaskPlex recovers from error, Superpowers fails
cat > "$TMPDIR_TEST/trace-tp3.json" <<'EOF'
{"story_id":"S003","plugin":"taskplex","events":[
  {"event":"skill_invoked","skill":"using-taskplex"},
  {"event":"skill_invoked","skill":"taskplex-tdd"},
  {"event":"error_occurred","error_type":"test_failure","message":"assert failed"},
  {"event":"skill_invoked","skill":"systematic-debugging"},
  {"event":"error_recovered","error_type":"test_failure","strategy":"fix"},
  {"event":"test_executed","command":"npm test","pass":true,"phase":"pre_completion"},
  {"event":"skill_invoked","skill":"requesting-code-review"},
  {"event":"agent_dispatched","agent":"spec-reviewer","for_story":"S003"}
]}
EOF
cat > "$TMPDIR_TEST/result-tp3.json" <<'EOF'
{"story_id":"S003","plugin":"taskplex","plugin_version":"3.1.0","tier":"T3",
 "metrics":{"tdd_applicable":true,"tdd_sequence_observed":true,"turns":80,"tokens_used":190000,"wall_clock_seconds":300,"retries":1},
 "budgets":{"max_turns":200,"token_budget":500000,"timeout_seconds":900,"max_retries":3},
 "commands":{"test_command":"npm test","build_command":"npm run build","typecheck_command":"tsc --noEmit"},
 "results":{"tests_pass":true,"build_pass":true,"typecheck_pass":true,"acceptance_criteria_total":5,"acceptance_criteria_met":5,"regressions":0,"syntax_errors":0,"fully_autonomous":true}}
EOF

cat > "$TMPDIR_TEST/trace-sp3.json" <<'EOF'
{"story_id":"S003","plugin":"superpowers","events":[
  {"event":"skill_invoked","skill":"using-superpowers"},
  {"event":"error_occurred","error_type":"test_failure","message":"assert failed"},
  {"event":"human_intervention","reason":"user helped debug"},
  {"event":"test_executed","command":"npm test","pass":true,"phase":"post_completion"}
]}
EOF
cat > "$TMPDIR_TEST/result-sp3.json" <<'EOF'
{"story_id":"S003","plugin":"superpowers","plugin_version":"4.3.1","tier":"T3",
 "metrics":{"tdd_applicable":true,"tdd_sequence_observed":false,"turns":110,"tokens_used":300000,"wall_clock_seconds":500,"retries":2},
 "budgets":{"max_turns":200,"token_budget":500000,"timeout_seconds":900,"max_retries":3},
 "commands":{"test_command":"npm test","build_command":"npm run build","typecheck_command":"tsc --noEmit"},
 "results":{"tests_pass":true,"build_pass":true,"typecheck_pass":false,"acceptance_criteria_total":5,"acceptance_criteria_met":3,"regressions":1,"syntax_errors":0,"fully_autonomous":false}}
EOF

# ─────────────────────────────────────────────
# Score all stories
# ─────────────────────────────────────────────

echo "Scoring stories..."
for i in 1 2 3; do
  bash "$SCORE_SH" "$TMPDIR_TEST/trace-tp${i}.json" "$TMPDIR_TEST/result-tp${i}.json" > "$SCORES_TASKPLEX/S00${i}.json"
  bash "$SCORE_SH" "$TMPDIR_TEST/trace-sp${i}.json" "$TMPDIR_TEST/result-sp${i}.json" > "$SCORES_SUPERPOWERS/S00${i}.json"
done
echo "Done. 6 score files generated."
echo ""

# ─────────────────────────────────────────────
# Run comparison
# ─────────────────────────────────────────────

echo "Running comparison..."
echo ""
bash "$COMPARE_SH" "$SCORES_TASKPLEX" "$SCORES_SUPERPOWERS" "$TMPDIR_TEST/summary.json"

echo ""
echo "JSON summary:"
jq '.' "$TMPDIR_TEST/summary.json"

# ─────────────────────────────────────────────
# Verify comparison makes sense
# ─────────────────────────────────────────────

echo ""
echo "Verification:"

# TaskPlex should win overall
delta=$(jq -r '.overall.delta' "$TMPDIR_TEST/summary.json")
is_positive=$(echo "$delta > 0" | bc)
if [ "$is_positive" -eq 1 ]; then
  echo "  PASS: TaskPlex has higher DQ (Δ=$delta)"
else
  echo "  FAIL: Expected TaskPlex to win (Δ=$delta)"
fi

# Effect size should be meaningful
d=$(jq -r '.overall.cohens_d' "$TMPDIR_TEST/summary.json")
is_meaningful=$(echo "$d > 0.3" | bc)
if [ "$is_meaningful" -eq 1 ]; then
  echo "  PASS: Effect size meaningful (d=$d)"
else
  echo "  WARN: Effect size small (d=$d) — need more stories"
fi

# Clean up
rm -rf "$TMPDIR_TEST"

echo ""
echo "═══════════════════════════════════════════"
echo "  Integration test complete"
echo "═══════════════════════════════════════════"
