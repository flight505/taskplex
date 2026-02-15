<script setup lang="ts">
import { computed } from "vue";
import type { StoryTimelineEntry } from "@/types";

const props = defineProps<{
  entry: StoryTimelineEntry;
}>();

const statusBadge: Record<string, string> = {
  completed: "bg-accent-green/20 text-accent-green",
  failed: "bg-accent-red/20 text-accent-red",
  skipped: "bg-accent-red/10 text-accent-red/70",
  in_progress: "bg-accent-blue/20 text-accent-blue",
  pending: "bg-gray-700 text-gray-400",
};

const duration = computed(() => {
  if (!props.entry.started_at) return "--";
  const start = new Date(props.entry.started_at).getTime();
  const end = props.entry.ended_at ? new Date(props.entry.ended_at).getTime() : Date.now();
  const sec = Math.round((end - start) / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  const rem = sec % 60;
  return `${min}m ${rem}s`;
});
</script>

<template>
  <div class="bg-surface-2 border border-surface-3 rounded-lg shadow-lg p-3 min-w-[200px] max-w-[280px]">
    <div class="flex items-center justify-between gap-2 mb-1.5">
      <span class="text-xs font-mono text-gray-300 truncate">{{ entry.story_id }}</span>
      <span
        class="text-[10px] font-medium px-1.5 py-0.5 rounded-full shrink-0"
        :class="statusBadge[entry.status] || 'bg-gray-700 text-gray-400'"
      >
        {{ entry.status }}
      </span>
    </div>

    <p v-if="entry.title" class="text-[11px] text-gray-400 mb-2 line-clamp-2">{{ entry.title }}</p>

    <div class="flex items-center gap-3 text-[10px] text-gray-500">
      <span>Duration: <span class="font-mono text-gray-400">{{ duration }}</span></span>
      <span>Attempts: <span class="font-mono text-gray-400">{{ entry.attempts }}</span></span>
    </div>

    <div v-if="entry.error_category" class="mt-1.5">
      <span class="text-[10px] font-mono px-1.5 py-0.5 rounded bg-accent-red/10 text-accent-red">
        {{ entry.error_category }}
      </span>
    </div>

    <div v-if="entry.wave !== null" class="mt-1.5 text-[10px] text-accent-cyan/70">
      Wave {{ entry.wave }}
    </div>
  </div>
</template>
