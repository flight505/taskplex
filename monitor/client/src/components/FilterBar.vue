<script setup lang="ts">
import { ref, watch } from "vue";

const props = defineProps<{
  runs: string[];
  stories: string[];
  eventTypes: string[];
  sources: string[];
  selectedRunId: string;
  selectedStoryId: string;
  selectedEventTypes: string[];
  selectedSource: string;
}>();

const emit = defineEmits<{
  change: [filters: { runId: string; storyId: string; eventTypes: string[]; source: string }];
  clear: [];
}>();

const localRunId = ref(props.selectedRunId);
const localStoryId = ref(props.selectedStoryId);
const localEventTypes = ref<string[]>([...props.selectedEventTypes]);
const localSource = ref(props.selectedSource);
const showEventTypeDropdown = ref(false);

watch(() => props.selectedRunId, (v) => { localRunId.value = v; });
watch(() => props.selectedStoryId, (v) => { localStoryId.value = v; });
watch(() => props.selectedEventTypes, (v) => { localEventTypes.value = [...v]; });
watch(() => props.selectedSource, (v) => { localSource.value = v; });

function emitChange() {
  emit("change", {
    runId: localRunId.value,
    storyId: localStoryId.value,
    eventTypes: localEventTypes.value,
    source: localSource.value,
  });
}

function toggleEventType(type: string) {
  const idx = localEventTypes.value.indexOf(type);
  if (idx >= 0) {
    localEventTypes.value.splice(idx, 1);
  } else {
    localEventTypes.value.push(type);
  }
  emitChange();
}

function handleClear() {
  localRunId.value = "";
  localStoryId.value = "";
  localEventTypes.value = [];
  localSource.value = "";
  emit("clear");
}

function closeDropdownDelayed() {
  window.setTimeout(() => { showEventTypeDropdown.value = false; }, 150);
}

const hasFilters = () =>
  localRunId.value || localStoryId.value || localEventTypes.value.length > 0 || localSource.value;
</script>

<template>
  <div class="flex items-center gap-2 flex-wrap min-w-0">
    <!-- Story filter -->
    <select
      v-model="localStoryId"
      @change="emitChange"
      class="bg-surface-2 border border-surface-3 rounded text-[11px] text-gray-300 px-1.5 py-1 focus:outline-none focus:border-accent-blue max-w-[120px]"
    >
      <option value="">All stories</option>
      <option v-for="s in stories" :key="s" :value="s">{{ s }}</option>
    </select>

    <!-- Source filter -->
    <select
      v-model="localSource"
      @change="emitChange"
      class="bg-surface-2 border border-surface-3 rounded text-[11px] text-gray-300 px-1.5 py-1 focus:outline-none focus:border-accent-blue max-w-[120px]"
    >
      <option value="">All sources</option>
      <option v-for="s in sources" :key="s" :value="s">{{ s }}</option>
    </select>

    <!-- Event type multi-select -->
    <div class="relative">
      <button
        class="bg-surface-2 border border-surface-3 rounded text-[11px] text-gray-300 px-1.5 py-1 flex items-center gap-1 focus:outline-none focus:border-accent-blue"
        @click="showEventTypeDropdown = !showEventTypeDropdown"
        @blur="closeDropdownDelayed"
      >
        <span v-if="localEventTypes.length === 0">All types</span>
        <span v-else>{{ localEventTypes.length }} type{{ localEventTypes.length > 1 ? "s" : "" }}</span>
        <span class="text-[9px] text-gray-500">\u25be</span>
      </button>
      <div
        v-if="showEventTypeDropdown"
        class="absolute top-full left-0 mt-1 bg-surface-2 border border-surface-3 rounded-lg shadow-lg z-40 max-h-48 overflow-y-auto min-w-[140px]"
      >
        <label
          v-for="et in eventTypes"
          :key="et"
          class="flex items-center gap-2 px-2 py-1 hover:bg-surface-3 cursor-pointer text-[11px] text-gray-300"
        >
          <input
            type="checkbox"
            :checked="localEventTypes.includes(et)"
            @change="toggleEventType(et)"
            class="rounded border-surface-3 bg-surface-1 text-accent-blue focus:ring-0 w-3 h-3"
          />
          {{ et }}
        </label>
      </div>
    </div>

    <!-- Clear filters -->
    <button
      v-if="hasFilters()"
      class="text-[11px] text-gray-500 hover:text-gray-300 transition-colors"
      @click="handleClear"
    >
      Clear filters
    </button>
  </div>
</template>
