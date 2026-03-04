# TaskPlex

<p align="center">
  <img src="./assets/TaskPlex_Hero@0.5x.png" alt="TaskPlex - Always-On Development Companion" width="800" />
</p>

[![Version](https://img.shields.io/badge/version-6.0.0-blue.svg)](https://github.com/flight505/taskplex)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://github.com/anthropics/claude-code)

Always-on development companion for Claude Code. TDD enforcement, verification gates, systematic debugging, code review, and disciplined workflows — powered by 16 pure-markdown skills and zero runtime dependencies.

Based on [Superpowers](https://github.com/obra/superpowers) v4.3.1 (MIT, Jesse Vincent) with targeted upgrades.

**For larger projects (6+ files, PRD-driven):** Use [SDK-Bridge](https://github.com/flight505/sdk-bridge).

---

## How It Works

TaskPlex activates automatically via a `SessionStart` hook that injects the `using-taskplex` skill into every conversation. This skill routes to the right workflow based on what you're doing — no explicit invocation needed.

**Three shortcuts for common workflows:**

| Command | Skill | When |
|---------|-------|------|
| `/brainstorm` | brainstorm | Before creating anything new |
| `/write-plan` | writing-plans | Need a task-by-task plan |
| `/execute-plan` | guided-implementation | Execute a plan with review checkpoints |

---

## Skills (16)

14 discipline skills from Superpowers + 2 TaskPlex originals:

| Skill | Triggers When |
|-------|--------------|
| **brainstorm** | New feature described, before implementation |
| **test-driven-development** | Before any implementation |
| **verification-before-completion** | Before claiming work is done |
| **systematic-debugging** | Bug, test failure, or unexpected behavior |
| **dispatching-parallel-agents** | 2+ independent tasks |
| **using-git-worktrees** | Feature work needs isolation |
| **finishing-a-development-branch** | Ready to integrate |
| **requesting-code-review** | After task completion |
| **receiving-code-review** | Responding to review feedback |
| **subagent-driven-development** | Multi-story execution with fresh agents |
| **guided-implementation** | Executing plan inline with human checkpoints |
| **writing-plans** | Need detailed task-by-task plan |
| **writing-skills** | Creating or editing skills |
| **using-taskplex** | Always-on routing gate |
| **focused-task** | Well-scoped task (1-5 files) without PRD *(TaskPlex upgrade)* |
| **failure-analyzer** | Implementation fails with unclear error *(TaskPlex upgrade)* |

---

## Quick Start

### Prerequisites

- [Claude Code CLI](https://code.claude.com)
- Git repository

### Installation

```bash
# Add marketplace
/plugin marketplace add flight505/flight505-marketplace

# Install plugin
/plugin install taskplex@flight505-marketplace
```

### Usage

**Proactive (recommended):** Just start working. TaskPlex activates automatically when it detects relevant context.

**Explicit:** Use the shortcut commands:
- `/brainstorm` — Explore requirements before jumping to code
- `/write-plan` — Create a detailed implementation plan
- `/execute-plan` — Execute a plan with batch review checkpoints

---

## Architecture

```
taskplex/
├── .claude-plugin/plugin.json     # v6.0.0
├── commands/                      # 3 shortcuts
│   ├── brainstorm.md
│   ├── write-plan.md
│   └── execute-plan.md
├── hooks/                         # 1 hook (SessionStart)
│   ├── hooks.json
│   ├── run-hook.cmd
│   └── session-start
└── skills/                        # 16 skills
    ├── brainstorm/
    ├── test-driven-development/
    ├── verification-before-completion/
    ├── systematic-debugging/
    ├── dispatching-parallel-agents/
    ├── using-git-worktrees/
    ├── finishing-a-development-branch/
    ├── requesting-code-review/
    ├── receiving-code-review/
    ├── subagent-driven-development/
    ├── guided-implementation/
    ├── writing-plans/
    ├── writing-skills/
    ├── using-taskplex/
    ├── focused-task/
    └── failure-analyzer/
```

| Component | Count | Notes |
|-----------|-------|-------|
| Skills | 16 | 14 from Superpowers + 2 TaskPlex originals |
| Commands | 3 | Shortcut entry points to key skills |
| Hooks | 1 | SessionStart injects skill awareness |
| Agents | 0 | Subagents dispatched via inline prompt templates |
| Config | 0 | No configuration files needed |

---

## What Changed in v6.0.0

TaskPlex was rebuilt to match [Superpowers](https://github.com/obra/superpowers) — lightweight, fast, always-on. Heavy orchestration infrastructure moved to [SDK-Bridge](https://github.com/flight505/sdk-bridge).

| Before (v5.x) | After (v6.0) |
|---------------|--------------|
| 5 registered agents | 0 (inline prompt templates) |
| 5 hooks across 5 events | 1 hook (SessionStart) |
| 8 config options | 0 |
| `/taskplex:start` wizard | 3 shortcut commands |
| PRD pipeline (generator + converter) | Removed (use SDK-Bridge) |
| Shell scripts (check-deps, check-git, check-destructive) | Removed |

---

## Documentation

| Document | Purpose |
|----------|---------|
| **CLAUDE.md** | Developer quick-reference |
| **CHANGELOG.md** | Version history |

---

## References

- [Superpowers](https://github.com/obra/superpowers) — Upstream skill library (MIT, Jesse Vincent)
- [SDK-Bridge](https://github.com/flight505/sdk-bridge) — PRD-driven project execution
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Skills](https://code.claude.com/docs/en/skills.md)

---

## License

MIT © [Jesper Vang](https://github.com/flight505)
