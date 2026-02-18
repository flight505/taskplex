# Monitor Dashboard Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 6 critical bugs preventing data flow, then rebuild the Vue 3 client as a single-page real-time dashboard with SVG wave Gantt visualization.

**Architecture:** Fix composables (WebSocket envelope, API routes, types), then replace 4-tab layout with single Dashboard.vue rendering SummaryBar, WaveTimeline (SVG), AgentFeed, and ErrorPanel. No new dependencies — pure Vue 3 + Tailwind + SVG.

**Tech Stack:** Vue 3.5, Tailwind CSS 3.4, Vite 6, Bun server (unchanged), SQLite (unchanged)

**Design doc:** `docs/plans/2026-02-18-monitor-dashboard-redesign.md`

---

### Task 1: Fix types.ts — align client types with server responses

Everything downstream depends on correct types. The current `types.ts` has 5 mismatches with the server.

**Files:**
- Modify: `monitor/client/src/types.ts`

**Step 1: Rewrite types.ts**

Replace entire file contents with types that match the server's actual response shapes:

```typescript
// MonitorEvent — server returns id as INTEGER, payload as JSON object
export interface MonitorEvent {
  id: number;
  timestamp: string;
  source: "hook" | "orchestrator" | "parallel";
  event_type: string;
  session_id?: string;
  run_id?: string;
  story_id?: string;
  wave: number | null;
  batch: number | null;
  payload: Record<string, any>;
}

// Run — server returns config as JSON string, model/branch can be null
export interface Run {
  id: string;
  started_at: string;
  ended_at: string | null;
  mode: string;
  model: string | null;
  branch: string | null;
  total_stories: number | null;
  completed: number;
  skipped: number;
  config: string; // JSON string from SQLite
}

// StoryTimelineEntry — from GET /api/analytics/timeline/:runId
export interface StoryTimelineEntry {
  story_id: string;
  started_at: string;
  ended_at: string | null;
  status: "completed" | "skipped" | "blocked" | "running" | "failed";
  attempts: number;
  wave: number | null;
  batch: number | null;
}

// ErrorBreakdown — from GET /api/analytics/errors
// Server returns {category, count} only — no stories array
export interface ErrorBreakdown {
  category: string;
  count: number;
}

// ToolUsageEntry — from GET /api/analytics/tools
export interface ToolUsageEntry {
  tool_name: string;
  agent_type: string;
  count: number;
}

// RunSummary — from GET /api/analytics/summary/:runId
export interface RunSummary {
  run_id: string;
  mode: string;
  model: string | null;
  branch: string | null;
  started_at: string;
  ended_at: string | null;
  elapsed_seconds: number | null;
  total_stories: number;
  completed: number;
  skipped: number;
  blocked: number;
  failed: number;
  error_rate: number;
}

// AgentDuration — from GET /api/analytics/agents
// Server returns *_seconds and invocations, NOT *_ms and count
export interface AgentDuration {
  agent_type: string;
  avg_duration_seconds: number;
  min_duration_seconds: number;
  max_duration_seconds: number;
  invocations: number;
}

// WebSocket message envelope — server broadcasts these wrappers
export type WsMessage =
  | { type: "event"; event: MonitorEvent }
  | { type: "run.created"; run: Run }
  | { type: "run.updated"; run: Run };
```

**Step 2: Verify build**

Run: `cd monitor/client && npx vite build 2>&1 | head -20`
Expected: Type errors in files that reference old field names (this is fine — we fix those in subsequent tasks)

**Step 3: Commit**

```bash
git add monitor/client/src/types.ts
git commit -m "fix(monitor): align client types with server response shapes"
```

---

### Task 2: Fix useWebSocket.ts — unwrap message envelope

The server broadcasts `{ type: "event", event: {...} }` but the client stores the entire wrapper. This causes every field access (`event_type`, `timestamp`, `story_id`) to return `undefined` — the root cause of "NaN ago" in the Timeline.

**Files:**
- Modify: `monitor/client/src/composables/useWebSocket.ts`

**Step 1: Fix the onmessage handler to unwrap the envelope**

Replace the `ws.onmessage` handler (lines 46-53) with code that handles all three message types:

```typescript
    ws.onmessage = (msgEvent: MessageEvent) => {
      try {
        const msg: WsMessage = JSON.parse(msgEvent.data);

        if (msg.type === "event") {
          events.value = [msg.event, ...events.value].slice(0, MAX_EVENTS);
        } else if (msg.type === "run.created") {
          latestRun.value = msg.run;
        } else if (msg.type === "run.updated") {
          latestRun.value = msg.run;
        }
      } catch {
        // ignore malformed messages
      }
    };
```

Also add the `WsMessage` import and export a `latestRun` ref:

At the top of the file, change the import:
```typescript
import type { MonitorEvent, WsMessage, Run } from "@/types";
```

Inside the function, after `const connected = ref(false);`, add:
```typescript
  const latestRun = ref<Run | null>(null);
```

Update the `UseWebSocketReturn` interface:
```typescript
interface UseWebSocketReturn {
  events: Ref<MonitorEvent[]>;
  connected: Ref<boolean>;
  latestRun: Ref<Run | null>;
  clear: () => void;
}
```

Update the return:
```typescript
  return { events, connected, latestRun, clear };
```

**Step 2: Commit**

```bash
git add monitor/client/src/composables/useWebSocket.ts
git commit -m "fix(monitor): unwrap WebSocket message envelope before storing events"
```

---

### Task 3: Fix useApi.ts — correct all API route paths

The client constructs wrong paths like `/runs/:id/timeline` but the server expects `/api/analytics/timeline/:id`. The `get()` helper already prepends `/api` to paths, so we just need correct relative paths.

**Files:**
- Modify: `monitor/client/src/composables/useApi.ts`

**Step 1: Rewrite useApi.ts with correct routes**

Replace entire file:

```typescript
import type {
  Run,
  MonitorEvent,
  StoryTimelineEntry,
  ErrorBreakdown,
  ToolUsageEntry,
  RunSummary,
  AgentDuration,
} from "@/types";

const BASE = "/api";

async function get<T>(path: string, params?: Record<string, string>): Promise<T> {
  const url = new URL(`${BASE}${path}`, window.location.origin);
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      if (v) url.searchParams.set(k, v);
    }
  }
  const res = await fetch(url.toString());
  if (!res.ok) {
    throw new Error(`API error: ${res.status} ${res.statusText}`);
  }
  return res.json() as Promise<T>;
}

export function useApi() {
  // GET /api/runs
  async function fetchRuns(): Promise<Run[]> {
    return get<Run[]>("/runs");
  }

  // GET /api/events?run_id=&story_id=&event_type=&limit=
  async function fetchEvents(filters?: {
    run_id?: string;
    story_id?: string;
    event_type?: string;
    limit?: number;
  }): Promise<MonitorEvent[]> {
    const params: Record<string, string> = {};
    if (filters?.run_id) params.run_id = filters.run_id;
    if (filters?.story_id) params.story_id = filters.story_id;
    if (filters?.event_type) params.event_type = filters.event_type;
    if (filters?.limit) params.limit = String(filters.limit);
    return get<MonitorEvent[]>("/events", params);
  }

  // GET /api/analytics/timeline/:runId
  async function fetchTimeline(runId: string): Promise<StoryTimelineEntry[]> {
    return get<StoryTimelineEntry[]>(`/analytics/timeline/${runId}`);
  }

  // GET /api/analytics/errors?run_id=
  async function fetchErrors(runId?: string): Promise<ErrorBreakdown[]> {
    const params: Record<string, string> = {};
    if (runId) params.run_id = runId;
    return get<ErrorBreakdown[]>("/analytics/errors", params);
  }

  // GET /api/analytics/tools?run_id=
  async function fetchTools(runId?: string): Promise<ToolUsageEntry[]> {
    const params: Record<string, string> = {};
    if (runId) params.run_id = runId;
    return get<ToolUsageEntry[]>("/analytics/tools", params);
  }

  // GET /api/analytics/summary/:runId
  async function fetchSummary(runId: string): Promise<RunSummary> {
    return get<RunSummary>(`/analytics/summary/${runId}`);
  }

  // GET /api/analytics/agents?run_id=
  async function fetchAgents(runId?: string): Promise<AgentDuration[]> {
    const params: Record<string, string> = {};
    if (runId) params.run_id = runId;
    return get<AgentDuration[]>("/analytics/agents", params);
  }

  return {
    fetchRuns,
    fetchEvents,
    fetchTimeline,
    fetchErrors,
    fetchTools,
    fetchSummary,
    fetchAgents,
  };
}
```

**Step 2: Commit**

```bash
git add monitor/client/src/composables/useApi.ts
git commit -m "fix(monitor): correct API route paths to match server endpoints"
```

---

### Task 4: Add CSS animations and glass utilities to style.css

Add the keyframe animations and utility classes we need for the dashboard visuals. This is pure CSS — no JS, GPU-accelerated.

**Files:**
- Modify: `monitor/client/src/style.css`

**Step 1: Add animations after the existing scrollbar styles**

Append to `style.css` after the existing `@layer base` block:

```css
@layer components {
  /* Glass card base */
  .glass-card {
    @apply bg-surface-1/80 backdrop-blur-sm border border-white/5 rounded-lg;
  }

  /* Stat card */
  .stat-card {
    @apply glass-card px-4 py-3 flex flex-col items-center justify-center min-w-0;
  }
}

@layer utilities {
  .tabular-nums {
    font-variant-numeric: tabular-nums;
  }
}

/* Shimmer animation for running bars */
@keyframes shimmer {
  0% { background-position: -200% 0; }
  100% { background-position: 200% 0; }
}

.bar-running {
  background: linear-gradient(
    90deg,
    #3b82f6 0%,
    #60a5fa 40%,
    #3b82f6 60%,
    #3b82f6 100%
  );
  background-size: 200% 100%;
  animation: shimmer 2s ease-in-out infinite;
}

/* Pulse animation for active agent dots */
@keyframes pulse-dot {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.5; transform: scale(1.5); }
}

.pulse-active {
  animation: pulse-dot 2s ease-in-out infinite;
}

/* Fade-in for new items */
@keyframes fade-in {
  from { opacity: 0; transform: translateY(-4px); }
  to { opacity: 1; transform: translateY(0); }
}

.animate-fade-in {
  animation: fade-in 300ms ease-out;
}

/* Progress ring animation */
@keyframes ring-fill {
  from { stroke-dashoffset: var(--ring-circumference); }
}

.progress-ring-circle {
  transition: stroke-dashoffset 500ms ease-out;
}
```

**Step 2: Commit**

```bash
git add monitor/client/src/style.css
git commit -m "feat(monitor): add glass-card, shimmer, pulse, fade-in CSS animations"
```

---

### Task 5: Create ProgressRing.vue — small SVG progress indicator

A simple reusable SVG donut ring component.

**Files:**
- Create: `monitor/client/src/components/ProgressRing.vue`

**Step 1: Write the component**

```vue
<script setup lang="ts">
import { computed } from "vue";

const props = withDefaults(defineProps<{
  value: number;    // 0-1
  size?: number;    // px
  stroke?: number;  // px
  color?: string;   // tailwind accent color hex
}>(), {
  size: 40,
  stroke: 3,
  color: "#22c55e",
});

const radius = computed(() => (props.size - props.stroke) / 2);
const circumference = computed(() => 2 * Math.PI * radius.value);
const offset = computed(() => circumference.value * (1 - Math.min(1, Math.max(0, props.value))));
const center = computed(() => props.size / 2);
</script>

<template>
  <svg
    :width="size"
    :height="size"
    class="transform -rotate-90"
  >
    <!-- Background circle -->
    <circle
      :cx="center"
      :cy="center"
      :r="radius"
      fill="none"
      stroke="#242430"
      :stroke-width="stroke"
    />
    <!-- Progress arc -->
    <circle
      :cx="center"
      :cy="center"
      :r="radius"
      fill="none"
      :stroke="color"
      :stroke-width="stroke"
      stroke-linecap="round"
      :stroke-dasharray="circumference"
      :stroke-dashoffset="offset"
      class="progress-ring-circle"
    />
    <!-- Center text -->
    <text
      :x="center"
      :y="center"
      text-anchor="middle"
      dominant-baseline="central"
      class="transform rotate-90 origin-center fill-gray-200 text-[10px] font-medium"
      :style="{ fontSize: `${size * 0.25}px` }"
    >
      {{ Math.round(value * 100) }}%
    </text>
  </svg>
</template>
```

**Step 2: Commit**

```bash
git add monitor/client/src/components/ProgressRing.vue
git commit -m "feat(monitor): add ProgressRing SVG component"
```

---

### Task 6: Create SummaryBar.vue — stat cards + elapsed time + progress ring

Displays run summary: completed/running/failed/skipped counts, elapsed time, and progress ring.

**Files:**
- Create: `monitor/client/src/components/SummaryBar.vue`

**Step 1: Write the component**

```vue
<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from "vue";
import type { RunSummary, StoryTimelineEntry } from "@/types";
import ProgressRing from "./ProgressRing.vue";

const props = defineProps<{
  summary: RunSummary | null;
  stories: StoryTimelineEntry[];
}>();

// Live elapsed time
const now = ref(Date.now());
let timer: ReturnType<typeof setInterval> | null = null;
onMounted(() => { timer = setInterval(() => { now.value = Date.now(); }, 1000); });
onUnmounted(() => { if (timer) clearInterval(timer); });

const elapsed = computed(() => {
  if (!props.summary?.started_at) return "--:--";
  const start = new Date(props.summary.started_at).getTime();
  const end = props.summary.ended_at
    ? new Date(props.summary.ended_at).getTime()
    : now.value;
  const secs = Math.max(0, Math.floor((end - start) / 1000));
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}m ${String(s).padStart(2, "0")}s`;
});

const running = computed(() => props.stories.filter(s => s.status === "running").length);
const completed = computed(() => props.summary?.completed ?? 0);
const failed = computed(() => props.summary?.failed ?? 0);
const skipped = computed(() => props.summary?.skipped ?? 0);
const total = computed(() => props.summary?.total_stories ?? 0);
const progress = computed(() => total.value > 0 ? completed.value / total.value : 0);
const mode = computed(() => props.summary?.mode ?? "sequential");
const model = computed(() => props.summary?.model ?? "—");

const stats = computed(() => [
  { label: "Completed", value: completed.value, color: "text-accent-green", bg: "bg-accent-green/10", border: "border-accent-green/20" },
  { label: "Running", value: running.value, color: "text-accent-blue", bg: "bg-accent-blue/10", border: "border-accent-blue/20", pulse: true },
  { label: "Failed", value: failed.value, color: "text-accent-red", bg: "bg-accent-red/10", border: "border-accent-red/20" },
  { label: "Skipped", value: skipped.value, color: "text-accent-yellow", bg: "bg-accent-yellow/10", border: "border-accent-yellow/20" },
]);
</script>

<template>
  <div class="flex items-stretch gap-3">
    <!-- Stat cards -->
    <div
      v-for="stat in stats"
      :key="stat.label"
      class="stat-card border"
      :class="[stat.bg, stat.border]"
    >
      <span
        class="text-2xl font-bold tabular-nums leading-none"
        :class="[stat.color, { 'pulse-active': stat.pulse && stat.value > 0 }]"
      >
        {{ stat.value }}
      </span>
      <span class="text-[10px] text-gray-400 mt-1 uppercase tracking-wider">{{ stat.label }}</span>
    </div>

    <!-- Progress ring + elapsed -->
    <div class="stat-card border border-white/5 flex-row gap-3 px-5">
      <ProgressRing :value="progress" :size="44" :stroke="3" />
      <div class="flex flex-col items-start">
        <span class="text-lg font-bold tabular-nums text-gray-100 leading-none">{{ elapsed }}</span>
        <span class="text-[10px] text-gray-400 mt-1">
          {{ total }} stories &middot; {{ mode }} &middot; {{ model }}
        </span>
      </div>
    </div>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add monitor/client/src/components/SummaryBar.vue
git commit -m "feat(monitor): add SummaryBar with stat cards and progress ring"
```

---

### Task 7: Create WaveTimeline.vue — SVG Gantt hero visualization

The main visual centerpiece. Stories as horizontal bars grouped by wave, color-coded by status, with running bars that grow in real-time.

**Files:**
- Create: `monitor/client/src/components/WaveTimeline.vue`

**Step 1: Write the component**

```vue
<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from "vue";
import type { StoryTimelineEntry } from "@/types";

const props = defineProps<{
  stories: StoryTimelineEntry[];
  runStartedAt: string | null;
}>();

const ROW_HEIGHT = 32;
const LABEL_WIDTH = 180;
const WAVE_GAP = 12;
const PAD_RIGHT = 80;

const now = ref(Date.now());
let timer: ReturnType<typeof setInterval> | null = null;
onMounted(() => { timer = setInterval(() => { now.value = Date.now(); }, 2000); });
onUnmounted(() => { if (timer) clearInterval(timer); });

const hoveredStory = ref<string | null>(null);
const hoverPos = ref({ x: 0, y: 0 });

// Group stories by wave
const waveGroups = computed(() => {
  const groups = new Map<number, StoryTimelineEntry[]>();
  for (const s of props.stories) {
    const w = s.wave ?? 0;
    if (!groups.has(w)) groups.set(w, []);
    groups.get(w)!.push(s);
  }
  return Array.from(groups.entries()).sort((a, b) => a[0] - b[0]);
});

// Time range
const timeRange = computed(() => {
  const start = props.runStartedAt
    ? new Date(props.runStartedAt).getTime()
    : Math.min(...props.stories.filter(s => s.started_at).map(s => new Date(s.started_at).getTime()));
  const ends = props.stories
    .filter(s => s.ended_at)
    .map(s => new Date(s.ended_at!).getTime());
  const maxEnd = ends.length > 0 ? Math.max(...ends) : now.value;
  const end = Math.max(maxEnd, now.value);
  const duration = end - start || 1;
  return { start, end, duration };
});

// Total SVG height
const totalHeight = computed(() => {
  let rows = 0;
  for (const [, stories] of waveGroups.value) {
    rows += stories.length;
  }
  return rows * ROW_HEIGHT + waveGroups.value.length * WAVE_GAP + 20;
});

// Status colors
function barColor(status: string): string {
  switch (status) {
    case "completed": return "#22c55e";
    case "failed": return "#ef4444";
    case "running": return "#3b82f6";
    case "skipped": return "#eab308";
    case "blocked": return "#a855f7";
    default: return "#4b5563";
  }
}

function barOpacity(status: string): number {
  return status === "skipped" ? 0.5 : 1;
}

// Compute bar geometry
interface BarData {
  story: StoryTimelineEntry;
  x: number;
  width: number;
  y: number;
  color: string;
  opacity: number;
  isRunning: boolean;
  duration: string;
  waveLabel: string | null;
}

const bars = computed<BarData[]>(() => {
  const result: BarData[] = [];
  let rowIndex = 0;
  const { start, duration } = timeRange.value;
  const chartWidth = 800; // We'll use viewBox, not pixels

  for (const [waveNum, stories] of waveGroups.value) {
    const yOffset = rowIndex * ROW_HEIGHT + result.filter(b => b.waveLabel).length * 0 + waveGroups.value.indexOf(waveGroups.value.find(([w]) => w === waveNum)!) * WAVE_GAP;

    for (let i = 0; i < stories.length; i++) {
      const s = stories[i];
      const sStart = s.started_at ? new Date(s.started_at).getTime() : 0;
      const sEnd = s.ended_at ? new Date(s.ended_at).getTime() : (s.status === "running" ? now.value : sStart);

      const x = sStart ? ((sStart - start) / duration) * chartWidth : 0;
      const w = sStart ? (((sEnd - sStart) || 1) / duration) * chartWidth : 0;

      const secs = Math.max(0, Math.floor(((sEnd || now.value) - (sStart || now.value)) / 1000));
      const durationStr = secs < 60 ? `${secs}s` : `${Math.floor(secs / 60)}m ${secs % 60}s`;

      result.push({
        story: s,
        x: LABEL_WIDTH + x,
        width: Math.max(w, 2),
        y: rowIndex * ROW_HEIGHT + waveGroups.value.findIndex(([w2]) => w2 === waveNum) * WAVE_GAP + 4,
        color: barColor(s.status),
        opacity: barOpacity(s.status),
        isRunning: s.status === "running",
        duration: s.status !== "running" && sStart ? durationStr : "",
        waveLabel: i === 0 ? `Wave ${waveNum}` : null,
      });
      rowIndex++;
    }
  }
  return result;
});

// Wave separator Y positions
const waveSeparators = computed(() => {
  const seps: number[] = [];
  let rowIndex = 0;
  for (let i = 0; i < waveGroups.value.length; i++) {
    if (i > 0) {
      seps.push(rowIndex * ROW_HEIGHT + i * WAVE_GAP - WAVE_GAP / 2);
    }
    rowIndex += waveGroups.value[i][1].length;
  }
  return seps;
});

const viewBoxWidth = computed(() => LABEL_WIDTH + 800 + PAD_RIGHT);

function onBarHover(storyId: string, event: MouseEvent) {
  hoveredStory.value = storyId;
  hoverPos.value = { x: event.clientX, y: event.clientY };
}

function onBarLeave() {
  hoveredStory.value = null;
}

const hoveredData = computed(() => {
  if (!hoveredStory.value) return null;
  return props.stories.find(s => s.story_id === hoveredStory.value) ?? null;
});

function formatDuration(s: StoryTimelineEntry): string {
  if (!s.started_at) return "—";
  const start = new Date(s.started_at).getTime();
  const end = s.ended_at ? new Date(s.ended_at).getTime() : now.value;
  const secs = Math.max(0, Math.floor((end - start) / 1000));
  return secs < 60 ? `${secs}s` : `${Math.floor(secs / 60)}m ${secs % 60}s`;
}
</script>

<template>
  <div class="glass-card p-4 relative overflow-hidden">
    <h2 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">Wave Timeline</h2>

    <div v-if="stories.length === 0" class="text-sm text-gray-500 py-8 text-center">
      No stories yet — waiting for run data...
    </div>

    <div v-else class="overflow-x-auto overflow-y-auto max-h-[50vh]">
      <svg
        :viewBox="`0 0 ${viewBoxWidth} ${totalHeight}`"
        :width="'100%'"
        :height="totalHeight"
        class="min-w-[600px]"
      >
        <!-- Wave separators -->
        <line
          v-for="(sepY, i) in waveSeparators"
          :key="'sep-' + i"
          :x1="0"
          :y1="sepY"
          :x2="viewBoxWidth"
          :y2="sepY"
          stroke="#242430"
          stroke-width="1"
          stroke-dasharray="4 4"
        />

        <!-- Bars + labels -->
        <g v-for="bar in bars" :key="bar.story.story_id">
          <!-- Wave label -->
          <text
            v-if="bar.waveLabel"
            :x="4"
            :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="fill-accent-cyan text-[10px] font-semibold"
            dominant-baseline="middle"
          >
            {{ bar.waveLabel }}
          </text>

          <!-- Story label -->
          <text
            :x="60"
            :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="fill-gray-300 text-[11px] font-mono"
            dominant-baseline="middle"
          >
            {{ bar.story.story_id.length > 16 ? bar.story.story_id.slice(0, 16) + '...' : bar.story.story_id }}
          </text>

          <!-- Status icon -->
          <text
            :x="LABEL_WIDTH - 16"
            :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="text-[11px]"
            :class="{
              'fill-accent-green': bar.story.status === 'completed',
              'fill-accent-red': bar.story.status === 'failed',
              'fill-accent-blue': bar.story.status === 'running',
              'fill-accent-yellow': bar.story.status === 'skipped',
              'fill-gray-500': bar.story.status === 'blocked',
            }"
            dominant-baseline="middle"
            text-anchor="end"
          >
            {{ bar.story.status === 'completed' ? '✓' : bar.story.status === 'failed' ? '✗' : bar.story.status === 'running' ? '⟳' : bar.story.status === 'skipped' ? '⏭' : '○' }}
          </text>

          <!-- Bar background (pending placeholder) -->
          <rect
            v-if="!bar.story.started_at"
            :x="LABEL_WIDTH"
            :y="bar.y + 4"
            :width="100"
            :height="ROW_HEIGHT - 12"
            rx="3"
            fill="none"
            stroke="#4b5563"
            stroke-width="1"
            stroke-dasharray="4 2"
          />

          <!-- Bar -->
          <rect
            v-else
            :x="bar.x"
            :y="bar.y + 4"
            :width="bar.width"
            :height="ROW_HEIGHT - 12"
            rx="3"
            :fill="bar.color"
            :opacity="bar.opacity"
            :class="{ 'bar-running': bar.isRunning }"
            class="transition-all duration-500"
            @mouseenter="onBarHover(bar.story.story_id, $event)"
            @mouseleave="onBarLeave"
          />

          <!-- Retry stripe overlay -->
          <rect
            v-if="bar.story.attempts > 1 && bar.story.started_at"
            :x="bar.x"
            :y="bar.y + 4"
            :width="bar.width"
            :height="ROW_HEIGHT - 12"
            rx="3"
            fill="url(#stripe-pattern)"
            opacity="0.3"
          />

          <!-- Duration label -->
          <text
            v-if="bar.duration"
            :x="bar.x + bar.width + 6"
            :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="fill-gray-500 text-[9px] font-mono"
            dominant-baseline="middle"
          >
            {{ bar.duration }}
          </text>
        </g>

        <!-- Stripe pattern for retries -->
        <defs>
          <pattern id="stripe-pattern" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <line x1="0" y1="0" x2="0" y2="6" stroke="white" stroke-width="2" />
          </pattern>
        </defs>
      </svg>
    </div>

    <!-- Hover tooltip -->
    <Teleport to="body">
      <div
        v-if="hoveredData"
        class="fixed z-50 pointer-events-none"
        :style="{ left: hoverPos.x + 12 + 'px', top: hoverPos.y - 10 + 'px' }"
      >
        <div class="glass-card bg-surface-2 p-3 shadow-xl border border-surface-3 text-xs space-y-1 min-w-[160px]">
          <div class="font-mono text-gray-100 font-semibold">{{ hoveredData.story_id }}</div>
          <div class="flex items-center gap-2">
            <span class="w-2 h-2 rounded-full" :style="{ backgroundColor: barColor(hoveredData.status) }" />
            <span class="text-gray-300 capitalize">{{ hoveredData.status }}</span>
          </div>
          <div class="text-gray-400">Duration: {{ formatDuration(hoveredData) }}</div>
          <div v-if="hoveredData.wave !== null" class="text-accent-cyan">Wave {{ hoveredData.wave }}</div>
          <div v-if="hoveredData.attempts > 1" class="text-accent-yellow">{{ hoveredData.attempts }} attempts</div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add monitor/client/src/components/WaveTimeline.vue
git commit -m "feat(monitor): add WaveTimeline SVG Gantt visualization"
```

---

### Task 8: Create AgentFeed.vue — live agent activity panel

Shows recent agent events (subagent start/stop) as a live feed, newest first.

**Files:**
- Create: `monitor/client/src/components/AgentFeed.vue`

**Step 1: Write the component**

```vue
<script setup lang="ts">
import { computed } from "vue";
import type { MonitorEvent } from "@/types";

const props = defineProps<{
  events: MonitorEvent[];
}>();

const AGENT_COLORS: Record<string, string> = {
  implementer: "bg-accent-blue",
  validator: "bg-accent-cyan",
  reviewer: "bg-accent-purple",
  merger: "bg-accent-yellow",
};

const AGENT_TEXT_COLORS: Record<string, string> = {
  implementer: "text-accent-blue",
  validator: "text-accent-cyan",
  reviewer: "text-accent-purple",
  merger: "text-accent-yellow",
};

interface AgentEntry {
  id: number;
  agentType: string;
  storyId: string;
  eventType: string;
  isActive: boolean;
  timestamp: string;
  duration: string;
}

const agentEvents = computed<AgentEntry[]>(() => {
  return props.events
    .filter(e => e.event_type === "subagent.start" || e.event_type === "subagent.end" || e.event_type === "subagent.stop")
    .slice(0, 20)
    .map(e => {
      const agentType = e.payload?.agent_type ?? e.payload?.agent_name ?? "unknown";
      const isStart = e.event_type === "subagent.start";
      const durationSecs = e.payload?.duration_seconds;
      let duration = "";
      if (durationSecs) {
        duration = durationSecs < 60 ? `${Math.round(durationSecs)}s` : `${Math.floor(durationSecs / 60)}m ${Math.round(durationSecs % 60)}s`;
      }
      return {
        id: e.id,
        agentType,
        storyId: e.story_id ?? "—",
        eventType: isStart ? "started" : "completed",
        isActive: isStart,
        timestamp: e.timestamp,
        duration,
      };
    });
});

function relativeTime(ts: string): string {
  const diff = Math.max(0, Math.floor((Date.now() - new Date(ts).getTime()) / 1000));
  if (diff < 5) return "just now";
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
}
</script>

<template>
  <div class="glass-card p-4 h-full flex flex-col">
    <h2 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">Agent Activity</h2>

    <div v-if="agentEvents.length === 0" class="text-sm text-gray-500 py-4 text-center flex-1 flex items-center justify-center">
      No agent activity yet
    </div>

    <div v-else class="space-y-1 overflow-y-auto flex-1">
      <div
        v-for="entry in agentEvents"
        :key="entry.id"
        class="flex items-center gap-2 px-2 py-1.5 rounded hover:bg-surface-2/50 transition-colors animate-fade-in"
      >
        <!-- Status dot -->
        <span
          class="w-2 h-2 rounded-full shrink-0"
          :class="[AGENT_COLORS[entry.agentType] || 'bg-gray-500', { 'pulse-active': entry.isActive }]"
        />

        <!-- Agent type -->
        <span
          class="text-[10px] font-medium shrink-0"
          :class="AGENT_TEXT_COLORS[entry.agentType] || 'text-gray-400'"
        >
          {{ entry.agentType }}
        </span>

        <!-- Story ID -->
        <span class="text-[10px] font-mono text-gray-400 truncate min-w-0">
          {{ entry.storyId }}
        </span>

        <!-- Status + duration -->
        <span class="text-[10px] text-gray-500 ml-auto shrink-0">
          <span v-if="entry.isActive" class="text-accent-blue">running</span>
          <span v-else class="text-accent-green">{{ entry.duration || 'done' }}</span>
        </span>

        <!-- Time -->
        <span class="text-[9px] text-gray-600 font-mono shrink-0 w-12 text-right">
          {{ relativeTime(entry.timestamp) }}
        </span>
      </div>
    </div>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add monitor/client/src/components/AgentFeed.vue
git commit -m "feat(monitor): add AgentFeed live activity panel"
```

---

### Task 9: Create ErrorPanel.vue — error & retry status panel

Shows failures with error categories and retry status. Collapses when empty.

**Files:**
- Create: `monitor/client/src/components/ErrorPanel.vue`

**Step 1: Write the component**

```vue
<script setup lang="ts">
import { computed } from "vue";
import type { MonitorEvent } from "@/types";

const props = defineProps<{
  events: MonitorEvent[];
}>();

const CATEGORY_COLORS: Record<string, string> = {
  env_missing: "bg-accent-yellow/20 text-accent-yellow",
  test_failure: "bg-accent-red/20 text-accent-red",
  timeout: "bg-accent-purple/20 text-accent-purple",
  code_error: "bg-orange-500/20 text-orange-400",
  dependency_missing: "bg-accent-cyan/20 text-accent-cyan",
  unknown: "bg-gray-600/20 text-gray-400",
};

interface ErrorEntry {
  id: number;
  storyId: string;
  category: string;
  retryCount: number;
  maxRetries: number;
  timestamp: string;
  message: string;
}

const errors = computed<ErrorEntry[]>(() => {
  return props.events
    .filter(e => e.event_type === "story.fail" || e.event_type === "error.categorized")
    .slice(0, 20)
    .map(e => ({
      id: e.id,
      storyId: e.story_id ?? "—",
      category: e.payload?.category ?? "unknown",
      retryCount: e.payload?.retry_count ?? 0,
      maxRetries: e.payload?.max_retries ?? 2,
      timestamp: e.timestamp,
      message: e.payload?.message ?? e.payload?.error ?? "",
    }));
});

function relativeTime(ts: string): string {
  const diff = Math.max(0, Math.floor((Date.now() - new Date(ts).getTime()) / 1000));
  if (diff < 5) return "just now";
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  return `${Math.floor(diff / 3600)}h ago`;
}
</script>

<template>
  <div class="glass-card p-4 h-full flex flex-col">
    <h2 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">Errors & Retries</h2>

    <div v-if="errors.length === 0" class="text-sm text-gray-500 py-4 text-center flex-1 flex items-center justify-center">
      No errors
    </div>

    <div v-else class="space-y-1 overflow-y-auto flex-1">
      <div
        v-for="err in errors"
        :key="err.id"
        class="border-l-2 border-accent-red/50 pl-3 pr-2 py-1.5 rounded-r hover:bg-surface-2/50 transition-colors animate-fade-in"
      >
        <div class="flex items-center gap-2">
          <!-- Story ID -->
          <span class="text-[11px] font-mono text-gray-300">{{ err.storyId }}</span>

          <!-- Category badge -->
          <span
            class="text-[9px] font-medium px-1.5 py-0.5 rounded-full shrink-0"
            :class="CATEGORY_COLORS[err.category] || CATEGORY_COLORS.unknown"
          >
            {{ err.category }}
          </span>

          <!-- Retry status -->
          <span class="text-[9px] text-gray-500 ml-auto shrink-0">
            <span v-if="err.retryCount < err.maxRetries" class="text-accent-yellow">
              Retry {{ err.retryCount + 1 }}/{{ err.maxRetries }}
            </span>
            <span v-else class="text-accent-red">
              Skipped
            </span>
          </span>

          <!-- Time -->
          <span class="text-[9px] text-gray-600 font-mono shrink-0">
            {{ relativeTime(err.timestamp) }}
          </span>
        </div>

        <!-- Error message (truncated) -->
        <div v-if="err.message" class="text-[9px] text-gray-500 mt-0.5 truncate">
          {{ err.message }}
        </div>
      </div>
    </div>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add monitor/client/src/components/ErrorPanel.vue
git commit -m "feat(monitor): add ErrorPanel with category badges and retry status"
```

---

### Task 10: Rewrite App.vue — single-page dashboard layout

Replace the 4-tab layout with a single Dashboard that composes all panels.

**Files:**
- Modify: `monitor/client/src/App.vue`

**Step 1: Rewrite App.vue**

Replace entire file:

```vue
<script setup lang="ts">
import { ref, computed, onMounted, watch } from "vue";
import { useWebSocket } from "@/composables/useWebSocket";
import { useApi } from "@/composables/useApi";
import type { Run, RunSummary, StoryTimelineEntry } from "@/types";
import SummaryBar from "@/components/SummaryBar.vue";
import WaveTimeline from "@/components/WaveTimeline.vue";
import AgentFeed from "@/components/AgentFeed.vue";
import ErrorPanel from "@/components/ErrorPanel.vue";

const { events, connected, latestRun } = useWebSocket();
const { fetchRuns, fetchTimeline, fetchSummary } = useApi();

const selectedRunId = ref("");
const runs = ref<Run[]>([]);
const summary = ref<RunSummary | null>(null);
const stories = ref<StoryTimelineEntry[]>([]);

async function loadRuns() {
  try {
    runs.value = await fetchRuns();
    if (runs.value.length > 0 && !selectedRunId.value) {
      selectedRunId.value = runs.value[0].id;
    }
  } catch {
    // API may not be available yet
  }
}

async function loadRunData(runId: string) {
  if (!runId) {
    summary.value = null;
    stories.value = [];
    return;
  }
  try {
    const [s, t] = await Promise.all([
      fetchSummary(runId),
      fetchTimeline(runId),
    ]);
    summary.value = s;
    stories.value = t;
  } catch {
    // Run may not exist yet
  }
}

// Reload data when run changes
watch(selectedRunId, (id) => { if (id) loadRunData(id); });

// Reload data periodically while run is active (every 5s)
let refreshTimer: ReturnType<typeof setInterval> | null = null;
watch(selectedRunId, (id) => {
  if (refreshTimer) clearInterval(refreshTimer);
  if (id) {
    refreshTimer = setInterval(() => {
      loadRunData(id);
    }, 5000);
  }
}, { immediate: true });

// Auto-select new run when received via WebSocket
watch(latestRun, (run) => {
  if (run) {
    if (!runs.value.find(r => r.id === run.id)) {
      runs.value = [run, ...runs.value];
    }
    selectedRunId.value = run.id;
  }
});

onMounted(loadRuns);

// Derive run start time for the wave timeline
const runStartedAt = computed(() => summary.value?.started_at ?? null);
</script>

<template>
  <div class="flex flex-col h-screen overflow-hidden bg-surface-0">
    <!-- Header -->
    <header class="bg-surface-1/80 backdrop-blur-sm border-b border-white/5 px-5 py-2.5 flex items-center justify-between shrink-0">
      <div class="flex items-center gap-3">
        <h1 class="text-sm font-semibold tracking-tight text-gray-100">TaskPlex Monitor</h1>
        <span
          class="flex items-center gap-1.5 text-[10px] px-2 py-0.5 rounded-full"
          :class="connected ? 'bg-accent-green/10 text-accent-green' : 'bg-accent-red/10 text-accent-red'"
        >
          <span
            class="w-1.5 h-1.5 rounded-full"
            :class="[connected ? 'bg-accent-green' : 'bg-accent-red', { 'pulse-active': connected }]"
          />
          {{ connected ? "Connected" : "Disconnected" }}
        </span>
      </div>

      <div class="flex items-center gap-3">
        <select
          v-model="selectedRunId"
          class="bg-surface-2 border border-surface-3 rounded-lg text-xs text-gray-300 px-2 py-1 focus:outline-none focus:border-accent-blue transition-colors"
        >
          <option value="">Select run...</option>
          <option v-for="run in runs" :key="run.id" :value="run.id">
            {{ run.id.slice(0, 8) }} — {{ run.branch || run.mode }} {{ run.ended_at ? '(done)' : '' }}
          </option>
        </select>
        <button
          class="text-[10px] text-gray-400 hover:text-gray-200 px-2 py-1 rounded hover:bg-surface-2 transition-colors"
          @click="loadRuns"
          title="Refresh runs"
        >
          Refresh
        </button>
      </div>
    </header>

    <!-- Dashboard content -->
    <main class="flex-1 overflow-y-auto p-4 space-y-4">
      <!-- Summary Bar -->
      <SummaryBar :summary="summary" :stories="stories" />

      <!-- Wave Timeline (hero) -->
      <WaveTimeline :stories="stories" :run-started-at="runStartedAt" />

      <!-- Bottom panels: Agent Activity + Errors -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4" style="min-height: 240px;">
        <AgentFeed :events="events" />
        <ErrorPanel :events="events" />
      </div>
    </main>
  </div>
</template>
```

**Step 2: Commit**

```bash
git add monitor/client/src/App.vue
git commit -m "feat(monitor): replace 4-tab layout with single-page dashboard"
```

---

### Task 11: Delete old views and unused components

Remove the files that have been replaced by the new dashboard components.

**Files:**
- Delete: `monitor/client/src/views/Timeline.vue`
- Delete: `monitor/client/src/views/StoryGantt.vue`
- Delete: `monitor/client/src/views/ErrorPatterns.vue`
- Delete: `monitor/client/src/views/AgentInsights.vue`
- Delete: `monitor/client/src/components/FilterBar.vue`
- Delete: `monitor/client/src/components/WaveProgress.vue`
- Delete: `monitor/client/src/components/StoryCard.vue`
- Delete: `monitor/client/src/composables/useFilters.ts`

**Step 1: Remove old files**

```bash
cd monitor/client/src
rm views/Timeline.vue views/StoryGantt.vue views/ErrorPatterns.vue views/AgentInsights.vue
rm components/FilterBar.vue components/WaveProgress.vue components/StoryCard.vue
rm composables/useFilters.ts
rmdir views  # remove empty directory
```

**Note:** Keep `components/EventRow.vue` — it may be useful for future detail views.

**Step 2: Commit**

```bash
git add -A monitor/client/src/views/ monitor/client/src/components/ monitor/client/src/composables/
git commit -m "chore(monitor): remove old tab views and unused components"
```

---

### Task 12: Build, test, and verify

Build the client and verify everything works together.

**Files:**
- No new files

**Step 1: Install dependencies (if needed)**

```bash
cd monitor/client && pnpm install
```

**Step 2: Build the client**

```bash
cd monitor/client && npx vite build
```

Expected: Clean build with no TypeScript errors and output in `monitor/client/dist/`.

**Step 3: Fix any build errors**

If TypeScript errors appear, fix them — likely unused imports or type mismatches. Common issues:
- `EventRow.vue` may reference old types — verify payload field access
- Tailwind JIT may warn about unused classes — safe to ignore

**Step 4: Test with Bun server**

```bash
cd monitor/server && SERVE_CLIENT=true bun run index.ts
```

Then open `http://localhost:4444` in browser. Verify:
- [ ] Header shows "TaskPlex Monitor" with connection status
- [ ] Run selector dropdown works
- [ ] Summary bar shows stat cards (will show zeros if no run selected)
- [ ] Wave Timeline shows "No stories yet" when empty
- [ ] Agent Activity shows "No agent activity yet" when empty
- [ ] Errors panel shows "No errors" when empty
- [ ] WebSocket connects (green "Connected" pill)

**Step 5: Test with sample data**

POST a test run and events to verify rendering:

```bash
# Create a test run
curl -s -X POST http://localhost:4444/api/runs -H 'Content-Type: application/json' -d '{"id":"test-001","started_at":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'","mode":"sequential","model":"sonnet","branch":"test","total_stories":3}'

# Start story 1
curl -s -X POST http://localhost:4444/api/events -H 'Content-Type: application/json' -d '{"event_type":"story.start","source":"orchestrator","run_id":"test-001","story_id":"auth-setup","wave":0,"payload":{}}'

# Complete story 1
sleep 2 && curl -s -X POST http://localhost:4444/api/events -H 'Content-Type: application/json' -d '{"event_type":"story.complete","source":"orchestrator","run_id":"test-001","story_id":"auth-setup","wave":0,"payload":{}}'

# Start story 2 (wave 1)
curl -s -X POST http://localhost:4444/api/events -H 'Content-Type: application/json' -d '{"event_type":"story.start","source":"orchestrator","run_id":"test-001","story_id":"api-routes","wave":1,"payload":{}}'

# Fail story 2
sleep 1 && curl -s -X POST http://localhost:4444/api/events -H 'Content-Type: application/json' -d '{"event_type":"story.fail","source":"orchestrator","run_id":"test-001","story_id":"api-routes","wave":1,"payload":{"category":"test_failure","message":"3 tests failed"}}'

# Subagent events
curl -s -X POST http://localhost:4444/api/events -H 'Content-Type: application/json' -d '{"event_type":"subagent.start","source":"hook","run_id":"test-001","story_id":"auth-setup","payload":{"agent_type":"implementer"}}'
```

Verify in browser:
- [ ] Summary bar updates counts
- [ ] Wave Timeline shows bars for auth-setup and api-routes in correct waves
- [ ] Completed bar is green, failed bar is red
- [ ] Agent Feed shows implementer entry
- [ ] Error Panel shows test_failure for api-routes

**Step 6: Final commit**

```bash
git add -A
git commit -m "feat(monitor): complete dashboard redesign with working data flow

- Fix WebSocket envelope unwrapping (NaN timestamps)
- Fix API route paths (JSON parse errors)
- Fix type mismatches (duration units, field names)
- Replace 4-tab layout with single-page dashboard
- Add SVG wave Gantt timeline visualization
- Add summary bar with progress ring and live elapsed time
- Add agent activity feed and error panel
- CSS glass-morphism, shimmer, pulse animations"
```

---

## Summary of all tasks

| # | Task | Files | Commit |
|---|------|-------|--------|
| 1 | Fix types.ts | types.ts | `fix: align client types` |
| 2 | Fix WebSocket envelope | useWebSocket.ts | `fix: unwrap WS envelope` |
| 3 | Fix API routes | useApi.ts | `fix: correct API paths` |
| 4 | Add CSS animations | style.css | `feat: glass/shimmer/pulse CSS` |
| 5 | ProgressRing component | ProgressRing.vue | `feat: SVG progress ring` |
| 6 | SummaryBar component | SummaryBar.vue | `feat: stat cards + progress` |
| 7 | WaveTimeline component | WaveTimeline.vue | `feat: SVG Gantt visualization` |
| 8 | AgentFeed component | AgentFeed.vue | `feat: agent activity panel` |
| 9 | ErrorPanel component | ErrorPanel.vue | `feat: error/retry panel` |
| 10 | Rewrite App.vue | App.vue | `feat: single-page dashboard` |
| 11 | Delete old files | 8 files removed | `chore: remove old views` |
| 12 | Build + test | — | `feat: complete redesign` |
