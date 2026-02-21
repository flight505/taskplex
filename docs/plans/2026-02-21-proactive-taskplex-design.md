# Design: Proactive TaskPlex v3.0

**Date:** 2026-02-21
**Author:** Jesper Vang
**Status:** Approved
**Version:** 2.0.8 → 3.0.0

---

## Problem

TaskPlex is a manual-only system. Users must type `/taskplex:start` and walk through an 8-checkpoint wizard before any autonomous execution happens. The competing Superpowers plugin (55k stars) feels "always-on" — it injects itself at session start and auto-suggests planning, TDD, and verification based on what the user is doing.

TaskPlex has superior execution intelligence (PRD generation, error recovery, SQLite knowledge persistence, model routing, background mode, dashboard). But Superpowers has superior discipline enforcement (SessionStart hook, 1% mandatory skill gate, TDD enforcement, verification gates, workflow chaining).

## Goal

Absorb all of Superpowers' discipline patterns into TaskPlex, making Superpowers unnecessary. TaskPlex v3.0 becomes the ONE plugin for the entire development lifecycle: proactive awareness → planning → execution → verification → merge.

## Design Decision

**Approach C: Layered Architecture** — Skills for discipline, hooks for proactivity, agents for execution.

Clean separation of concerns across 5 layers:

```
Layer 1: PROACTIVITY  — hooks fire automatically, inject context
Layer 2: DISCIPLINE   — skills auto-invoke based on context
Layer 3: INTELLIGENCE — existing TaskPlex execution smarts
Layer 4: EXECUTION    — agent pipeline with two-stage review
Layer 5: ORCHESTRATION — commands, scripts, dashboard
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    TaskPlex v3.0 Architecture                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  LAYER 1: PROACTIVITY (automatic — no user action needed)       │
│  ┌───────────────────────────────────────────────────────┐      │
│  │  SessionStart hook (startup|resume|clear|compact)     │      │
│  │  → session-context.sh                                 │      │
│  │  → Injects using-taskplex + prd.json status           │      │
│  └───────────────────────────────────────────────────────┘      │
│       ↓ Claude now aware of TaskPlex in every session           │
│                                                                 │
│  LAYER 2: DISCIPLINE (auto-invoked by Claude based on context)  │
│  ┌─────────────────┐ ┌──────────────┐ ┌───────────────┐        │
│  │  using-taskplex  │ │ taskplex-tdd │ │taskplex-verify│        │
│  │  (1% gate +      │ │ (RED-GREEN-  │ │ (Iron Law:    │        │
│  │   decision tree)  │ │  REFACTOR)   │ │  evidence     │        │
│  └────────┬─────────┘ └──────┬───────┘ │  before claim)│        │
│           │                  │         └───────┬───────┘        │
│           ↓                  ↓                 ↓                │
│  "Build X" → PRD      Before coding     Before "done"          │
│                                                                 │
│  LAYER 3: INTELLIGENCE (TaskPlex-unique execution smarts)       │
│  ┌──────────────┐ ┌──────────────┐ ┌────────────────┐          │
│  │prd-generator  │ │prd-converter │ │failure-analyzer│          │
│  │(auto-invocable│ │(auto-invocable│ │(internal only) │          │
│  │ context:fork) │ │ context:fork) │ │                │          │
│  └──────┬───────┘ └──────┬───────┘ └───────┬────────┘          │
│         │ PRD.md         │ prd.json        │ retry strategy     │
│         └────────┬───────┘                 │                    │
│                  ↓                         │                    │
│  LAYER 4: EXECUTION (agent pipeline)       │                    │
│  ┌────────────────────────────────────────────────────────┐     │
│  │                                                        │     │
│  │  implementer → validator → spec-reviewer → code-       │     │
│  │  (TDD + verify  (acceptance  (Stage 1: right  reviewer │     │
│  │   REQUIRED)      criteria)    thing built?)   (Stage 2  │     │
│  │                                               quality)  │     │
│  │       ↑ retry                                          │     │
│  │       └──── failure-analyzer (categorize + hint) ──────┘     │
│  │                                                        │     │
│  │  merger (branch ops)    knowledge.db (SQLite learning)  │     │
│  │  model routing          decision calls (1-shot Opus)    │     │
│  │  parallel worktrees     pre-compact state saving        │     │
│  └────────────────────────────────────────────────────────┘     │
│                  ↓                                              │
│  LAYER 5: ORCHESTRATION                                         │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  /taskplex:start (wizard — optional entry point)       │     │
│  │  taskplex.sh (execution loop)                          │     │
│  │  parallel.sh (worktree-based concurrency)              │     │
│  │  monitor/ (Vue 3 dashboard sidecar)                    │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  HOOKS (safety net — fires automatically)                       │
│  Stop: blocks premature exit                                    │
│  TaskCompleted: gates on test pass                              │
│  SubagentStart: knowledge injection (implementer, spec-reviewer)│
│  SubagentStop: inline validation + learnings extraction         │
│  PreCompact: saves state before context compression             │
│  PreToolUse: blocks destructive commands, injects edit context  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Layer 1: SessionStart Context Injection

**New file:** `hooks/session-context.sh`

Fires on every `startup`, `resume`, `clear`, and `compact` event. Reads `skills/using-taskplex/SKILL.md` and injects it as `additionalContext` wrapped in `<EXTREMELY_IMPORTANT>` tags. If `prd.json` exists with pending stories, appends a status summary.

**Modified:** `hooks/hooks.json` — adds sync SessionStart entry with `matcher: "startup|resume|clear|compact"`, `statusMessage`, and `timeout: 5`. Existing async monitor hook unchanged.

---

## Layer 2: Discipline Skills

### using-taskplex

**New file:** `skills/using-taskplex/SKILL.md`

The 1% mandatory gate. Replaces `using-superpowers`. Contains:

- The 1% rule: "If even 1% chance a skill applies, you MUST invoke it"
- TaskPlex skill catalog with trigger descriptions
- Decision graph routing user intent to correct skill
- Red flags table preventing rationalization
- Workflow priority order
- Coexistence note (supersedes Superpowers when both installed)

Frontmatter: `disable-model-invocation: false`, `user-invocable: false` (injected via SessionStart, not in `/` menu).

**Decision graph:**

```
Active prd.json? → Report status, offer resume
Building/adding/implementing? → prd-generator
Bug fix with unclear scope? → prd-generator
Touches 3+ files? → prd-generator
Single-file implementation? → taskplex-tdd
Claiming completion? → taskplex-verify
None of the above → Proceed normally
```

### taskplex-tdd

**New file:** `skills/taskplex-tdd/SKILL.md`

TDD enforcement. Auto-invoked before any implementation.

Core rule: "NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST."

RED-GREEN-REFACTOR cycle with pragmatic adaptations:
- No test infra → set it up first
- Existing code without tests → characterization tests first
- Pure CSS/config → skip TDD
- Bug fix → reproduce with test first

Frontmatter: `disable-model-invocation: false`, `user-invocable: true`.

### taskplex-verify

**New file:** `skills/taskplex-verify/SKILL.md`

Verification gate. Auto-invoked before any completion claim.

The Iron Law: "NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE."

Five-step verification: IDENTIFY → RUN → READ → VERIFY → CLAIM.

Integrates with existing hook system for triple-layer enforcement:
1. Skill (cognitive discipline)
2. TaskCompleted hook (test gate)
3. Stop hook (exit gate)

Frontmatter: `disable-model-invocation: false`, `user-invocable: true`.

---

## Layer 3: Auto-Invocation Changes

Three existing skills change `disable-model-invocation` from `true` to `false`:

| Skill | Change | Rationale |
|-------|--------|-----------|
| prd-generator | `true` → `false` | Claude auto-invokes when using-taskplex routes feature requests |
| prd-converter | `true` → `false` | Claude auto-invokes after PRD generation |
| failure-analyzer | `true` → `false` | Claude can use during any debugging, not just inside implementer |

Description updates for prd-generator and prd-converter to include proactive trigger phrases.

All other frontmatter unchanged (`context: fork`, `agent: Explore`, `model: sonnet`).

---

## Layer 4: Agent Enhancements

### New agent: spec-reviewer

**New file:** `agents/spec-reviewer.md`

Stage 1 of two-stage review. Checks spec compliance only: every acceptance criterion implemented, nothing more, nothing less.

- Model: `haiku` (mechanical check, fast/cheap)
- permissionMode: `dontAsk`
- maxTurns: 30
- Read-only (no Edit/Write/Task)

Output: `{ spec_compliance: "pass"|"fail", issues: [...], verdict: "approve"|"reject" }`

### Modified: implementer

Add two REQUIRED blocks to prompt:
1. REQUIRED TDD discipline (RED-GREEN-REFACTOR for each criterion)
2. REQUIRED verification before completion (evidence before claims)

Add preloaded skills: `taskplex-tdd`, `taskplex-verify` (alongside existing `failure-analyzer`).

### Modified: code-reviewer

Description update only — clarify it's Stage 2 (code quality), runs only after spec-reviewer approves.

### Modified: validator

Description update only — clarify role as acceptance criteria verification (read-only), distinct from spec-review.

### Execution pipeline

```
implementer (TDD + verify REQUIRED)
    ↓
validator (acceptance criteria — read-only)
    ↓
spec-reviewer (Stage 1: spec compliance — mandatory)
    ↓ only if spec passes
code-reviewer (Stage 2: code quality — config-driven)
    ↓
commit + mark complete
```

---

## Layer 5: Orchestration Changes

### taskplex.sh

Add `run_spec_review()` function (modeled on existing `run_code_review()`). Insert in pipeline between validator and code-reviewer. Spec review is mandatory by default (`spec_review: true` in config).

### start.md

Add proactive entry note. When prd.json already exists (created via auto-invoked skills), wizard detects it and skips to Checkpoint 7 (config). No structural changes to the wizard itself.

### hooks.json

- Add sync SessionStart hook (Layer 1)
- Add spec-reviewer to SubagentStart knowledge injection matcher

### plugin.json

- Add 3 skills: using-taskplex, taskplex-tdd, taskplex-verify
- Add 1 agent: spec-reviewer
- Version: 3.0.0

---

## Superpowers Replacement Matrix

| Superpowers Skill | TaskPlex v3.0 Replacement | Improvement |
|-------------------|--------------------------|-------------|
| using-superpowers | using-taskplex | Decision tree, prd.json detection, specific routing |
| brainstorming | prd-generator (auto-invoked) | Structured PRD with acceptance criteria |
| writing-plans | prd-converter (auto-invoked) | Machine-executable JSON with dependencies |
| test-driven-development | taskplex-tdd | Same discipline + pragmatic rules |
| verification-before-completion | taskplex-verify | Triple-layer enforcement (skill + 2 hooks) |
| subagent-driven-development | taskplex.sh orchestration | Error categorization, retry, knowledge |
| executing-plans | taskplex.sh background mode | Unattended execution |
| dispatching-parallel-agents | parallel.sh | Wave-based with worktrees |
| using-git-worktrees | Built into taskplex.sh | Automatic setup/cleanup |
| finishing-a-development-branch | merger agent | Automated merge with conflict detection |
| requesting-code-review | spec-reviewer + code-reviewer | Two-stage pipeline, automated in loop |
| receiving-code-review | Implementer retry loop | Feedback as retry context |

---

## File Inventory

| File | Action | Layer |
|------|--------|-------|
| `hooks/session-context.sh` | NEW | L1 |
| `hooks/hooks.json` | MODIFY | L1 + L4 |
| `skills/using-taskplex/SKILL.md` | NEW | L2 |
| `skills/taskplex-tdd/SKILL.md` | NEW | L2 |
| `skills/taskplex-verify/SKILL.md` | NEW | L2 |
| `skills/prd-generator/SKILL.md` | MODIFY | L3 |
| `skills/prd-converter/SKILL.md` | MODIFY | L3 |
| `skills/failure-analyzer/SKILL.md` | MODIFY | L3 |
| `agents/implementer.md` | MODIFY | L4 |
| `agents/spec-reviewer.md` | NEW | L4 |
| `agents/code-reviewer.md` | MODIFY | L4 |
| `agents/validator.md` | MODIFY | L4 |
| `scripts/taskplex.sh` | MODIFY | L5 |
| `commands/start.md` | MODIFY | L5 |
| `.claude-plugin/plugin.json` | MODIFY | Manifest |

**15 files total:** 5 new, 10 modified. Zero deletions.

---

## Version

`2.0.8` → `3.0.0` (major: new architectural layer, new plugin behavior, breaking change in presentation)

---

## Non-Goals

- No changes to monitor/dashboard sidecar
- No changes to parallel.sh
- No changes to knowledge-db.sh or decision-call.sh
- No new hook events beyond existing Claude Code CLI support
- No external plugin dependencies
