---
name: writing-plans
description: "Creates bite-sized, TDD-driven implementation plans from specs or design briefs. Use when breaking down a feature into implementation tasks, when a brainstorm produced a design needing an execution plan, or when the user asks to plan, outline, or decompose work. If the task touches more than 2-3 files, this skill applies."
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Context:** This should be run in a dedicated worktree (created by brainstorming skill).

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" - step
- "Run it to make sure it fails" - step
- "Implement the minimal code to make the test pass" - step
- "Run the tests and make sure they pass" - step
- "Commit" - step

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** Execute this plan task-by-task using TDD. For parallel execution, the user can run `/batch` with this plan file.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

---
```

## Task Structure

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

**Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

**Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

**Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## Remember
- Exact file paths always
- Complete code in plan (not "add validation")
- Exact commands with expected output
- Reference relevant skills with @ syntax
- DRY, YAGNI, TDD, frequent commits

## Execution Handoff

After saving the plan, present a **contextual handoff** — not a generic menu. Describe what each option will do *for this specific plan*.

**Template** (adapt to the actual plan content):

> "Plan saved to `docs/plans/<filename>.md` with N tasks.
>
> **Parallel execution:** `/batch` will decompose these N tasks into isolated worktrees — each task gets its own agent that implements, runs tests, and opens a PR. [Mention which areas of the codebase the tasks cover]. Type:
> `/batch docs/plans/<filename>.md`
>
> **Inline execution:** I'll work through the tasks one at a time in this session using TDD — write failing test, implement, verify, commit. Better for tasks with tight dependencies or when you want to review each step.
>
> Which approach?"

**Key:** The `/batch` command is a CLI bundled skill — you cannot invoke it via the Skill tool. Give the user the exact command to type, with context about what it will do for *their* plan.

### When the User Chooses

**User picks /batch** (option 1, "parallel", "batch", etc.):
1. Output the exact `/batch docs/plans/<filename>.md` command
2. **STOP.** Do not invoke `test-driven-development`. Do not start implementing. Do not load any other skill.
3. The user will type the command themselves — the CLI takes over from here.

**User picks inline** (option 2, "inline", "one at a time", etc.):
Invoke `taskplex:test-driven-development` and begin with Task 1 of the plan.
