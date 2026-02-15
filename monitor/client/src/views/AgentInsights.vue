<script setup lang="ts">
import { ref, watch, computed } from "vue";
import { useApi } from "@/composables/useApi";
import type { ToolUsageEntry, AgentDuration } from "@/types";

const props = defineProps<{
  runId: string;
}>();

const { fetchTools, fetchAgents } = useApi();

const tools = ref<ToolUsageEntry[]>([]);
const agents = ref<AgentDuration[]>([]);
const loading = ref(false);
const loadError = ref("");

async function load() {
  loading.value = true;
  loadError.value = "";
  try {
    const runParam = props.runId || undefined;
    const [t, a] = await Promise.all([fetchTools(runParam), fetchAgents(runParam)]);
    tools.value = t;
    agents.value = a;
  } catch (e: any) {
    loadError.value = e.message || "Failed to load agent data";
  } finally {
    loading.value = false;
  }
}

watch(() => props.runId, load, { immediate: true });

const hasData = computed(() => tools.value.length > 0 || agents.value.length > 0);

// Group tools by agent_type
const toolsByAgent = computed(() => {
  const map = new Map<string, ToolUsageEntry[]>();
  for (const t of tools.value) {
    const key = t.agent_type || "unknown";
    if (!map.has(key)) map.set(key, []);
    map.get(key)!.push(t);
  }
  return map;
});

const maxToolCount = computed(() => Math.max(...tools.value.map((t) => t.count), 1));
const maxDuration = computed(() => Math.max(...agents.value.map((a) => a.avg_duration_ms), 1));

const agentColors: Record<string, string> = {
  implementer: "bg-accent-blue",
  validator: "bg-accent-green",
  reviewer: "bg-accent-purple",
  merger: "bg-accent-cyan",
  unknown: "bg-gray-500",
};

const agentTextColors: Record<string, string> = {
  implementer: "text-accent-blue",
  validator: "text-accent-green",
  reviewer: "text-accent-purple",
  merger: "text-accent-cyan",
  unknown: "text-gray-400",
};

function formatMs(ms: number): string {
  if (ms < 1000) return `${Math.round(ms)}ms`;
  const sec = ms / 1000;
  if (sec < 60) return `${sec.toFixed(1)}s`;
  const min = Math.floor(sec / 60);
  const rem = (sec % 60).toFixed(0);
  return `${min}m ${rem}s`;
}
</script>

<template>
  <div class="h-full flex flex-col overflow-hidden">
    <div v-if="loading" class="flex items-center justify-center h-full text-gray-500 text-sm">
      Loading agent data...
    </div>

    <div v-else-if="loadError" class="flex items-center justify-center h-full text-accent-red text-sm">
      {{ loadError }}
    </div>

    <div v-else-if="!hasData" class="flex items-center justify-center h-full text-gray-500 text-sm">
      No agent data available
    </div>

    <div v-else class="flex-1 overflow-y-auto p-4 space-y-6">
      <!-- Agent Durations -->
      <section v-if="agents.length > 0">
        <h2 class="text-xs font-semibold text-gray-300 uppercase tracking-wider mb-3">Average Duration by Agent</h2>
        <div class="space-y-2">
          <div v-for="agent in agents" :key="agent.agent_type" class="flex items-center gap-3">
            <div class="w-24 shrink-0 text-xs font-mono text-right">
              <span :class="agentTextColors[agent.agent_type] || 'text-gray-400'">
                {{ agent.agent_type }}
              </span>
            </div>
            <div class="flex-1 h-5 bg-surface-2 rounded overflow-hidden relative">
              <div
                class="h-full rounded transition-all duration-300"
                :class="agentColors[agent.agent_type] || 'bg-gray-500'"
                :style="{ width: `${(agent.avg_duration_ms / maxDuration) * 100}%` }"
              />
              <span class="absolute inset-y-0 left-2 flex items-center text-[10px] font-mono text-white/80">
                {{ formatMs(agent.avg_duration_ms) }}
              </span>
            </div>
            <div class="w-14 shrink-0 text-xs text-gray-500 text-right font-mono">
              x{{ agent.count }}
            </div>
          </div>
        </div>
      </section>

      <!-- Tool Usage by Agent -->
      <section v-if="tools.length > 0">
        <h2 class="text-xs font-semibold text-gray-300 uppercase tracking-wider mb-3">Tool Usage by Agent</h2>

        <div v-for="[agentType, agentTools] in toolsByAgent" :key="agentType" class="mb-4">
          <h3 class="text-xs font-mono mb-2" :class="agentTextColors[agentType] || 'text-gray-400'">
            {{ agentType }}
          </h3>
          <div class="border border-surface-3 rounded-lg overflow-hidden">
            <table class="w-full text-xs">
              <thead>
                <tr class="bg-surface-2 text-gray-400">
                  <th class="text-left px-3 py-1.5 font-medium">Tool</th>
                  <th class="text-left px-3 py-1.5 font-medium w-1/2">Usage</th>
                  <th class="text-right px-3 py-1.5 font-medium">Count</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-surface-3">
                <tr v-for="tool in agentTools" :key="tool.tool_name" class="hover:bg-surface-2/50 transition-colors">
                  <td class="px-3 py-1.5 font-mono text-gray-300">{{ tool.tool_name }}</td>
                  <td class="px-3 py-1.5">
                    <div class="h-3 bg-surface-2 rounded overflow-hidden">
                      <div
                        class="h-full rounded"
                        :class="agentColors[agentType] || 'bg-gray-500'"
                        :style="{ width: `${(tool.count / maxToolCount) * 100}%` }"
                      />
                    </div>
                  </td>
                  <td class="px-3 py-1.5 text-right text-gray-400 font-mono">{{ tool.count }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </div>
  </div>
</template>
