---
description: "Start TaskPlex interactive wizard - generates PRD, converts to JSON, and runs resilient autonomous agent loop with dependency enforcement"
argument-hint: "[feature-description]"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Task, AskUserQuestion, TodoWrite
---

# TaskPlex Start

**Active state detection:**

!`if [ -f prd.json ]; then echo "EXISTING_PRD=true"; jq '{project: .project, stories: (.userStories | length), done: [.userStories[] | select(.passes == true)] | length, pending: [.userStories[] | select(.passes == false and .status != "skipped" and .status != "rewritten")] | length}' prd.json 2>/dev/null; else echo "EXISTING_PRD=false"; fi`

!`if [ -f .claude/taskplex.config.json ]; then echo "EXISTING_CONFIG=true"; else echo "EXISTING_CONFIG=false"; fi`

If EXISTING_PRD=true and there are pending stories:

1. Display the run status to the user: project name, total stories, done count, pending count
2. Use AskUserQuestion with these options:
   - **Resume existing run** — Skip directly to Checkpoint 8 (Launch) using existing prd.json and .claude/taskplex.config.json
   - **Start fresh** — Archive the current run by moving `prd.json` to `archive/YYYY-MM-DD-{project}/prd.json`, `progress.txt` to same dir, `knowledge.db` to same dir, then start from Checkpoint 3
   - **Cancel** — Stop the wizard
3. If "Resume": verify .claude/taskplex.config.json exists. If yes, jump to Checkpoint 8. If not, jump to Checkpoint 7 to configure first.
4. If "Start fresh": create the archive directory with `mkdir -p archive/$(date +%Y-%m-%d)-$(jq -r .project prd.json | tr ' ' '-')`, move files, then continue to Checkpoint 1.

If EXISTING_PRD=false, continue with the full wizard below.

Interactive wizard that guides you through the complete TaskPlex workflow:
1. Check dependencies
2. Validate git repository
3. Describe your project/feature
4. Generate PRD with clarifying questions
5. Review and approve PRD
6. Convert to execution format
7. Configure execution settings
8. Launch autonomous agent loop

## Execution

**Checkpoint 1: Check Dependencies**

First, verify required dependencies are installed:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/check-deps.sh
```

If dependencies are missing, use AskUserQuestion:

Question: "TaskPlex requires these tools: [list missing]. Install automatically?"
- Header: "Install"
- multiSelect: false
- Options:
  - Label: "Yes - install for me" | Description: "Automatically install missing dependencies"
  - Label: "No - I'll install manually" | Description: "Show installation instructions and exit"

If user approves automatic install:
- For claude CLI: Explain that the `claude` command comes with Claude Code and should already be available. If not found, the user may need to reinstall Claude Code or add it to their PATH.
- For jq on macOS: `brew install jq`
- For jq on Linux: Show instructions for apt/yum (e.g., `sudo apt-get install jq` or `sudo yum install jq`)
- For coreutils on macOS: `brew install coreutils` (provides gtimeout command for iteration timeouts)
- For coreutils on Linux: Usually pre-installed; if missing: `sudo apt-get install coreutils` or `sudo yum install coreutils`

If user declines or install fails, show manual installation instructions and exit.

**Checkpoint 2: Validate Git Repository**

Run the git diagnostic script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/check-git.sh
```

Parse the JSON output. Handle each scenario:

**Scenario A: No git repository (`needs_init: true`, exit code 1)**

Use AskUserQuestion:

Question: "No git repository found. TaskPlex needs a git repo to manage branches and track changes. Initialize one?"
- Header: "Git Init"
- multiSelect: false
- Options:
  - Label: "Yes — initialize git repo (Recommended)" | Description: "Run git init, create .gitignore with TaskPlex entries, and make initial commit"
  - Label: "No — I'll set it up myself" | Description: "Exit so you can configure git manually"

If user approves:
1. Run `git init`
2. Create `.gitignore` with TaskPlex state files (see gitignore entries below)
3. Run `git add .gitignore && git commit -m "chore: initialize repository with .gitignore"`
4. Display: "Git repository initialized. Continuing..."

If user declines, exit gracefully: "Please initialize a git repository and run /taskplex:start again."

**Scenario B: Detached HEAD (`is_detached: true`)**

Display warning: "You are in detached HEAD state. TaskPlex needs a named branch to create feature branches."

Use AskUserQuestion:

Question: "Create a new branch from current state?"
- Header: "Branch"
- multiSelect: false
- Options:
  - Label: "Yes — create 'main' branch" | Description: "git checkout -b main"
  - Label: "No — I'll fix this myself" | Description: "Exit to resolve manually"

If user approves, run `git checkout -b main`.

**Scenario C: Dirty working tree (`is_dirty: true`)**

Display the dirty files summary from the diagnostic output (show the `dirty_files` array, e.g., " M src/index.ts", "?? new-file.txt").

Use AskUserQuestion:

Question: "[dirty_count] uncommitted changes found. TaskPlex creates a feature branch — uncommitted changes may cause conflicts."
- Header: "Dirty state"
- multiSelect: false
- Options:
  - Label: "Stash changes (Recommended)" | Description: "git stash — restore later with git stash pop"
  - Label: "Commit changes now" | Description: "Quick commit of all changes before starting"
  - Label: "Continue anyway" | Description: "Proceed with uncommitted changes (may cause issues with branch creation)"

Handle:
- **Stash**: Run `git stash push -m "taskplex: auto-stash before run"`. Display: "Changes stashed. Restore with: git stash pop"
- **Commit**: Run `git add -A && git commit -m "chore: save work before taskplex run"`. Display: "Changes committed."
- **Continue**: Display: "Continuing with uncommitted changes. If branch creation fails, stash or commit first."

**Scenario D: New repo with no commits (`has_commits: false`)**

Display: "Git repository exists but has no commits yet."

Run:
1. Check if `.gitignore` exists; if not, create it with TaskPlex entries
2. Run `git add .` (stage everything)
3. Run `git commit -m "chore: initial commit"`
4. Display: "Initial commit created. Continuing..."

**Scenario E: Missing .gitignore entries (`missing_ignores` is non-empty)**

Display which TaskPlex state files are not in `.gitignore`.

Silently add missing entries — these are always correct to ignore. Append to `.gitignore`:

```
# TaskPlex state files (auto-added)
prd.json
progress.txt
knowledge.db
knowledge.md
.claude/taskplex*.pid
.claude/taskplex.log
.claude/taskplex.config.json
```

Only add entries that are actually missing (don't duplicate existing ones). Display: "Updated .gitignore with TaskPlex state files."

**Scenario F: Stale worktrees (`stale_worktrees > 0`)**

Display: "[stale_worktrees] leftover git worktrees found from a previous run."

Run `git worktree prune` silently. Display: "Cleaned up stale worktrees."

**After all scenarios resolved**, display summary:
- "Git repository: [git_root]"
- "Branch: [current_branch]"
- "Remote: [configured/not configured]"
- "Status: Ready"

Proceed to Checkpoint 3.

**Optional: Optimize Planning Quality**

For best results, configure Opus for PRD generation (Steps 3 & 5 use subagents):

```bash
# Add to ~/.zshrc or ~/.bashrc
export CLAUDE_CODE_SUBAGENT_MODEL=opus
```

This makes the PRD generator and converter use Opus 4.6 (the latest, with adaptive reasoning) for superior planning. The planning phase only runs once, so the cost is minimal. Restart your terminal after adding this.

**Checkpoint 3: Project Input**

**Step 1: Get user input**

If `$ARGUMENTS` is non-empty (user ran `/taskplex:start Fix the login bug` or similar):
- Set `user_input` to `$ARGUMENTS`
- Skip the question below and go directly to Step 2

If `$ARGUMENTS` is empty (user ran `/taskplex:start` with no arguments):
- Ask the user: "What would you like to build? Describe your project or provide a file path to an existing spec (e.g., ~/docs/spec.md or ./tasks/plan.md)."
- Wait for the user's response in the chat
- Set `user_input` to the user's response

**Step 2: Process input**

Check if `user_input` looks like a file path:
  - Starts with `~/`, `./`, `/`, or `../`
  - OR ends with common extensions: `.md`, `.txt`, `.pdf`
- If it looks like a file path:
  - Expand `~` to user's home directory if needed
  - Use Read tool to read the file
  - If file exists: Store content as `project_input` and proceed to Checkpoint 4
  - If file doesn't exist: Show error and ask user to provide the description directly
- If it's not a file path:
  - Use `user_input` directly as `project_input`

**If input insufficient (less than 20 words and no file read):**

Conduct a smart interview to gather REQUIRED information:

1. **Project Type (REQUIRED)**: Ask "What type of project is this?"
   - Examples: web app, API, CLI tool, mobile app, library, script, etc.

2. **Main Functionality (REQUIRED)**: Ask "What's the core functionality or purpose?"
   - What problem does it solve?
   - What should users be able to do?

3. **Technical Preferences (optional)**: Ask if relevant:
   - "Any specific language, framework, or stack preferences?"
   - "Any existing systems this needs to integrate with?"

4. **Scale/Complexity (optional)**: Ask if needed for context:
   - "Is this a small feature, medium project, or large system?"

**When to proceed:**
- Once you have clear answers to both REQUIRED items (project type + main functionality), proceed automatically to Checkpoint 4
- No need to ask "do you have enough?" - use your judgment
- If user provides very detailed initial input (>50 words), skip interview entirely

**Example interview flow:**
```
User: "Build an auth system"  [insufficient]
You: "What type of project is this? (web app, API, mobile app, etc.)"
User: "It's a REST API"
You: "What's the core functionality? What should users be able to do with authentication?"
User: "User registration, login with email/password, JWT tokens"
[You now have: type=API, functionality=auth with registration/login/JWT]
→ Proceed to Checkpoint 4 automatically
```

- Proceed to Checkpoint 4

**Checkpoint 4: Generate PRD**

Load the `prd-generator` skill using Task tool:
```
Use the prd-generator skill to create a PRD based on the user's input: [user's description]
```

The skill will:
- Ask 3-5 clarifying questions with lettered options
- Generate structured PRD
- Save to `tasks/prd-[feature-name].md`

**Checkpoint 5: Review PRD**

Open the PRD file with the default editor:
- Run `open tasks/prd-[feature-name].md` to open with default app

Use AskUserQuestion:

Question: "Review the PRD in `tasks/prd-[feature-name].md`. Ready to proceed?"
- Header: "PRD Review"
- multiSelect: false
- Options:
  - Label: "Approved - convert to JSON" | Description: "PRD looks good, proceed to execution format"
  - Label: "Suggest improvements" | Description: "Have Claude review and suggest enhancements"
  - Label: "Need edits - I'll edit" | Description: "Let me edit the file manually, then ask again"
  - Label: "Start over" | Description: "Regenerate PRD from scratch"

**After collecting answer:**

- **If "Approved - convert to JSON"**: Proceed to Checkpoint 6

- **If "Suggest improvements"**:
  1. Read the PRD file with Read tool
  2. Analyze the PRD for potential improvements:
     - Missing edge cases or error scenarios
     - Additional features that complement the core functionality
     - Acceptance criteria that could be more specific or testable
     - Dependencies between stories that weren't captured
     - Security, performance, or accessibility considerations
  3. Present findings to user conversationally:
     - "I've reviewed the PRD. Here are some suggestions:"
     - List 3-5 specific improvements with brief rationale
     - Ask conversationally: "Would you like me to update the PRD with these improvements?"
  4. Wait for user response in chat
  5. If user approves suggestions:
     - Update the PRD file with improvements using Edit tool
     - Display: "PRD updated with improvements"
  6. **Return to the beginning of Checkpoint 5**: Use AskUserQuestion again with the same 4 options (this creates a loop - user can approve improved PRD, request more improvements, manually edit, or start over)

- **If "Need edits - I'll edit"**:
  1. Pause and display "Make your edits to tasks/prd-[feature-name].md and let me know when ready."
  2. Wait for user confirmation in chat
  3. **Return to the beginning of Checkpoint 5**: Use AskUserQuestion again with the same 4 options

- **If "Start over"**: Return to Checkpoint 3

**Checkpoint 6: Convert to JSON**

Load the `prd-converter` skill using Task tool:
```
Use the prd-converter skill to convert tasks/prd-[feature-name].md to prd.json
```

The skill will:
- Convert markdown PRD to JSON format
- Validate structure (IDs, priorities, acceptance criteria)
- Save to `prd.json` in project root

**After conversion, read prd.json and display summary:**
- Count stories in `userStories` array
- Count total acceptance criteria across all stories
- Calculate average criteria per story
- Display: "✓ PRD converted: [story_count] stories, [total_criteria] criteria (avg [avg_criteria]/story)"

**Checkpoint 7: Execution Settings**

Create `.claude/taskplex.config.json` configuration if it doesn't exist.

**First, analyze prd.json to calculate smart defaults:**

1. Read `prd.json` and extract:
   - `story_count` = number of stories in `userStories` array
   - `total_criteria` = sum of all `acceptanceCriteria` arrays across stories
   - `avg_criteria` = total_criteria / story_count (rounded to 1 decimal)

2. Calculate iteration options:
   - `recommended` = ceil(story_count × 2.5) — standard buffer for retries
   - `comfortable` = ceil(story_count × 3.5) — extra buffer for complex work
   - `conservative` = ceil(story_count × 5) — maximum safety margin
   - `minimum` = story_count — absolute minimum (1 per story, no retries)

3. Calculate timeout options based on avg_criteria (complexity proxy):
   - If avg_criteria ≤ 2: `base_timeout` = 30 min (simple stories)
   - If avg_criteria ≤ 4: `base_timeout` = 45 min (standard stories)
   - If avg_criteria ≤ 6: `base_timeout` = 60 min (complex stories)
   - If avg_criteria > 6: `base_timeout` = 90 min (very complex stories)

   Then calculate options:
   - `quick` = base_timeout (may timeout on harder stories)
   - `recommended` = base_timeout + 15 min (buffer for exploration)
   - `generous` = base_timeout + 30 min (extra time for difficult work)
   - `maximum` = 120 min (2 hours, prevents runaway)

Use AskUserQuestion to collect settings (all 4 questions in one call for tabbed UI):

Question 1: "You have [story_count] stories. How many iterations?"
- Header: "Iterations"
- multiSelect: false
- Options:
  - Label: "[recommended] iterations" | Description: "Recommended (2.5× stories) - handles typical retries"
  - Label: "[comfortable] iterations" | Description: "Comfortable (3.5× stories) - extra buffer for complex work"
  - Label: "[conservative] iterations" | Description: "Conservative (5× stories) - maximum safety margin"
  - Label: "[minimum] iterations" | Description: "Minimum (1× stories) - no retry buffer, optimistic"

Question 2: "Stories avg [avg_criteria] criteria each. Timeout per iteration?"
- Header: "Timeout"
- multiSelect: false
- Options:
  - Label: "[quick] minutes" | Description: "Quick ([base_timeout] base) - may timeout on harder stories"
  - Label: "[recommended] minutes" | Description: "Recommended ([base_timeout]+15) - buffer for exploration"
  - Label: "[generous] minutes" | Description: "Generous ([base_timeout]+30) - extra time for difficult work"
  - Label: "120 minutes" | Description: "Maximum (2 hours) - prevents runaway"

Question 3: "How do you want to run TaskPlex?"
- Header: "Mode"
- multiSelect: false
- Options:
  - Label: "Foreground" | Description: "See live output as Claude works (blocks terminal)"
  - Label: "Background" | Description: "Continue working while it runs (check .claude/taskplex.log)"

Question 4: "Which model and effort level for story implementation?"
- Header: "Model"
- multiSelect: false
- Options:
  - Label: "Sonnet 4.5" | Description: "Fast and efficient - good for most tasks (recommended)"
  - Label: "Opus 4.6 (high effort)" | Description: "Best quality - adaptive reasoning, #1 SWE-bench, 128K output (default effort)"
  - Label: "Opus 4.6 (medium effort)" | Description: "Opus quality at 76% fewer tokens - matches Sonnet speed, better reasoning"

**After collecting Q1-Q4, ask parallel execution question:**

Use AskUserQuestion for parallel mode:

Question: "How should stories execute?"
- Header: "Execution"
- multiSelect: false
- Options:
  - Label: "Sequential (Recommended)" | Description: "One story at a time — safest, no merge conflicts"
  - Label: "Parallel (3 concurrent)" | Description: "Independent stories run simultaneously in git worktrees"
  - Label: "Parallel (5 concurrent)" | Description: "More parallelism — faster but uses more resources"

**If parallel mode selected, ask follow-up:**

Question: "Worktree setup command? (run in each new worktree, e.g., npm install)"
- Header: "Setup cmd"
- multiSelect: false
- Options:
  - Label: "None needed" | Description: "No setup required per worktree"
  - Label: "npm install" | Description: "Install Node.js dependencies in each worktree"
  - Label: "pnpm install" | Description: "Install dependencies with pnpm"

**After collecting answers, parse values:**

For iterations (Question 1):
- "[recommended] iterations" → use the calculated `recommended` value
- "[comfortable] iterations" → use the calculated `comfortable` value
- "[conservative] iterations" → use the calculated `conservative` value
- "[minimum] iterations" → use the calculated `minimum` value
- Custom input (via "Other") → parse number from string

For timeout (Question 2):
- "[quick] minutes" → quick × 60 (in seconds)
- "[recommended] minutes" → recommended × 60 (in seconds)
- "[generous] minutes" → generous × 60 (in seconds)
- "120 minutes" → 7200
- Custom input (via "Other") → multiply number by 60

For mode (Question 3):
- "Foreground" → foreground
- "Background" → background

For model (Question 4):
- "Sonnet 4.5" → execution_model: sonnet, effort_level: (not set)
- "Opus 4.6 (high effort)" → execution_model: opus, effort_level: high
- "Opus 4.6 (medium effort)" → execution_model: opus, effort_level: medium
- Custom input (via "Other") → parse model and effort from string

For parallel mode:
- "Sequential (Recommended)" → parallel_mode: sequential
- "Parallel (3 concurrent)" → parallel_mode: parallel, max_parallel: 3
- "Parallel (5 concurrent)" → parallel_mode: parallel, max_parallel: 5

For worktree setup (only if parallel):
- "None needed" → worktree_setup_command: ""
- "npm install" → worktree_setup_command: "npm install"
- "pnpm install" → worktree_setup_command: "pnpm install"
- Custom input (via "Other") → use as-is

**After parallel mode, ask about execution monitor:**

Use AskUserQuestion:

Question: "Enable the execution monitor? Opens a browser dashboard showing real-time progress."
- Header: "Monitor"
- multiSelect: false
- Options:
  - Label: "Yes — open dashboard (Recommended)" | Description: "Launches monitor sidecar on port 4444 and opens browser"
  - Label: "No — skip monitor" | Description: "Run without the dashboard (check logs manually)"

For monitor:
- "Yes — open dashboard" → launch monitor before execution
- "No — skip monitor" → skip monitor launch

**After monitor question, ask about v2.0 intelligence features:**

Use AskUserQuestion:

Question: "Enable Smart Scaffold intelligence features? (decision calls cost ~$0.03/story via Opus)"
- Header: "Intelligence"
- multiSelect: false
- Options:
  - Label: "Full intelligence (Recommended)" | Description: "Decision calls + knowledge store + inline validation — ~$0.03/story overhead"
  - Label: "Knowledge store only" | Description: "SQLite knowledge + inline validation, no decision calls — $0 overhead"
  - Label: "Classic mode" | Description: "Exact v1.2.1 behavior — no decision calls, no inline validation, no SQLite"

For intelligence:
- "Full intelligence" → decision_calls: true, validate_on_stop: true, model_routing: "auto"
- "Knowledge store only" → decision_calls: false, validate_on_stop: true, model_routing: "fixed"
- "Classic mode" → decision_calls: false, validate_on_stop: false, model_routing: "fixed"

Create config file at `.claude/taskplex.config.json` (must be valid JSON — `jq` parses it):
```json
{
  "max_iterations": [parsed number from Q1],
  "iteration_timeout": [parsed seconds from Q2],
  "execution_mode": "[parsed mode from Q3]",
  "execution_model": "[parsed model from Q4]",
  "effort_level": "[parsed effort from Q4, empty string for Sonnet]",
  "branch_prefix": "taskplex",
  "parallel_mode": "[sequential or parallel from Q5]",
  "max_parallel": [3 or 5 from Q5],
  "worktree_setup_command": "[from Q5 follow-up]",
  "conflict_strategy": "abort",
  "decision_calls": "[from intelligence question]",
  "decision_model": "opus",
  "knowledge_db": "knowledge.db",
  "validate_on_stop": "[from intelligence question]",
  "model_routing": "[from intelligence question]"
}
```

Example (8 stories, avg 4 criteria each, parallel mode, full intelligence):
```json
{
  "max_iterations": 20,
  "iteration_timeout": 3600,
  "execution_mode": "foreground",
  "execution_model": "opus",
  "effort_level": "high",
  "branch_prefix": "taskplex",
  "parallel_mode": "parallel",
  "max_parallel": 3,
  "worktree_setup_command": "npm install",
  "conflict_strategy": "abort",
  "decision_calls": true,
  "decision_model": "opus",
  "knowledge_db": "knowledge.db",
  "validate_on_stop": true,
  "model_routing": "auto"
}
```

**Checkpoint 8: Launch**

**If monitor enabled**, start the monitor sidecar first:
```bash
MONITOR_PORT=$(bash ${CLAUDE_PLUGIN_ROOT}/monitor/scripts/start-monitor.sh 2>/dev/null | tail -1)
export TASKPLEX_MONITOR_PORT="${MONITOR_PORT:-4444}"
```

Show user what will happen:
"Starting TaskPlex with [max_iterations] iterations in [mode] mode..."
If monitor is running, also show: "Monitor dashboard: http://localhost:$TASKPLEX_MONITOR_PORT"

If **foreground mode**:
```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/taskplex.sh [max_iterations]
```

User sees live output. Loop continues until:
- All stories complete (outputs `<promise>COMPLETE</promise>`)
- Max iterations reached
- User presses Ctrl+C

If **background mode**:
```bash
mkdir -p .claude
nohup bash ${CLAUDE_PLUGIN_ROOT}/scripts/taskplex.sh [max_iterations] > .claude/taskplex.log 2>&1 &
```

Note: The script creates its own per-branch PID file at `.claude/taskplex-{branchName}.pid`.

Then tell user:
"TaskPlex running in background (PID: $!)"
"View logs: tail -f .claude/taskplex.log"
"Check status: ps -p $!"

## Error Handling

- If prd.json already exists, warn user: "Found existing prd.json. This will be archived when you run TaskPlex."
- If tasks/ directory doesn't exist, create it
- If claude or jq not found and user declines install, exit gracefully with install instructions
- If skill loading fails, show helpful error message

## Success Output

When complete (foreground mode):
"TaskPlex completed [X] iterations"
"Completed stories: [count]"
"Check prd.json for status"
"Review progress.txt for learnings"

When launched (background mode):
"TaskPlex launched in background"
"Monitor with: tail -f .claude/taskplex.log"
"Or check prd.json for completion status"

## Important Notes

- Use TodoWrite to track progress through checkpoints
- Keep user informed at each step
- Validate all file paths before operations
- Use ${CLAUDE_PLUGIN_ROOT} for script paths
- Handle both success and error cases gracefully
