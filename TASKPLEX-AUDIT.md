# TaskPlex Codebase Audit

**Date:** 2026-02-27 | **Version audited:** 4.1.0 | **Author:** Jesper Vang

---

## 1. Component Connectivity Map

### Core Pipeline (All Connected)

```
SessionStart hook ──→ session-context.sh ──→ injects using-taskplex awareness
                                              │
User prompt ──→ using-taskplex skill ──→ routes to brainstorm/prd-generator/etc.
                                              │
/taskplex:start command ──→ prd-generator ──→ prd-converter ──→ prd.json
                                              │
taskplex.sh orchestrator ←── reads prd.json ──┘
  │
  ├── decision-call.sh (sourced) ──→ model routing per story
  ├── knowledge-db.sh (sourced) ──→ SQLite queries/inserts
  ├── harden_spec() ──→ claude -p --model haiku (SSC)
  │
  ├── claude -p --agent implementer ──→ SubagentStart hook
  │     │                                  │
  │     │                    inject-knowledge.sh ──→ knowledge-db.sh
  │     │                    subagent-start.sh ──→ inject-edit-context.sh
  │     │
  │     ├── implementer works ──→ PreToolUse hooks fire
  │     │     │
  │     │     └── check-destructive.sh (every Bash call)
  │     │
  │     └── implementer stops ──→ SubagentStop hook
  │           │
  │           └── validate-result.sh ──→ typecheck/build/test
  │                                      mines implicit learnings
  │
  ├── run_spec_review() ──→ claude -p --agent spec-reviewer
  ├── run_code_review() ──→ claude -p --agent code-reviewer (opt-in)
  │
  ├── commit_story() ──→ git add + commit
  ├── record_learning_success() ──→ knowledge-db.sh (Bayesian)
  └── emit_event() ──→ monitor dashboard (optional, fire-and-forget)

Stop hook ──→ stop-guard.sh ──→ blocks premature exit
TaskCompleted hook ──→ task-completed.sh ──→ gates on test pass
PreCompact hook ──→ pre-compact.sh ──→ saves state before compaction
TeammateIdle hook ──→ teammate-idle.sh ──→ assigns work (Agent Teams)
SessionEnd hook ──→ session-lifecycle.sh ──→ cleanup
```

### Agent Invocation Map

| Agent | Invoked By | Method | Frequency |
|-------|-----------|--------|-----------|
| **implementer** | taskplex.sh | `claude -p --agent implementer` | Every story |
| **spec-reviewer** | taskplex.sh `run_spec_review()` | `claude -p --agent spec-reviewer` | Every story |
| **code-reviewer** | taskplex.sh `run_code_review()` | `claude -p --agent code-reviewer` | Opt-in (config) |
| **validator** | taskplex.sh (via Task tool in agents) | Task tool dispatch | Per validation |
| **architect** | brainstorm skill | Task tool dispatch | Per brainstorm |
| **merger** | taskplex.sh `invoke_merger()` | `claude -p --agent merger` | On merge conflicts |
| **reviewer** | **NOBODY** | — | **NEVER** |

### Script Sourcing Graph

```
taskplex.sh
  ├── sources: knowledge-db.sh (all DB functions)
  └── sources: decision-call.sh (routing functions)

inject-knowledge.sh (hook)
  └── sources: knowledge-db.sh

validate-result.sh (hook)
  └── sources: knowledge-db.sh

parallel.sh
  ├── sources: knowledge-db.sh
  └── sources: decision-call.sh

teams.sh
  └── sources: knowledge-db.sh

pre-compact.sh (hook)
  └── sources: knowledge-db.sh
```

### Skill Cross-References

| Skill | References These Skills |
|-------|----------------------|
| using-taskplex | All 16 other skills (routing table) |
| writing-plans | subagent-driven-development, executing-plans |
| executing-plans | using-git-worktrees, writing-plans, finishing-a-development-branch |
| subagent-driven-development | requesting-code-review |
| requesting-code-review | receiving-code-review, code-reviewer agent |
| finishing-a-development-branch | (standalone) |
| brainstorm | architect agent, writing-plans |

---

## 2. Orphaned / Dead Components

### 🔴 CONFIRMED: `reviewer` Agent — Never Invoked

**File:** `agents/reviewer.md`
**Evidence:** Zero references in scripts, hooks, or skills. Only in `plugin.json` and historical plan docs.
- `run_review_agent()` dispatches `spec-reviewer` and `code-reviewer`, never `reviewer`
- `requesting-code-review` skill dispatches `code-reviewer`, not `reviewer`
- The agent was designed for PRD review but no code path ever calls it

**Impact:** Registered in plugin.json → loaded into Claude's agent registry → occupies context. Removing it saves ~65 lines of agent spec from plugin loading.

**Recommendation:** Remove from plugin.json. Keep the file for reference or delete entirely.

### 🟡 QUESTIONABLE: `query_decisions()` — Test-Only Function

**File:** `scripts/knowledge-db.sh:357`
**Evidence:** Only called by `test-results/taskplex/run-tests.sh:480` (test suite). Zero production callers.
**Impact:** Minimal — 12 lines, harmless. But `query_decision_stats()` (line 370) is the production version.
**Recommendation:** Keep (test infrastructure), but mark clearly as test-only in comment.

### 🟡 QUESTIONABLE: `monitor/` Directory — Optional Sidecar

**Size:** Full Bun+Vue3 app (280KB+ with node_modules)
**Connected:** Yes — `emit_event()` sends data to it, `monitor/hooks/` has PostToolUse/SubagentStop handlers
**Impact:** Zero overhead when not running (all guarded by `[ -z "$MONITOR_PORT" ]`). Node_modules is gitignored.
**Recommendation:** Keep as-is. It's properly optional.

---

## 3. Documentation Consolidation

### Current State: 11 tracked doc files, 280KB plans

| File | Size | Status | Action |
|------|------|--------|--------|
| **CLAUDE.md** | 7KB | ✅ Current (v4.1.0) | Keep — developer quick-ref |
| **README.md** | 12KB | ⚠️ **SEVERELY OUTDATED** (v2.0.1) | **REWRITE** |
| **TASKPLEX-ARCHITECTURE.md** | 20KB | ✅ Current (v4.0.0) | Keep — ground truth |
| **TASKPLEX-SOTA-RESEARCH-AND-PLAN.md** | 17KB | ✅ Current (v1.1) | Keep — competitive intel |
| **CHANGELOG.md** | 8KB | ✅ Current (v4.1.0) | Keep — version history |
| **docs/2026-02-17-evolution-audit.md** | 15KB | ⚠️ Stale (v2.0 era) | Archive |
| **docs/plans/** (10 files) | 250KB | ⚠️ All historical, all shipped | Archive |

### One True Source Map

| Topic | Authoritative File | Alternatives to Remove/Redirect |
|-------|-------------------|-------------------------------|
| How to develop/configure | **CLAUDE.md** | README.md config section (outdated) |
| Architecture deep dive | **TASKPLEX-ARCHITECTURE.md** | README.md "How It Works" (outdated) |
| Competitive positioning | **TASKPLEX-SOTA-RESEARCH-AND-PLAN.md** | — |
| Version history | **CHANGELOG.md** | — |
| Public overview | **README.md** (needs rewrite) | — |

### Recommended Actions

1. **REWRITE README.md** — Update from v2.0.1 to v4.1.0:
   - Missing 3 agents (architect, spec-reviewer, code-reviewer)
   - Missing 13 config options
   - No mention of: proactive path, brainstorm, routing, checksums, scope drift, Agent Teams, interactive mode, SSC, Bayesian
   - Wizard says 7 checkpoints (now 8)

2. **Archive historical plans** — Move to `docs/archive/`:
   - All 10 plan files are shipped features (v1.2.1 → v4.0.0)
   - The evolution audit is v2.0-era analysis
   - Add a one-line `docs/archive/README.md` explaining they're historical

3. **Remove content duplication** — Architecture overview appears in 4 places:
   - CLAUDE.md (brief) ✅ keep
   - TASKPLEX-ARCHITECTURE.md (detailed) ✅ keep
   - README.md (outdated) → rewrite, link to architecture doc
   - SOTA doc (competitive context) ✅ keep

---

## 4. Performance Concerns

### Hot Path Analysis

Hooks that fire on **every tool use** (hundreds of times per run):

| Hook | Script | Event | Lines | Concern |
|------|--------|-------|-------|---------|
| check-destructive.sh | PreToolUse (Bash) | Every Bash call | 40 | Uses `jq` to parse input — could use native bash pattern matching |
| inject-edit-context.sh | PreToolUse (Edit/Write) | Every file edit | ~50 | Queries SQLite for file patterns per edit |

Hooks that fire **per agent lifecycle** (7-20x per run):

| Hook | Script | Event | Lines | Concern |
|------|--------|-------|-------|---------|
| inject-knowledge.sh | SubagentStart | Agent spawn | 259 | **Largest hook**. 4+ separate jq calls to parse prd.json, SQLite queries, eval of check_before_implementing commands |
| validate-result.sh | SubagentStop | Agent complete | 236 | Multiple jq calls, builds test commands, mines learnings |

### Optimization Opportunities

1. **check-destructive.sh** — Replace `jq` parse with bash regex:
   ```bash
   # Current (spawns jq process):
   COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
   # Faster (pure bash):
   COMMAND="${INPUT##*\"command\":\"}" && COMMAND="${COMMAND%%\"*}"
   ```
   **Savings:** ~30-40% per invocation, multiplied by hundreds of Bash calls per run.

2. **inject-knowledge.sh** — Batch jq queries:
   ```bash
   # Current: 4 separate jq calls to prd.json
   # Could: Single jq call extracting story, deps, checks, others at once
   ```
   **Savings:** ~50% per agent start (4 process spawns → 1).

3. **harden_spec()** (new in v4.1.0) — calls `claude -p` which is slow (~5-10s). Already gated to first attempt only, which is correct. No further optimization needed.

---

## 5. Config Consistency Audit

All 25 config options in CLAUDE.md are loaded in `taskplex.sh` `load_configuration()`:

| Config Key | Loaded? | Used? | Notes |
|-----------|---------|-------|-------|
| max_iterations | ✅ | ✅ | CLI arg overrides |
| iteration_timeout | ✅ | ✅ | |
| execution_mode | ✅ | ✅ | |
| execution_model | ✅ | ✅ | |
| effort_level | ✅ | ✅ | Opus 4.6 only |
| branch_prefix | ✅ | ✅ | |
| max_retries_per_story | ✅ | ✅ | |
| max_turns | ✅ | ✅ | |
| merge_on_complete | ✅ | ✅ | |
| test_command | ✅ | ✅ | |
| build_command | ✅ | ✅ | |
| typecheck_command | ✅ | ✅ | |
| parallel_mode | ✅ | ✅ | |
| interactive_mode | ✅ | ✅ | |
| scope_drift_action | ✅ | ✅ | |
| max_parallel | ✅ | ✅ | parallel.sh |
| worktree_dir | ✅ | ✅ | parallel.sh |
| worktree_setup_command | ✅ | ✅ | parallel.sh |
| conflict_strategy | ✅ | ✅ | parallel.sh |
| code_review | ✅ | ✅ | run_code_review() |
| decision_calls | ✅ | ✅ | |
| decision_model | ✅ | ✅ | |
| validate_on_stop | ✅ | ✅ | validate-result.sh |
| model_routing | ✅ | ✅ | |
| spec_hardening | ✅ | ✅ | harden_spec() |
| spec_harden_model | ✅ | ✅ | harden_spec() |

**Result:** 100% config coverage. No phantom options.

---

## 6. Recommended Cleanup Actions

### Priority 1: Quick wins (can do now)

| Action | Impact | Risk | Effort |
|--------|--------|------|--------|
| Remove `reviewer` agent from plugin.json | Smaller plugin footprint | None (never invoked) | 1 min |
| Archive `docs/plans/` → `docs/archive/` | Cleaner directory structure | None (all shipped) | 2 min |
| Archive `docs/2026-02-17-evolution-audit.md` → `docs/archive/` | Same | None | 1 min |

### Priority 2: Documentation (should do soon)

| Action | Impact | Risk | Effort |
|--------|--------|------|--------|
| Rewrite README.md to v4.1.0 | Public docs match reality | Low | 30 min |
| Add doc navigation headers to root docs | Cross-referencing | None | 10 min |

### Priority 3: Performance (optional)

| Action | Impact | Risk | Effort |
|--------|--------|------|--------|
| Optimize check-destructive.sh (bash regex) | Faster Bash tool use | Low (needs testing) | 15 min |
| Batch jq in inject-knowledge.sh | Faster agent start | Medium (complex jq) | 30 min |

---

## 7. Overall Health

```
Codebase: 5,220 lines across scripts + hooks
Active:   5,155 lines (98.8%)
Dead:     ~65 lines (reviewer agent, 1.2%)
Optional: ~300 lines (monitor emit_event, properly guarded)

Documentation: 79KB root docs + 280KB historical plans
Current:  64KB (81%)
Outdated: 15KB README (19%)
Archive:  280KB plans (historical, all shipped)
```

**Verdict:** The codebase is tight. The v2→v3→v4 transformations left remarkably little dead code — mainly the `reviewer` agent that was designed but never wired into the runtime pipeline. The real debt is in documentation (README.md stuck at v2.0.1).
