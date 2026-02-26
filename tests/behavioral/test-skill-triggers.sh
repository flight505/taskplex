#!/usr/bin/env bash
# US-005: Behavioral Test Harness — Skill Triggering
# Tests that each skill triggers on appropriate prompts and not on others
# Usage: bash tests/behavioral/test-skill-triggers.sh [--dry-run] [--skill <name>] [--all]
# Requires: claude CLI with --plugin-dir support (Claude Code 2.1.x+)
# Exit 0: all tested prompts behave correctly | Exit 1: any failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIXTURES="${SCRIPT_DIR}/fixtures/skill-triggers.json"
RESULTS_DIR="${SCRIPT_DIR}/results"
TIMEOUT=60

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

mkdir -p "$RESULTS_DIR"

# Parse args
DRY_RUN=0
TARGET_SKILL=""
RUN_ALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --skill)   TARGET_SKILL="$2"; shift 2 ;;
    --all)     RUN_ALL=1; shift ;;
    *)         shift ;;
  esac
done

# ─────────────────────────────────────────────
# Validate fixture format
# ─────────────────────────────────────────────
validate_fixture() {
  if [ ! -f "$FIXTURES" ]; then
    echo "ERROR: fixtures/skill-triggers.json not found" >&2
    exit 1
  fi
  if ! jq . "$FIXTURES" > /dev/null 2>&1; then
    echo "ERROR: fixtures/skill-triggers.json has invalid JSON" >&2
    exit 1
  fi
  local count
  count=$(jq '.skills | length' "$FIXTURES")
  if [ "$count" -ne 16 ]; then
    echo "ERROR: expected 16 skills in fixture, got ${count}" >&2
    exit 1
  fi
  echo "Fixture: ${count} skills validated"
}

# ─────────────────────────────────────────────
# Dry-run mode: validate and list prompts
# ─────────────────────────────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
  echo "=== US-005: Skill Trigger Tests (DRY RUN) ==="
  echo ""
  validate_fixture
  echo ""
  total_prompts=0
  while IFS= read -r skill_name; do
    [ -z "$skill_name" ] && continue
    triggers=$(jq -r --arg n "$skill_name" '.skills[] | select(.name==$n) | .should_trigger[]' "$FIXTURES" 2>/dev/null)
    no_trigger=$(jq -r --arg n "$skill_name" '.skills[] | select(.name==$n) | .should_not_trigger' "$FIXTURES" 2>/dev/null)
    trigger_count=$(echo "$triggers" | grep -c . || echo 0)
    total_prompts=$((total_prompts + trigger_count + 1))
    printf "  %-40s %d should_trigger, 1 should_not_trigger\n" "${skill_name}:" "$trigger_count"
  done <<EOF
$(jq -r '.skills[].name' "$FIXTURES")
EOF
  echo ""
  echo "Total prompts to test: ${total_prompts} (at ~\$0.15/prompt = ~\$$(echo "$total_prompts 0.15" | awk '{printf "%.2f", $1*$2}'))"
  exit 0
fi

# ─────────────────────────────────────────────
# Check claude CLI available
# ─────────────────────────────────────────────
if ! command -v claude > /dev/null 2>&1; then
  echo "ERROR: claude CLI not found — required for skill trigger tests" >&2
  exit 1
fi

# Guard: nested claude -p hangs inside an active Claude Code session
# These tests MUST be run from a terminal or CI, not from within Claude Code
if [ -n "$CLAUDECODE" ]; then
  echo "ERROR: Cannot run skill trigger tests from within an active Claude Code session." >&2
  echo "       The nested claude -p call will hang indefinitely." >&2
  echo "       Run from a terminal: bash tests/behavioral/test-skill-triggers.sh --skill taskplex-tdd" >&2
  echo "       Or in CI: GitHub Actions (US-012) provides the correct environment." >&2
  exit 1
fi

validate_fixture

# ─────────────────────────────────────────────
# Run one prompt through claude and detect skill invocation
# Returns: name of skill invoked (empty if none)
# ─────────────────────────────────────────────
run_prompt() {
  local prompt="$1"
  local tmp_file
  tmp_file=$(mktemp /tmp/skill-trigger-XXXXXX.json)

  local exit_code=0
  env -u CLAUDECODE timeout "$TIMEOUT" claude -p "$prompt" \
    --plugin-dir "$PLUGIN_ROOT" \
    --dangerously-skip-permissions \
    --output-format stream-json \
    2>/dev/null > "$tmp_file" || exit_code=$?

  # Parse stream-json for Skill tool invocations
  # Look for content_block_start with tool_use name "Skill" and extract input.skill
  local invoked_skill=""
  if [ -f "$tmp_file" ] && [ -s "$tmp_file" ]; then
    # Primary: look for Skill tool_use events in stream
    invoked_skill=$(cat "$tmp_file" \
      | grep '"type":"content_block_start"' \
      | grep '"type":"tool_use"' \
      | grep '"name":"Skill"' \
      | grep -o '"skill":"[^"]*"' \
      | sed 's/"skill":"//;s/"//' \
      | head -1 2>/dev/null || true)

    # Fallback: look for taskplex: skill mentions in stream (text or JSON values)
    if [ -z "$invoked_skill" ]; then
      invoked_skill=$(grep -oE '"taskplex:[a-z-]+"' "$tmp_file" 2>/dev/null \
        | grep -v 'using-taskplex' \
        | tr -d '"' \
        | sed 's/taskplex://' \
        | head -1 || true)
    fi

    # Last resort: scan for skill name in any output text
    if [ -z "$invoked_skill" ]; then
      invoked_skill=$(grep -oE 'taskplex:[a-z-]+' "$tmp_file" 2>/dev/null \
        | grep -v 'taskplex:using-taskplex\|taskplex:start' \
        | sed 's/taskplex://' \
        | head -1 || true)
    fi
  fi

  rm -f "$tmp_file"
  echo "$invoked_skill"
}

# ─────────────────────────────────────────────
# Test a single skill (all its prompts)
# ─────────────────────────────────────────────
test_skill() {
  local skill_name="$1"
  local results="[]"
  local correct=0
  local total=0

  # Verify skill exists in fixture
  if ! jq -e --arg n "$skill_name" '.skills[] | select(.name==$n)' "$FIXTURES" > /dev/null 2>&1; then
    echo "ERROR: skill '${skill_name}' not found in fixture" >&2
    return 1
  fi

  # should_trigger prompts
  while IFS= read -r prompt; do
    [ -z "$prompt" ] && continue
    total=$((total + 1))
    printf "  Testing should_trigger: %.60s...\n" "$prompt"

    invoked=$(run_prompt "$prompt")
    is_correct=false
    if echo "$invoked" | grep -q "$skill_name"; then
      is_correct=true
      correct=$((correct + 1))
      printf "    ${GREEN}✓${RESET} triggered '%s'\n" "$invoked"
    else
      if [ -n "$invoked" ]; then
        printf "    ${RED}✗${RESET} triggered wrong skill: '%s'\n" "$invoked"
      else
        printf "    ${RED}✗${RESET} no skill triggered\n"
      fi
    fi

    results=$(echo "$results" | jq \
      --arg skill "$skill_name" \
      --arg prompt "$prompt" \
      --arg expected "trigger" \
      --arg actual "$invoked" \
      --argjson correct "$is_correct" \
      '. + [{"skill": $skill, "prompt": $prompt, "expected": $expected, "actual": $actual, "correct": $correct}]')
  done <<EOF
$(jq -r --arg n "$skill_name" '.skills[] | select(.name==$n) | .should_trigger[]' "$FIXTURES" 2>/dev/null)
EOF

  # should_not_trigger prompt
  no_trigger_prompt=$(jq -r --arg n "$skill_name" '.skills[] | select(.name==$n) | .should_not_trigger' "$FIXTURES" 2>/dev/null)
  if [ -n "$no_trigger_prompt" ]; then
    total=$((total + 1))
    printf "  Testing should_not_trigger: %.60s...\n" "$no_trigger_prompt"

    invoked=$(run_prompt "$no_trigger_prompt")
    is_correct=false
    if ! echo "$invoked" | grep -q "$skill_name"; then
      is_correct=true
      correct=$((correct + 1))
      if [ -n "$invoked" ]; then
        printf "    ${GREEN}✓${RESET} correctly invoked different skill: '%s'\n" "$invoked"
      else
        printf "    ${GREEN}✓${RESET} correctly did not trigger '%s'\n" "$skill_name"
      fi
    else
      printf "    ${RED}✗${RESET} incorrectly triggered '%s'\n" "$skill_name"
    fi

    results=$(echo "$results" | jq \
      --arg skill "$skill_name" \
      --arg prompt "$no_trigger_prompt" \
      --arg expected "no_trigger" \
      --arg actual "$invoked" \
      --argjson correct "$is_correct" \
      '. + [{"skill": $skill, "prompt": $prompt, "expected": $expected, "actual": $actual, "correct": $correct}]')
  fi

  echo "$correct $total" > "/tmp/skill-test-result-${skill_name}"
  echo "$results"
}

# ─────────────────────────────────────────────
# Main execution
# ─────────────────────────────────────────────
TIMESTAMP=$(date +%s)
VERSION=$(jq -r '.version // empty' "${PLUGIN_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)
GIT_SHA=$(git -C "$PLUGIN_ROOT" rev-parse --short HEAD 2>/dev/null)

echo "=== US-005: Skill Trigger Tests v${VERSION} ==="
echo ""

all_results="[]"
total_prompts=0
total_correct=0
worst_skills=""
test_exit=0

if [ "$RUN_ALL" -eq 1 ]; then
  SKILLS=$(jq -r '.skills[].name' "$FIXTURES")
elif [ -n "$TARGET_SKILL" ]; then
  SKILLS="$TARGET_SKILL"
else
  echo "Usage: $0 --dry-run | --skill <name> | --all" >&2
  echo "  --dry-run     Validate fixture and list prompts (no API calls)" >&2
  echo "  --skill <n>   Test one skill (2-3 prompts, ~\$0.30-0.45)" >&2
  echo "  --all         Test all 16 skills (~\$7.80 total)" >&2
  exit 1
fi

while IFS= read -r skill_name; do
  [ -z "$skill_name" ] && continue
  echo "Testing skill: ${skill_name}"

  skill_results=$(test_skill "$skill_name" || echo "[]")
  all_results=$(echo "[$all_results, $skill_results]" | jq 'add // []')

  if [ -f "/tmp/skill-test-result-${skill_name}" ]; then
    read -r c t < "/tmp/skill-test-result-${skill_name}"
    total_prompts=$((total_prompts + t))
    total_correct=$((total_correct + c))
    accuracy=$(echo "$c $t" | awk '{if($2>0)printf "%.0f", $1/$2*100; else printf "0"}')
    if [ "$accuracy" -lt 67 ]; then
      worst_skills="${worst_skills} ${skill_name}(${accuracy}%)"
    fi
    rm -f "/tmp/skill-test-result-${skill_name}"
  fi
  echo ""
done <<EOF
$SKILLS
EOF

# Compute overall accuracy
accuracy_pct=0
if [ "$total_prompts" -gt 0 ]; then
  accuracy_pct=$(echo "$total_correct $total_prompts" | awk '{printf "%.1f", $1/$2*100}')
fi

echo "=== Results: ${total_correct}/${total_prompts} correct (${accuracy_pct}% accuracy) ==="

# Build worst_skills array
worst_arr="[]"
for ws in $worst_skills; do
  worst_arr=$(echo "$worst_arr" | jq --arg s "$ws" '. + [$s]')
done

# Write results JSON
REPORT="${RESULTS_DIR}/skill-triggers-${TIMESTAMP}.json"
jq -n \
  --arg version "$VERSION" \
  --arg git_sha "$GIT_SHA" \
  --argjson timestamp "$TIMESTAMP" \
  --argjson results "$all_results" \
  --argjson total "$total_prompts" \
  --argjson correct "$total_correct" \
  --arg accuracy "$accuracy_pct" \
  --argjson worst "$worst_arr" \
  '{
    suite: "skill-triggers",
    version: $version,
    git_sha: $git_sha,
    timestamp: $timestamp,
    results: $results,
    summary: {
      total_prompts: $total,
      correct: $correct,
      accuracy_pct: ($accuracy | tonumber),
      worst_skills: $worst
    }
  }' > "$REPORT"

echo "  Report: ${REPORT}"

[ "$test_exit" -eq 0 ] && exit 0 || exit 1
