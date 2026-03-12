# CLAUDE.md

**Version 8.0.0** | Last Updated: 2026-03-12

Developer instructions for the TaskPlex plugin.

---

## Overview

TaskPlex is a **development companion** that right-sizes process to task complexity. TDD enforcement, verification gates, systematic debugging, and disciplined workflows — applied proportionally. Pure markdown skills, zero runtime dependencies. Execution handled by CLI built-ins (`/batch`, `/simplify`).

**Philosophy:** Right-size the process. Trivial work gets trivial process. Complex work gets full discipline. Always verify before claiming done.

**For complete projects and long-running builds:** Use [SDK-Bridge](https://github.com/flight505/sdk-bridge) (`/sdk-bridge:start`).

---

## Architecture

```
taskplex/
├── .claude-plugin/plugin.json        # Plugin manifest
├── commands/                          # 2 shortcut commands
│   ├── write-plan.md                 # → taskplex:writing-plans skill
│   └── e2e-test.md                  # → taskplex:e2e-testing skill
├── hooks/
│   ├── hooks.json                    # 1 hook (SessionStart)
│   ├── run-hook.cmd                  # Cross-platform hook runner
│   └── session-start                 # Injects using-taskplex awareness
└── skills/                           # 11 skills
    ├── brainstorm/                   # Design exploration (Complex tier only)
    ├── test-driven-development/      # RED-GREEN-REFACTOR
    ├── verification-before-completion/ # Proportional evidence before claims
    ├── systematic-debugging/         # 4-phase root cause
    ├── using-git-worktrees/          # Isolated workspaces
    ├── finishing-a-development-branch/ # Branch lifecycle + worktree cleanup
    ├── receiving-code-review/        # Technical evaluation
    ├── writing-plans/                # Bite-sized task plans
    ├── writing-skills/               # TDD for documentation
    ├── using-taskplex/               # Tier-based routing
    └── e2e-testing/                  # Systematic journey testing (command-only)
```

### Components

| Type | Count | Notes |
|------|-------|-------|
| Skills | 11 | Discipline patterns (TDD, debugging, verification, E2E testing, etc.) |
| Commands | 2 | write-plan, e2e-test (brainstorm is invoked directly as a skill) |
| Hooks | 1 | SessionStart (inject skill awareness) |
| Agents | 0 | Execution handled by CLI built-ins |
| Config | 0 | No configuration files |

### Task Tiers (v8.0.0)

| Tier | Process | Skills Used |
|------|---------|-------------|
| **Trivial** | Just do it | TDD if adding behavior, verify when done |
| **Standard** | Plan → execute | writing-plans → /batch or inline TDD |
| **Complex** | Design → plan → execute | brainstorm → writing-plans → /batch |

---

## Development Guidelines

### Modifying Skills

- Skills are pure markdown — no runtime code, no dependencies
- Frontmatter: `name` + `description` required; optional: `disable-model-invocation`, `user-invocable`, `argument-hint`, `allowed-tools`, `model`, `context`, `agent`, `hooks`
- Description: hybrid pattern — start with what it does (third-person), then "Use when..." triggers
- See `writing-skills` skill for TDD approach to skill authoring

### Skills 2.0 Compliance

- Hybrid descriptions: what-it-does + "Use when..." triggers (under 420 chars)
- `argument-hint` on commands for autocomplete
- `${CLAUDE_SKILL_DIR}` for self-references within skill content
- `context: fork` available for heavy skills that benefit from isolated subagent execution
- `hooks:` in frontmatter for scoped hooks (fire only while skill is active)
- Progressive disclosure: descriptions load at startup, full content on invocation

### Available Hook Events

| Event | Use Case |
|-------|----------|
| `SessionStart` | Inject skill awareness (used by TaskPlex) |
| `PreCompact` | Preserve context before compaction |
| `WorktreeCreate` / `WorktreeRemove` | Worktree lifecycle management |
| `TaskCompleted` | Enforcement gate for agent teams |
| `TeammateIdle` | Keep teammates working |
| `InstructionsLoaded` | React to CLAUDE.md changes |
| `ConfigChange` | React to config changes |

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

- Never create a command with the same name as a skill — both register as `taskplex:<name>`, causing circular invocation loops. Use commands only as shortcuts to differently-named skills (e.g. `write-plan` → `writing-plans`).
- `hooks/hooks.json` is auto-discovered — never add `"hooks"` field to plugin.json
- Use `/reload-plugins` to activate plugin changes without restart (2.1.69+)
- Skills in plugins don't hot-reload (standalone symlinked skills do)
- Hook scripts run in non-interactive shells — no aliases, no .zshrc
- `PermissionRequest` hooks don't fire in `-p` (headless) mode

---

## References

- [SDK-Bridge](https://github.com/flight505/sdk-bridge) — PRD-driven project execution
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Skills](https://code.claude.com/docs/en/skills.md)
- [Plugin Development](https://code.claude.com/docs/en/plugins.md)
- [Agent Teams](https://code.claude.com/docs/en/agent-teams.md) — Experimental parallel teammates

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/taskplex
**License:** MIT
