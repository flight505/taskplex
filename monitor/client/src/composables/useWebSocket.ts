import { ref, type Ref } from "vue";
import type { MonitorEvent, WsMessage, Run } from "@/types";

const MAX_EVENTS = 500;

interface UseWebSocketReturn {
  events: Ref<MonitorEvent[]>;
  connected: Ref<boolean>;
  latestRun: Ref<Run | null>;
  clear: () => void;
}

export function useWebSocket(): UseWebSocketReturn {
  const events = ref<MonitorEvent[]>([]);
  const connected = ref(false);
  const latestRun = ref<Run | null>(null);

  let ws: WebSocket | null = null;
  let reconnectDelay = 1000;
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  let intentionallyClosed = false;

  function getWsUrl(): string {
    if (import.meta.env.PROD) {
      const proto = location.protocol === "https:" ? "wss:" : "ws:";
      return `${proto}//${location.host}/ws`;
    }
    return "ws://localhost:4444/ws";
  }

  function connect(): void {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    try {
      ws = new WebSocket(getWsUrl());
    } catch {
      scheduleReconnect();
      return;
    }

    ws.onopen = () => {
      connected.value = true;
      reconnectDelay = 1000;
    };

    ws.onmessage = (msgEvent: MessageEvent) => {
      try {
        const msg: WsMessage = JSON.parse(msgEvent.data);

        if (msg.type === "event") {
          events.value = [msg.event, ...events.value].slice(0, MAX_EVENTS);
        } else if (msg.type === "run.created") {
          latestRun.value = msg.run;
        } else if (msg.type === "run.updated") {
          latestRun.value = msg.run;
        }
      } catch {
        // ignore malformed messages
      }
    };

    ws.onclose = () => {
      connected.value = false;
      ws = null;
      if (!intentionallyClosed) {
        scheduleReconnect();
      }
    };

    ws.onerror = () => {
      connected.value = false;
      ws?.close();
    };
  }

  function scheduleReconnect(): void {
    if (reconnectTimer) clearTimeout(reconnectTimer);
    reconnectTimer = setTimeout(() => {
      reconnectDelay = Math.min(reconnectDelay * 2, 10000);
      connect();
    }, reconnectDelay);
  }

  function clear(): void {
    events.value = [];
  }

  // initial connection
  connect();

  return { events, connected, latestRun, clear };
}
