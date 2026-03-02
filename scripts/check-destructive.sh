#!/bin/bash
# TaskPlex - Block destructive git commands during implementation
# Used as a PreToolUse hook for Bash commands
# Reads hook JSON from stdin, extracts the command, checks for destructive ops
#
# Exit codes:
#   0 = allow (with optional JSON deny on stdout for blocked commands)
#   PreToolUse uses JSON permissionDecision, not exit 2
#
# NOTE: set -e intentionally omitted — hook requires explicit exit code control

# Read hook input from stdin and extract the bash command
HOOK_INPUT=$(cat)
INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# If no command or jq failed, allow through
if [ -z "$INPUT" ]; then
  exit 0
fi

deny() {
  # Include git status in the reason so Claude has context when denied
  # (additionalContext is documented for "before the tool executes" — may not apply on deny)
  local git_context
  git_context=$(git status --short 2>/dev/null | head -20) || git_context=""
  local full_reason="$1
Blocked command: $INPUT"
  if [ -n "$git_context" ]; then
    full_reason="${full_reason}
Current git status:
${git_context}"
  fi

  jq -n --arg reason "$full_reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Check for destructive git operations
# Covers: git push --force / -f, git reset --hard, git clean -f (any flag combo with f)
# Allows --force-with-lease (safer alternative to --force)
if echo "$INPUT" | grep -qE 'git\s+reset\s+--hard'; then
  deny "Destructive git command detected. TaskPlex prevents hard-reset during implementation."
elif echo "$INPUT" | grep -qE 'git\s+clean\s+-[a-z]*f'; then
  deny "Destructive git command detected. TaskPlex prevents git clean -f during implementation."
elif echo "$INPUT" | grep -qE 'git\s+push\s+' && ! echo "$INPUT" | grep -qE '\-\-force-with-lease'; then
  if echo "$INPUT" | grep -qE 'git\s+push\s+.*(--force\b|-f\b)'; then
    deny "Destructive git command detected. TaskPlex prevents force-push during implementation. Use --force-with-lease instead."
  fi
fi

# Check for pushing to main/master directly
if echo "$INPUT" | grep -qE 'git\s+push\s+(origin\s+)?(main|master)(\s|$)'; then
  deny "Direct push to main/master not allowed. TaskPlex manages branch merges."
fi

exit 0
