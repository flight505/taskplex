# TaskPlex Architecture

**Version 5.2.0** | Last Updated: 2026-03-03

Ground truth for TaskPlex's design. For developer instructions and config schema, see [CLAUDE.md](./CLAUDE.md). For version history, see [CHANGELOG.md](./CHANGELOG.md).

---

## 1. Overview & Philosophy

TaskPlex is an **always-on autonomous development companion** for Claude Code. It provides 18 discipline skills, 5 subagents, and 5 hooks that together enable PRD-driven autonomous execution with TDD enforcement, verification gates, and two-stage code review.

**v5.0 design principle:** Leverage native Claude Code features instead of custom infrastructure.

| Feature | v4.x (custom) | v5.0 (native) |
|---------|---------------|--------------|
| Memory | SQLite `knowledge.db` (526 lines) | `memory: project` in agent frontmatter |
| Routing | `decision-call.sh` (332 lines) | `model:` field in agent frontmatter |
| Parallelism | `parallel.sh` (787 lines) | Orchestrator-level worktree via `using-git-worktrees` skill |
| Task tracking | `progress.txt` + bash loop (2,361 lines) | `TaskCreate` / `TaskUpdate` (native) |
| Orchestration | `taskplex.sh` bash loop | `subagent-driven-development` skill |

**Core principles:**

1. **Always-on awareness** — SessionStart hook injects context; skills auto-trigger
2. **Challenge assumptions first** — brainstorm with architect agent before implementation
3. **Discipline before code** — 17 skills enforce TDD, verification, planning, review
4. **Precise PRD** — interactive refinement produces verifiable acceptance criteria
5. **Fresh context per task** — each agent starts with clean context via `memory: project`
6. **Quality gates via hooks** — destructive commands blocked, validation before agent completion

---

## 2. Three-Layer Architecture

### Layer 1: Skills (18)

Skills are the core value — discipline patterns that shape how Claude works:

| Category | Skills | Purpose |
|----------|--------|---------|
| **Gate** | using-taskplex | Always-on 1% routing gate |
| **Discipline** | taskplex-tdd, taskplex-verify | TDD enforcement, verification gates |
| **Planning** | brainstorm, prd-generator, prd-converter, writing-plans | Idea → PRD → execution format |
| **Execution** | focused-task, subagent-driven-development, guided-implementation, dispatching-parallel-agents | Task dispatch patterns (scale-aware) |
| **Git** | using-git-worktrees, finishing-a-development-branch | Branch lifecycle |
| **Review** | requesting-code-review, receiving-code-review | Code review workflow |
| **Diagnosis** | failure-analyzer, systematic-debugging | Error categorization |
| **Meta** | writing-skills | Creating new skills |

Skills are pure markdown — no runtime dependencies.

### Layer 2: Agents (5)

| Agent | Model | Permission | maxTurns | Purpose |
|-------|-------|------------|----------|---------|
| architect | sonnet | dontAsk | 30 | Read-only codebase exploration (brainstorm) |
| implementer | inherit | bypassPermissions | 150 | Code a single story (TDD + verify, runs in orchestrator's worktree) |
| reviewer | haiku | dontAsk | 40 | Spec compliance + validation (two-phase) |
| code-reviewer | sonnet | dontAsk | 40 | Code quality review (opt-in) |
| merger | haiku | bypassPermissions | 50 | Git branch operations |

**Design decisions:**
- Worktree isolation is handled at orchestration level (`using-git-worktrees` skill) — the implementer runs inside the orchestrator's worktree, not its own. This avoids nested worktree issues with Claude Code's agent system.
- `memory: project` is worktree-local (`.claude/agent-memory/`) — each story starts fresh. Cross-story context flows through the orchestrator's `learnings` field. Auto memory (`~/.claude/projects/`) IS shared across worktrees
- `disallowedTools: [Task]` on implementer prevents subagent spawning
- `disallowedTools: [Write, Edit, Task]` on reviewer/code-reviewer enforces read-only
- `model: inherit` means implementer uses the user's configured model
- `skills: [failure-analyzer, taskplex-tdd, taskplex-verify]` on implementer preloads discipline
- `skills: [brainstorm]` on architect preloads brainstorming patterns
- `skills: [receiving-code-review]` on reviewer preloads review evaluation patterns
- `skills: [using-git-worktrees]` on merger preloads git worktree awareness

### Layer 3: Hooks (5)

| Event | Script | Type | Purpose |
|-------|--------|------|---------|
| SessionStart | `session-context.sh` | sync | Detect prd.json, inject using-taskplex awareness |
| PreToolUse (Bash) | `check-destructive.sh` | sync | Block `git push --force`, `reset --hard`, etc. (with git status context) |
| SubagentStop (implementer) | `validate-result.sh` | sync | Run test/build/typecheck, parse structured output, exit 2 if fail |
| TaskCompleted | `task-completed.sh` | sync | Verify story reviewed + tests pass before task completion |
| TeammateIdle | `teammate-idle.sh` | sync | Assign next story to idle Agent Teams teammate |

Plus agent-scoped hooks in `implementer.md` frontmatter:

| Event | Matcher | Script | Purpose |
|-------|---------|--------|---------|
| PreToolUse | Bash | `check-destructive.sh` | Block dangerous commands during implementation |

---

## 3. Data Flow

### Proactive Path (always-on)

```
Session starts
    │
    ├─ SessionStart hook fires (session-context.sh)
    │   ├─ Detects prd.json
    │   └─ Injects status summary into conversation context
    │
    ├─ using-taskplex skill auto-triggers on relevant prompts
    │   ├─ Routes to focused-task if well-scoped (1-5 files)
    │   ├─ Routes to brainstorm if exploration needed
    │   ├─ Routes to prd-generator/prd-converter if PRD needed
    │   └─ Routes to taskplex:start if execution needed
    │
    └─ Discipline skills auto-trigger on matching patterns
        ├─ taskplex-tdd: enforces RED-GREEN-REFACTOR
        ├─ taskplex-verify: enforces verification gates
        └─ systematic-debugging: structured debugging
```

### Explicit Path (via /taskplex:start)

```
User → /taskplex:start (wizard)
    │
    ├─ Checkpoints 1-2: Dependencies + git validation
    ├─ Checkpoints 3-6: PRD generation → prd.json
    ├─ Checkpoint 7: Config (model, review, interactive)
    └─ Checkpoint 8: Launch subagent-driven-development
```

### Execution Pipeline

```
subagent-driven-development skill guides main conversation:

For each story in prd.json:
    │
    ├─ Dispatch implementer agent (via Task tool)
    │   ├─ Agent implements story (TDD enforced via skills)
    │   ├─ Agent commits with structured output
    │   └─ SubagentStop hook validates (test/build/typecheck)
    │       └─ If fail: agent continues fixing (self-healing)
    │
    ├─ Dispatch reviewer agent
    │   ├─ Phase 1: Spec compliance (file:line evidence)
    │   └─ Phase 2: Validation (run commands, verify commit)
    │
    ├─ [Optional] Dispatch code-reviewer agent
    │   └─ Code quality: architecture, security, types, tests
    │
    └─ Update task status via TaskUpdate
```

### State Files

| File | Purpose |
|------|---------|
| `prd.json` | Source of truth for story status |
| `.claude/taskplex.config.json` | Execution configuration |
| `tasks/prd-{feature}.md` | Human-readable PRD |

---

## 4. Hook Details

**SessionStart: session-context.sh** — Fires on startup, resume, clear, compact. Detects `prd.json` and injects status summary. Hardened against malformed JSON.

**PreToolUse: check-destructive.sh** — Blocks: `git push --force`, `git reset --hard`, `git clean -f`, direct pushes to main/master. Allows `--force-with-lease`. Includes git status in `permissionDecisionReason` for agent awareness on deny.

**SubagentStop: validate-result.sh** — Reads `test_command`, `build_command`, `typecheck_command` from config. Extracts `last_assistant_message` to parse implementer's structured JSON output — skips validation if status is `"skipped"`, includes `retry_hint` in failure feedback. Runs each command, collects failures. If any fail, exits 2 — the implementer continues in the same context with error injected as feedback (self-healing loop). Prevents infinite loops via `stop_hook_active` check.

**TaskCompleted: task-completed.sh** — Gates story task completion. Checks that the story has been reviewed (not still `in_progress` in prd.json) and that configured tests pass. Exits 2 to block premature completion. Only fires for tasks with US-XXX in the subject.

**TeammateIdle: teammate-idle.sh** — Queries `prd.json` for next ready story (respects dependency order). Marks story as `in_progress`, returns assignment context.

---

## 5. Agent Pipeline

```
brainstorm (architect agent)
    │
    v
PRD generation (prd-generator + prd-converter skills)
    │
    v
Per-story:
    implementer → reviewer → code-reviewer (opt-in)
    │
    v
merger (on completion)
```

### Structured Output (implementer)

```json
{
  "story_id": "US-001",
  "status": "completed|failed|skipped",
  "error_category": null,
  "files_modified": ["src/models/task.ts"],
  "files_created": ["src/components/Badge.tsx"],
  "commits": ["abc1234"],
  "learnings": ["This project uses barrel exports"],
  "acceptance_criteria_results": [
    {"criterion": "Add priority column", "passed": true, "evidence": "Migration ran"}
  ],
  "retry_hint": null
}
```

---

## 6. Safety & Quality

### Destructive Command Blocking
Agent-scoped PreToolUse hook blocks: `git push --force`, `git reset --hard`, `git clean -f`, pushes to main/master.

### Rationalization Prevention
The `taskplex-tdd` skill includes tables of common rationalizations for skipping tests, with correct responses.

### Two-Layer Verification
1. `taskplex-verify` skill (cognitive) — Claude self-checks before claiming done
2. `validate-result.sh` hook (mechanical) — automated test/build/typecheck gate

---

## 7. Migration from v4.x

| v4.x Component | v5.0 Replacement | Lines Removed |
|----------------|------------------|---------------|
| `taskplex.sh` | `subagent-driven-development` skill | 2,361 |
| `parallel.sh` | Orchestrator-level worktree (`using-git-worktrees`) | 787 |
| `knowledge-db.sh` | `memory: project` in frontmatter | 526 |
| `decision-call.sh` | `model:` in agent frontmatter | 332 |
| `teams.sh` | Agent Teams (native) | 123 |
| `monitor/` | Removed (sidecar extracted) | ~2,000 |
| `validator.md` + `spec-reviewer.md` | `reviewer.md` (merged) | 144 → 100 |
| 9 hook scripts | 3 hook scripts (4 hooks) | ~500 |

**Total reduction:** ~8,400 → ~1,100 lines of infrastructure.

**Compatible:** Existing `prd.json` files work unchanged. Existing `taskplex.config.json` files have unrecognized fields (harmless, ignored).

**Abandoned:** `knowledge.db` (SQLite) — replaced by native `memory: project`. `progress.txt` — replaced by `TaskCreate`/`TaskUpdate`.

---

## 8. Version History

| Version | Date | Highlights |
|---------|------|------------|
| 5.2.0 | 2026-03-03 | Workflow refactoring: focused-task skill, executing-plans→guided-implementation rename, resume intelligence, code review boundaries |
| 5.0.0 | 2026-02-28 | Remove orchestration, leverage native Claude Code. 6→5 agents, 13→4 hooks, 24→8 config options, monitor extracted |
| 4.1.0 | 2026-02-27 | SSC spec hardening, Bayesian confidence tracking |
| 4.0.0 | 2026-02-26 | SOTA transformation: brainstorm, 17 skills, rule-based routing, reward hacking prevention |
| 3.0.0 | 2026-02-22 | Proactive architecture: SessionStart hook, spec-reviewer, always-on gate |
| 2.0.0 | 2026-02-17 | Smart Scaffold: SQLite knowledge, decision calls, inline validation |
| 1.0.0 | 2026-02-11 | Initial release |

For detailed changelogs, see [CHANGELOG.md](./CHANGELOG.md).
