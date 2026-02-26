#!/usr/bin/env bash
# US-003: Structural Validator — Cross-Reference Integrity
# Validates that all internal cross-references are consistent:
#   1. Skills in using-taskplex catalog → match skills/ directories
#   2. SubagentStart/Stop matcher names → match agents/ .md files
#   3. Implementer frontmatter skill list → match skills/ directories
#   4. plugin.json paths → resolve to actual files
# Exit 0: all pass | Exit 1: any failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

# Use temp file to track results across subshells
RESULTS_FILE="/tmp/taskplex-test-crossrefs-$$"
echo "0 0" > "$RESULTS_FILE"

cleanup() { rm -f "$RESULTS_FILE"; }
trap cleanup EXIT

pass() {
  local desc="$1"
  printf "  ${GREEN}✓${RESET} %s\n" "$desc"
  local p f; read -r p f < "$RESULTS_FILE"; echo "$((p+1)) $f" > "$RESULTS_FILE"
}

fail() {
  local desc="$1" reason="$2"
  printf "  ${RED}✗${RESET} %s\n" "$desc"
  printf "    → %s\n" "$reason"
  local p f; read -r p f < "$RESULTS_FILE"; echo "$p $((f+1))" > "$RESULTS_FILE"
}

echo "=== US-003: Cross-Reference Integrity Validation ==="
echo ""

SKILLS_DIR="${PLUGIN_ROOT}/skills"
AGENTS_DIR="${PLUGIN_ROOT}/agents"
HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"
USING_TASKPLEX="${SKILLS_DIR}/using-taskplex/SKILL.md"

# ─────────────────────────────────────────────
# 1. Skills in using-taskplex catalog → skills/ directories
# ─────────────────────────────────────────────
echo "1. using-taskplex skill catalog → skills/ directories"

if [ ! -f "$USING_TASKPLEX" ]; then
  fail "using-taskplex/SKILL.md exists" "file not found"
else
  # Extract skill names from table rows: "| `taskplex:skill-name` |"
  catalog_skills=$(grep '| `taskplex:' "$USING_TASKPLEX" \
    | grep -o 'taskplex:[a-z-]*' \
    | sed 's/taskplex://' \
    | sort -u)

  count=0
  while IFS= read -r skill_name; do
    [ -z "$skill_name" ] && continue
    count=$((count + 1))
    skill_dir="${SKILLS_DIR}/${skill_name}"
    if [ -d "$skill_dir" ] && [ -f "${skill_dir}/SKILL.md" ]; then
      pass "catalog skill '${skill_name}' exists at skills/${skill_name}/"
    elif [ -d "$skill_dir" ]; then
      fail "catalog skill '${skill_name}' has SKILL.md" "directory exists but missing SKILL.md"
    else
      fail "catalog skill '${skill_name}' exists" "skills/${skill_name}/ not found"
    fi
  done <<EOF
$catalog_skills
EOF
  echo "  (checked $count skills from catalog table)"
fi

echo ""

# ─────────────────────────────────────────────
# 2. SubagentStart/Stop matcher names → agents/ .md files
# ─────────────────────────────────────────────
echo "2. hooks.json SubagentStart/Stop matchers → agents/ files"

if ! jq . "$HOOKS_JSON" > /dev/null 2>&1; then
  fail "hooks.json valid JSON" "invalid JSON syntax"
else
  # Extract matchers only from SubagentStart and SubagentStop (agent-targeting events)
  agent_matchers=$(jq -r '
    .hooks | to_entries[] |
    select(.key == "SubagentStart" or .key == "SubagentStop") |
    .value[] | .matcher // empty
  ' "$HOOKS_JSON" 2>/dev/null | sort -u)

  matcher_count=0
  while IFS= read -r matcher; do
    [ -z "$matcher" ] && continue
    matcher_count=$((matcher_count + 1))
    agent_file="${AGENTS_DIR}/${matcher}.md"
    if [ -f "$agent_file" ]; then
      pass "hook matcher '${matcher}' → agents/${matcher}.md exists"
    else
      fail "hook matcher '${matcher}' → agents/${matcher}.md" "file not found"
    fi
  done <<EOF
$agent_matchers
EOF
  echo "  (checked $matcher_count agent matchers)"
fi

echo ""

# ─────────────────────────────────────────────
# 3. Implementer agent frontmatter skills list → skills/ directories
# ─────────────────────────────────────────────
echo "3. implementer.md frontmatter skills → skills/ directories"

IMPLEMENTER="${AGENTS_DIR}/implementer.md"

if [ ! -f "$IMPLEMENTER" ]; then
  fail "agents/implementer.md exists" "file not found"
else
  # Extract the skills list from frontmatter
  # Frontmatter format: skills:\n  - skill-name\n  - skill-name
  impl_skills=$(awk '
    /^---$/{if(f)exit;f=1;next}
    f && /^skills:/{in_skills=1;next}
    f && in_skills && /^[a-z]/{in_skills=0}
    f && in_skills && /^  - /{gsub(/^[[:space:]]*-[[:space:]]*/,"");print}
  ' "$IMPLEMENTER" 2>/dev/null)

  skill_count=0
  while IFS= read -r skill_name; do
    [ -z "$skill_name" ] && continue
    skill_count=$((skill_count + 1))
    skill_dir="${SKILLS_DIR}/${skill_name}"
    if [ -d "$skill_dir" ] && [ -f "${skill_dir}/SKILL.md" ]; then
      pass "implementer skill '${skill_name}' exists at skills/${skill_name}/"
    elif [ -d "$skill_dir" ]; then
      fail "implementer skill '${skill_name}' has SKILL.md" "directory exists but missing SKILL.md"
    else
      fail "implementer skill '${skill_name}' exists" "skills/${skill_name}/ not found"
    fi
  done <<EOF
$impl_skills
EOF
  echo "  (checked $skill_count implementer skills)"
fi

echo ""

# ─────────────────────────────────────────────
# 4. plugin.json paths → actual files
# ─────────────────────────────────────────────
echo "4. plugin.json paths → actual files"

if ! jq . "$PLUGIN_JSON" > /dev/null 2>&1; then
  fail "plugin.json valid JSON" "invalid JSON syntax"
else
  # Skills: path → path/SKILL.md
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    rel="${path#./}"
    full="${PLUGIN_ROOT}/${rel}/SKILL.md"
    if [ -f "$full" ]; then
      pass "plugin.json skill '${rel}' → ${rel}/SKILL.md exists"
    else
      fail "plugin.json skill '${rel}' → ${rel}/SKILL.md" "file not found"
    fi
  done <<EOF
$(jq -r '.skills[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
EOF

  # Agents: path → actual .md file
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    rel="${path#./}"
    full="${PLUGIN_ROOT}/${rel}"
    if [ -f "$full" ]; then
      pass "plugin.json agent '${rel}' exists"
    else
      fail "plugin.json agent '${rel}'" "file not found"
    fi
  done <<EOF
$(jq -r '.agents[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
EOF

  # Commands: path → actual file
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    rel="${path#./}"
    full="${PLUGIN_ROOT}/${rel}"
    if [ -f "$full" ]; then
      pass "plugin.json command '${rel}' exists"
    else
      fail "plugin.json command '${rel}'" "file not found"
    fi
  done <<EOF
$(jq -r '.commands[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
EOF
fi

echo ""
PASSED=$(awk '{print $1}' "$RESULTS_FILE")
FAILED=$(awk '{print $2}' "$RESULTS_FILE")
echo "=== Results: ${PASSED} passed, ${FAILED} failed ==="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
