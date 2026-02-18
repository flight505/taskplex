# Monitor Dashboard Redesign

**Date:** 2026-02-18
**Status:** Approved
**Scope:** Fix server/client bugs + rebuild client as single-page real-time dashboard

---

## Problem

The current Vue 3 monitor dashboard is non-functional:

1. WebSocket envelope mismatch — client stores `{ type, event }` wrapper instead of unwrapping `event`, so all fields (`event_type`, `timestamp`, `story_id`) are `undefined` → "NaN ago" everywhere
2. API route mismatch — client calls `/runs/:id/errors` but server expects `/api/analytics/errors?run_id=` → 404 → HTML fallback → "Unexpected token '<'" JSON parse error
3. Duration units — server returns `avg_duration_seconds`, client reads `avg_duration_ms` → 1000x off
4. Missing `stories` field — server `getErrorBreakdown()` omits `stories[]` array the client expects → empty table
5. Type mismatches — `MonitorEvent.id` typed `string` (server returns `number`), `RunSummary` field names differ
6. URL construction — redundant double-assignment in `useApi.ts`

Additionally, the 4-tab layout requires switching tabs during live monitoring, hiding critical information behind clicks.

## Decision

- **Fix all 6 bugs** in server and client
- **Replace 4-tab layout** with a single-page dashboard
- **No new dependencies** — Vue 3 + Tailwind + Vite + simple SVG
- **CSS-driven visuals** — glass-morphism, CSS animations, GPU-accelerated transitions
- **Lightweight** — must not compete with TaskPlex agents for compute

## Architecture

### Data Flow (unchanged)

```
Hooks/Orchestrator → POST /api/events → SQLite → WebSocket broadcast → Vue client
```

### Layout

```
┌─────────────────────────────────────────────────────────┐
│  Header: title, connection status, run selector, refresh│
├─────────────────────────────────────────────────────────┤
│  Summary Bar: 4 stat cards + elapsed time + progress    │
├─────────────────────────────────────────────────────────┤
│  Wave Timeline (SVG hero):                              │
│    Stories as horizontal bars grouped by wave            │
│    Color-coded by status, live-growing for active        │
├──────────────────────┬──────────────────────────────────┤
│  Agent Activity Feed │  Error & Retry Panel             │
│  (live, newest first)│  (failures + retry status)       │
└──────────────────────┴──────────────────────────────────┘
```

## Component Specs

### Summary Bar
- 4 stat cards: Completed (green), Running (blue+pulse), Failed (red), Skipped (yellow)
- Each shows count with `tabular-nums` for stable width
- Elapsed time card with live clock (`setInterval` 1s)
- Small SVG progress ring: `completed / total` animated via `stroke-dashoffset`

### Wave Timeline (SVG)
- Y-axis: stories grouped by wave, wave labels on left
- X-axis: time, auto-scaling from run start to now
- Bar states:
  - Pending: gray-600, dashed outline
  - Running: blue-500 + CSS shimmer animation
  - Completed: green-500
  - Failed: red-500 + retry stripe if retried
  - Skipped: yellow-600/60
- Wave separators: horizontal lines between groups
- Story labels at left, duration labels at right of completed bars
- Running bars grow reactively (recalc every 2s)
- Hover tooltip: story ID, status, duration, wave, attempts

### Agent Activity Panel
- Vertical feed, max ~20 entries, newest first
- Colored dot per agent type + badge + story ID + status + duration
- Active agents: CSS pulse animation on dot
- Agent colors: implementer=blue, validator=cyan, reviewer=purple, merger=yellow
- Auto-scroll to top on new entry (pause if user scrolled)

### Error & Retry Panel
- Hidden when no errors (collapses to "No errors" line)
- Each error: red left border, story ID, category badge, retry status
- Category colors: env_missing=yellow, test_failure=red, timeout=purple, code_error=orange, dependency_missing=cyan
- New errors: fade-in + subtle shake animation

## Visual Design

- Glass cards: `bg-surface-1/80 backdrop-blur-sm border border-white/5 rounded-lg`
- Dark palette (existing): surface-0 through surface-3, accent colors
- Status transitions: 300ms color + width CSS transitions
- Running shimmer: `@keyframes shimmer` moving gradient
- Pulse dots: `@keyframes pulse` on active agents
- Font: system stack, `tabular-nums` for counters
- Generous whitespace, clean hierarchy

## Server Fixes

1. No server endpoint changes needed — routes are correct
2. Optionally add `stories` array to `getErrorBreakdown()` or simplify client
3. All fixes are client-side path corrections and type alignment

## Client Fixes

1. `useWebSocket.ts`: unwrap `msg.event` from envelope before storing
2. `useApi.ts`: correct all route paths to match server
3. `types.ts`: align with server response shapes
4. `AgentInsights` → merged into dashboard: use `seconds` not `ms`
5. Remove 4-tab routing, replace with single `Dashboard.vue`

## Files Changed

### Server (minor)
- `server/analytics.ts` — optionally add `stories` to error breakdown

### Client (rewrite)
- `client/src/App.vue` — remove tab nav, render single Dashboard
- `client/src/views/Dashboard.vue` — new single-page layout
- `client/src/views/Timeline.vue` — delete
- `client/src/views/StoryGantt.vue` — delete (merged into Dashboard)
- `client/src/views/ErrorPatterns.vue` — delete (merged into Dashboard)
- `client/src/views/AgentInsights.vue` — delete (merged into Dashboard)
- `client/src/components/SummaryBar.vue` — new
- `client/src/components/WaveTimeline.vue` — new (SVG Gantt)
- `client/src/components/AgentFeed.vue` — new
- `client/src/components/ErrorPanel.vue` — new
- `client/src/components/ProgressRing.vue` — new (small SVG component)
- `client/src/components/EventRow.vue` — keep (used in AgentFeed)
- `client/src/components/FilterBar.vue` — simplify (run selector only)
- `client/src/components/StoryCard.vue` — keep (tooltip)
- `client/src/components/WaveProgress.vue` — delete (merged into WaveTimeline)
- `client/src/composables/useWebSocket.ts` — fix envelope unwrapping
- `client/src/composables/useApi.ts` — fix all route paths
- `client/src/composables/useFilters.ts` — simplify (run filter only)
- `client/src/types.ts` — align with server types

## Constraints

- No new npm dependencies
- CSS animations only (no JS animation loops)
- SVG for Gantt (no Canvas, no D3)
- Must work alongside live TaskPlex execution without resource contention
- Bun serves built static files — negligible overhead
