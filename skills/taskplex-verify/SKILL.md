---
name: taskplex-verify
description: "Use before claiming ANY work is complete, fixed, or passing. Enforces fresh verification evidence before completion claims. The Iron Law."
disable-model-invocation: false
user-invocable: true
---

# Verification Before Completion

## The Iron Law

**NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE.**

Before saying "done", "fixed", "passing", "working", or "complete":

1. **IDENTIFY** what needs verification
2. **RUN** the verification command (fresh — not cached output)
3. **READ** the actual output
4. **VERIFY** it matches expectations
5. **THEN** — and only then — make your claim

## Forbidden Without Evidence

| Phrase | Required Evidence |
|--------|-------------------|
| "This should work" | Run it. Show output. Does it? |
| "Tests are passing" | Show the test output. Which tests? All of them? |
| "The bug is fixed" | Reproduce the original bug. Is it gone? Show before/after. |
| "I've implemented X" | Run the acceptance criteria verification commands. |
| "Everything looks good" | What did you check? Show the commands and output. |
| "It's ready" | Run test suite + typecheck + build. Show all output. |

## Verification Checklist

Before claiming any work is complete:

- [ ] Ran test suite (fresh execution, not cached result)
- [ ] Ran typecheck/lint (if project has it configured)
- [ ] Ran build command (if project has it configured)
- [ ] Verified each acceptance criterion with its "Must verify" command
- [ ] Checked for regressions (existing tests still pass)
- [ ] Evidence captured (actual command output, not just "it worked")

## Triple-Layer Enforcement

TaskPlex enforces verification at three levels:

```
Layer 1: This skill (cognitive discipline)
  Claude self-checks before claiming done
      ↓ (if Claude claims done anyway)
Layer 2: TaskCompleted hook (automated gate)
  Runs tests, blocks completion if they fail
      ↓ (if Claude tries to stop the session)
Layer 3: Stop hook (safety net)
  Checks for active stories, blocks premature exit
```

If you follow this skill's discipline, the hooks never need to fire. The hooks exist as a safety net for when discipline slips.

## When This Skill Applies

- Before ANY message containing: "done", "complete", "fixed", "passing", "working", "ready", "finished"
- Before committing implementation work
- Before marking a TaskPlex story as complete
- Before responding to "is it working?" with a yes
- Before closing a task or issue
