---
name: guided-implementation
description: "Use when you have a written implementation plan to execute inline with human review checkpoints between batches. YOU (Claude) implement directly — no agent dispatch. For autonomous agent execution, use subagent-driven-development instead."
---

# Guided Implementation

## Overview

Load plan, review critically, execute tasks in batches, report for review between batches.

**Core principle:** Batch execution with checkpoints for architect review.

**Announce at start:** "I'm using the guided-implementation skill to implement this plan."

## How This Differs

| Aspect | Guided Implementation | Subagent-Driven Development |
|--------|----------------------|----------------------------|
| **Who implements** | You (Claude) directly | Fresh subagent per task |
| **Review style** | Human checkpoints between batches | Automated two-stage review |
| **Session** | Can be same or separate session | Same session |
| **Best for** | Plans needing human judgment at each step | Independent tasks with clear acceptance criteria |
| **Context** | Accumulates across batch | Fresh per task (no pollution) |

## The Process

### Step 1: Load and Review Plan
1. Read plan file
2. Review critically - identify any questions or concerns about the plan
3. If concerns: Raise them with the user before starting
4. If no concerns: Create tasks with TaskCreate and proceed

### Step 2: Execute Batch
**Default: First 3 tasks**

For each task:
1. Mark as in_progress
2. Follow each step exactly (plan has bite-sized steps)
3. Run verifications as specified
4. Mark as completed

### Step 3: Report
When batch complete:
- Show what was implemented
- Show verification output
- Say: "Ready for feedback."

### Step 4: Continue
Based on feedback:
- Apply changes if needed
- Execute next batch
- Repeat until complete

### Step 5: Complete Development

After all tasks complete and verified:
- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use taskplex:finishing-a-development-branch
- Follow that skill to verify tests, present options, execute choice

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker mid-batch (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly

**Ask for clarification rather than guessing.**

## When to Revisit Earlier Steps

**Return to Review (Step 1) when:**
- Partner updates the plan based on your feedback
- Fundamental approach needs rethinking

**Don't force through blockers** - stop and ask.

## Remember
- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Reference skills when plan says to
- Between batches: just report and wait
- Stop when blocked, don't guess
- Never start implementation on main/master branch without explicit user consent

## Integration

**Required workflow skills:**
- **taskplex:using-git-worktrees** - REQUIRED: Set up isolated workspace before starting
- **taskplex:writing-plans** - Creates the plan this skill executes
- **taskplex:finishing-a-development-branch** - Complete development after all tasks
