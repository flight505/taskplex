---
name: finishing-a-development-branch
description: "Guides branch integration with structured options: merge, PR, keep, or discard. Use when implementation is complete and tests pass, when a worktree task is done and needs cleanup, when the user says they're finished with a branch, or when it's time to merge, create a PR, or discard experimental work."
---

# Finishing a Development Branch

## Overview

Guide completion of development work by presenting clear options and handling chosen workflow.

**Core principle:** Verify tests → Present options → Execute choice → Clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## The Process

### Step 1: Verify Tests

**Before presenting options, verify tests pass:**

```bash
# Run project's test suite
npm test / cargo test / pytest / go test ./...
```

**If tests fail:**
```
Tests failing (<N> failures). Must fix before completing:

[Show failures]

Cannot proceed with merge/PR until tests pass.
```

Stop. Don't proceed to Step 2.

**If tests pass:** Continue to Step 2.

### Step 2: Determine Base Branch

```bash
# Try common base branches
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

Or ask: "This branch split from main - is that correct?"

### Step 3: Present Options

Present exactly these 4 options:

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
4. Discard this work

Which option?
```

**Don't add explanation** - keep options concise.

### Step 4: Execute Choice

#### Option 1: Merge Locally

```bash
# Switch to base branch
git checkout <base-branch>

# Pull latest
git pull

# Merge feature branch
git merge <feature-branch>

# Verify tests on merged result
<test command>

# If tests pass
git branch -d <feature-branch>
```

Then: Cleanup worktree (Step 5)

#### Option 2: Push and Create PR

```bash
# Push branch
git push -u origin <feature-branch>

# Create PR
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<2-3 bullets of what changed>

## Test Plan
- [ ] <verification steps>
EOF
)"
```

Then: Cleanup worktree (Step 5)

#### Option 3: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

**Don't cleanup worktree.**

#### Option 4: Discard

**Confirm first:**
```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for exact confirmation.

If confirmed:
```bash
git checkout <base-branch>
git branch -D <feature-branch>
```

Then: Cleanup worktree (Step 5)

### Step 5: Cleanup Worktree

**For Options 1, 2, 4:**

If in an `EnterWorktree` session, use the `ExitWorktree` tool to return to the original directory (handles cleanup automatically).

Otherwise, check and remove manually:
```bash
git worktree list | grep $(git branch --show-current)
```

If yes:
```bash
git worktree remove <worktree-path>
```

**For Option 2:** The code is safely on the remote after pushing. Clean up the worktree — the user can check out the branch again from the PR if review feedback requires changes.

**For Option 3:** Keep worktree. Remind user: "Worktree at `<path>` — run `git worktree remove <path>` when done."

### Step 6: Orphan Worktree Check

After cleanup, scan for stale worktrees:
```bash
git worktree list
```

Report any worktrees whose branches no longer exist or that point to merged branches. Offer to clean them up.

## Quick Reference

| Option | Merge | Push | Cleanup Worktree | Cleanup Branch |
|--------|-------|------|-----------------|----------------|
| 1. Merge locally | yes | - | yes | yes |
| 2. Create PR | - | yes | yes | - |
| 3. Keep as-is | - | - | - | - |
| 4. Discard | - | - | yes | yes (force) |

## Guard Rails

- Always verify tests before offering options
- Present exactly 4 options — no open-ended questions
- Require typed "discard" confirmation for Option 4
- Never force-push without explicit request
- Clean worktrees for Options 1, 2, and 4 (code is safe on remote or merged)

## Integration

**Pairs with:**
- **using-git-worktrees** — Cleans up worktree created by that skill
- **code-review plugin** — After creating a PR (Option 2), run `/code-review` for automated 4-agent review
- **receiving-code-review** — Process any review feedback with technical rigor
