<script setup lang="ts">
import { computed } from "vue";
import type { MonitorEvent } from "@/types";

const props = defineProps<{
  event: MonitorEvent;
  events: MonitorEvent[];
}>();

const waveNumber = computed(() => props.event.wave ?? 0);

const storiesInWave = computed(() => {
  const w = waveNumber.value;
  const storyIds = new Set<string>();
  for (const e of props.events) {
    if (e.wave === w && e.story_id) {
      storyIds.add(e.story_id);
    }
  }
  return storyIds;
});

const completedInWave = computed(() => {
  const w = waveNumber.value;
  const completed = new Set<string>();
  for (const e of props.events) {
    if (e.wave === w && e.story_id && e.event_type === "story.complete") {
      completed.add(e.story_id);
    }
  }
  return completed;
});

const totalStories = computed(() => storiesInWave.value.size);
const completedCount = computed(() => completedInWave.value.size);
const progressPct = computed(() => (totalStories.value > 0 ? (completedCount.value / totalStories.value) * 100 : 0));
</script>

<template>
  <div class="bg-surface-1 border-b border-surface-3 px-4 py-2 flex items-center gap-4">
    <div class="flex items-center gap-2">
      <span class="text-accent-cyan text-sm">\ud83c\udf0a</span>
      <span class="text-xs font-medium text-accent-cyan">Wave {{ waveNumber }}</span>
    </div>

    <div class="flex-1 max-w-xs">
      <div class="h-1.5 bg-surface-3 rounded-full overflow-hidden">
        <div
          class="h-full bg-accent-cyan rounded-full transition-all duration-500"
          :style="{ width: `${progressPct}%` }"
        />
      </div>
    </div>

    <span class="text-[11px] text-gray-400 font-mono">
      {{ completedCount }}/{{ totalStories }} stories
    </span>
  </div>
</template>
