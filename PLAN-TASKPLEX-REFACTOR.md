# Plan: TaskPlex Refactor — Superpowers-Compatible Always-On Plugin

**Date:** 2026-03-04
**Goal:** Make TaskPlex identical to Superpowers but with targeted upgrades that genuinely impact the human developer experience. Remove all heavy orchestration (PRD pipeline, multi-agent system, config, complex hooks) → move to SDK-Bridge.

---

## Current State

TaskPlex v5.2.0 has 18 skills, 5 agents, 5 hooks, config system, PRD pipeline.
Superpowers v4.3.1 has 14 skills, 1 agent, 1 hook, zero config.

**Problem:** TaskPlex is too slow for daily use. The PRD pipeline, multi-agent system, and 5 hooks add latency that defeats the "always-on companion" purpose. Superpowers is fast because it's just markdown skills + 1 lightweight hook.

---

## Design Principle

> TaskPlex = Superpowers + battle-tested upgrades that help the human, not the system.

Every addition must pass this test: **"Does this make the human's daily coding better, or does it just add orchestration complexity?"**

---

## What Stays (From Superpowers, Unchanged)

These 14 skills are the proven Superpowers core. Keep them identical (or near-identical) to upstream:

| # | Skill | Superpowers Name | Notes |
|---|-------|-----------------|-------|
| 1 | brainstorm | brainstorming | Already adapted, keep |
| 2 | taskplex-tdd | test-driven-development | Rename back to `test-driven-development` for Superpowers compatibility |
| 3 | taskplex-verify | verification-before-completion | Rename back to `verification-before-completion` |
| 4 | systematic-debugging | systematic-debugging | Identical |
| 5 | dispatching-parallel-agents | dispatching-parallel-agents | Identical |
| 6 | using-git-worktrees | using-git-worktrees | Identical |
| 7 | finishing-a-development-branch | finishing-a-development-branch | Identical |
| 8 | requesting-code-review | requesting-code-review | Identical |
| 9 | receiving-code-review | receiving-code-review | Identical |
| 10 | subagent-driven-development | subagent-driven-development | Identical |
| 11 | guided-implementation | executing-plans | Keep TaskPlex name (clearer) |
| 12 | writing-plans | writing-plans | Identical |
| 13 | writing-skills | writing-skills | Identical |
| 14 | using-taskplex | using-superpowers | Keep as routing gate, simplified |

## What Stays (TaskPlex Upgrades Worth Keeping)

These additions have proven impact on the human experience:

### 1. `focused-task` skill (v5.2.0)
**Why keep:** Superpowers lacks a lightweight path. Everything goes through brainstorm → write-plan → execute, even for 1-file fixes. `focused-task` gives discipline without ceremony for small tasks. This directly helps humans who want TDD rigor on a quick fix without 10 minutes of planning overhead.

### 2. `failure-analyzer` skill
**Why keep:** When an agent fails, categorizing the error (env_missing vs code_error vs dependency_missing) prevents futile retries. Without this, agents waste 5+ minutes trying to fix environment issues they can't solve. Direct time savings for humans watching agent output.

### 3. `code-reviewer` agent (same as Superpowers)
**Why keep:** Both plugins have this. Keep identical to Superpowers.

### 4. Scale-aware routing in `using-taskplex`
**Why keep:** The 1-5 files → focused-task, 6+ files → "escalate to PRD" routing prevents both under-planning and over-planning. Superpowers' `using-superpowers` doesn't have this distinction.

**Modification:** Instead of routing to internal PRD pipeline, route 6+ file tasks to: "This task is larger than focused-task scope. Consider using SDK-Bridge (`/sdk-bridge:start`) for PRD-driven development."

---

## What Gets Removed (→ Moves to SDK-Bridge)

| Component | Why Remove | Where It Goes |
|-----------|-----------|---------------|
| `prd-generator` skill | Heavy orchestration, slow | SDK-Bridge (already has it) |
| `prd-converter` skill | Heavy orchestration, slow | SDK-Bridge (already has it) |
| `commands/start.md` wizard | 8-checkpoint wizard, slow | SDK-Bridge `/sdk-bridge:start` |
| `agents/architect.md` | Only used by brainstorm (which works fine with Explore agent) | SDK-Bridge |
| `agents/implementer.md` | Only used by subagent-driven-dev with prd.json | SDK-Bridge |
| `agents/reviewer.md` | Spec compliance reviewer for PRD stories | SDK-Bridge |
| `agents/merger.md` | Git merge operations for PRD workflow | SDK-Bridge |
| `hooks/check-destructive.sh` (PreToolUse) | Over-protective for daily use; slows every Bash call | Remove (users have git reflog) |
| `hooks/validate-result.sh` (SubagentStop) | Only relevant for PRD agent pipeline | SDK-Bridge |
| `hooks/task-completed.sh` (TaskCompleted) | Only relevant for PRD story tracking | SDK-Bridge |
| `hooks/teammate-idle.sh` (TeammateIdle) | Only relevant for Agent Teams PRD execution | SDK-Bridge |
| `.claude/taskplex.config.json` system | Config for PRD execution (model, review, interactive) | SDK-Bridge |
| `scripts/check-git.sh` | Only used by start.md wizard | SDK-Bridge |
| `scripts/check-deps.sh` | Only used by start.md wizard | SDK-Bridge |

---

## Target State: TaskPlex v6.0.0

```
taskplex/
├── .claude-plugin/plugin.json
├── agents/
│   └── code-reviewer.md              # 1 agent (same as Superpowers)
├── hooks/
│   └── hooks.json                     # 1 hook (SessionStart only)
├── skills/                            # 16 skills
│   ├── brainstorm/                    # From Superpowers
│   ├── test-driven-development/       # Renamed from taskplex-tdd
│   ├── verification-before-completion/ # Renamed from taskplex-verify
│   ├── systematic-debugging/
│   ├── dispatching-parallel-agents/
│   ├── using-git-worktrees/
│   ├── finishing-a-development-branch/
│   ├── requesting-code-review/
│   ├── receiving-code-review/
│   ├── subagent-driven-development/
│   ├── guided-implementation/         # TaskPlex name (was executing-plans)
│   ├── writing-plans/
│   ├── writing-skills/
│   ├── using-taskplex/                # Simplified routing gate
│   ├── focused-task/                  # TaskPlex upgrade
│   └── failure-analyzer/              # TaskPlex upgrade
├── scripts/
│   └── check-destructive.sh           # Keep as optional safety net (not hooked)
├── README.md
├── CLAUDE.md
└── CHANGELOG.md
```

### Key Metrics

| Metric | v5.2.0 | v6.0.0 Target | Superpowers |
|--------|--------|---------------|-------------|
| Skills | 18 | 16 | 14 |
| Agents | 5 | 1 | 1 |
| Hooks | 5 | 1 | 1 |
| Config files | 1 | 0 | 0 |
| Commands | 1 | 0 | 3 |
| Scripts | 3 | 1 (optional) | 0 |

---

## Migration Steps

### Phase 1: Restructure Skills (keep, rename, remove)

1. **Rename `taskplex-tdd/` → `test-driven-development/`**
   - Update SKILL.md name field
   - Update all cross-references in other skills

2. **Rename `taskplex-verify/` → `verification-before-completion/`**
   - Update SKILL.md name field
   - Update all cross-references

3. **Remove skills:** `prd-generator/`, `prd-converter/`
   - These move to SDK-Bridge

4. **Simplify `using-taskplex`**
   - Remove PRD routing logic
   - Remove prd.json detection
   - Add pointer to SDK-Bridge for large tasks
   - Keep focused-task routing for 1-5 file tasks
   - Keep skill catalog and decision tree

5. **Simplify `focused-task`**
   - Remove reference to PRD escalation path (point to SDK-Bridge instead)
   - Keep TDD + verify + optional code review flow

6. **Update `subagent-driven-development`**
   - Remove prd.json-specific resume logic (that moves to SDK-Bridge)
   - Keep core pattern: fresh subagent per task + two-stage review
   - Keep as skill for users who write plans manually (writing-plans → subagent-driven-development)

7. **Sync skill content with Superpowers upstream**
   - Diff each of the 14 shared skills against Superpowers v4.3.1
   - Take upstream improvements (rationalization tables, red flags, CSO fixes)
   - Keep TaskPlex improvements where they genuinely add value

### Phase 2: Restructure Agents

1. **Keep `code-reviewer.md`** — sync with Superpowers version
2. **Remove:** `architect.md`, `implementer.md`, `reviewer.md`, `merger.md` (→ SDK-Bridge)

### Phase 3: Simplify Hooks

1. **Keep `SessionStart` hook** — `session-context.sh` injects using-taskplex awareness
2. **Remove:** PreToolUse, SubagentStop, TaskCompleted, TeammateIdle hooks
3. **Update `hooks.json`** — single hook only
4. **Remove hook scripts:** `check-destructive.sh`, `validate-result.sh`, `task-completed.sh`, `teammate-idle.sh`

### Phase 4: Remove Orchestration Infrastructure

1. **Remove `commands/start.md`** — wizard moves to SDK-Bridge
2. **Remove config system** — no `.claude/taskplex.config.json`
3. **Remove `scripts/check-deps.sh`** and **`scripts/check-git.sh`** — only used by wizard
4. **Keep `scripts/check-destructive.sh`** as optional utility (not hooked)

### Phase 5: Update Documentation

1. **Rewrite `CLAUDE.md`** — reflect lightweight architecture
2. **Rewrite `TASKPLEX-ARCHITECTURE.md`** — or remove (may be overkill for a lightweight plugin)
3. **Update `README.md`** — position as "Superpowers + targeted upgrades"
4. **Write `CHANGELOG.md` v6.0.0 entry** — document the split

### Phase 6: Update Plugin Manifest

1. **Update `plugin.json`** — remove agents, update skill list, bump to v6.0.0
2. **Update marketplace** — version bump

### Phase 7: Verify

1. Run marketplace validation (`validate-plugin-manifests.sh`)
2. Run `plugin-doctor.sh`
3. Install and test: `/taskplex:focused-task`, skill auto-triggering, SessionStart hook
4. Verify no broken cross-references between skills

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Users rely on `/taskplex:start` | Document migration path to SDK-Bridge |
| Skills reference removed agents | Audit all skill cross-references |
| Superpowers upstream diverges | Pin to v4.3.1, periodic sync |
| Memory references stale architecture | Update MEMORY.md after refactor |

---

## Open Questions

1. **Commands:** Superpowers has 3 commands (brainstorm, write-plan, execute-plan). Should TaskPlex add these as convenience shortcuts?
2. **Naming:** Keep `using-taskplex` or rename to `using-superpowers`? (Identity question)
3. **Subagent prompt templates:** Superpowers has `implementer-prompt.md`, `spec-reviewer-prompt.md`, `code-quality-reviewer-prompt.md` inside subagent-driven-development. Should TaskPlex keep these or use the agent definitions?
