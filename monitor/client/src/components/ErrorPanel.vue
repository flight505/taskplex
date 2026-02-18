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
          <span class="text-[11px] font-mono text-gray-300">{{ err.storyId }}</span>
          <span
            class="text-[9px] font-medium px-1.5 py-0.5 rounded-full shrink-0"
            :class="CATEGORY_COLORS[err.category] || CATEGORY_COLORS.unknown"
          >{{ err.category }}</span>
          <span class="text-[9px] text-gray-500 ml-auto shrink-0">
            <span v-if="err.retryCount < err.maxRetries" class="text-accent-yellow">
              Retry {{ err.retryCount + 1 }}/{{ err.maxRetries }}
            </span>
            <span v-else class="text-accent-red">Skipped</span>
          </span>
          <span class="text-[9px] text-gray-600 font-mono shrink-0">{{ relativeTime(err.timestamp) }}</span>
        </div>
        <div v-if="err.message" class="text-[9px] text-gray-500 mt-0.5 truncate">{{ err.message }}</div>
      </div>
    </div>
  </div>
</template>
