#!/bin/bash
# Dependency checker for TaskPlex
# Returns 0 if all dependencies present, 1 if missing
# Outputs list of missing dependencies to stdout
# NOTE: Bash 3.2 compatible — no arrays, no bash 4+ features

set -e

MISSING=""

# Check for claude CLI (Claude Code)
if ! command -v claude &> /dev/null; then
  MISSING="claude"
fi

# Check for jq (JSON parser)
if ! command -v jq &> /dev/null; then
  if [ -n "$MISSING" ]; then
    MISSING="$MISSING jq"
  else
    MISSING="jq"
  fi
fi

# Output results
if [ -z "$MISSING" ]; then
  # All dependencies present
  exit 0
else
  # Output missing dependencies (space-separated)
  echo "$MISSING"
  exit 1
fi
