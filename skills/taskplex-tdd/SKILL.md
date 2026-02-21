---
name: taskplex-tdd
description: "Use when implementing any feature, bugfix, or refactor — before writing implementation code. Enforces RED-GREEN-REFACTOR test-driven development discipline."
disable-model-invocation: false
user-invocable: true
---

# Test-Driven Development

## The Rule

**NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.**

If you wrote production code before writing a test: DELETE IT. Write the test. Watch it fail. Then implement.

## The Cycle

For each piece of functionality:

### RED — Write a failing test

Write a test that describes the desired behavior. Run it. It MUST fail.

If the test passes immediately:
- Your test is wrong (testing nothing useful)
- OR the feature already exists (check before implementing)

### GREEN — Write minimal code

Write the MINIMUM code to make the test pass. Run it. It MUST pass.

Rules:
- No extra code beyond what makes the test pass
- No "while I'm here" additions
- No premature abstractions
- Ugly code is fine — it works

### REFACTOR — Clean up

Clean up the implementation without changing behavior. Run tests. They MUST still pass.

Then move to the next requirement — back to RED.

## Practical Adaptations

TDD is the default. These are the ONLY exceptions:

| Situation | Adaptation |
|-----------|-----------|
| Project has no test infrastructure | Set it up first: one test file, one runner, one passing test. Then TDD. |
| Existing code with no tests | Write characterization tests for code you're changing, then TDD new behavior. |
| Pure CSS/visual-only changes | Snapshot or component tests where practical. Skip TDD for CSS-only. |
| Config/infrastructure files | Smoke test that config loads correctly. Full TDD not always applicable. |
| Bug fix | Write a test that reproduces the bug FIRST (red), then fix (green). This is the most important TDD case. |

## Verification

After each GREEN phase, verify:
- [ ] The new test was RED before implementation
- [ ] The test is now GREEN
- [ ] All existing tests still pass
- [ ] No production code was written without a failing test

## Integration with TaskPlex

When running inside the TaskPlex execution loop:
- Each acceptance criterion gets its own RED-GREEN-REFACTOR cycle
- The implementer agent follows this discipline per criterion
- The validator and spec-reviewer verify the tests exist and pass
