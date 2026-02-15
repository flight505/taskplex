<script setup lang="ts">
import { ref, computed, watch, onMounted } from "vue";
import { useApi } from "@/composables/useApi";
import type { StoryTimelineEntry } from "@/types";
import StoryCard from "@/components/StoryCard.vue";

const props = defineProps<{
  runId: string;
}>();

const { fetchTimeline } = useApi();

const timeline = ref<StoryTimelineEntry[]>([]);
const loading = ref(false);
const error = ref("");
const hoveredStory = ref<StoryTimelineEntry | null>(null);
const tooltipPos = ref({ x: 0, y: 0 });

async function load() {
  if (!props.runId) {
    timeline.value = [];
    return;
  }
  loading.value = true;
  error.value = "";
  try {
    timeline.value = await fetchTimeline(props.runId);
  } catch (e: any) {
    error.value = e.message || "Failed to load timeline";
  } finally {
    loading.value = false;
  }
}

watch(() => props.runId, load, { immediate: true });

const statusColor: Record<string, string> = {
  completed: "bg-accent-green",
  failed: "bg-accent-red",
  skipped: "bg-accent-red/60",
  in_progress: "bg-accent-blue",
  pending: "bg-gray-600",
};

const statusBorder: Record<string, string> = {
  completed: "border-accent-green",
  failed: "border-accent-red",
  skipped: "border-accent-red/60",
  in_progress: "border-accent-blue",
  pending: "border-gray-600",
};

// time range for the chart
const timeRange = computed(() => {
  const entries = timeline.value.filter((s) => s.started_at);
  if (entries.length === 0) return { start: 0, end: 1 };
  const starts = entries.map((s) => new Date(s.started_at).getTime());
  const ends = entries
    .filter((s) => s.ended_at)
    .map((s) => new Date(s.ended_at!).getTime());
  const allEnds = ends.length > 0 ? ends : [Date.now()];
  const start = Math.min(...starts);
  const end = Math.max(...allEnds, Date.now());
  const pad = (end - start) * 0.02 || 1000;
  return { start: start - pad, end: end + pad };
});

function barStyle(entry: StoryTimelineEntry): Record<string, string> {
  if (!entry.started_at) return { display: "none" };
  const range = timeRange.value;
  const total = range.end - range.start;
  if (total <= 0) return { display: "none" };
  const start = new Date(entry.started_at).getTime();
  const end = entry.ended_at ? new Date(entry.ended_at).getTime() : Date.now();
  const left = ((start - range.start) / total) * 100;
  const width = Math.max(((end - start) / total) * 100, 0.5);
  return {
    left: `${left}%`,
    width: `${width}%`,
  };
}

// wave separators
const waves = computed(() => {
  const waveMap = new Map<number, number>();
  for (const entry of timeline.value) {
    if (entry.wave !== null && entry.started_at) {
      const t = new Date(entry.started_at).getTime();
      const existing = waveMap.get(entry.wave);
      if (!existing || t < existing) {
        waveMap.set(entry.wave, t);
      }
    }
  }
  const range = timeRange.value;
  const total = range.end - range.start;
  if (total <= 0) return [];
  return Array.from(waveMap.entries())
    .sort(([a], [b]) => a - b)
    .map(([wave, time]) => ({
      wave,
      left: ((time - range.start) / total) * 100,
    }));
});

function formatDuration(entry: StoryTimelineEntry): string {
  if (!entry.started_at) return "--";
  const start = new Date(entry.started_at).getTime();
  const end = entry.ended_at ? new Date(entry.ended_at).getTime() : Date.now();
  const sec = Math.round((end - start) / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  const rem = sec % 60;
  return `${min}m ${rem}s`;
}

function onBarHover(entry: StoryTimelineEntry, event: MouseEvent) {
  hoveredStory.value = entry;
  tooltipPos.value = { x: event.clientX, y: event.clientY };
}

function onBarLeave() {
  hoveredStory.value = null;
}
</script>

<template>
  <div class="h-full flex flex-col overflow-hidden">
    <div v-if="!runId" class="flex items-center justify-center h-full text-gray-500 text-sm">
      Select a run to view story timeline
    </div>

    <div v-else-if="loading" class="flex items-center justify-center h-full text-gray-500 text-sm">
      Loading timeline...
    </div>

    <div v-else-if="error" class="flex items-center justify-center h-full text-accent-red text-sm">
      {{ error }}
    </div>

    <div v-else-if="timeline.length === 0" class="flex items-center justify-center h-full text-gray-500 text-sm">
      No stories in this run
    </div>

    <div v-else class="flex-1 overflow-y-auto p-4">
      <!-- Legend -->
      <div class="flex items-center gap-4 mb-4 text-xs text-gray-400">
        <span class="flex items-center gap-1"><span class="w-3 h-2 rounded-sm bg-accent-green inline-block" /> Completed</span>
        <span class="flex items-center gap-1"><span class="w-3 h-2 rounded-sm bg-accent-blue inline-block" /> In Progress</span>
        <span class="flex items-center gap-1"><span class="w-3 h-2 rounded-sm bg-accent-red inline-block" /> Failed</span>
        <span class="flex items-center gap-1"><span class="w-3 h-2 rounded-sm bg-gray-600 inline-block" /> Pending</span>
      </div>

      <!-- Gantt rows -->
      <div class="space-y-1">
        <div
          v-for="entry in timeline"
          :key="entry.story_id"
          class="flex items-center gap-3 h-8 group"
        >
          <!-- Story label -->
          <div class="w-32 shrink-0 text-xs text-gray-300 font-mono truncate" :title="entry.title">
            {{ entry.story_id }}
          </div>

          <!-- Bar area -->
          <div class="flex-1 relative h-6 bg-surface-2 rounded overflow-hidden">
            <!-- Wave separators -->
            <div
              v-for="w in waves"
              :key="w.wave"
              class="absolute top-0 bottom-0 border-l border-dashed border-accent-cyan/30"
              :style="{ left: `${w.left}%` }"
            >
              <span class="absolute -top-0.5 left-1 text-[9px] text-accent-cyan/50">W{{ w.wave }}</span>
            </div>

            <!-- Story bar -->
            <div
              class="absolute top-1 bottom-1 rounded-sm cursor-pointer transition-opacity group-hover:opacity-90"
              :class="statusColor[entry.status] || 'bg-gray-600'"
              :style="barStyle(entry)"
              @mouseenter="onBarHover(entry, $event)"
              @mouseleave="onBarLeave"
            >
              <!-- Retry indicator (lighter segments) -->
              <div
                v-if="entry.attempts > 1"
                class="absolute inset-0 rounded-sm opacity-40"
                :style="{ background: 'repeating-linear-gradient(90deg, transparent 0, transparent 45%, rgba(255,255,255,0.15) 45%, rgba(255,255,255,0.15) 55%)' }"
              />
            </div>
          </div>

          <!-- Status + duration -->
          <div class="w-20 shrink-0 text-right text-xs text-gray-500 font-mono">
            {{ formatDuration(entry) }}
          </div>
        </div>
      </div>
    </div>

    <!-- Floating tooltip -->
    <Teleport to="body">
      <div
        v-if="hoveredStory"
        class="fixed z-50 pointer-events-none"
        :style="{ left: `${tooltipPos.x + 12}px`, top: `${tooltipPos.y - 10}px` }"
      >
        <StoryCard :entry="hoveredStory" />
      </div>
    </Teleport>
  </div>
</template>
