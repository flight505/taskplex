---
name: failure-analyzer
description: "Analyzes failed task output to categorize the error and suggest a retry strategy. Use when a TaskPlex implementation attempt fails."
---

# Failure Analyzer

Analyzes failed task output to determine the error category and recommend a retry strategy.

## Error Categories

| Category | Detection Patterns | Strategy | Max Retries |
|----------|-------------------|----------|-------------|
| `env_missing` | "API key", "token", "credentials", "ECONNREFUSED", "connection refused" | Skip immediately, log for user | 0 |
| `test_failure` | Tests ran but assertions failed | Retry with test output as context | 2 |
| `timeout` | Exit code 124, "timed out" | Retry with 1.5x timeout | 1 |
| `code_error` | Linter, typecheck, build errors | Retry with error output as context | 2 |
| `dependency_missing` | "Cannot find module", "ModuleNotFoundError", "package not found" | Skip, log for user | 0 |
| `unknown` | Unclassifiable | Retry once, then skip | 1 |

## Input

Provide the failed task output (stdout + stderr) and the story details.

## Output

```json
{
  "error_category": "test_failure",
  "confidence": 0.95,
  "evidence": "pytest output shows 2 assertion failures in test_priority.py",
  "retry_recommended": true,
  "retry_context": "Previous attempt failed because: ...",
  "user_action_needed": false,
  "user_action": null
}
```

## Analysis Steps

1. Scan output for category-specific patterns
2. Determine confidence level
3. Extract relevant error context for retry prompt
4. Recommend: retry with context, skip, or request user action
