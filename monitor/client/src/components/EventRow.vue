<script setup lang="ts">
import { ref, computed } from "vue";
import type { MonitorEvent } from "@/types";

const props = defineProps<{
  event: MonitorEvent;
}>();

const expanded = ref(false);

const eventIcons: Record<string, string> = {
  "story.start": "\u25b6",
  "story.complete": "\u2713",
  "story.failed": "\u2717",
  "story.retry": "\u21bb",
  "tool.use": "\ud83d\udd27",
  "subagent.start": "\ud83e\udd16",
  "subagent.stop": "\u23f9",
  "merge.start": "\ud83d\udd00",
  "wave.start": "\ud83c\udf0a",
  "run.start": "\ud83d\ude80",
  "run.end": "\ud83c\udfc1",
};

const eventBadgeColors: Record<string, string> = {
  "story.start": "bg-accent-blue/20 text-accent-blue",
  "story.complete": "bg-accent-green/20 text-accent-green",
  "story.failed": "bg-accent-red/20 text-accent-red",
  "story.retry": "bg-accent-yellow/20 text-accent-yellow",
  "tool.use": "bg-gray-700 text-gray-300",
  "subagent.start": "bg-accent-purple/20 text-accent-purple",
  "subagent.stop": "bg-accent-purple/10 text-accent-purple/70",
  "merge.start": "bg-accent-cyan/20 text-accent-cyan",
  "wave.start": "bg-accent-cyan/20 text-accent-cyan",
  "run.start": "bg-accent-blue/20 text-accent-blue",
  "run.end": "bg-accent-green/20 text-accent-green",
};

function storyColor(storyId: string): string {
  if (!storyId) return "border-transparent";
  let hash = 0;
  for (let i = 0; i < storyId.length; i++) {
    hash = ((hash << 5) - hash + storyId.charCodeAt(i)) | 0;
  }
  const hue = Math.abs(hash) % 360;
  return `border-l-[hsl(${hue},60%,55%)]`;
}

// Inline style for story border color (Tailwind arbitrary values are JIT only)
const borderStyle = computed(() => {
  if (!props.event.story_id) return { borderLeftColor: "transparent" };
  let hash = 0;
  const s = props.event.story_id;
  for (let i = 0; i < s.length; i++) {
    hash = ((hash << 5) - hash + s.charCodeAt(i)) | 0;
  }
  const hue = Math.abs(hash) % 360;
  return { borderLeftColor: `hsl(${hue}, 60%, 55%)` };
});

const icon = computed(() => eventIcons[props.event.event_type] || "\u25cf");
const badgeClass = computed(() => eventBadgeColors[props.event.event_type] || "bg-surface-3 text-gray-400");

const relativeTime = computed(() => {
  const now = Date.now();
  const ts = new Date(props.event.timestamp).getTime();
  const diff = Math.max(0, Math.floor((now - ts) / 1000));
  if (diff < 5) return "just now";
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
});

const payloadSummary = computed(() => {
  const p = props.event.payload;
  if (!p || Object.keys(p).length === 0) return "";
  const keys = Object.keys(p);
  const parts: string[] = [];
  for (const k of keys.slice(0, 3)) {
    const v = p[k];
    const str = typeof v === "string" ? v : JSON.stringify(v);
    const truncated = str.length > 60 ? str.slice(0, 57) + "..." : str;
    parts.push(`${k}: ${truncated}`);
  }
  if (keys.length > 3) parts.push(`+${keys.length - 3} more`);
  return parts.join(" | ");
});

const payloadJson = computed(() => {
  try {
    return JSON.stringify(props.event.payload, null, 2);
  } catch {
    return "{}";
  }
});
</script>

<template>
  <div
    class="border-l-2 px-3 py-1.5 hover:bg-surface-1 cursor-pointer transition-colors"
    :style="borderStyle"
    @click="expanded = !expanded"
  >
    <div class="flex items-center gap-2 min-w-0">
      <!-- Icon -->
      <span class="text-sm w-5 text-center shrink-0">{{ icon }}</span>

      <!-- Timestamp -->
      <span class="text-[10px] text-gray-500 font-mono w-16 shrink-0">{{ relativeTime }}</span>

      <!-- Event type badge -->
      <span
        class="text-[10px] font-medium px-1.5 py-0.5 rounded-full shrink-0"
        :class="badgeClass"
      >
        {{ event.event_type }}
      </span>

      <!-- Story ID badge -->
      <span
        v-if="event.story_id"
        class="text-[10px] font-mono px-1.5 py-0.5 rounded bg-surface-3 text-gray-400 shrink-0"
      >
        {{ event.story_id }}
      </span>

      <!-- Payload summary -->
      <span class="text-[10px] text-gray-500 truncate min-w-0">{{ payloadSummary }}</span>

      <!-- Expand indicator -->
      <span class="text-[10px] text-gray-600 ml-auto shrink-0 transition-transform" :class="{ 'rotate-90': expanded }">
        \u25b8
      </span>
    </div>

    <!-- Expanded payload -->
    <div v-if="expanded" class="mt-2 ml-7">
      <pre class="text-[10px] text-gray-400 font-mono bg-surface-2 rounded-lg p-2 overflow-x-auto max-h-48 overflow-y-auto whitespace-pre">{{ payloadJson }}</pre>
      <div class="mt-1 flex gap-3 text-[10px] text-gray-500">
        <span>ID: <span class="font-mono">{{ event.id }}</span></span>
        <span>Source: <span class="font-mono">{{ event.source }}</span></span>
        <span v-if="event.run_id">Run: <span class="font-mono">{{ event.run_id.slice(0, 8) }}</span></span>
        <span v-if="event.wave !== null">Wave: {{ event.wave }}</span>
        <span v-if="event.batch !== null">Batch: {{ event.batch }}</span>
      </div>
    </div>
  </div>
</template>
