---
name: verification-before-completion
description: "Gates completion claims with fresh verification evidence, scaled to the size of the change. Use when about to claim work is complete, fixed, or passing, before committing or creating PRs, or before trusting a subagent's success report."
---

# Verification Before Completion

**Core principle:** Run the command, read the output, then make the claim.

## Proportional Verification

Scale verification to the change:

| Change Size | What to Verify |
|-------------|---------------|
| **Single file** (typo, config, rename) | Relevant test or linter for that file |
| **Multi-file** (feature, refactor) | Full test suite + build |
| **Cross-system** (API change, migration) | Full suite + integration tests + manual check |

Don't run a 10-minute test suite for a typo fix. Don't skip tests for a 4-file refactor.

## The Gate

Before claiming any status:

1. **Identify** — what command proves this claim?
2. **Run** — execute fresh in this turn (not from memory or a previous run)
3. **Read** — full output, check exit code, count failures
4. **Report** — state the result with evidence

## Common Checks

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test output: 0 failures | Previous run, "should pass" |
| Build succeeds | Build exit 0 | Linter passing |
| Bug fixed | Reproducer passes after fix | "Code changed, assumed fixed" |
| Agent completed | VCS diff shows expected changes | Agent reports "success" |
| Requirements met | Line-by-line checklist against spec | "Tests pass" alone |

## Watch For

- Using "should", "probably", "seems to" — these are guesses, not evidence
- Expressing satisfaction before running verification
- Trusting a subagent's success report without checking the diff
- Relying on a previous run instead of running fresh
- Claiming partial success as full completion

## Bottom Line

Evidence before claims. Scale the evidence to the change.
