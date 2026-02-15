#!/bin/bash
# TaskPlex - Block destructive git commands during implementation
# Used as a PostToolUse hook for Bash commands

INPUT="$1"

# Check for destructive git operations
# Covers: git push --force / -f, git reset --hard, git clean -f (any flag combo with f)
if echo "$INPUT" | grep -qE 'git\s+(push\s+.*(--force|-f)\b|reset\s+--hard|clean\s+-[a-z]*f)'; then
  echo "BLOCKED: Destructive git command detected. TaskPlex prevents force-push, hard-reset, and clean during implementation."
  exit 2
fi

# Check for pushing to main/master directly
if echo "$INPUT" | grep -qE 'git\s+push\s+(origin\s+)?(main|master)(\s|$)'; then
  echo "BLOCKED: Direct push to main/master not allowed. TaskPlex manages branch merges."
  exit 2
fi

exit 0
