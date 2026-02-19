#!/bin/bash
# Dependency checker for TaskPlex
# Returns 0 if all dependencies present, 1 if missing
# Outputs list of missing dependencies to stdout

set -e

MISSING=()

# Check for claude CLI (Claude Code)
if ! command -v claude &> /dev/null; then
  MISSING+=("claude")
fi

# Check for jq (JSON parser)
if ! command -v jq &> /dev/null; then
  MISSING+=("jq")
fi

# Check for sqlite3 (knowledge store)
if ! command -v sqlite3 &> /dev/null; then
  MISSING+=("sqlite3")
fi

# Check for timeout command (GNU coreutils)
# On macOS with Homebrew coreutils, it's called gtimeout
# On Linux, it's timeout
if ! command -v timeout &> /dev/null && ! command -v gtimeout &> /dev/null; then
  MISSING+=("coreutils")
fi

# Output results
if [ ${#MISSING[@]} -eq 0 ]; then
  # All dependencies present
  exit 0
else
  # Output missing dependencies (space-separated)
  echo "${MISSING[@]}"
  exit 1
fi
