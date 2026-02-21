#!/usr/bin/env bash
# SessionStart hook for TaskPlex plugin
# Injects using-taskplex skill content + active prd.json status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read using-taskplex skill content
using_taskplex_content=$(cat "${PLUGIN_ROOT}/skills/using-taskplex/SKILL.md" 2>/dev/null || echo "Error reading using-taskplex skill")

# Check for active prd.json
prd_status=""
if [ -f "prd.json" ]; then
  project=$(jq -r '.project // "unknown"' prd.json 2>/dev/null || echo "unknown")
  total=$(jq '.userStories | length' prd.json 2>/dev/null || echo "0")
  done_count=$(jq '[.userStories[] | select(.passes == true)] | length' prd.json 2>/dev/null || echo "0")
  pending=$(jq '[.userStories[] | select(.passes == false and .status != "skipped")] | length' prd.json 2>/dev/null || echo "0")
  skipped=$(jq '[.userStories[] | select(.status == "skipped")] | length' prd.json 2>/dev/null || echo "0")

  if [ "$pending" -gt 0 ] 2>/dev/null; then
    prd_status="\\n\\n---\\n**Active TaskPlex Run Detected:**\\nProject: ${project}\\nStories: ${done_count}/${total} complete, ${pending} pending, ${skipped} skipped\\n\\nRun \`/taskplex:start\` to resume execution."
  fi
fi

# Escape string for JSON embedding using bash parameter substitution
escape_for_json() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

using_taskplex_escaped=$(escape_for_json "$using_taskplex_content")
prd_status_escaped=$(escape_for_json "$prd_status")
session_context="<EXTREMELY_IMPORTANT>\\nYou have TaskPlex — an always-on development companion.\\n\\n**Below is your 'taskplex:using-taskplex' skill. Follow it for every task:**\\n\\n${using_taskplex_escaped}\\n${prd_status_escaped}\\n</EXTREMELY_IMPORTANT>"

# Output context injection as JSON
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${session_context}"
  }
}
EOF

exit 0
