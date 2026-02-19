<script setup lang="ts">
import { computed } from "vue";
import type { MonitorEvent } from "@/types";

const props = defineProps<{
  events: MonitorEvent[];
}>();

const AGENT_COLORS: Record<string, string> = {
  implementer: "bg-accent-blue",
  validator: "bg-accent-cyan",
  reviewer: "bg-accent-purple",
  merger: "bg-accent-yellow",
};

const AGENT_TEXT_COLORS: Record<string, string> = {
  implementer: "text-accent-blue",
  validator: "text-accent-cyan",
  reviewer: "text-accent-purple",
  merger: "text-accent-yellow",
};

interface AgentEntry {
  id: number;
  agentType: string;
  storyId: string;
  isActive: boolean;
  timestamp: string;
  duration: string;
}

const agentEvents = computed<AgentEntry[]>(() => {
  return props.events
    .filter(e => e.event_type === "subagent.start" || e.event_type === "subagent.end" || e.event_type === "subagent.stop")
    .slice(0, 20)
    .map(e => {
      const agentType = e.payload?.agent_type ?? e.payload?.agent_name ?? "unknown";
      const isStart = e.event_type === "subagent.start";
      const durationSecs = e.payload?.duration_seconds;
      let duration = "";
      if (durationSecs) {
        duration = durationSecs < 60 ? `${Math.round(durationSecs)}s` : `${Math.floor(durationSecs / 60)}m ${Math.round(durationSecs % 60)}s`;
      }
      return {
        id: e.id,
        agentType,
        storyId: e.story_id ?? "—",
        isActive: isStart,
        timestamp: e.timestamp,
        duration,
      };
    });
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
    <h2 class="text-xs font-medium text-gray-400 uppercase tracking-wider mb-3">Agent Activity</h2>

    <div v-if="agentEvents.length === 0" class="text-sm text-gray-500 py-4 text-center flex-1 flex items-center justify-center">
      No agent activity yet
    </div>

    <div v-else class="space-y-1 overflow-y-auto flex-1">
      <div
        v-for="entry in agentEvents"
        :key="entry.id"
        class="flex items-center gap-2 px-2 py-1.5 rounded hover:bg-surface-2/50 transition-colors animate-fade-in"
      >
        <span
          class="w-2 h-2 rounded-full shrink-0"
          :class="[AGENT_COLORS[entry.agentType] || 'bg-gray-500', { 'pulse-active': entry.isActive }]"
        />
        <span
          class="text-[10px] font-medium shrink-0"
          :class="AGENT_TEXT_COLORS[entry.agentType] || 'text-gray-400'"
        >{{ entry.agentType }}</span>
        <span class="text-[10px] font-mono text-gray-400 truncate min-w-0">{{ entry.storyId }}</span>
        <span class="text-[10px] text-gray-500 ml-auto shrink-0">
          <span v-if="entry.isActive" class="text-accent-blue">running</span>
          <span v-else class="text-accent-green">{{ entry.duration || 'done' }}</span>
        </span>
        <span class="text-[9px] text-gray-600 font-mono shrink-0 w-12 text-right">{{ relativeTime(entry.timestamp) }}</span>
      </div>
    </div>
  </div>
</template>
