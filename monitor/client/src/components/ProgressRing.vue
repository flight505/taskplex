<script setup lang="ts">
import { computed } from "vue";

const props = withDefaults(defineProps<{
  value: number;
  size?: number;
  stroke?: number;
  color?: string;
}>(), {
  size: 40,
  stroke: 3,
  color: "#22c55e",
});

const radius = computed(() => (props.size - props.stroke) / 2);
const circumference = computed(() => 2 * Math.PI * radius.value);
const offset = computed(() => circumference.value * (1 - Math.min(1, Math.max(0, props.value))));
const center = computed(() => props.size / 2);
</script>

<template>
  <svg
    :width="size"
    :height="size"
    class="transform -rotate-90"
  >
    <circle
      :cx="center"
      :cy="center"
      :r="radius"
      fill="none"
      stroke="#242430"
      :stroke-width="stroke"
    />
    <circle
      :cx="center"
      :cy="center"
      :r="radius"
      fill="none"
      :stroke="color"
      :stroke-width="stroke"
      stroke-linecap="round"
      :stroke-dasharray="circumference"
      :stroke-dashoffset="offset"
      class="progress-ring-circle"
    />
    <text
      :x="center"
      :y="center"
      text-anchor="middle"
      dominant-baseline="central"
      class="transform rotate-90 origin-center fill-gray-200 text-[10px] font-medium"
      :style="{ fontSize: `${size * 0.25}px` }"
    >
      {{ Math.round(value * 100) }}%
    </text>
  </svg>
</template>
