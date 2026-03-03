---
description: "Start TaskPlex interactive wizard - generates PRD, converts to JSON, and launches subagent-driven development"
argument-hint: "[feature-description]"
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Task, AskUserQuestion
---

# TaskPlex Start

**Active state detection:**

!`if [ -f prd.json ]; then echo "EXISTING_PRD=true"; jq '{project: .project, stories: (.userStories | length), done: [.userStories[] | select(.passes == true)] | length, pending: [.userStories[] | select(.passes == false and ((.status == "skipped") | not) and ((.status == "rewritten") | not))] | length}' prd.json 2>/dev/null; else echo "EXISTING_PRD=false"; fi`

!`if [ -f .claude/taskplex.config.json ]; then echo "EXISTING_CONFIG=true"; else echo "EXISTING_CONFIG=false"; fi`

**Proactive entry:** TaskPlex skills (prd-generator, prd-converter) can create prd.json
automatically when Claude detects a feature request. If prd.json already exists when you
run this command, the wizard skips directly to configuration (Checkpoint 7). The full
wizard below is a fallback for users who prefer the guided experience or need to start
from scratch.

If EXISTING_PRD=true and there are pending stories:

1. Display the run status to the user: project name, total stories, done count, pending count
2. Use AskUserQuestion with these options:
   - **Resume existing run** — Skip directly to Checkpoint 8 (Launch) using existing prd.json and .claude/taskplex.config.json
   - **Start fresh** — Archive the current run by moving `prd.json` to `archive/YYYY-MM-DD-{project}/prd.json`, then start from Checkpoint 3
   - **Cancel** — Stop the wizard
3. If "Resume": verify .claude/taskplex.config.json exists. If yes, jump to Checkpoint 8. If not, jump to Checkpoint 7 to configure first.
4. If "Start fresh": create the archive directory with `mkdir -p archive/$(date +%Y-%m-%d)-$(jq -r .project prd.json | tr ' ' '-')`, move prd.json, then continue to Checkpoint 1.

If EXISTING_PRD=false, continue with the full wizard below.

Interactive wizard that guides you through the complete TaskPlex workflow:
1. Check dependencies
2. Validate git repository
3. Describe your project/feature
4. Generate PRD with clarifying questions
5. Review and approve PRD
6. Convert to execution format
7. Configure execution settings
8. Launch subagent-driven development

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
- For claude CLI: Explain that the `claude` command comes with Claude Code and should already be available.
- For jq on macOS: `brew install jq`
- For jq on Linux: Show instructions for apt/yum

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
2. Create `.gitignore` with TaskPlex state files
3. Run `git add .gitignore && git commit -m "chore: initialize repository with .gitignore"`

If user declines, exit gracefully.

**Scenario B: Detached HEAD (`is_detached: true`)**

Display warning and offer to create a branch.

**Scenario C: Dirty working tree (`is_dirty: true`)**

Display the dirty files summary and offer stash, commit, or continue.

**Scenario D: New repo with no commits (`has_commits: false`)**

Create initial commit.

**Scenario E: Missing .gitignore entries (`missing_ignores` is non-empty)**

Silently add missing entries for TaskPlex state files:

```
# TaskPlex state files (auto-added)
prd.json
.claude/taskplex.config.json
```

**Scenario F: Stale worktrees (`stale_worktrees > 0`)**

Run `git worktree prune` silently.

**After all scenarios resolved**, display summary and proceed to Checkpoint 3.

**Checkpoint 3: Project Input**

**Step 1: Get user input**

If `$ARGUMENTS` is non-empty (user ran `/taskplex:start Fix the login bug`):
- Set `user_input` to `$ARGUMENTS`
- Skip the question and go directly to Step 2

If `$ARGUMENTS` is empty:
- Ask the user: "What would you like to build? Describe your project or provide a file path to an existing spec."
- Wait for the user's response

**Step 2: Process input**

Check if `user_input` looks like a file path. If so, read it. Otherwise use directly.

**If input insufficient (less than 20 words and no file read):**

Conduct a smart interview:
1. **Project Type (REQUIRED)**: What type of project?
2. **Main Functionality (REQUIRED)**: Core functionality or purpose?
3. **Technical Preferences (optional)**: Language, framework, stack preferences?

Proceed once you have clear answers to both REQUIRED items.

**Checkpoint 4: Generate PRD**

Load the `prd-generator` skill using Task tool:
```
Use the prd-generator skill to create a PRD based on the user's input: [user's description]
```

**Checkpoint 5: Review PRD**

Open the PRD file and use AskUserQuestion:

Question: "Review the PRD in `tasks/prd-[feature-name].md`. Ready to proceed?"
- Header: "PRD Review"
- multiSelect: false
- Options:
  - Label: "Approved - convert to JSON" | Description: "PRD looks good, proceed to execution format"
  - Label: "Suggest improvements" | Description: "Have Claude review and suggest enhancements"
  - Label: "Need edits - I'll edit" | Description: "Let me edit the file manually, then ask again"
  - Label: "Start over" | Description: "Regenerate PRD from scratch"

Handle each option as a loop (suggest improvements and manual edits return to this question).

**Checkpoint 6: Convert to JSON**

Load the `prd-converter` skill using Task tool:
```
Use the prd-converter skill to convert tasks/prd-[feature-name].md to prd.json
```

After conversion, display summary: story count, total criteria, average criteria per story.

**Checkpoint 7: Execution Settings**

Create `.claude/taskplex.config.json` if it doesn't exist.

Use AskUserQuestion to collect 3 settings:

Question 1: "Which model for story implementation?"
- Header: "Model"
- multiSelect: false
- Options:
  - Label: "Sonnet (Recommended)" | Description: "Fast and efficient — good for most tasks"
  - Label: "Opus" | Description: "Best quality — adaptive reasoning, top SWE-bench"
  - Label: "Inherit" | Description: "Use whatever model the user's session is running"

Question 2: "Enable code review after each story?"
- Header: "Review"
- multiSelect: false
- Options:
  - Label: "No (Recommended)" | Description: "Reviewer agent checks spec compliance and validation only"
  - Label: "Yes" | Description: "Add code-reviewer agent for architecture, security, performance review"

Question 3: "Pause between stories for approval?"
- Header: "Interactive"
- multiSelect: false
- Options:
  - Label: "No (Recommended)" | Description: "Execute all stories without pausing"
  - Label: "Yes" | Description: "Pause after each story for user review before continuing"

Parse values and create config:
```json
{
  "branch_prefix": "taskplex",
  "test_command": "",
  "build_command": "",
  "typecheck_command": "",
  "execution_model": "[sonnet|opus|inherit]",
  "merge_on_complete": false,
  "code_review": [true|false],
  "interactive_mode": [true|false]
}
```

Also ask if the project has test/build/typecheck commands to populate those fields.

**Checkpoint 8: Launch**

Display a PRD summary showing:
- Project name from prd.json
- Number of stories and their titles
- Branch name
- Config settings (model, review, interactive)

Then invoke the `subagent-driven-development` skill to guide the main conversation through dispatching agents via the native Task tool.

Tell the user:
"TaskPlex is now executing your PRD using subagent-driven development. Each story will be implemented by a fresh implementer subagent, then reviewed by the reviewer agent."

The skill handles:
- Reading prd.json and creating a task list
- Dispatching implementer agents per story
- Running reviewer after each story
- Optionally running code-reviewer
- Tracking progress via TaskCreate/TaskUpdate

## Error Handling

- If prd.json already exists, warn user and offer to archive
- If tasks/ directory doesn't exist, create it
- If dependencies missing and user declines install, exit gracefully
- If skill loading fails, show helpful error message

## Important Notes

- Keep user informed at each step
- Validate all file paths before operations
- Use ${CLAUDE_PLUGIN_ROOT} for script paths
- Handle both success and error cases gracefully
