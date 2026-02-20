# TaskPlex v2.0.8 SOTA Upgrade — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all 28 verified gaps from the SOTA audit to achieve complete CLI feature coverage and adopt 3 competitive patterns.

**Architecture:** Declarative config changes (YAML frontmatter, JSON) plus 3 new shell scripts (stop-guard, task-completed, env injection). No application logic changes.

**Tech Stack:** Bash 3.2, YAML frontmatter, JSON (jq), Claude Code CLI hooks

**PRD:** `docs/plans/2026-02-20-sota-upgrade-design.md`

---

## Task 1: Agent Frontmatter — implementer.md

**Files:**
- Modify: `agents/implementer.md:1-15` (YAML frontmatter only)

**Step 1: Add `permissionMode: bypassPermissions` after `model: inherit` line**

```yaml
model: inherit
permissionMode: bypassPermissions
maxTurns: 150
```

**Step 2: Verify frontmatter parses**

Run: `head -30 agents/implementer.md`
Expected: `permissionMode: bypassPermissions` visible between `model` and `maxTurns`

---

## Task 2: Agent Frontmatter — validator.md

**Files:**
- Modify: `agents/validator.md:1-16` (YAML frontmatter only)

**Step 1: Add `permissionMode: dontAsk` after `model: haiku` line**

```yaml
model: haiku
permissionMode: dontAsk
maxTurns: 50
```

**Step 2: Verify**

Run: `head -20 agents/validator.md`

---

## Task 3: Agent Frontmatter — reviewer.md

**Files:**
- Modify: `agents/reviewer.md:1-15` (YAML frontmatter only)

**Step 1: Add `permissionMode: plan` after `model: sonnet` line**

```yaml
model: sonnet
permissionMode: plan
maxTurns: 30
```

**Step 2: Verify**

Run: `head -20 agents/reviewer.md`

---

## Task 4: Agent Frontmatter — merger.md

**Files:**
- Modify: `agents/merger.md:1-10` (YAML frontmatter only)

**Step 1: Add `permissionMode`, `disallowedTools` after existing fields**

```yaml
name: merger
description: "Handles git operations: branch creation, merge to main, conflict resolution, branch cleanup."
tools:
  - Bash
  - Read
  - Grep
disallowedTools:
  - Write
  - Edit
  - Task
model: haiku
permissionMode: bypassPermissions
maxTurns: 50
```

**Step 2: Verify**

Run: `head -15 agents/merger.md`

---

## Task 5: Agent Frontmatter — code-reviewer.md

**Files:**
- Modify: `agents/code-reviewer.md:1-15` (YAML frontmatter only)

**Step 1: Add `permissionMode: dontAsk` and `memory: project` after `maxTurns`**

```yaml
model: sonnet
permissionMode: dontAsk
maxTurns: 40
memory: project
```

**Step 2: Verify**

Run: `head -20 agents/code-reviewer.md`

---

## Task 6: Commit Batch A

```bash
git add agents/implementer.md agents/validator.md agents/reviewer.md agents/merger.md agents/code-reviewer.md
git commit -m "feat: add permissionMode to all agents for clean headless execution"
```

---

## Task 7: Skill Frontmatter — prd-generator

**Files:**
- Modify: `skills/prd-generator/SKILL.md:1-5` (YAML frontmatter only)

**Step 1: Add fields to frontmatter**

```yaml
---
name: prd-generator
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
context: fork
agent: Explore
model: sonnet
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Write, AskUserQuestion
---
```

**Step 2: Verify**

Run: `head -10 skills/prd-generator/SKILL.md`

---

## Task 8: Skill Frontmatter — prd-converter

**Files:**
- Modify: `skills/prd-converter/SKILL.md:1-5` (YAML frontmatter only)

**Step 1: Add fields to frontmatter**

```yaml
---
name: prd-converter
description: "Convert PRDs to prd.json format for the TaskPlex autonomous agent system. Use when you have an existing PRD and need to convert it to TaskPlex's JSON format. Triggers on: convert this prd, turn this into taskplex format, create prd.json from this, convert prd to json."
context: fork
agent: Explore
model: sonnet
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Write
---
```

**Step 2: Verify**

Run: `head -10 skills/prd-converter/SKILL.md`

---

## Task 9: Skill Frontmatter — failure-analyzer

**Files:**
- Modify: `skills/failure-analyzer/SKILL.md:1-4` (YAML frontmatter only)

**Step 1: Add fields**

```yaml
---
name: failure-analyzer
description: "Analyzes failed task output to categorize the error and suggest a retry strategy. Use when a TaskPlex implementation attempt fails."
user-invocable: false
disable-model-invocation: true
---
```

**Step 2: Verify**

Run: `head -6 skills/failure-analyzer/SKILL.md`

---

## Task 10: Command Frontmatter — start.md

**Files:**
- Modify: `commands/start.md:1-5` (YAML frontmatter only)

**Step 1: Add `disable-model-invocation` and update `argument-hint`**

```yaml
---
description: "Start TaskPlex interactive wizard - generates PRD, converts to JSON, and runs resilient autonomous agent loop with dependency enforcement"
argument-hint: "[feature-description]"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Task, AskUserQuestion, TodoWrite
---
```

**Step 2: Verify**

Run: `head -7 commands/start.md`

---

## Task 11: Commit Batch B

```bash
git add skills/prd-generator/SKILL.md skills/prd-converter/SKILL.md skills/failure-analyzer/SKILL.md commands/start.md
git commit -m "feat: add agent routing, model pinning, and access control to all skills"
```

---

## Task 12: Create stop-guard.sh

**Files:**
- Create: `hooks/stop-guard.sh`

**Step 1: Write the Stop hook script**

```bash
#!/bin/bash
# stop-guard.sh — Stop hook
# Prevents Claude from stopping prematurely when TaskPlex stories are in progress.
# Exit 0 = allow stop
# Exit 2 = block stop (with reason on stdout as JSON)

HOOK_INPUT=$(cat)

# Prevent infinite loops — if we already blocked once, let it go
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# Check if prd.json exists with in_progress stories
PRD_FILE="$(pwd)/prd.json"
if [ ! -f "$PRD_FILE" ]; then
  exit 0
fi

IN_PROGRESS=$(jq '[.userStories[] | select(.status == "in_progress")] | length' "$PRD_FILE" 2>/dev/null || echo "0")
PENDING=$(jq '[.userStories[] | select(.passes == false and .status != "skipped" and .status != "rewritten")] | length' "$PRD_FILE" 2>/dev/null || echo "0")

if [ "$IN_PROGRESS" -gt 0 ] || [ "$PENDING" -gt 0 ]; then
  cat <<'BLOCK_JSON'
{
  "decision": "block",
  "reason": "TaskPlex run still active. There are stories in progress or pending. Continue working on the next story from prd.json, or explicitly mark remaining stories as skipped if you cannot proceed."
}
BLOCK_JSON
  exit 2
fi

exit 0
```

**Step 2: Make executable**

Run: `chmod +x hooks/stop-guard.sh`

**Step 3: Verify syntax**

Run: `bash -n hooks/stop-guard.sh && echo OK`
Expected: `OK`

---

## Task 13: Create task-completed.sh

**Files:**
- Create: `hooks/task-completed.sh`

**Step 1: Write the TaskCompleted hook script**

```bash
#!/bin/bash
# task-completed.sh — TaskCompleted hook
# Validates that tests pass before allowing a task to be marked complete.
# Exit 0 = allow completion
# Exit 2 = block completion (stderr message fed back to agent)

PROJECT_DIR="$(pwd)"
CONFIG_FILE="$PROJECT_DIR/.claude/taskplex.config.json"

# Read test command from config
TEST_CMD=""
if [ -f "$CONFIG_FILE" ]; then
  TEST_CMD=$(jq -r '.test_command // ""' "$CONFIG_FILE" 2>/dev/null)
fi

# No test command configured — allow completion
if [ -z "$TEST_CMD" ]; then
  exit 0
fi

# Run tests
TEST_OUTPUT=$(eval "$TEST_CMD" 2>&1)
TEST_EXIT=$?

if [ $TEST_EXIT -eq 0 ]; then
  exit 0
fi

# Tests failed — block completion
echo "Tests failed (exit $TEST_EXIT). Fix the failing tests before marking this task complete:" >&2
echo "$TEST_OUTPUT" | head -c 1500 >&2
exit 2
```

**Step 2: Make executable**

Run: `chmod +x hooks/task-completed.sh`

**Step 3: Verify syntax**

Run: `bash -n hooks/task-completed.sh && echo OK`

---

## Task 14: Update session-lifecycle.sh for CLAUDE_ENV_FILE

**Files:**
- Modify: `monitor/hooks/session-lifecycle.sh`

**Step 1: Add env var persistence before the exec line**

```bash
#!/bin/bash
# TaskPlex Monitor — SessionStart/SessionEnd hook
# Captures Claude Code session lifecycle events.
# Also persists TaskPlex env vars via CLAUDE_ENV_FILE on session start.

EVENT_TYPE="${1:-session.start}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Persist TaskPlex environment variables for all subsequent Bash commands
if [ "$EVENT_TYPE" = "session.start" ] && [ -n "$CLAUDE_ENV_FILE" ]; then
  # Detect monitor port from PID file or env
  MONITOR_PORT="${TASKPLEX_MONITOR_PORT:-}"
  if [ -z "$MONITOR_PORT" ]; then
    PID_FILE="$(pwd)/.claude/taskplex-monitor.pid"
    if [ -f "$PID_FILE" ]; then
      MONITOR_PORT=$(head -2 "$PID_FILE" | tail -1 2>/dev/null || echo "")
    fi
  fi
  [ -n "$MONITOR_PORT" ] && echo "export TASKPLEX_MONITOR_PORT=\"$MONITOR_PORT\"" >> "$CLAUDE_ENV_FILE"

  # Persist run ID if set
  [ -n "$TASKPLEX_RUN_ID" ] && echo "export TASKPLEX_RUN_ID=\"$TASKPLEX_RUN_ID\"" >> "$CLAUDE_ENV_FILE"
fi

exec "$SCRIPT_DIR/send-event.sh" "$EVENT_TYPE"
```

**Step 2: Verify syntax**

Run: `bash -n monitor/hooks/session-lifecycle.sh && echo OK`

---

## Task 15: Commit Batch C

```bash
git add hooks/stop-guard.sh hooks/task-completed.sh monitor/hooks/session-lifecycle.sh
git commit -m "feat: add Stop guard, TaskCompleted gate, and env var persistence hooks"
```

---

## Task 16: Update hooks.json — add new hooks + statusMessage + timeout

**Files:**
- Modify: `hooks/hooks.json`

**Changes:**
1. Add `Stop` hook entry → `stop-guard.sh` with `statusMessage` and `timeout`
2. Add `TaskCompleted` hook entry → `task-completed.sh` with `statusMessage` and `timeout`
3. Add `statusMessage` and `timeout` to existing sync hooks (inject-knowledge, validate-result, pre-compact)
4. Add `once: true` SessionStart hook for active run status display

**The full updated hooks.json content replaces the existing file.**

---

## Task 17: Commit Batch D

```bash
git add hooks/hooks.json
git commit -m "feat: add statusMessage, timeout, Stop and TaskCompleted hooks to hooks.json"
```

---

## Task 18: Update plugin.json

**Files:**
- Modify: `.claude-plugin/plugin.json`

**Changes:**
- Add `"hooks": "./hooks/hooks.json"`
- Add `"email"` to author
- Bump version to `2.0.8`

---

## Task 19: Add $ARGUMENTS support to start.md

**Files:**
- Modify: `commands/start.md` (Checkpoint 3 section)

**Step 1: Add $ARGUMENTS handling at start of Checkpoint 3**

After the "Checkpoint 3: Project Input" heading, add before the AskUserQuestion:

```markdown
**Fast-start with arguments:**

If `$ARGUMENTS` is non-empty (user ran `/taskplex:start <description>`), use it as the project description and skip the interview. Proceed directly to Checkpoint 4 with this description.

If `$ARGUMENTS` is empty, ask the user:
```

**Step 2: Add dynamic context injection at top of wizard**

At the very top of the skill body (after the frontmatter), add:

```markdown
**Active state detection:**

!`if [ -f prd.json ]; then echo "EXISTING_PRD=true"; jq '{project: .project, stories: [.userStories[] | {id, title, status: (if .passes then "done" elif .status == "skipped" then "skipped" else "pending" end)}]}' prd.json 2>/dev/null; else echo "EXISTING_PRD=false"; fi`

!`if [ -f .claude/taskplex.config.json ]; then echo "EXISTING_CONFIG=true"; cat .claude/taskplex.config.json 2>/dev/null; else echo "EXISTING_CONFIG=false"; fi`

If EXISTING_PRD=true, inform the user and ask if they want to continue the existing run or start fresh. If continuing, skip to Checkpoint 8 (Launch).
```

---

## Task 20: Commit Batch E

```bash
git add .claude-plugin/plugin.json commands/start.md
git commit -m "feat: add fast-start arguments, dynamic context injection, and plugin manifest enhancements"
```

---

## Task 21: Update docs (CLAUDE.md + TASKPLEX-ARCHITECTURE.md)

**Files:**
- Modify: `CLAUDE.md` — version header, v2.0.8 changelog, agent table updates
- Modify: `TASKPLEX-ARCHITECTURE.md` — version header, version history table

---

## Task 22: Final commit + version bump

```bash
git add CLAUDE.md TASKPLEX-ARCHITECTURE.md docs/plans/
git commit -m "docs: v2.0.8 SOTA upgrade — PRD, competitive analysis, and changelog"
```
