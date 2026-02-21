# CLAUDE.md

**Version 3.0.0** | Last Updated: 2026-02-21

Developer instructions for the TaskPlex plugin. For architecture deep dives, see [TASKPLEX-ARCHITECTURE.md](./TASKPLEX-ARCHITECTURE.md). For version history, see [CHANGELOG.md](./CHANGELOG.md).

---

## Overview

TaskPlex is an **always-on autonomous development companion** — proactive PRD generation, TDD enforcement, verification gates, two-stage code review, and resilient autonomous execution. Replaces Superpowers.

**Philosophy:** Always-on awareness, discipline before code, precise PRD, sequential execution, fresh context per task, resilient error recovery.

---

## Architecture

```
taskplex/
├── .claude-plugin/plugin.json        # Plugin manifest
├── agents/                            # 6 subagents (implementer, validator, spec-reviewer, reviewer, merger, code-reviewer)
├── commands/start.md                  # 8-checkpoint interactive wizard (optional — proactive path available)
├── skills/                            # 6 skills: prd-generator, prd-converter, failure-analyzer, using-taskplex, taskplex-tdd, taskplex-verify
├── hooks/
│   ├── hooks.json                     # 9 hooks across 7 events
│   ├── stop-guard.sh                  # Stop: prevents premature exit
│   ├── task-completed.sh              # TaskCompleted: gates on test pass
│   ├── inject-knowledge.sh            # SubagentStart: SQLite → additionalContext
│   ├── inject-edit-context.sh         # PreToolUse: file patterns → additionalContext
│   ├── pre-compact.sh                 # PreCompact: saves state before compaction
│   └── validate-result.sh             # SubagentStop: inline validation + learnings
├── scripts/
│   ├── taskplex.sh                    # Main orchestration loop
│   ├── parallel.sh                    # Wave-based parallel execution (opt-in)
│   ├── knowledge-db.sh                # SQLite knowledge store helpers
│   ├── decision-call.sh               # 1-shot Opus decision calls
│   └── check-*.sh                     # Dependency, git, and destructive command checks
├── monitor/                           # Optional Bun + Vue 3 dashboard sidecar
└── tests/
```

### Subagents

| Agent | Model | Permission | Tools | Purpose |
|-------|-------|------------|-------|---------|
| implementer | inherit | bypassPermissions | Bash, Read, Edit, Write, Glob, Grep | Code a single story (TDD + verify REQUIRED) |
| validator | haiku | dontAsk | Bash, Read, Glob, Grep | Verify acceptance criteria (read-only) |
| spec-reviewer | haiku | dontAsk | Read, Grep, Glob, Bash | Spec compliance review — Stage 1 (mandatory) |
| reviewer | sonnet | plan | Read, Glob, Grep | Review PRD quality |
| merger | haiku | bypassPermissions | Bash, Read, Grep | Git branch operations |
| code-reviewer | sonnet | dontAsk | Read, Grep, Glob, Bash | Code quality review — Stage 2 (opt-in) |

For detailed data flow, hook system, knowledge architecture, and error handling, see [TASKPLEX-ARCHITECTURE.md](./TASKPLEX-ARCHITECTURE.md).

---

## Configuration

`.claude/taskplex.config.json`:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_iterations` | int | 25 | Stop after N iterations (formula: stories x 2.5) |
| `iteration_timeout` | int | 900 | Timeout per iteration in seconds |
| `execution_mode` | string | "foreground" | "foreground" (interactive) or "background" |
| `execution_model` | string | "sonnet" | "sonnet" or "opus" for story implementation |
| `effort_level` | string | "" | "low"/"medium"/"high" (Opus 4.6 only) |
| `branch_prefix` | string | "taskplex" | Git branch prefix |
| `max_retries_per_story` | int | 2 | Max retry attempts before skipping |
| `max_turns` | int | 200 | Max agentic turns per Claude invocation |
| `merge_on_complete` | bool | false | Auto-merge to main when all stories complete |
| `test_command` | string | "" | e.g. "npm test" |
| `build_command` | string | "" | e.g. "npm run build" |
| `typecheck_command` | string | "" | e.g. "tsc --noEmit" |
| `parallel_mode` | string | "sequential" | "sequential" or "parallel" (worktree-based) |
| `max_parallel` | int | 3 | Max concurrent agents per wave |
| `worktree_dir` | string | "" | Custom worktree base dir |
| `worktree_setup_command` | string | "" | e.g. "npm install" |
| `conflict_strategy` | string | "abort" | "abort" or "merger" (invoke merger agent) |
| `code_review` | bool | false | Enable two-stage code review after validation |
| `decision_calls` | bool | true | Enable 1-shot Opus decision calls |
| `decision_model` | string | "opus" | Model for decision calls |
| `validate_on_stop` | bool | true | Enable SubagentStop inline validation |
| `model_routing` | string | "auto" | "auto" (decision call picks) or "fixed" |

---

## Development Guidelines

### Modifying Components

- **Agents** — YAML frontmatter defines tools, model, permissionMode, maxTurns. Keep tool lists minimal (least privilege). Use `haiku` for cheap/fast, `sonnet` for quality, `inherit` for user's model.
- **Skills** — Single responsibility. Lettered options (A, B, C, D) for questions. `context: fork` runs in isolated subagent.
- **Hooks** — `${CLAUDE_PLUGIN_ROOT}` resolves to install path. Scripts must be `chmod +x`. Sync hooks need `statusMessage` and `timeout`.
- **Scripts** — `set -e` for fail-fast. Bash 3.2 compatible (no `declare -A`). `jq` is the only JSON parser.
- **Commands** — Follow 8-checkpoint structure. Use `AskUserQuestion` at decision points.

### Testing Changes

```bash
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
- `env -u CLAUDECODE` is required before nested `claude -p` calls
- `--dangerously-skip-permissions` is required for headless file writes
- `jq` piped output needs `-r` for raw strings (no quotes around IDs)
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

# Test script directly
bash scripts/taskplex.sh 1

# Verify dependencies
bash scripts/check-deps.sh

# Validate hooks.json
jq . hooks/hooks.json

# Test destructive command blocker
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | bash scripts/check-destructive.sh
```

---

## References

- [TaskPlex Architecture](./TASKPLEX-ARCHITECTURE.md) — Design, data flow, knowledge system, hooks, roadmap
- [Changelog](./CHANGELOG.md) — Version history
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents.md)
- [Plugin Development](https://github.com/anthropics/claude-code/blob/main/docs/plugins.md)

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/taskplex
**License:** MIT
