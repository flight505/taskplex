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
const CHART_WIDTH = 800;

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
  const starts = props.stories.filter(s => s.started_at).map(s => new Date(s.started_at).getTime());
  const start = props.runStartedAt
    ? new Date(props.runStartedAt).getTime()
    : (starts.length > 0 ? Math.min(...starts) : now.value);
  const ends = props.stories
    .filter(s => s.ended_at)
    .map(s => new Date(s.ended_at!).getTime());
  const maxEnd = ends.length > 0 ? Math.max(...ends) : now.value;
  const end = Math.max(maxEnd, now.value);
  const duration = end - start || 1;
  return { start, end, duration };
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

// Compute bar data
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

  for (let wIdx = 0; wIdx < waveGroups.value.length; wIdx++) {
    const [waveNum, stories] = waveGroups.value[wIdx];

    for (let i = 0; i < stories.length; i++) {
      const s = stories[i];
      const sStart = s.started_at ? new Date(s.started_at).getTime() : 0;
      const sEnd = s.ended_at ? new Date(s.ended_at).getTime() : (s.status === "running" ? now.value : sStart);

      const x = sStart ? ((sStart - start) / duration) * CHART_WIDTH : 0;
      const w = sStart ? (((sEnd - sStart) || 1) / duration) * CHART_WIDTH : 0;

      const secs = sStart ? Math.max(0, Math.floor((sEnd - sStart) / 1000)) : 0;
      const durationStr = secs < 60 ? `${secs}s` : `${Math.floor(secs / 60)}m ${secs % 60}s`;

      result.push({
        story: s,
        x: LABEL_WIDTH + x,
        width: Math.max(w, 2),
        y: rowIndex * ROW_HEIGHT + wIdx * WAVE_GAP + 4,
        color: barColor(s.status),
        opacity: s.status === "skipped" ? 0.5 : 1,
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

const totalHeight = computed(() => {
  let rows = 0;
  for (const [, stories] of waveGroups.value) rows += stories.length;
  return rows * ROW_HEIGHT + waveGroups.value.length * WAVE_GAP + 20;
});

const viewBoxWidth = computed(() => LABEL_WIDTH + CHART_WIDTH + PAD_RIGHT);

function onBarHover(storyId: string, event: MouseEvent) {
  hoveredStory.value = storyId;
  hoverPos.value = { x: event.clientX, y: event.clientY };
}
function onBarLeave() { hoveredStory.value = null; }

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
        width="100%"
        :height="totalHeight"
        class="min-w-[600px]"
      >
        <!-- Wave separators -->
        <line
          v-for="(sepY, i) in waveSeparators"
          :key="'sep-' + i"
          :x1="0" :y1="sepY"
          :x2="viewBoxWidth" :y2="sepY"
          stroke="#242430" stroke-width="1" stroke-dasharray="4 4"
        />

        <g v-for="bar in bars" :key="bar.story.story_id">
          <!-- Wave label -->
          <text
            v-if="bar.waveLabel"
            :x="4" :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="fill-accent-cyan text-[10px] font-semibold"
            dominant-baseline="middle"
          >{{ bar.waveLabel }}</text>

          <!-- Story label -->
          <text
            :x="60" :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="fill-gray-300 text-[11px] font-mono"
            dominant-baseline="middle"
          >{{ bar.story.story_id.length > 16 ? bar.story.story_id.slice(0, 16) + '...' : bar.story.story_id }}</text>

          <!-- Status icon -->
          <text
            :x="LABEL_WIDTH - 16" :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="text-[11px]"
            :class="{
              'fill-accent-green': bar.story.status === 'completed',
              'fill-accent-red': bar.story.status === 'failed',
              'fill-accent-blue': bar.story.status === 'running',
              'fill-accent-yellow': bar.story.status === 'skipped',
              'fill-gray-500': bar.story.status === 'blocked',
            }"
            dominant-baseline="middle" text-anchor="end"
          >{{ bar.story.status === 'completed' ? '✓' : bar.story.status === 'failed' ? '✗' : bar.story.status === 'running' ? '⟳' : bar.story.status === 'skipped' ? '⏭' : '○' }}</text>

          <!-- Pending placeholder -->
          <rect
            v-if="!bar.story.started_at"
            :x="LABEL_WIDTH" :y="bar.y + 4" :width="100" :height="ROW_HEIGHT - 12"
            rx="3" fill="none" stroke="#4b5563" stroke-width="1" stroke-dasharray="4 2"
          />

          <!-- Bar -->
          <rect
            v-else
            :x="bar.x" :y="bar.y + 4" :width="bar.width" :height="ROW_HEIGHT - 12"
            rx="3" :fill="bar.color" :opacity="bar.opacity"
            :class="{ 'bar-running': bar.isRunning }"
            class="transition-all duration-500"
            @mouseenter="onBarHover(bar.story.story_id, $event)"
            @mouseleave="onBarLeave"
          />

          <!-- Retry stripe -->
          <rect
            v-if="bar.story.attempts > 1 && bar.story.started_at"
            :x="bar.x" :y="bar.y + 4" :width="bar.width" :height="ROW_HEIGHT - 12"
            rx="3" fill="url(#stripe-pattern)" opacity="0.3"
          />

          <!-- Duration label -->
          <text
            v-if="bar.duration"
            :x="bar.x + bar.width + 6" :y="bar.y + ROW_HEIGHT / 2 - 2"
            class="fill-gray-500 text-[9px] font-mono" dominant-baseline="middle"
          >{{ bar.duration }}</text>
        </g>

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
