# CLAUDE.md

**Version 9.0.0** | Last Updated: 2026-03-20

---

## What TaskPlex Is

A **context-preservation layer**. The main context window is the most precious resource in a Claude Code session. TaskPlex ensures all work — implementation, debugging, testing, exploration — runs in **subagents with their own context windows**. The main window stays thin for conversation and coordination. Agent results come back as concise summaries (~200-500 chars), not full file contents or test output.

**Core rule: Never do work in the main context. Always delegate to an agent.**

**For complete projects:** Use [SDK-Bridge](https://github.com/flight505/sdk-bridge) (`/sdk-bridge:start`).

---

## Architecture

```
taskplex/
├── agents/                             # 5 work-type agents (own context)
│   ├── taskplex-implementer.md         # Code changes, TDD enforced
│   ├── taskplex-debugger.md            # Investigation + fix
│   ├── taskplex-verifier.md            # Background verification
│   ├── taskplex-researcher.md          # Design exploration
│   └── taskplex-e2e.md                # E2E testing
├── skills/                             # 4 skills (main context)
│   ├── using-taskplex/                 # Dispatcher
│   ├── using-git-worktrees/            # Interactive workflow
│   ├── finishing-a-development-branch/ # Interactive workflow
│   └── writing-skills/                 # Skill authoring
├── commands/
│   └── e2e-test.md                     # → @taskplex-e2e
├── hooks/
│   ├── hooks.json                      # SessionStart
│   ├── run-hook.cmd                    # Cross-platform runner
│   └── session-start                   # Injects dispatcher (~1.6K chars)
└── evals/
    └── discipline-eval/                # Eval harness
```

### Agent Tuning

| Agent | Work type | Effort | Model | Memory | Background | Tools |
|-------|-----------|--------|-------|--------|------------|-------|
| implementer | Code changes | high | inherit | project | no | Full |
| debugger | Bug investigation | high | inherit | project | no | Full |
| verifier | Test/build checks | low | sonnet | project | **yes** | Read-only |
| researcher | Design exploration | medium | inherit | project | no | Read-only |
| e2e | E2E testing | high | inherit | project | no | Full |

### What stays in main context

- User conversation and agent routing
- Interactive skills (git worktrees, branch lifecycle, skill authoring)
- CLI handoffs: `/batch`, `/plan`, `/simplify`, `/debug`, `/loop`
- Agent summaries — never raw results

---

## Development Guidelines

### Agent Design Principles

1. **Context is the constraint.** Every agent exists to keep work out of the main window.
2. **Agents return summaries, not data.** "42 tests pass, fixed null check in auth.ts:42" — not the full test output.
3. **Tune per work type.** `effort`, `model`, `background`, `disallowedTools` all differ by agent.
4. **Memory compounds.** `memory: project` on all agents — they learn across sessions.
5. **Subagents can't spawn sub-subagents.** Design agent workflows accordingly.

### Frontmatter Reference (Claude Code 2.1.80)

| Field | Purpose |
|-------|---------|
| `effort` | `low`/`medium`/`high`/`max` — reasoning depth |
| `background` | `true` — non-blocking execution |
| `isolation` | `worktree` — isolated git copy |
| `maxTurns` | Cap turns to prevent runaway |
| `memory` | `user`/`project`/`local` — persistent learning |
| `model` | `sonnet`/`haiku`/`inherit` — cost control |
| `disallowedTools` | Enforce read-only agents |
| `skills` | Preload skill content into agent context |

### Plugin Security Restrictions

Plugin-shipped agents do NOT support `hooks`, `mcpServers`, or `permissionMode`. These are ignored for security. If needed, copy agent to `.claude/agents/`.

### Validation

```bash
# From marketplace root
./scripts/validate-plugin-manifests.sh
./scripts/plugin-doctor.sh

# Eval
cd evals/discipline-eval && ./run-eval.sh && ./run-eval.sh --judge
```

---

## Gotchas

- Never create a command with the same name as a skill — circular invocation
- `hooks/hooks.json` is auto-discovered — never add `"hooks"` to plugin.json
- Subagents cannot spawn sub-subagents
- `PermissionRequest` hooks don't fire in `-p` (headless) mode
- Use `/reload-plugins` to activate changes without restart (2.1.69+)

---

## References

- [SDK-Bridge](https://github.com/flight505/sdk-bridge) — PRD-driven project execution
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents.md)
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins.md)

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/taskplex
**License:** MIT
