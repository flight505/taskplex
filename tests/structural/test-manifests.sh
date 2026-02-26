#!/usr/bin/env bash
# US-001: Structural Validator — Manifests and Frontmatter
# Validates plugin.json, skill frontmatters, agent frontmatters, hooks.json
# Exit 0: all pass | Exit 1: any failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PASSED=0
FAILED=0
FAILURES=""

# Color output (bash 3.2 compatible via printf)
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

pass() {
  local desc="$1"
  printf "  ${GREEN}✓${RESET} %s\n" "$desc"
  PASSED=$((PASSED + 1))
}

fail() {
  local desc="$1" reason="$2"
  printf "  ${RED}✗${RESET} %s\n" "$desc"
  printf "    → %s\n" "$reason"
  FAILED=$((FAILED + 1))
  FAILURES="${FAILURES}${desc}: ${reason}\n"
}

# Extract YAML frontmatter field value (awk-based, BSD/macOS compatible)
# Usage: get_fm_field <file> <field>
get_fm_field() {
  local file="$1" field="$2"
  # Extract content between first pair of --- delimiters using awk
  awk '/^---$/{if(f)exit;f=1;next} f{print}' "$file" 2>/dev/null \
    | grep "^${field}:" \
    | sed "s/^${field}:[[:space:]]*//" \
    | head -1
}

# Check if frontmatter has a field (awk-based, BSD/macOS compatible)
has_fm_field() {
  local file="$1" field="$2"
  awk '/^---$/{if(f)exit;f=1;next} f{print}' "$file" 2>/dev/null \
    | grep -q "^${field}:"
}

echo "=== US-001: Manifest and Frontmatter Validation ==="
echo ""

# ─────────────────────────────────────────────
# 1. Validate plugin.json
# ─────────────────────────────────────────────
echo "1. plugin.json"

PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

if ! jq . "$PLUGIN_JSON" > /dev/null 2>&1; then
  fail "plugin.json valid JSON" "invalid JSON syntax"
else
  pass "plugin.json valid JSON"

  # Required fields
  for field in name version description author; do
    val=$(jq -r ".${field} // empty" "$PLUGIN_JSON" 2>/dev/null)
    if [ -z "$val" ]; then
      fail "plugin.json has '${field}'" "field missing or null"
    else
      pass "plugin.json has '${field}'"
    fi
  done

  # Semver format X.Y.Z
  version=$(jq -r '.version // empty' "$PLUGIN_JSON")
  if echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    pass "plugin.json version is semver ($version)"
  else
    fail "plugin.json version is semver" "got '$version', expected X.Y.Z"
  fi

  # All skills paths start with ./
  skill_paths=$(jq -r '.skills[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
  skill_ok=1
  bad_skill=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if ! echo "$p" | grep -q '^\./'; then
      skill_ok=0
      bad_skill="$p"
    fi
  done <<EOF
$skill_paths
EOF
  if [ "$skill_ok" -eq 1 ]; then
    pass "plugin.json skills paths start with ./"
  else
    fail "plugin.json skills paths start with ./" "bad path: $bad_skill"
  fi

  # All agents paths start with ./
  agent_paths=$(jq -r '.agents[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
  agent_ok=1
  bad_agent=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if ! echo "$p" | grep -q '^\./'; then
      agent_ok=0
      bad_agent="$p"
    fi
  done <<EOF
$agent_paths
EOF
  if [ "$agent_ok" -eq 1 ]; then
    pass "plugin.json agents paths start with ./"
  else
    fail "plugin.json agents paths start with ./" "bad path: $bad_agent"
  fi

  # commands paths start with ./ (if present)
  cmd_paths=$(jq -r '.commands[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
  if [ -n "$cmd_paths" ]; then
    cmd_ok=1
    bad_cmd=""
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      if ! echo "$p" | grep -q '^\./'; then
        cmd_ok=0
        bad_cmd="$p"
      fi
    done <<EOF
$cmd_paths
EOF
    if [ "$cmd_ok" -eq 1 ]; then
      pass "plugin.json commands paths start with ./"
    else
      fail "plugin.json commands paths start with ./" "bad path: $bad_cmd"
    fi
  fi
fi

echo ""

# ─────────────────────────────────────────────
# 2. Validate skill SKILL.md frontmatters
# ─────────────────────────────────────────────
echo "2. Skill frontmatters (skills/*/SKILL.md)"

SKILLS_DIR="${PLUGIN_ROOT}/skills"
skill_count=0
skill_errors=0

for skill_dir in "${SKILLS_DIR}"/*/; do
  skill_file="${skill_dir}SKILL.md"
  skill_name="$(basename "$skill_dir")"

  if [ ! -f "$skill_file" ]; then
    fail "skills/${skill_name}/SKILL.md exists" "file not found"
    skill_errors=$((skill_errors + 1))
    continue
  fi

  skill_count=$((skill_count + 1))
  skill_ok=1

  # Must have --- frontmatter delimiters
  if ! grep -q '^---$' "$skill_file" 2>/dev/null; then
    fail "skills/${skill_name} has frontmatter" "no --- delimiters found"
    skill_errors=$((skill_errors + 1))
    continue
  fi

  # Required: name
  fm_name=$(get_fm_field "$skill_file" "name")
  if [ -z "$fm_name" ]; then
    fail "skills/${skill_name} frontmatter has 'name'" "field missing"
    skill_ok=0
    skill_errors=$((skill_errors + 1))
  fi

  # Required: description
  fm_desc=$(get_fm_field "$skill_file" "description")
  if [ -z "$fm_desc" ]; then
    fail "skills/${skill_name} frontmatter has 'description'" "field missing"
    skill_ok=0
    skill_errors=$((skill_errors + 1))
  fi

  # Optional: disable-model-invocation must be boolean if present
  if has_fm_field "$skill_file" "disable-model-invocation"; then
    dmi=$(get_fm_field "$skill_file" "disable-model-invocation")
    if [ "$dmi" = "true" ] || [ "$dmi" = "false" ]; then
      : # valid
    else
      fail "skills/${skill_name} disable-model-invocation is boolean" "got '$dmi'"
      skill_ok=0
      skill_errors=$((skill_errors + 1))
    fi
  fi

  # Optional: user-invocable must be boolean if present
  if has_fm_field "$skill_file" "user-invocable"; then
    ui=$(get_fm_field "$skill_file" "user-invocable")
    if [ "$ui" = "true" ] || [ "$ui" = "false" ]; then
      : # valid
    else
      fail "skills/${skill_name} user-invocable is boolean" "got '$ui'"
      skill_ok=0
      skill_errors=$((skill_errors + 1))
    fi
  fi

  if [ "$skill_ok" -eq 1 ]; then
    pass "skills/${skill_name} frontmatter valid"
  fi
done

echo "  (checked $skill_count skill files, $skill_errors errors)"
echo ""

# ─────────────────────────────────────────────
# 3. Validate agent .md frontmatters
# ─────────────────────────────────────────────
echo "3. Agent frontmatters (agents/*.md)"

AGENTS_DIR="${PLUGIN_ROOT}/agents"
agent_count=0
agent_errors=0
VALID_MODELS="sonnet opus haiku inherit"
VALID_PERMISSIONS="default acceptEdits dontAsk bypassPermissions plan"

for agent_file in "${AGENTS_DIR}"/*.md; do
  agent_name="$(basename "$agent_file" .md)"
  agent_count=$((agent_count + 1))
  agent_ok=1

  # Must have --- frontmatter delimiters
  if ! grep -q '^---$' "$agent_file" 2>/dev/null; then
    fail "agents/${agent_name}.md has frontmatter" "no --- delimiters found"
    agent_errors=$((agent_errors + 1))
    continue
  fi

  # Required fields: name, description, tools, model, permissionMode
  for field in name description model permissionMode; do
    val=$(get_fm_field "$agent_file" "$field")
    if [ -z "$val" ]; then
      fail "agents/${agent_name} frontmatter has '${field}'" "field missing"
      agent_ok=0
      agent_errors=$((agent_errors + 1))
    fi
  done

  # tools must be present (it's a list — check the line exists)
  if ! has_fm_field "$agent_file" "tools"; then
    fail "agents/${agent_name} frontmatter has 'tools'" "field missing"
    agent_ok=0
    agent_errors=$((agent_errors + 1))
  fi

  # model must be a valid enum
  model_val=$(get_fm_field "$agent_file" "model")
  if [ -n "$model_val" ]; then
    model_valid=0
    for m in $VALID_MODELS; do
      [ "$model_val" = "$m" ] && model_valid=1 && break
    done
    if [ "$model_valid" -eq 0 ]; then
      fail "agents/${agent_name} model is valid enum" "got '$model_val', expected: $VALID_MODELS"
      agent_ok=0
      agent_errors=$((agent_errors + 1))
    fi
  fi

  # permissionMode must be a valid enum
  perm_val=$(get_fm_field "$agent_file" "permissionMode")
  if [ -n "$perm_val" ]; then
    perm_valid=0
    for p in $VALID_PERMISSIONS; do
      [ "$perm_val" = "$p" ] && perm_valid=1 && break
    done
    if [ "$perm_valid" -eq 0 ]; then
      fail "agents/${agent_name} permissionMode is valid enum" "got '$perm_val', expected: $VALID_PERMISSIONS"
      agent_ok=0
      agent_errors=$((agent_errors + 1))
    fi
  fi

  if [ "$agent_ok" -eq 1 ]; then
    pass "agents/${agent_name} frontmatter valid"
  fi
done

echo "  (checked $agent_count agent files, $agent_errors errors)"
echo ""

# ─────────────────────────────────────────────
# 4. Validate hooks.json
# ─────────────────────────────────────────────
echo "4. hooks/hooks.json"

HOOKS_JSON="${PLUGIN_ROOT}/hooks/hooks.json"
VALID_EVENTS="SessionStart Stop PreToolUse PostToolUse PostToolUseFailure PermissionRequest UserPromptSubmit Notification SubagentStart SubagentStop TaskCompleted PreCompact TeammateIdle SessionEnd"

if ! jq . "$HOOKS_JSON" > /dev/null 2>&1; then
  fail "hooks.json valid JSON" "invalid JSON syntax"
else
  pass "hooks.json valid JSON"

  # All top-level event names must be in valid set
  events=$(jq -r '.hooks | keys[]' "$HOOKS_JSON" 2>/dev/null)
  while IFS= read -r event; do
    [ -z "$event" ] && continue
    event_valid=0
    for e in $VALID_EVENTS; do
      [ "$event" = "$e" ] && event_valid=1 && break
    done
    if [ "$event_valid" -eq 1 ]; then
      pass "hooks.json event '${event}' is valid"
    else
      fail "hooks.json event '${event}' is valid" "unknown event name; valid: $VALID_EVENTS"
    fi
  done <<EOF
$events
EOF

  # All handler script paths exist and are executable
  # Extract commands: strip ${CLAUDE_PLUGIN_ROOT}/ prefix, get relative path
  commands=$(jq -r '.. | objects | .command? // empty' "$HOOKS_JSON" 2>/dev/null)
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    # Extract the path portion (first word of command, strip ${CLAUDE_PLUGIN_ROOT}/)
    script_path=$(echo "$cmd" | awk '{print $1}' | sed 's|${CLAUDE_PLUGIN_ROOT}/||')
    full_path="${PLUGIN_ROOT}/${script_path}"
    if [ ! -f "$full_path" ]; then
      fail "hook script exists: ${script_path}" "not found at $full_path"
    elif [ ! -x "$full_path" ]; then
      fail "hook script executable: ${script_path}" "not executable"
    else
      pass "hook script ok: ${script_path}"
    fi
  done <<EOF
$commands
EOF

  # Sync hooks (no async:true) must have statusMessage and timeout
  # A hook entry is sync if it has no async field or async != true
  sync_count=0
  sync_missing=0
  # Use jq to find sync hooks: entries with a command but no async:true
  sync_hooks=$(jq -r '
    .hooks | to_entries[] |
    .key as $event |
    .value[] |
    .hooks[] |
    select(.command != null and (.async // false) != true) |
    "\($event)|\(.command // "")|\(.statusMessage // "")|\(.timeout // "")"
  ' "$HOOKS_JSON" 2>/dev/null)

  while IFS='|' read -r event cmd sm to; do
    [ -z "$event" ] && continue
    sync_count=$((sync_count + 1))
    script=$(echo "$cmd" | awk '{print $1}' | sed 's|${CLAUDE_PLUGIN_ROOT}/||')
    if [ -z "$sm" ]; then
      fail "sync hook '${event}/${script}' has statusMessage" "missing statusMessage"
      sync_missing=$((sync_missing + 1))
    elif [ -z "$to" ]; then
      fail "sync hook '${event}/${script}' has timeout" "missing timeout"
      sync_missing=$((sync_missing + 1))
    else
      pass "sync hook '${event}/${script}' has statusMessage+timeout"
    fi
  done <<EOF
$sync_hooks
EOF
  echo "  (checked $sync_count sync hooks)"
fi

echo ""

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo "=== Results: ${PASSED} passed, ${FAILED} failed ==="
if [ "$FAILED" -gt 0 ]; then
  echo ""
  printf "Failures:\n${FAILURES}"
  exit 1
fi
exit 0
