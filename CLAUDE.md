# CLAUDE.md

**Version 5.0.0** | Last Updated: 2026-02-28

Developer instructions for the TaskPlex plugin. For architecture details, see [TASKPLEX-ARCHITECTURE.md](./TASKPLEX-ARCHITECTURE.md). For version history, see [CHANGELOG.md](./CHANGELOG.md).

---

## Overview

TaskPlex is an **always-on autonomous development companion** — brainstorming + 17 skills (adapted, MIT licensed from Jesse Vincent's Superpowers) + PRD-driven subagent execution, TDD enforcement, verification gates, two-stage code review, and error recovery. Leverages native Claude Code features (`memory: project`, `model:` frontmatter, `isolation: worktree`, `TaskCreate`/`TaskUpdate`) instead of custom orchestration.

**Philosophy:** Always-on awareness, challenge assumptions first, discipline before code, precise PRD, lean context, fresh context per task, resilient error recovery.

---

## Architecture

```
taskplex/
├── .claude-plugin/plugin.json        # Plugin manifest
├── agents/                            # 5 registered subagents
│   ├── architect.md                   # Read-only codebase explorer (brainstorm)
│   ├── implementer.md                 # Code a single story (TDD + verify, worktree-isolated)
│   ├── reviewer.md                    # Spec compliance + validation (merged validator+spec-reviewer)
│   ├── code-reviewer.md              # Code quality review (opt-in)
│   └── merger.md                      # Git branch operations
├── commands/start.md                  # Interactive wizard
├── skills/                            # 17 skills: brainstorm + 14 adapted Superpowers + failure-analyzer + using-taskplex gate
├── hooks/
│   ├── hooks.json                     # 5 hooks across 5 events
│   ├── session-context.sh             # SessionStart: inject using-taskplex awareness
│   ├── validate-result.sh             # SubagentStop: run test/build/typecheck + parse structured output
│   ├── task-completed.sh              # TaskCompleted: verify story reviewed + tests pass
│   └── teammate-idle.sh               # TeammateIdle: story assignment
├── scripts/
│   ├── check-deps.sh                  # Dependency verification
│   ├── check-destructive.sh           # Block dangerous git/rm commands
│   └── check-git.sh                   # Git repository diagnostics
└── tests/
    └── run-suite.sh                   # Delegates to marketplace test suite
```

### Subagents

| Agent | Model | Permission | Tools | Purpose |
|-------|-------|------------|-------|---------|
| architect | sonnet | dontAsk | Read, Grep, Glob, Bash | Read-only codebase explorer (brainstorm phase) |
| implementer | inherit | bypassPermissions | Bash, Read, Edit, Write, Glob, Grep | Code a single story (TDD + verify, worktree-isolated) |
| reviewer | haiku | dontAsk | Read, Grep, Glob, Bash | Spec compliance + validation (two-phase) |
| code-reviewer | sonnet | dontAsk | Read, Grep, Glob, Bash | Code quality review (opt-in) |
| merger | haiku | bypassPermissions | Bash, Read, Grep | Git branch operations |

For detailed data flow and hook system, see [TASKPLEX-ARCHITECTURE.md](./TASKPLEX-ARCHITECTURE.md).

---

## Configuration

`.claude/taskplex.config.json`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `branch_prefix` | string | "taskplex" | Git branch prefix |
| `test_command` | string | "" | e.g. "npm test" |
| `build_command` | string | "" | e.g. "npm run build" |
| `typecheck_command` | string | "" | e.g. "tsc --noEmit" |
| `execution_model` | string | "sonnet" | "sonnet", "opus", or "inherit" |
| `merge_on_complete` | bool | false | Auto-merge to main when all stories complete |
| `code_review` | bool | false | Enable code-reviewer agent after validation |
| `interactive_mode` | bool | false | Pause between stories for user approval |

---

## Development Guidelines

### Modifying Components

- **Agents** — YAML frontmatter defines tools, model, permissionMode, maxTurns. Keep tool lists minimal (least privilege). Use `haiku` for cheap/fast, `sonnet` for quality, `inherit` for user's model.
- **Skills** — Single responsibility. Lettered options (A, B, C, D) for questions. `context: fork` runs in isolated subagent.
- **Hooks** — `${CLAUDE_PLUGIN_ROOT}` resolves to install path. Scripts must be `chmod +x`. Sync hooks need `statusMessage` and `timeout`.
- **Scripts** — `set -e` for fail-fast. Bash 3.2 compatible (no `declare -A`). `jq` is the only JSON parser.
- **Commands** — Use `AskUserQuestion` at decision points.

### Testing Changes

```bash
# Full test suite (from marketplace root)
bash test-results/taskplex/run-tests.sh

# Or via thin wrapper (auto-delegates to marketplace suite)
bash tests/run-suite.sh

# Structural validation (from marketplace root)
cd /path/to/flight505-marketplace
./scripts/validate-plugin-manifests.sh
./scripts/plugin-doctor.sh

# Reinstall and test
/plugin uninstall taskplex@flight505-marketplace
/plugin install taskplex@flight505-marketplace
# Restart Claude Code, then:
/taskplex:start
```

### File Conventions

| Context | Pattern |
|---------|---------|
| Commands (markdown) | `${CLAUDE_PLUGIN_ROOT}/scripts/file.sh` |
| Skills (markdown) | Relative paths `./examples/file.md` |
| Hooks (JSON) | `${CLAUDE_PLUGIN_ROOT}/scripts/file.sh` |
| Bash scripts | Absolute paths `$HOME/.claude/...` |
| Naming | `kebab-case` everywhere |
| Permissions | `chmod +x scripts/*.sh && git add --chmod=+x scripts/*.sh` |

---

## Authentication

```bash
# OAuth (recommended for Max subscribers)
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN='your-token'

# API key (fallback)
export ANTHROPIC_API_KEY='your-key'
```

---

## Gotchas

- Shell scripts must be **bash 3.2 compatible** — no `declare -A`, no bash 4+ features
- `jq` is the only JSON parser — no `yq` or Python for JSON
- `PermissionRequest` hooks do NOT fire in `-p` (headless) mode — use `permissionMode` in agent frontmatter instead
- `set -e` + `[ cond ] && action` at end of function = silent crash — use `if/then/fi`
- Always use `python3` not `python` in hook commands (macOS has no `python` binary)
- Hook scripts run in non-interactive shells — aliases and `.zshrc` not loaded
- Exit 2 messages must go to stderr; stdout is for structured JSON output
- No external plugin dependencies in runtime files — plugin must work standalone

---

## Debugging

```bash
# Check installation
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins | keys'

# Verify plugin structure
ls -la ~/.claude/plugins/cache/flight505-marketplace/taskplex/*/

# Verify dependencies
bash scripts/check-deps.sh

# Validate hooks.json
jq . hooks/hooks.json

# Test destructive command blocker
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | bash scripts/check-destructive.sh
```

---

## References

- [TaskPlex Architecture](./TASKPLEX-ARCHITECTURE.md) — Design, data flow, hooks
- [Changelog](./CHANGELOG.md) — Version history
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents.md)
- [Plugin Development](https://github.com/anthropics/claude-code/blob/main/docs/plugins.md)

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/taskplex
**License:** MIT
