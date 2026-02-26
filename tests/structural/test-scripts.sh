#!/usr/bin/env bash
# US-002: Structural Validator — Scripts and File Integrity
# Validates shebangs, bash -n syntax, bash 3.2 compatibility, referenced file existence
# Exit 0: all pass | Exit 1: any failure
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

# Use temp file to track results across subshells
RESULTS_FILE="/tmp/taskplex-test-scripts-$$"
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

# Check if a script contains a bash 4+ pattern (ignoring comments)
# Usage: has_bash4_pattern <script> <pattern>
has_bash4_pattern() {
  local script="$1" pattern="$2"
  # grep -n gives "lineno:content"; strip line number, then filter out comment lines
  grep -n "$pattern" "$script" 2>/dev/null \
    | sed 's/^[0-9]*://' \
    | grep -v '^[[:space:]]*#' \
    | grep -q "$pattern"
}

echo "=== US-002: Script and File Integrity Validation ==="
echo ""

# Collect all .sh files (scripts/, hooks/, monitor/hooks/)
SCRIPTS_DIR="${PLUGIN_ROOT}/scripts"
HOOKS_DIR="${PLUGIN_ROOT}/hooks"
MONITOR_DIR="${PLUGIN_ROOT}/monitor/hooks"

echo "1. Shebang validation (#!/usr/bin/env bash or #!/bin/bash)"
for script in "${SCRIPTS_DIR}"/*.sh "${HOOKS_DIR}"/*.sh "${MONITOR_DIR}"/*.sh; do
  [ -f "$script" ] || continue
  rel="${script#${PLUGIN_ROOT}/}"
  first_line=$(head -1 "$script" 2>/dev/null)
  if echo "$first_line" | grep -qE '^#!((/usr/bin/env bash)|(/bin/bash))'; then
    pass "$rel shebang ok"
  else
    fail "$rel shebang" "got: $(echo "$first_line" | head -c 60)"
  fi
done

echo ""
echo "2. Bash syntax check (bash -n)"
for script in "${SCRIPTS_DIR}"/*.sh "${HOOKS_DIR}"/*.sh "${MONITOR_DIR}"/*.sh; do
  [ -f "$script" ] || continue
  rel="${script#${PLUGIN_ROOT}/}"
  if bash -n "$script" 2>/dev/null; then
    pass "$rel syntax ok"
  else
    err=$(bash -n "$script" 2>&1 | head -2)
    fail "$rel syntax" "$err"
  fi
done

echo ""
echo "3. Bash 3.2 compatibility (no bash 4+ features)"
for script in "${SCRIPTS_DIR}"/*.sh "${HOOKS_DIR}"/*.sh "${MONITOR_DIR}"/*.sh; do
  [ -f "$script" ] || continue
  rel="${script#${PLUGIN_ROOT}/}"
  script_ok=1

  # declare -A = associative arrays (bash 4+)
  if has_bash4_pattern "$script" 'declare -A'; then
    line=$(grep -n 'declare -A' "$script" | sed 's/^[0-9]*://' | grep -v '^[[:space:]]*#' | head -1)
    fail "$rel: declare -A (bash 4+)" "$line"
    script_ok=0
  fi

  # ${var,,} lowercase expansion
  if has_bash4_pattern "$script" '\${[^}]*,,}'; then
    line=$(grep -n '\${[^}]*,,}' "$script" | sed 's/^[0-9]*://' | grep -v '^[[:space:]]*#' | head -1)
    fail "$rel: \${,,} expansion (bash 4+)" "$line"
    script_ok=0
  fi

  # ${var^^} uppercase expansion
  if has_bash4_pattern "$script" '\${[^}]*\^\^}'; then
    line=$(grep -n '\${[^}]*\^\^}' "$script" | sed 's/^[0-9]*://' | grep -v '^[[:space:]]*#' | head -1)
    fail "$rel: \${^^} expansion (bash 4+)" "$line"
    script_ok=0
  fi

  # |& pipe stderr (bash 4+)
  if has_bash4_pattern "$script" '|&'; then
    line=$(grep -n '|&' "$script" | sed 's/^[0-9]*://' | grep -v '^[[:space:]]*#' | head -1)
    fail "$rel: |& pipe (bash 4+)" "$line"
    script_ok=0
  fi

  if [ "$script_ok" -eq 1 ]; then
    pass "$rel bash 3.2 compatible"
  fi
done

echo ""
echo "4. Executable permissions"
for script in "${SCRIPTS_DIR}"/*.sh "${HOOKS_DIR}"/*.sh "${MONITOR_DIR}"/*.sh; do
  [ -f "$script" ] || continue
  rel="${script#${PLUGIN_ROOT}/}"
  if [ -x "$script" ]; then
    pass "$rel is executable"
  else
    fail "$rel is executable" "missing execute permission"
  fi
done

echo ""
echo "5. File references in plugin.json exist on disk"
PLUGIN_JSON="${PLUGIN_ROOT}/.claude-plugin/plugin.json"

while IFS= read -r path; do
  [ -z "$path" ] && continue
  rel="${path#./}"
  full="${PLUGIN_ROOT}/${rel}/SKILL.md"
  [ -f "$full" ] && pass "${rel}/SKILL.md" || fail "${rel}/SKILL.md" "file not found"
done <<EOF
$(jq -r '.skills[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
EOF

while IFS= read -r path; do
  [ -z "$path" ] && continue
  rel="${path#./}"
  full="${PLUGIN_ROOT}/${rel}"
  [ -f "$full" ] && pass "${rel}" || fail "${rel}" "file not found"
done <<EOF
$(jq -r '.agents[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
EOF

while IFS= read -r path; do
  [ -z "$path" ] && continue
  rel="${path#./}"
  full="${PLUGIN_ROOT}/${rel}"
  [ -f "$full" ] && pass "${rel}" || fail "${rel}" "file not found"
done <<EOF
$(jq -r '.commands[]? // empty' "$PLUGIN_JSON" 2>/dev/null)
EOF

echo ""
PASSED=$(awk '{print $1}' "$RESULTS_FILE")
FAILED=$(awk '{print $2}' "$RESULTS_FILE")
echo "=== Results: ${PASSED} passed, ${FAILED} failed ==="
[ "$FAILED" -eq 0 ] && exit 0 || exit 1
