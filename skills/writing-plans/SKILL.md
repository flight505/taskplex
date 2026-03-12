---
name: writing-plans
description: "Creates bite-sized, TDD-driven implementation plans from specs or design briefs. Use when breaking down a feature into implementation tasks, when a brainstorm produced a design needing an execution plan, or when the user asks to plan, outline, or decompose work."
---

# Writing Plans

Write implementation plans as bite-sized TDD tasks. Assume the executing agent has zero codebase context — document exact file paths, code, and commands.

**Save plans to:** `docs/plans/YYYY-MM-DD-<feature-name>.md`

## Plan Header

```markdown
# [Feature Name] Implementation Plan

> **For Claude:** Execute task-by-task using TDD. For parallel execution: `/batch` with this plan file.

**Goal:** [One sentence]
**Architecture:** [2-3 sentences]
**Tech Stack:** [Key technologies]

---
```

## Task Structure

Each task is 2-5 minutes of focused work:

````markdown
### Task N: [Component Name]

**Files:** Create: `path/to/file.py` | Modify: `path/to/existing.py` | Test: `tests/path/test.py`

**Step 1: Write failing test**
```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

**Step 2: Run test — expect FAIL**
`pytest tests/path/test.py::test_name -v`

**Step 3: Implement**
```python
def function(input):
    return expected
```

**Step 4: Run test — expect PASS**
`pytest tests/path/test.py::test_name -v`

**Step 5: Commit**
`git add <files> && git commit -m "feat: add specific feature"`
````

## Execution Handoff

After saving the plan, recommend based on the work:

**3+ independent tasks** → recommend `/batch`:
> "Plan saved with N tasks covering [areas]. These are independent — `/batch` will run them in parallel worktrees. Type:
> `/batch docs/plans/<filename>.md`"

**Sequential tasks or <3 tasks** → recommend inline:
> "Plan saved with N tasks. These are tightly coupled — I'll work through them inline with TDD."

When the user accepts `/batch`: output the command and **STOP**. Don't invoke other skills — the CLI takes over.

When the user picks inline: invoke `taskplex:test-driven-development` and begin Task 1.

## Principles

- Exact file paths, complete code, exact commands with expected output
- DRY, YAGNI, TDD, frequent commits
- One plan doc per feature — no separate design doc
- Reference relevant docs the agent might need to check
