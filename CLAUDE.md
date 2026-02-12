# CLAUDE.md

**Version 1.0.0** | Last Updated: 2026-02-11

Developer instructions for working with the TaskPlex plugin for Claude Code CLI.

---

## Overview

TaskPlex is a **resilient autonomous development assistant** — the next-generation successor to SDK Bridge. It provides a single command (`/taskplex:start`) that:
1. Generates detailed PRDs with clarifying questions
2. Converts to executable JSON format with dependency inference
3. Runs custom subagents with error categorization, retry strategies, and branch lifecycle management

**Philosophy:** Precise PRD, sequential execution, fresh context per task, resilient error recovery.

**What's new vs SDK Bridge:**
- Custom subagents (implementer, validator, reviewer, merger) replace monolithic `claude -p` calls
- Error categorization with intelligent retry/skip decisions
- Dependency-aware task selection (enforced, not just tracked)
- Branch lifecycle management (create, merge, cleanup)
- Quality gate hooks (block destructive commands during implementation)
- Failure analyzer skill for structured error diagnosis

---

## Architecture

### Component Structure

```
taskplex/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (v1.0.0)
├── agents/
│   ├── implementer.md           # Codes a single story, outputs structured result
│   ├── validator.md             # Verifies acceptance criteria (read-only)
│   ├── reviewer.md              # Reviews PRD from specific angles
│   └── merger.md                # Git branch operations
├── commands/
│   └── start.md                 # Interactive wizard (7-checkpoint workflow)
├── hooks/
│   └── hooks.json               # PostToolUse: block destructive git commands
├── skills/
│   ├── prd-generator/           # PRD creation with clarifying questions
│   │   └── SKILL.md
│   ├── prd-converter/           # Markdown → JSON converter with dependency inference
│   │   └── SKILL.md
│   └── failure-analyzer/        # Error categorization and retry strategy
│       └── SKILL.md
├── scripts/
│   ├── taskplex.sh              # Main bash loop (orchestrator)
│   ├── prompt.md                # Instructions for each Claude iteration
│   ├── check-deps.sh            # Dependency checker (claude, jq, coreutils)
│   ├── check-destructive.sh     # Hook script: blocks destructive git commands
│   └── prd.json.example         # Reference format
├── examples/
│   ├── prd-simple-feature.md    # Simple PRD example
│   └── prd-complex-feature.md   # Complex PRD with decomposition
├── TASKPLEX-ARCHITECTURE.md     # Full architecture plan (v1.0 design doc)
└── .gitignore
```

### Component Roles

**Commands (`start.md`):**
- Single entry point orchestrating 7-checkpoint workflow
- Uses AskUserQuestion for user input at decision points
- Invokes skills via Task tool for PRD generation/conversion
- Launches bash scripts via Bash tool for execution

**Agents:**
- `implementer`: Implements a single user story. Tools: Bash, Read, Edit, Write, Glob, Grep. Disallowed: Task (no subagent spawning). Model: inherit from parent. Outputs structured JSON with error categorization.
- `validator`: Verifies completed stories work. Tools: Bash, Read, Glob, Grep. Model: haiku (fast, cheap). Read-only — does NOT fix issues.
- `reviewer`: Reviews PRDs from specific angles (security, performance, testability, sizing). Tools: Read, Glob, Grep. Model: sonnet.
- `merger`: Git branch lifecycle (create, merge, cleanup). Tools: Bash, Read, Grep. Model: haiku.

**Skills:**
- `prd-generator`: Creates detailed PRDs with verifiable acceptance criteria and dependency tracking. Uses 5-criteria threshold for story decomposition.
- `prd-converter`: Transforms markdown PRD to `prd.json` with inferred `depends_on`, `related_to`, `implementation_hint`, and `check_before_implementing` fields.
- `failure-analyzer`: Categorizes failed task output into: `env_missing`, `test_failure`, `timeout`, `code_error`, `dependency_missing`, `unknown`. Recommends retry strategy with max retry limits per category.

**Hooks:**
- `PostToolUse` on Bash: Runs `check-destructive.sh` to block `git push --force`, `git reset --hard`, `git clean`, and direct pushes to main/master during implementation.

**Scripts:**
- `taskplex.sh`: Main orchestration loop — runs fresh Claude instances until all stories complete
- `prompt.md`: Instructions given to each Claude agent (includes "check before implementing" guidance)
- `check-deps.sh`: Validates `claude` CLI, `jq`, and `coreutils` installation
- `check-destructive.sh`: PostToolUse hook — blocks dangerous git commands

### State Files (User's Project)

```
.claude/
├── taskplex.config.json         # Config (JSON format)
├── taskplex-{branch}.pid        # Per-branch PID file
└── taskplex.log                 # Background mode log

tasks/
└── prd-{feature}.md             # Human-readable PRD

prd.json                         # Execution format (source of truth)
progress.txt                     # Learnings log (append-only)
```

---

## Key Features

### 1. Custom Subagents

Each agent has restricted tools and a specific model, replacing the monolithic `claude -p` approach:

| Agent | Model | Tools | Purpose |
|-------|-------|-------|---------|
| implementer | inherit | Bash, Read, Edit, Write, Glob, Grep | Code a single story |
| validator | haiku | Bash, Read, Glob, Grep | Verify acceptance criteria |
| reviewer | sonnet | Read, Glob, Grep | Review PRD quality |
| merger | haiku | Bash, Read, Grep | Git branch operations |

### 2. Error Categorization & Retry

When a task fails, the failure-analyzer skill classifies the error:

| Category | Retry? | Max Retries | Action |
|----------|--------|-------------|--------|
| `env_missing` | No | 0 | Skip, log for user |
| `test_failure` | Yes | 2 | Retry with test output as context |
| `timeout` | Yes | 1 | Retry with 1.5x timeout |
| `code_error` | Yes | 2 | Retry with error output as context |
| `dependency_missing` | No | 0 | Skip, log for user |
| `unknown` | Once | 1 | Retry once, then skip |

### 3. Resilience & Process Management

**Iteration Timeouts:**
- Default: 3600 seconds (60 minutes)
- Configurable via `iteration_timeout` in config
- Foreground: Interactive prompt (skip/retry/abort)
- Background: Auto-skip with logging

**Process Management:**
- Trap-based cleanup (graceful SIGTERM, force SIGKILL fallback)
- Per-branch PID files (allows parallel execution)
- Duplicate run prevention
- Automatic stale file cleanup
- Structured logging to stderr (`[INIT]`, `[ITER-N]`, `[CLEANUP]`, `[TIMEOUT]`)

### 4. Already-Implemented Detection

**Prompt-based** (`scripts/prompt.md`):
- Agents search for existing implementation before coding
- Verify each acceptance criterion
- If all met: mark complete and skip
- If partial: implement only missing pieces
- Never refactor working code

### 5. Quality Gate Hooks

**PostToolUse hook** blocks destructive commands:
- `git push --force` / `git push -f`
- `git reset --hard`
- `git clean -f`
- Direct `git push` to main/master

### 6. Enhanced PRD Generation

**Story Decomposition** (5-criteria threshold):
- 3-5 criteria: Ideal story size
- 6-7 criteria: Warning, consider splitting
- 8+ criteria: Must split into multiple stories

**Verifiable Acceptance Criteria:**
- Every criterion must be checkable (not vague)
- Always include "Typecheck passes" as final criterion
- UI stories include "Verify in browser using dev-browser skill"

**Dependency Tracking:**
- `depends_on`: Hard dependencies (must complete first)
- `related_to`: Soft dependencies (check for related work)
- `implementation_hint`: Free-form guidance
- `check_before_implementing`: Grep commands to detect existing code

---

## Development Guidelines

### Modifying Components

**Commands (`start.md`):**
- Follow 7-checkpoint structure
- Use AskUserQuestion at decision points
- Test both foreground and background modes

**Agents (`agents/*.md`):**
- YAML frontmatter defines: name, description, tools, disallowedTools, model
- Keep tool lists minimal (principle of least privilege)
- Use `model: haiku` for cheap/fast agents (validator, merger)
- Use `model: sonnet` for quality-sensitive agents (reviewer)
- Use `model: inherit` for agents that should use user's configured model (implementer)

**Skills (`skills/*/SKILL.md`):**
- Single responsibility per skill
- Lettered options for questions (A, B, C, D)
- Document expected input/output format

**Hooks (`hooks/hooks.json`):**
- Follow Claude Code hooks schema
- `${CLAUDE_PLUGIN_ROOT}` resolves to plugin install path
- Hook scripts must be executable (`chmod +x`)

**Scripts (`scripts/*.sh`):**
- Use `set -e` for fail-fast
- Keep portable (avoid bash 4+ features)
- Use `${CLAUDE_PLUGIN_ROOT}` in command references
- Use absolute paths in scripts
- Make executable: `chmod +x scripts/*.sh`

### Testing Changes

```bash
# 1. Make changes in this directory

# 2. Reinstall plugin
/plugin uninstall taskplex@flight505-marketplace
/plugin install taskplex@flight505-marketplace

# 3. Restart Claude Code

# 4. Test command
/taskplex:start

# 5. Verify files created
ls -la .claude/ tasks/ prd.json progress.txt
```

---

## File Conventions

**Naming:**
- Commands: `kebab-case.md`
- Skills: `kebab-case/` directories with `SKILL.md`
- Agents: `kebab-case.md` in `agents/` directory
- Scripts: `kebab-case.sh` or `kebab-case.md`
- Hooks: `hooks.json` in `hooks/` directory
- Config: `.claude/taskplex.config.json`

**Path References:**
- In commands (markdown): `${CLAUDE_PLUGIN_ROOT}/scripts/file.sh`
- In skills (markdown): relative paths `./examples/file.md`
- In hooks (JSON): `${CLAUDE_PLUGIN_ROOT}/scripts/file.sh`
- In bash scripts: absolute paths `$HOME/.claude/...`
- Never hardcode absolute paths in committed files

**Script Permissions:**
```bash
chmod +x scripts/*.sh
git add --chmod=+x scripts/*.sh
```

---

## Configuration Schema

`.claude/taskplex.config.json` format:

```json
{
  "max_iterations": 25,
  "iteration_timeout": 3600,
  "execution_mode": "foreground",
  "execution_model": "opus",
  "effort_level": "high",
  "editor_command": "code",
  "branch_prefix": "taskplex"
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `max_iterations` | int | 25 | Stop after N iterations (1 story = 1-3 iterations) |
| `iteration_timeout` | int | 3600 | Timeout per iteration in seconds (60 min) |
| `execution_mode` | string | "foreground" | "foreground" (interactive) or "background" |
| `execution_model` | string | "opus" | "sonnet" or "opus" for story implementation |
| `effort_level` | string | "high" | "low", "medium", or "high" (Opus 4.6 only) |
| `editor_command` | string | "code" | Command to open files |
| `branch_prefix` | string | "taskplex" | Git branch prefix |

**Iteration Guidelines:**
- Each story typically consumes 1-3 iterations
- Simple stories: 1 iteration (already-implemented check passes)
- Standard stories: 1-2 iterations (implement + verify)
- Complex stories: 2-3 iterations (may need retries/fixes)
- Formula: `stories x 2.5 = recommended iterations`

**Model Selection:**
- `execution_model`: Which Claude model implements the stories
- `effort_level`: Controls reasoning depth for Opus 4.6 (low/medium/high). Ignored for Sonnet.
  - `high` (default): Deep reasoning, best quality, highest cost
  - `medium`: Best cost/quality balance
  - `low`: Fastest, minimal reasoning, cheapest
- Planning (PRD generation) uses `CLAUDE_CODE_SUBAGENT_MODEL` env var (recommend: opus)

---

## Authentication

TaskPlex supports two methods with intelligent fallback:

**OAuth Token (Recommended for Max subscribers):**
```bash
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN='your-token'
```

**API Key (Fallback):**
```bash
export ANTHROPIC_API_KEY='your-key'
```

Script prioritizes OAuth if available, falls back to API key otherwise.

---

## Debugging

### Command Not Appearing

```bash
# Check installation
cat ~/.claude/plugins/installed_plugins.json | jq '.plugins | keys'

# Verify plugin structure
ls -la ~/.claude/plugins/cache/flight505-marketplace/taskplex/*/

# Check manifest
cat ~/.claude/plugins/cache/flight505-marketplace/taskplex/*/.claude-plugin/plugin.json
```

### Loop Issues

```bash
# Test script directly
bash scripts/taskplex.sh 1

# Check Claude CLI
claude -p "What is 2+2?" --output-format json --no-session-persistence

# Verify dependencies
bash scripts/check-deps.sh
```

### Skills Not Loading

```bash
# Verify skill structure
ls -la skills/*/SKILL.md

# Check frontmatter
head -5 skills/*/SKILL.md
```

### Agent Issues

```bash
# Verify agent structure
ls -la agents/*.md

# Check frontmatter has required fields
head -15 agents/*.md
```

### Hook Issues

```bash
# Verify hooks.json is valid JSON
jq . hooks/hooks.json

# Test destructive command blocker
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | bash scripts/check-destructive.sh
```

---

## Version History

### v1.0.0 (2026-02-11)

**Initial release — successor to SDK Bridge v4.8.1:**

**Added:**
- Custom subagents: implementer, validator, reviewer, merger
- Failure analyzer skill with 6 error categories and retry strategies
- PostToolUse hook to block destructive git commands
- JSON configuration format (replaces YAML frontmatter)
- Structured agent output format with error categorization

**Inherited from SDK Bridge:**
- Interactive wizard with 7 checkpoints
- PRD generator skill with smart decomposition
- PRD converter skill with dependency inference
- Configurable iteration timeouts
- Already-implemented detection
- Robust process management
- Verifiable acceptance criteria
- Automatic archiving of previous runs

**Architecture changes:**
- Monolithic `claude -p` replaced with purpose-built agents
- Config moved from `.claude/sdk-bridge.local.md` (YAML) to `.claude/taskplex.config.json` (JSON)
- Branch prefix changed from `sdk-bridge/` to `taskplex/`
- All references renamed from sdk-bridge to taskplex

---

## References

- [Claude Code CLI](https://code.claude.com/docs/en/cli-reference.md)
- [Claude Code Headless Mode](https://code.claude.com/docs/en/headless.md)
- [Claude Code Custom Subagents](https://code.claude.com/docs/en/sub-agents.md)
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks.md)
- [Plugin Development Guide](https://github.com/anthropics/claude-code/blob/main/docs/plugins.md)
- [Marketplace Format](https://github.com/anthropics/claude-code/blob/main/docs/plugin-marketplace.md)
- [TaskPlex Architecture Plan](./TASKPLEX-ARCHITECTURE.md)

---

**Maintained by:** Jesper Vang (@flight505)
**Repository:** https://github.com/flight505/flight505-marketplace
**License:** MIT
