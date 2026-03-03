# TaskPlex

<p align="center">
  <img src="./assets/TaskPlex_Hero@0.5x.png" alt="TaskPlex - Always-On Autonomous Dev Companion" width="800" />
</p>

[![Version](https://img.shields.io/badge/version-5.2.0-blue.svg)](https://github.com/flight505/taskplex)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://github.com/anthropics/claude-code)

Always-on autonomous development companion for Claude Code. Brainstorming, TDD enforcement, verification gates, two-stage code review, and error recovery — powered by 17 discipline skills and 5 subagents.

Discipline skills adapted from [Superpowers](https://github.com/obra/superpowers) (MIT, Jesse Vincent).

---

## How It Works

TaskPlex has two paths — both lead to the same execution pipeline:

**Proactive path (always-on):** The `SessionStart` hook detects active `prd.json` and injects context. The `using-taskplex` skill automatically routes to the right workflow skill based on what you're doing.

**Explicit path:** Run `/taskplex:start` for the interactive wizard.

### Execution Pipeline

```
Brainstorm → PRD → Implement → Review → Code Review (opt-in) → Merge
     │                  │           │            │
  architect        implementer   reviewer    code-reviewer
  agent            (fresh per    (spec +      (quality)
                    story)       validation)
```

Each story gets a **fresh Claude subagent** with clean context. The `subagent-driven-development` skill guides the main conversation to dispatch agents via native Task tool — no bash orchestrator needed.

---

## Key Features

### Always-On Awareness

The plugin activates automatically via hooks — no need to invoke `/taskplex:start`:

- **SessionStart hook** detects active `prd.json` and injects status
- **using-taskplex skill** (1% gate) routes to the right workflow
- **18 skills** covering the full development lifecycle

### Brainstorming

Before jumping to a PRD, the `brainstorm` skill challenges assumptions using the `architect` agent (read-only codebase explorer). Produces a Design Brief saved to `docs/plans/`.

### Two-Stage Review

1. **Reviewer** (mandatory) — spec compliance + validation (run test/build/typecheck, verify commit)
2. **Code-reviewer** (opt-in) — architecture, security, types, tests, performance

Both run as separate agents, not in-context suggestions. Cannot be rationalized away.

### Hook-Based Enforcement

| Hook | Event | Purpose |
|------|-------|---------|
| session-context.sh | SessionStart | Inject active prd.json status |
| check-destructive.sh | PreToolUse | Block `git push --force`, `reset --hard`, etc. |
| validate-result.sh | SubagentStop | Run test/build/typecheck after implementer |
| teammate-idle.sh | TeammateIdle | Assign work in Agent Teams mode |

All enforcement is **mechanical** (hook-based), not advisory.

### Native Claude Code Integration

v5.0 leverages native features instead of custom infrastructure:

| Feature | Before (v4.x) | After (v5.0) |
|---------|---------------|--------------|
| Memory | SQLite knowledge.db | `memory: project` in agent frontmatter |
| Routing | decision-call.sh + Opus calls | `model:` field in agent frontmatter |
| Parallelism | parallel.sh + wave orchestration | `isolation: worktree` (native) |
| Task tracking | progress.txt + bash loop | `TaskCreate` / `TaskUpdate` (native) |
| Orchestration | taskplex.sh (2,361 lines) | subagent-driven-development skill |

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

**Explicit:** Run `/taskplex:start` for the interactive wizard:

1. **Dependency check** — verifies `claude` and `jq`
2. **Git validation** — ensures clean repo state
3. **Project input** — describe your feature or provide a file path
4. **Generate PRD** — structured PRD with clarifying questions
5. **Review PRD** — approve, improve, or edit
6. **Convert to JSON** — `prd.json` with dependency inference
7. **Execution settings** — model, review, interactive mode
8. **Launch** — starts subagent-driven development

---

## Agents

| Agent | Model | Permission | Purpose |
|-------|-------|------------|---------|
| **architect** | sonnet | dontAsk | Read-only codebase explorer for brainstorm |
| **implementer** | inherit | bypassPermissions | Code a single story (TDD + verify enforced) |
| **reviewer** | haiku | dontAsk | Spec compliance + validation |
| **code-reviewer** | sonnet | dontAsk | Code quality review (opt-in) |
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
| **focused-task** | Well-scoped task (1-5 files) without PRD |
| **guided-implementation** | Executing plan inline with human checkpoints |
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

## Configuration

Edit `.claude/taskplex.config.json`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `branch_prefix` | string | "taskplex" | Git branch prefix |
| `test_command` | string | "" | e.g. "npm test" |
| `build_command` | string | "" | e.g. "npm run build" |
| `typecheck_command` | string | "" | e.g. "tsc --noEmit" |
| `execution_model` | string | "sonnet" | "sonnet", "opus", or "inherit" |
| `merge_on_complete` | bool | false | Auto-merge to main |
| `code_review` | bool | false | Enable code-reviewer after validation |
| `interactive_mode` | bool | false | Pause between stories |

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
| `.claude/taskplex.config.json` | Configuration |

---

## Debugging

```bash
# Story status
jq '.userStories[] | {id, title, passes, status}' prd.json

# Git history
git log --oneline -10
```

---

## Documentation

| Document | Purpose |
|----------|---------|
| **CLAUDE.md** | Developer quick-reference (config, agents, testing) |
| **TASKPLEX-ARCHITECTURE.md** | Single source of truth for architecture, components, competitive position |
| **CHANGELOG.md** | Version history |
| **docs/diagrams/** | Architecture diagrams |

---

## References

- [Claude Code CLI](https://code.claude.com/docs/en/cli-reference.md)
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents.md)
- [Superpowers](https://github.com/obra/superpowers) — Discipline skill patterns (MIT, Jesse Vincent)

---

## License

MIT © [Jesper Vang](https://github.com/flight505)
