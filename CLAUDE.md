# CLAUDE.md

**Version 6.0.0** | Last Updated: 2026-03-04

Developer instructions for the TaskPlex plugin.

---

## Overview

TaskPlex is an **always-on development companion** — TDD enforcement, verification gates, systematic debugging, code review, and disciplined workflows. Pure markdown skills, zero runtime dependencies.

**Philosophy:** Discipline before code, challenge assumptions first, verify before claiming done. Lightweight enough for daily use — no orchestration overhead.

**For larger projects (6+ files, PRD-driven):** Use [SDK-Bridge](https://github.com/flight505/sdk-bridge) (`/sdk-bridge:start`).

---

## Architecture

```
taskplex/
├── .claude-plugin/plugin.json        # Plugin manifest
├── commands/                          # 3 shortcut commands
│   ├── brainstorm.md                 # → taskplex:brainstorm skill
│   ├── write-plan.md                 # → taskplex:writing-plans skill
│   └── execute-plan.md              # → taskplex:guided-implementation skill
├── hooks/
│   ├── hooks.json                    # 1 hook (SessionStart)
│   ├── run-hook.cmd                  # Cross-platform hook runner
│   └── session-start                 # Injects using-taskplex awareness
├── agents/
│   └── code-reviewer.md             # Code quality review agent
└── skills/                           # 14 skills
    ├── brainstorm/                   # Design before code
    ├── test-driven-development/      # RED-GREEN-REFACTOR
    ├── verification-before-completion/ # Evidence before claims
    ├── systematic-debugging/         # 4-phase root cause
    ├── dispatching-parallel-agents/  # Concurrent independent work
    ├── using-git-worktrees/          # Isolated workspaces
    ├── finishing-a-development-branch/ # Branch lifecycle
    ├── requesting-code-review/       # Dispatch reviewer
    ├── receiving-code-review/        # Technical evaluation
    ├── subagent-driven-development/  # Fresh agent per task + two-stage review
    ├── guided-implementation/        # Human-guided batch execution
    ├── writing-plans/                # Bite-sized task plans
    ├── writing-skills/               # TDD for documentation
    └── using-taskplex/               # Always-on routing gate
```

### Components

| Type | Count | Notes |
|------|-------|-------|
| Skills | 14 | Discipline patterns (TDD, debugging, verification, etc.) |
| Commands | 3 | brainstorm, write-plan, execute-plan |
| Hooks | 1 | SessionStart (inject skill awareness) |
| Agents | 1 | code-reviewer (dispatched by requesting-code-review) |
| Config | 0 | No configuration files |

---

## Development Guidelines

### Modifying Skills

- Skills are pure markdown — no runtime code, no dependencies
- Frontmatter: `name` + `description` only (max 1024 chars)
- Description must start with "Use when..." (triggering conditions, NOT workflow summary)
- See `writing-skills` skill for TDD approach to skill authoring

### Testing Changes

```bash
# From marketplace root
./scripts/validate-plugin-manifests.sh
./scripts/plugin-doctor.sh

# Reinstall and test
/plugin uninstall taskplex@flight505-marketplace
/plugin install taskplex@flight505-marketplace
# Restart Claude Code
```

### File Conventions

| Context | Pattern |
|---------|---------|
| Hook commands | `'${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd' <script>` |
| Skills | Relative paths within skill directory |
| Naming | `kebab-case` everywhere |
| Permissions | `chmod +x hooks/*` |

---

## Gotchas

- `hooks/hooks.json` is auto-discovered — never add `"hooks"` field to plugin.json
- Plugins update on restart only, not mid-session
- Skills in plugins don't hot-reload (standalone symlinked skills do)
- Hook scripts run in non-interactive shells — no aliases, no .zshrc
- `PermissionRequest` hooks don't fire in `-p` (headless) mode

---

## References

- [SDK-Bridge](https://github.com/flight505/sdk-bridge) — PRD-driven project execution
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Skills](https://code.claude.com/docs/en/skills.md)
- [Plugin Development](https://code.claude.com/docs/en/plugins.md)

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/taskplex
**License:** MIT
