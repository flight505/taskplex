#!/bin/bash
# TaskPlex - Block destructive git commands during implementation
# Used as a PreToolUse hook for Bash commands
# Reads hook JSON from stdin, extracts the command, checks for destructive ops

# Read hook input from stdin and extract the bash command
INPUT=$(cat | jq -r '.tool_input.command // ""' 2>/dev/null)

# If no command found, allow
if [ -z "$INPUT" ]; then
  exit 0
fi

deny() {
  jq -n --arg reason "$1" '{
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
if echo "$INPUT" | grep -qE 'git\s+(push\s+.*(--force|-f)\b|reset\s+--hard|clean\s+-[a-z]*f)'; then
  deny "Destructive git command detected. TaskPlex prevents force-push, hard-reset, and clean during implementation."
fi

# Check for pushing to main/master directly
if echo "$INPUT" | grep -qE 'git\s+push\s+(origin\s+)?(main|master)(\s|$)'; then
  deny "Direct push to main/master not allowed. TaskPlex manages branch merges."
fi

exit 0
