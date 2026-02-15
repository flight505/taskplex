<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useWebSocket } from "@/composables/useWebSocket";
import { useApi } from "@/composables/useApi";
import type { Run } from "@/types";
import Timeline from "@/views/Timeline.vue";
import StoryGantt from "@/views/StoryGantt.vue";
import ErrorPatterns from "@/views/ErrorPatterns.vue";
import AgentInsights from "@/views/AgentInsights.vue";

const { events, connected, clear } = useWebSocket();
const { fetchRuns } = useApi();

const activeTab = ref<"timeline" | "stories" | "errors" | "agents">("timeline");
const selectedRunId = ref("");
const runs = ref<Run[]>([]);

const tabs = [
  { key: "timeline" as const, label: "Timeline" },
  { key: "stories" as const, label: "Stories" },
  { key: "errors" as const, label: "Errors" },
  { key: "agents" as const, label: "Agents" },
];

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

onMounted(loadRuns);
</script>

<template>
  <div class="flex flex-col h-screen overflow-hidden">
    <!-- Header -->
    <header class="bg-surface-1 border-b border-surface-3 px-4 py-2 flex items-center justify-between shrink-0">
      <div class="flex items-center gap-3">
        <h1 class="text-base font-semibold tracking-tight text-gray-100">TaskPlex Monitor</h1>
        <span
          class="flex items-center gap-1.5 text-xs px-2 py-0.5 rounded-full"
          :class="connected ? 'bg-accent-green/10 text-accent-green' : 'bg-accent-red/10 text-accent-red'"
        >
          <span class="w-1.5 h-1.5 rounded-full" :class="connected ? 'bg-accent-green' : 'bg-accent-red'" />
          {{ connected ? "Connected" : "Disconnected" }}
        </span>
      </div>

      <div class="flex items-center gap-3">
        <select
          v-model="selectedRunId"
          class="bg-surface-2 border border-surface-3 rounded-lg text-xs text-gray-300 px-2 py-1 focus:outline-none focus:border-accent-blue"
        >
          <option value="">All runs</option>
          <option v-for="run in runs" :key="run.id" :value="run.id">
            {{ run.id.slice(0, 8) }} &mdash; {{ run.branch || run.mode }}
          </option>
        </select>
        <button
          class="text-xs text-gray-400 hover:text-gray-200 px-2 py-1 rounded hover:bg-surface-2 transition-colors"
          @click="loadRuns"
          title="Refresh runs"
        >
          Refresh
        </button>
      </div>
    </header>

    <!-- Tab Navigation -->
    <nav class="bg-surface-1 border-b border-surface-3 px-4 flex gap-0 shrink-0">
      <button
        v-for="tab in tabs"
        :key="tab.key"
        class="px-3 py-2 text-xs font-medium border-b-2 transition-colors"
        :class="
          activeTab === tab.key
            ? 'border-accent-blue text-accent-blue'
            : 'border-transparent text-gray-400 hover:text-gray-200 hover:border-surface-3'
        "
        @click="activeTab = tab.key"
      >
        {{ tab.label }}
      </button>
    </nav>

    <!-- Active View -->
    <main class="flex-1 overflow-hidden">
      <Timeline
        v-if="activeTab === 'timeline'"
        :events="events"
        :connected="connected"
        @clear="clear"
      />
      <StoryGantt
        v-else-if="activeTab === 'stories'"
        :run-id="selectedRunId"
      />
      <ErrorPatterns
        v-else-if="activeTab === 'errors'"
        :run-id="selectedRunId"
      />
      <AgentInsights
        v-else-if="activeTab === 'agents'"
        :run-id="selectedRunId"
      />
    </main>
  </div>
</template>
