<script setup lang="ts">
import { ref, computed, watch, nextTick, onMounted } from "vue";
import type { MonitorEvent } from "@/types";
import { useFilters } from "@/composables/useFilters";
import EventRow from "@/components/EventRow.vue";
import FilterBar from "@/components/FilterBar.vue";
import WaveProgress from "@/components/WaveProgress.vue";

const props = defineProps<{
  events: MonitorEvent[];
  connected: boolean;
}>();

const emit = defineEmits<{
  clear: [];
}>();

const {
  selectedRunId,
  selectedStoryId,
  selectedEventTypes,
  selectedSource,
  filteredEvents,
  availableRuns,
  availableStories,
  availableEventTypes,
  availableSources,
  clearFilters,
} = useFilters();

const pinned = ref(true);
const listRef = ref<HTMLElement | null>(null);

const displayed = computed(() => filteredEvents(props.events));

const hasWaveEvents = computed(() =>
  props.events.some((e) => e.event_type === "wave.start" || e.wave !== null)
);

const latestWaveEvent = computed(() => {
  return props.events.find((e) => e.event_type === "wave.start");
});

// auto-scroll when pinned and new events arrive
watch(
  () => props.events.length,
  async () => {
    if (pinned.value && listRef.value) {
      await nextTick();
      listRef.value.scrollTop = 0;
    }
  }
);

function handleFilterChange(filters: {
  runId: string;
  storyId: string;
  eventTypes: string[];
  source: string;
}) {
  selectedRunId.value = filters.runId;
  selectedStoryId.value = filters.storyId;
  selectedEventTypes.value = filters.eventTypes;
  selectedSource.value = filters.source;
}
</script>

<template>
  <div class="flex flex-col h-full">
    <!-- Wave progress (if parallel mode detected) -->
    <WaveProgress
      v-if="hasWaveEvents && latestWaveEvent"
      :event="latestWaveEvent"
      :events="events"
      class="shrink-0"
    />

    <!-- Filter bar + controls -->
    <div class="shrink-0 bg-surface-1 border-b border-surface-3 px-4 py-2 flex items-center gap-3">
      <FilterBar
        :runs="availableRuns(events)"
        :stories="availableStories(events)"
        :event-types="availableEventTypes(events)"
        :sources="availableSources(events)"
        :selected-run-id="selectedRunId"
        :selected-story-id="selectedStoryId"
        :selected-event-types="selectedEventTypes"
        :selected-source="selectedSource"
        @change="handleFilterChange"
        @clear="clearFilters"
      />

      <div class="flex items-center gap-2 ml-auto shrink-0">
        <span class="text-xs text-gray-500">{{ displayed.length }} events</span>
        <button
          class="text-xs px-2 py-1 rounded transition-colors"
          :class="pinned ? 'bg-accent-blue/20 text-accent-blue' : 'bg-surface-2 text-gray-400 hover:text-gray-200'"
          @click="pinned = !pinned"
          :title="pinned ? 'Auto-scroll ON' : 'Auto-scroll OFF'"
        >
          {{ pinned ? "Pinned" : "Unpinned" }}
        </button>
        <button
          class="text-xs text-gray-400 hover:text-accent-red px-2 py-1 rounded hover:bg-surface-2 transition-colors"
          @click="emit('clear')"
        >
          Clear
        </button>
      </div>
    </div>

    <!-- Event list -->
    <div ref="listRef" class="flex-1 overflow-y-auto">
      <div v-if="displayed.length === 0" class="flex items-center justify-center h-full text-gray-500 text-sm">
        {{ connected ? "Waiting for events..." : "Not connected" }}
      </div>
      <div v-else class="divide-y divide-surface-3">
        <EventRow v-for="event in displayed" :key="event.id" :event="event" />
      </div>
    </div>
  </div>
</template>
