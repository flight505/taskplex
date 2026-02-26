# TaskPlex Benchmark Baseline — v3.1.0

**Date:** 2026-02-26
**Branch:** `taskplex/internal-benchmark`
**Git SHA:** 99bcc46
**Plugin version:** 3.1.0

---

## Structural Tests (tests/structural/)

**All pass — 3/3 suites, 0 failures.**

| Suite | Checks | Status |
|-------|--------|--------|
| manifests (test-manifests.sh) | 61 checks | ✅ PASS |
| scripts (test-scripts.sh) | 103 checks | ✅ PASS |
| cross-refs (test-cross-refs.sh) | 43 checks | ✅ PASS |

**Total:** 207 individual checks, 0 failures.

**Run time:** ~0.97 seconds (no API calls).

---

## Behavioral Tests (tests/behavioral/)

**Hooks suite — 23/23 checks, 0 failures.**

| Suite | Checks | API Calls | Status |
|-------|--------|-----------|--------|
| hooks (test-hooks.sh) | 23 checks | 0 (pure bash) | ✅ PASS |
| skills (test-skill-triggers.sh) | — | — | ⊘ NOT YET (US-005) |
| agents (test-agents.sh) | — | — | ⊘ NOT YET (US-007) |

**Cost:** $0.00 (hooks suite requires no Claude API).

---

## Known Pre-Existing Issues

None — all implemented tests pass at baseline.

**Pending implementation (not failures):**
- `test-skill-triggers.sh` — US-005 (requires real Claude API, ~$4.80/run)
- `test-agents.sh` — US-007 (requires real Claude API, ~$3.00/run)

---

## Regression Detection

To compare future versions against this baseline:

```bash
# Run full structural suite
bash tests/structural/run-all.sh

# Record results
bash tests/regression/record-results.sh tests/structural/results/structural-*.json

# Run hook behavioral suite
bash tests/behavioral/run-all.sh --suite hooks

# Record results
bash tests/regression/record-results.sh tests/behavioral/results/behavioral-*.json

# Compare against this baseline
bash tests/regression/regression-report.sh --baseline 3.1.0
```

**Verdict gates:**
- `FAIL` — any structural test regressed (was PASS, now FAIL)
- `WARN` — behavioral: regressions > improvements (net-negative)
- `PASS` — no structural regressions, behavioral net-neutral or positive

---

## Database State

```
sqlite3 tests/benchmark.db "SELECT version, COUNT(*) FROM structural_results GROUP BY version;"
```
Expected: `3.1.0|1` (1 structural suite run recorded)

```
sqlite3 tests/benchmark.db "SELECT COUNT(*) FROM behavioral_results WHERE version='3.1.0';"
```
Expected: `1` (1 behavioral hooks run recorded)
