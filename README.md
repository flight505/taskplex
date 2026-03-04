# TaskPlex

<p align="center">
  <img src="./assets/TaskPlex_Hero@0.5x.png" alt="TaskPlex - Always-On Development Companion" width="800" />
</p>

[![Version](https://img.shields.io/badge/version-6.1.0-blue.svg)](https://github.com/flight505/taskplex)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://github.com/anthropics/claude-code)

Always-on development companion for Claude Code. TDD enforcement, verification gates, systematic debugging, code review, E2E testing, and disciplined workflows — powered by pure-markdown skills and zero runtime dependencies.

**For larger projects (6+ files, PRD-driven):** Use [SDK-Bridge](https://github.com/flight505/sdk-bridge).

---

## How It Works

TaskPlex activates automatically via a `SessionStart` hook that injects the `using-taskplex` skill into every conversation. This skill routes to the right workflow based on what you're doing — no explicit invocation needed.

**Four shortcuts for common workflows:**

| Command | Skill | When |
|---------|-------|------|
| `/brainstorm` | brainstorm | Before creating anything new |
| `/write-plan` | writing-plans | Need a task-by-task plan |
| `/execute-plan` | guided-implementation | Execute a plan with review checkpoints |
| `/e2e-test` | e2e-testing | Systematic end-to-end testing of your application |

---

## Skills (15)

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
| **e2e-testing** | User invokes `/e2e-test` for systematic journey testing |

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
- `/e2e-test` — Research all user journeys, then test every path with evidence

---

## Architecture

```
taskplex/
├── .claude-plugin/plugin.json     # v6.1.0
├── agents/
│   └── code-reviewer.md           # Code quality review agent
├── commands/                      # 4 shortcuts
│   ├── brainstorm.md
│   ├── write-plan.md
│   ├── execute-plan.md
│   └── e2e-test.md
├── hooks/                         # 1 hook (SessionStart)
│   ├── hooks.json
│   ├── run-hook.cmd
│   └── session-start
└── skills/                        # 15 skills
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
    └── e2e-testing/
```

| Component | Count | Notes |
|-----------|-------|-------|
| Skills | 15 | Discipline patterns (TDD, debugging, verification, E2E testing, etc.) |
| Commands | 4 | Shortcut entry points to key skills |
| Hooks | 1 | SessionStart injects skill awareness |
| Agents | 1 | code-reviewer (dispatched by requesting-code-review) |
| Config | 0 | No configuration files needed |

---

## What's New

### v6.1.0

Added `/e2e-test` command and `e2e-testing` skill — systematic end-to-end testing that works for web apps, APIs, CLIs, and desktop applications. Launches 3 parallel research sub-agents to map all user journeys, state flows, and risk areas, then lets you choose between writing permanent test files (TDD) or running an exploratory testing session with evidence collection.

### v6.0.0

Stripped heavy orchestration infrastructure — PRD pipeline, config system, shell scripts — in favor of pure discipline skills. Heavy project execution moved to [SDK-Bridge](https://github.com/flight505/sdk-bridge).

| Before (v5.x) | After (v6.0) |
|---------------|--------------|
| 5 registered agents | 1 (code-reviewer) |
| 5 hooks across 5 events | 1 hook (SessionStart) |
| 8 config options | 0 |
| `/taskplex:start` wizard | Shortcut commands |
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

- [SDK-Bridge](https://github.com/flight505/sdk-bridge) — PRD-driven project execution
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Skills](https://code.claude.com/docs/en/skills.md)

---

## License

MIT © [Jesper Vang](https://github.com/flight505)
