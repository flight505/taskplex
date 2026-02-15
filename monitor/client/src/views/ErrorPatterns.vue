<script setup lang="ts">
import { ref, watch, computed } from "vue";
import { useApi } from "@/composables/useApi";
import type { ErrorBreakdown } from "@/types";

const props = defineProps<{
  runId: string;
}>();

const { fetchErrors } = useApi();

const errors = ref<ErrorBreakdown[]>([]);
const loading = ref(false);
const loadError = ref("");

async function load() {
  loading.value = true;
  loadError.value = "";
  try {
    errors.value = await fetchErrors(props.runId || undefined);
  } catch (e: any) {
    loadError.value = e.message || "Failed to load errors";
  } finally {
    loading.value = false;
  }
}

watch(() => props.runId, load, { immediate: true });

const totalErrors = computed(() => errors.value.reduce((sum, e) => sum + e.count, 0));
const maxCount = computed(() => Math.max(...errors.value.map((e) => e.count), 1));

const categoryColors: Record<string, string> = {
  env_missing: "bg-accent-yellow",
  test_failure: "bg-accent-red",
  timeout: "bg-accent-purple",
  code_error: "bg-accent-red/70",
  dependency_missing: "bg-accent-cyan",
  unknown: "bg-gray-500",
};

const categoryTextColors: Record<string, string> = {
  env_missing: "text-accent-yellow",
  test_failure: "text-accent-red",
  timeout: "text-accent-purple",
  code_error: "text-accent-red/70",
  dependency_missing: "text-accent-cyan",
  unknown: "text-gray-400",
};
</script>

<template>
  <div class="h-full flex flex-col overflow-hidden">
    <div v-if="loading" class="flex items-center justify-center h-full text-gray-500 text-sm">
      Loading errors...
    </div>

    <div v-else-if="loadError" class="flex items-center justify-center h-full text-accent-red text-sm">
      {{ loadError }}
    </div>

    <div v-else-if="errors.length === 0" class="flex items-center justify-center h-full text-gray-500 text-sm">
      No errors recorded
    </div>

    <div v-else class="flex-1 overflow-y-auto p-4 space-y-6">
      <!-- Summary -->
      <div class="text-xs text-gray-400">
        {{ totalErrors }} total error{{ totalErrors !== 1 ? "s" : "" }} across {{ errors.length }} categor{{ errors.length !== 1 ? "ies" : "y" }}
      </div>

      <!-- Bar chart -->
      <div class="space-y-2">
        <div v-for="err in errors" :key="err.category" class="flex items-center gap-3">
          <div class="w-36 shrink-0 text-xs font-mono text-gray-300 text-right">
            {{ err.category }}
          </div>
          <div class="flex-1 h-5 bg-surface-2 rounded overflow-hidden relative">
            <div
              class="h-full rounded transition-all duration-300"
              :class="categoryColors[err.category] || 'bg-gray-500'"
              :style="{ width: `${(err.count / maxCount) * 100}%` }"
            />
            <span class="absolute inset-y-0 left-2 flex items-center text-[10px] font-mono text-white/80">
              {{ err.count }}
            </span>
          </div>
        </div>
      </div>

      <!-- Detail table -->
      <div class="border border-surface-3 rounded-lg overflow-hidden">
        <table class="w-full text-xs">
          <thead>
            <tr class="bg-surface-2 text-gray-400">
              <th class="text-left px-3 py-2 font-medium">Story</th>
              <th class="text-left px-3 py-2 font-medium">Category</th>
              <th class="text-right px-3 py-2 font-medium">Count</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-surface-3">
            <template v-for="err in errors" :key="err.category">
              <tr v-for="story in err.stories" :key="`${err.category}-${story}`" class="hover:bg-surface-2/50 transition-colors">
                <td class="px-3 py-1.5 font-mono text-gray-300">{{ story }}</td>
                <td class="px-3 py-1.5">
                  <span
                    class="px-1.5 py-0.5 rounded text-[10px] font-medium"
                    :class="[categoryTextColors[err.category] || 'text-gray-400', 'bg-surface-3']"
                  >
                    {{ err.category }}
                  </span>
                </td>
                <td class="px-3 py-1.5 text-right text-gray-400 font-mono">{{ err.count }}</td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
