#!/usr/bin/env bash
# SessionStart hook for TaskPlex plugin
# Injects using-taskplex skill content + active prd.json status
#
# Output: JSON on stdout with hookSpecificOutput.additionalContext
# Exit 0 always

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read using-taskplex skill content
using_taskplex_content=$(cat "${PLUGIN_ROOT}/skills/using-taskplex/SKILL.md" 2>/dev/null || echo "Error reading using-taskplex skill")

# Check for active prd.json
prd_status=""
if [ -f "prd.json" ]; then
  # Validate JSON first — malformed prd.json must not crash the hook
  if ! jq empty prd.json 2>/dev/null; then
    prd_status="

---
**Warning:** prd.json exists but contains invalid JSON. Run \`/taskplex:start\` to regenerate."
  else
    project=$(jq -r '.project // "unknown"' prd.json 2>/dev/null) || project="unknown"
    total=$(jq '.userStories | length' prd.json 2>/dev/null) || total="0"
    done_count=$(jq '[.userStories[] | select(.passes == true)] | length' prd.json 2>/dev/null) || done_count="0"
    pending=$(jq '[.userStories[] | select(.passes == false and .status != "skipped")] | length' prd.json 2>/dev/null) || pending="0"
    skipped=$(jq '[.userStories[] | select(.status == "skipped")] | length' prd.json 2>/dev/null) || skipped="0"

    if [ "$pending" -gt 0 ] 2>/dev/null; then
      prd_status="

---
**Active TaskPlex Run Detected:**
Project: ${project}
Stories: ${done_count}/${total} complete, ${pending} pending, ${skipped} skipped

Run \`/taskplex:start\` to resume execution."
    fi
  fi
fi

# Build context with actual newlines — jq handles all JSON escaping
session_context="<EXTREMELY_IMPORTANT>
You have TaskPlex — an always-on development companion.

**Below is your 'taskplex:using-taskplex' skill. Follow it for every task:**

---

${using_taskplex_content}
${prd_status}
</EXTREMELY_IMPORTANT>"

# Output JSON using jq — handles all escaping (quotes, newlines, control chars)
jq -n --arg ctx "$session_context" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
