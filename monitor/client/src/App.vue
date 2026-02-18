<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch } from "vue";
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

// Reload data when run changes + auto-refresh every 5s
let refreshTimer: ReturnType<typeof setInterval> | null = null;
watch(selectedRunId, (id) => {
  if (refreshTimer) clearInterval(refreshTimer);
  if (id) {
    loadRunData(id);
    refreshTimer = setInterval(() => {
      loadRunData(id);
    }, 5000);
  } else {
    summary.value = null;
    stories.value = [];
  }
}, { immediate: true });
onUnmounted(() => { if (refreshTimer) clearInterval(refreshTimer); });

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
      <SummaryBar :summary="summary" :stories="stories" />
      <WaveTimeline :stories="stories" :run-started-at="runStartedAt" />
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4" style="min-height: 240px;">
        <AgentFeed :events="events" />
        <ErrorPanel :events="events" />
      </div>
    </main>
  </div>
</template>
