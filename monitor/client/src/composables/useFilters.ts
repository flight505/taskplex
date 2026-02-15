import { ref, computed, type Ref, type ComputedRef } from "vue";
import type { MonitorEvent } from "@/types";

interface UseFiltersReturn {
  selectedRunId: Ref<string>;
  selectedStoryId: Ref<string>;
  selectedEventTypes: Ref<string[]>;
  selectedSource: Ref<string>;
  filteredEvents: (events: MonitorEvent[]) => MonitorEvent[];
  availableRuns: (events: MonitorEvent[]) => string[];
  availableStories: (events: MonitorEvent[]) => string[];
  availableEventTypes: (events: MonitorEvent[]) => string[];
  availableSources: (events: MonitorEvent[]) => string[];
  clearFilters: () => void;
}

export function useFilters(): UseFiltersReturn {
  const selectedRunId = ref("");
  const selectedStoryId = ref("");
  const selectedEventTypes = ref<string[]>([]);
  const selectedSource = ref("");

  function filteredEvents(events: MonitorEvent[]): MonitorEvent[] {
    return events.filter((e) => {
      if (selectedRunId.value && e.run_id !== selectedRunId.value) return false;
      if (selectedStoryId.value && e.story_id !== selectedStoryId.value) return false;
      if (selectedEventTypes.value.length > 0 && !selectedEventTypes.value.includes(e.event_type)) return false;
      if (selectedSource.value && e.source !== selectedSource.value) return false;
      return true;
    });
  }

  function availableRuns(events: MonitorEvent[]): string[] {
    const set = new Set<string>();
    for (const e of events) {
      if (e.run_id) set.add(e.run_id);
    }
    return Array.from(set).sort();
  }

  function availableStories(events: MonitorEvent[]): string[] {
    const set = new Set<string>();
    for (const e of events) {
      if (e.story_id) set.add(e.story_id);
    }
    return Array.from(set).sort();
  }

  function availableEventTypes(events: MonitorEvent[]): string[] {
    const set = new Set<string>();
    for (const e of events) {
      if (e.event_type) set.add(e.event_type);
    }
    return Array.from(set).sort();
  }

  function availableSources(events: MonitorEvent[]): string[] {
    const set = new Set<string>();
    for (const e of events) {
      if (e.source) set.add(e.source);
    }
    return Array.from(set).sort();
  }

  function clearFilters(): void {
    selectedRunId.value = "";
    selectedStoryId.value = "";
    selectedEventTypes.value = [];
    selectedSource.value = "";
  }

  return {
    selectedRunId,
    selectedStoryId,
    selectedEventTypes,
    selectedSource,
    filteredEvents,
    availableRuns,
    availableStories,
    availableEventTypes,
    availableSources,
    clearFilters,
  };
}
