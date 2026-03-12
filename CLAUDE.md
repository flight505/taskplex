# CLAUDE.md

**Version 7.0.4** | Last Updated: 2026-03-12

Developer instructions for the TaskPlex plugin.

---

## Overview

TaskPlex is an **always-on development companion** — TDD enforcement, verification gates, systematic debugging, and disciplined workflows. Pure markdown skills, zero runtime dependencies. Execution handled by CLI built-ins (`/batch`, `/simplify`).

**Philosophy:** Discipline before code, challenge assumptions first, verify before claiming done. Lightweight enough for daily use — no orchestration overhead.

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
    ├── brainstorm/                   # Design before code
    ├── test-driven-development/      # RED-GREEN-REFACTOR
    ├── verification-before-completion/ # Evidence before claims
    ├── systematic-debugging/         # 4-phase root cause
    ├── using-git-worktrees/          # Isolated workspaces
    ├── finishing-a-development-branch/ # Branch lifecycle
    ├── receiving-code-review/        # Technical evaluation
    ├── writing-plans/                # Bite-sized task plans
    ├── writing-skills/               # TDD for documentation
    ├── using-taskplex/               # Always-on routing gate
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

---

## Development Guidelines

### Modifying Skills

- Skills are pure markdown — no runtime code, no dependencies
- Frontmatter: `name` + `description` required; optional: `disable-model-invocation`, `user-invocable`, `argument-hint`, `allowed-tools`, `model`, `context`, `agent`, `hooks`
- Description: hybrid pattern — start with what it does (third-person), then "Use when..." triggers. Never summarize workflow.
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

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/taskplex
**License:** MIT
