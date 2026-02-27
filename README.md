# TaskPlex

<p align="center">
  <img src="./assets/TaskPlex_Hero@0.5x.png" alt="TaskPlex - Always-On Autonomous Dev Companion" width="800" />
</p>

[![Version](https://img.shields.io/badge/version-4.1.0-blue.svg)](https://github.com/flight505/taskplex)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://github.com/anthropics/claude-code)

Always-on autonomous development companion for Claude Code. Brainstorming, TDD enforcement, difficulty-aware model routing, SSC spec hardening, Bayesian knowledge persistence, two-stage code review, reward hacking prevention, and wave-based parallel execution.

Discipline skills adapted from [Superpowers](https://github.com/obra/superpowers) (MIT, Jesse Vincent). Orchestration based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

---

## How It Works

TaskPlex has two paths — both lead to the same execution pipeline:

**Proactive path (always-on):** The `SessionStart` hook detects active `prd.json` and injects context. The `using-taskplex` skill automatically routes to the right workflow skill based on what you're doing.

**Explicit path:** Run `/taskplex:start` for the interactive 8-checkpoint wizard.

### Execution Pipeline

```
Brainstorm → PRD → Decision Call → Spec Hardening → Implement → Validate → Review → Merge
     │              │                    │                │           │          │
  architect     knowledge-db.sh    harden_spec()    implementer  spec-reviewer  merger
  agent         + decision-call.sh  (Haiku SSC)     (fresh per   + code-reviewer agent
                                                     story)       (two-stage)
```

Each story gets a **fresh Claude subagent** with clean context. The orchestrator (`taskplex.sh`) manages the loop, routing, knowledge, and validation — agents remain stateless.

---

## Key Features

### Always-On Awareness (v3.0+)

The plugin activates automatically via hooks — no need to invoke `/taskplex:start`:

- **SessionStart hook** detects active `prd.json` and injects status
- **using-taskplex skill** (1% gate) routes to the right workflow: brainstorm for new ideas, TDD for implementation, systematic-debugging for failures, verify before claiming done
- **17 skills** covering the full development lifecycle

### Brainstorming (v4.0+)

Before jumping to a PRD, the `brainstorm` skill challenges assumptions using the `architect` agent (read-only codebase explorer). Produces a Design Brief saved to `docs/plans/`.

### SSC Spec Hardening (v4.1)

Before implementation, a Haiku call tightens vague acceptance criteria to prevent spec gaming (63-75% gaming rate per [SSC paper](https://arxiv.org/abs/2507.18742)). Concrete bounds replace vague language. First attempt only.

### Difficulty-Aware Routing (v4.0+)

Rule-based fast path eliminates ~40% of Opus decision calls:
- Simple stories (rename, config) → Haiku
- Standard stories → Sonnet
- Complex/retry stories → Opus with effort auto-tuning

### Bayesian Knowledge Persistence (v4.1)

SQLite knowledge store with 6 tables. Learnings with 2+ applications switch from time-based decay to Bayesian posterior — reliable knowledge persists, unreliable decays fast.

### Two-Stage Code Review

1. **Spec compliance** (mandatory) — `spec-reviewer` agent verifies every acceptance criterion
2. **Code quality** (opt-in) — `code-reviewer` agent reviews architecture, security, types, tests, performance

Both run as separate agents, not in-context suggestions. Cannot be rationalized away.

### Reward Hacking Prevention (v4.0+)

- **Test file checksums** — computed before implementation, verified after
- **COMPLETE signal gating** — agent can't claim done without validation pass
- **Scope drift detection** — configurable warn/block/review strategies

### Hook-Based Enforcement

| Hook | Event | Purpose |
|------|-------|---------|
| session-context.sh | SessionStart | Inject active prd.json status |
| inject-knowledge.sh | SubagentStart | SQLite context injection per agent |
| validate-result.sh | SubagentStop | Inline typecheck/build/test + learning extraction |
| stop-guard.sh | Stop | Block premature exit when stories remain |
| task-completed.sh | TaskCompleted | Gate completion on test pass |
| check-destructive.sh | PreToolUse | Block `git push --force`, `reset --hard`, etc. |
| inject-edit-context.sh | PreToolUse | File pattern context per edit |
| pre-compact.sh | PreCompact | Save state before context compaction |
| teammate-idle.sh | TeammateIdle | Assign work in Agent Teams mode |

All enforcement is **mechanical** (hook-based), not advisory. The model cannot rationalize its way around hooks.

### Parallel Execution

Four execution modes:

| Mode | How | When |
|------|-----|------|
| **Sequential** (default) | One story at a time | Most projects |
| **Parallel** | Wave-based git worktrees | Independent stories, large PRDs |
| **Interactive** | Pause between stories for approval | High-stakes changes |
| **Agent Teams** | Claude Code Agent Teams orchestration | Opt-in, experimental |

---

## Quick Start

### Prerequisites

- [Claude Code CLI](https://code.claude.com)
- `jq` JSON parser (`brew install jq` on macOS)
- Git repository
- Authentication (OAuth token or API key)

### Installation

```bash
# Add marketplace
/plugin marketplace add flight505/flight505-marketplace

# Install plugin
/plugin install taskplex@flight505-marketplace
```

### Usage

**Proactive (recommended):** Just start working. TaskPlex activates automatically when it detects relevant context.

**Explicit:** Run `/taskplex:start` for the 8-checkpoint interactive wizard:

1. **Dependency check** — verifies `claude`, `jq`, and `coreutils`
2. **Project input** — describe your feature or provide a file path
3. **Brainstorm** — optional design challenge before PRD
4. **Generate PRD** — structured PRD with clarifying questions
5. **Review PRD** — approve, improve, or edit
6. **Convert to JSON** — `prd.json` with dependency inference
7. **Execution settings** — iterations, timeout, model, mode
8. **Launch** — starts the orchestration loop

---

## Agents

| Agent | Model | Permission | Purpose |
|-------|-------|------------|---------|
| **architect** | sonnet | dontAsk | Read-only codebase explorer for brainstorm |
| **implementer** | inherit | bypassPermissions | Code a single story (TDD + verify enforced) |
| **validator** | haiku | dontAsk | Verify acceptance criteria |
| **spec-reviewer** | haiku | dontAsk | Spec compliance review (Stage 1, mandatory) |
| **code-reviewer** | sonnet | dontAsk | Code quality review (Stage 2, opt-in) |
| **merger** | haiku | bypassPermissions | Git branch operations |

Each agent follows **least privilege** — only the tools needed for its role. Fresh context per invocation prevents context rot.

---

## Skills (17)

| Skill | Triggers When |
|-------|--------------|
| **brainstorm** | New feature described, before PRD |
| **prd-generator** | Feature needs structured requirements |
| **prd-converter** | PRD markdown needs execution format |
| **taskplex-tdd** | Before any implementation |
| **taskplex-verify** | Before claiming work is done |
| **systematic-debugging** | Bug, test failure, or unexpected behavior |
| **failure-analyzer** | Implementation fails with unclear error |
| **writing-plans** | Need detailed task-by-task plan |
| **executing-plans** | Executing plan in separate session |
| **subagent-driven-development** | Executing plan in current session |
| **dispatching-parallel-agents** | 2+ independent tasks |
| **using-git-worktrees** | Feature work needs isolation |
| **finishing-a-development-branch** | Ready to integrate |
| **requesting-code-review** | After task completion |
| **receiving-code-review** | Responding to review feedback |
| **writing-skills** | Creating or editing skills |
| **using-taskplex** | Always-on routing gate |

All discipline skills adapted from [Superpowers](https://github.com/obra/superpowers) (MIT license, Jesse Vincent).

---

## Knowledge Architecture

Three-layer persistence system:

### Layer 1: Operational Log (`progress.txt`)
Orchestrator-only timestamped entries. Agents never read this.

### Layer 2: SQLite Knowledge Store (`knowledge.db`)
Six tables with Bayesian confidence tracking:

| Table | Purpose |
|-------|---------|
| **learnings** | Codebase patterns, with `applied_count`/`success_count` for Bayesian decay |
| **error_history** | Categorized errors with resolution tracking |
| **decisions** | Per-story decision call results and outcomes |
| **file_patterns** | Discovered file conventions |
| **patterns** | Promoted learnings (3+ story occurrences, no decay) |
| **runs** | Execution lifecycle tracking |

**Confidence formula:** When a learning has been applied 2+ times, confidence switches from time-decay (`0.95^days`) to Bayesian posterior (`(success+1)/(applied+2)`). Reliable knowledge persists; unreliable decays.

### Layer 3: Hook-Based Context Injection
The **SubagentStart hook** queries SQLite and injects per agent:
- Story details and acceptance criteria
- `check_before_implementing` results
- Dependency diffs and established patterns
- Relevant learnings (with Bayesian confidence scores)
- Error history and retry context

---

## Error Handling

| Category | Retryable | Max Retries | Action |
|----------|-----------|-------------|--------|
| `env_missing` | No | 0 | Skip, log for user |
| `test_failure` | Yes | 2 | Retry with test output |
| `timeout` | Yes | 1 | Retry with 1.5x timeout |
| `code_error` | Yes | 2 | Retry with error output |
| `dependency_missing` | No | 0 | Skip, log for user |
| `unknown` | Once | 1 | Retry once, then skip |

**Effort auto-tuning on retries:** Failed stories automatically escalate — retry 2 → Opus/medium, retry 3 → Opus/high.

---

## Configuration

Edit `.claude/taskplex.config.json`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_iterations` | int | 25 | Stop after N iterations (formula: stories x 2.5) |
| `iteration_timeout` | int | 900 | Timeout per iteration in seconds |
| `execution_mode` | string | "foreground" | "foreground" or "background" |
| `execution_model` | string | "sonnet" | "sonnet" or "opus" for implementation |
| `effort_level` | string | "" | "low"/"medium"/"high" (Opus 4.6 only) |
| `branch_prefix` | string | "taskplex" | Git branch prefix |
| `max_retries_per_story` | int | 2 | Max retries before skipping |
| `max_turns` | int | 200 | Max agentic turns per invocation |
| `merge_on_complete` | bool | false | Auto-merge to main |
| `test_command` | string | "" | e.g. "npm test" |
| `build_command` | string | "" | e.g. "npm run build" |
| `typecheck_command` | string | "" | e.g. "tsc --noEmit" |
| `parallel_mode` | string | "sequential" | "sequential", "parallel", "teams" |
| `interactive_mode` | bool | false | Pause between stories |
| `scope_drift_action` | string | "warn" | "warn", "block", or "review" |
| `max_parallel` | int | 3 | Max concurrent agents per wave |
| `worktree_dir` | string | "" | Custom worktree base dir |
| `worktree_setup_command` | string | "" | e.g. "npm install" |
| `conflict_strategy` | string | "abort" | "abort" or "merger" |
| `code_review` | bool | false | Enable two-stage code review |
| `decision_calls` | bool | true | Enable 1-shot decision calls |
| `decision_model` | string | "opus" | Model for decision calls |
| `validate_on_stop` | bool | true | Enable SubagentStop validation |
| `model_routing` | string | "auto" | "auto" or "fixed" |
| `spec_hardening` | bool | true | Enable SSC spec hardening |
| `spec_harden_model` | string | "haiku" | Model for spec hardening |

---

## Authentication

```bash
# OAuth (recommended for Max subscribers)
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN='your-token'

# API key (alternative)
export ANTHROPIC_API_KEY='your-key'
```

---

## Key Files

| File | Purpose |
|------|---------|
| `prd.json` | Task list with execution status (source of truth) |
| `progress.txt` | Operational log (orchestrator-only) |
| `knowledge.db` | SQLite knowledge store (Bayesian confidence) |
| `.claude/taskplex.config.json` | Configuration |

---

## Debugging

```bash
# Story status
jq '.userStories[] | {id, title, passes, status}' prd.json

# Knowledge store
sqlite3 knowledge.db "SELECT content, applied_count, success_count FROM learnings ORDER BY created_at DESC LIMIT 10;"

# Operational log
cat progress.txt

# Background mode monitor
tail -f .claude/taskplex.log

# Git history
git log --oneline -10
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| **CLAUDE.md** | Developer quick-reference (config, agents, testing) |
| **TASKPLEX-ARCHITECTURE.md** | Architecture deep dive (8 layers, data flow, hooks) |
| **TASKPLEX-SOTA-RESEARCH-AND-PLAN.md** | Competitive analysis (vs. Superpowers, SOTA literature) |
| **CHANGELOG.md** | Version history |
| **docs/archive/** | Historical design documents (all shipped) |

---

## References

- [Claude Code CLI](https://code.claude.com/docs/en/cli-reference.md)
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents.md)
- [Superpowers](https://github.com/obra/superpowers) — Discipline skill patterns (MIT, Jesse Vincent)
- [SSC Paper](https://arxiv.org/abs/2507.18742) — Specification self-correction
- [MACLA Paper](https://arxiv.org/abs/2512.18950) — Bayesian procedural memory

---

## License

MIT © [Jesper Vang](https://github.com/flight505)
