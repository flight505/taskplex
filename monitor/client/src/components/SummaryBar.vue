<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from "vue";
import type { RunSummary, StoryTimelineEntry } from "@/types";
import ProgressRing from "./ProgressRing.vue";

const props = defineProps<{
  summary: RunSummary | null;
  stories: StoryTimelineEntry[];
}>();

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
