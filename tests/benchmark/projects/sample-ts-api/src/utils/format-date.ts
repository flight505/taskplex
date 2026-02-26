// BUG: S001 — missing default export. Some modules import as default.

export function formatDate(date: Date): string {
  return date.toISOString().split("T")[0];
}

export function formatDateTime(date: Date): string {
  return date.toISOString().replace("T", " ").replace("Z", "");
}

export function formatRelative(date: Date): string {
  const diff = Date.now() - date.getTime();
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return `${seconds}s ago`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return formatDate(date);
}
