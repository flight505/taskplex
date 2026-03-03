---
name: focused-task
description: "Use when implementing a single well-scoped task (1-5 files) that doesn't need PRD planning. Triggers on: clear bugfixes, small features, refactors, single-story tasks with obvious acceptance criteria."
---

# Focused Task

## Overview

Implement a well-scoped task directly with TDD discipline — no PRD, no prd.json, no agent dispatch. You (Claude) work directly in the main conversation.

**Core principle:** Discipline without ceremony. Small tasks deserve the same rigor (TDD, verification, review) but not the same overhead (PRD, subagents, prd.json).

**Announce at start:** "I'm using the focused-task skill for this implementation."

## When to Use

**Good fit:**
- Clear bugfix with known root cause
- Small feature (1-5 files changed)
- Refactor with well-defined scope
- Single-story task with obvious acceptance criteria
- User explicitly says "just do it" or "quick fix"

**Bad fit — escalate to PRD:**
- Touches 6+ files
- Multiple stories or unclear acceptance criteria
- Architectural decisions needed
- Novel feature with unknowns
- Cross-cutting concern (auth, logging, etc.)

**When in doubt:** Start with focused-task. If scope grows beyond 5 files or acceptance criteria multiply, stop and escalate: "This is growing beyond focused-task scope. Should I switch to prd-generator?"

## The Process

### Step 1: Define Acceptance Criteria

Before writing any code, state 2-5 acceptance criteria and confirm with the user:

```
Acceptance criteria for this task:
1. [specific, verifiable criterion]
2. [specific, verifiable criterion]
3. [specific, verifiable criterion]

Does this match your expectations?
```

**Don't proceed until confirmed.** This is the scope contract.

### Step 2: Set Up Workspace

- **REQUIRED SUB-SKILL:** Use taskplex:using-git-worktrees
- Create an isolated branch for this work

### Step 3: Implement with TDD

- **REQUIRED SUB-SKILL:** Use taskplex:taskplex-tdd
- Follow RED-GREEN-REFACTOR for each criterion
- Commit after each passing test

### Step 4: Verify

- **REQUIRED SUB-SKILL:** Use taskplex:taskplex-verify
- Run full test suite
- Check each acceptance criterion against evidence

### Step 5: Optional Code Review

For tasks touching 3+ files:
- **SUB-SKILL:** Use taskplex:requesting-code-review
- Fix any Critical or Important issues before proceeding

### Step 6: Finish Branch

- **REQUIRED SUB-SKILL:** Use taskplex:finishing-a-development-branch
- Verify tests, present options, execute choice

## Red Flags

**Never:**
- Skip acceptance criteria definition (even for "obvious" fixes)
- Skip TDD because "it's too small"
- Skip verification because "I just ran the tests"
- Exceed 5 files without checking with user about escalating to PRD

**Always:**
- Get acceptance criteria confirmed before coding
- Use TDD even for single-file changes
- Verify with fresh evidence before claiming done
- Escalate when scope grows

**Escalation triggers:**
- Acceptance criteria exceed 5 items
- Files changed exceed 5
- You discover unknowns mid-implementation
- User adds "one more thing" that changes architecture

## Integration

**Called by:**
- **taskplex:using-taskplex** — Routes well-scoped tasks (1-5 files) here

**Sub-skills used:**
- **taskplex:using-git-worktrees** — REQUIRED: Isolated workspace
- **taskplex:taskplex-tdd** — REQUIRED: TDD discipline
- **taskplex:taskplex-verify** — REQUIRED: Verification gate
- **taskplex:requesting-code-review** — Optional: For 3+ file changes
- **taskplex:finishing-a-development-branch** — REQUIRED: Branch completion
