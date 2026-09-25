// Small, dependency-free helpers shared across the app.

export function formatBytes(bytes: number | undefined | null): string {
  if (bytes === undefined || bytes === null || Number.isNaN(bytes)) return "–";
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KiB", "MiB", "GiB", "TiB", "PiB"];
  let value = bytes;
  let unit = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return `${value < 10 ? value.toFixed(2) : value < 100 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
}

export function formatDuration(ms: number | undefined | null): string {
  if (ms === undefined || ms === null || Number.isNaN(ms)) return "–";
  if (ms < 1000) return `${Math.round(ms)} ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)} s`;
  const m = Math.floor(ms / 60_000);
  const s = Math.round((ms % 60_000) / 1000);
  return `${m}m ${s}s`;
}

export function formatNumber(n: number | undefined | null): string {
  if (n === undefined || n === null || Number.isNaN(n)) return "–";
  return n.toLocaleString("en-US");
}

// BigQuery on-demand analysis pricing (US multi-region) is $6.25 per TiB
// as of 2025. This is an estimate for display only; actual billing depends
// on the project's pricing model, region and free-tier usage.
const USD_PER_TIB = 6.25;
export function estimateCostUsd(bytes: number | undefined | null): string {
  if (bytes === undefined || bytes === null) return "–";
  const usd = (bytes / 1024 ** 4) * USD_PER_TIB;
  if (usd === 0) return "$0.00";
  if (usd < 0.01) return "<$0.01";
  return `$${usd.toFixed(2)}`;
}

export function formatTimestamp(epochMs: number | undefined | null): string {
  if (!epochMs) return "–";
  const d = new Date(epochMs);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function relativeTime(epochMs: number): string {
  const diff = Date.now() - epochMs;
  const s = Math.floor(diff / 1000);
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h}h ago`;
  const d = Math.floor(h / 24);
  return `${d}d ago`;
}

/** Render any cell value (string, null, nested struct/array) as display text. */
export function stringifyCell(value: unknown): string {
  if (value === null || value === undefined) return "NULL";
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  return JSON.stringify(value);
}

/** Truncate a string to `width` display cells, appending an ellipsis when cut. */
export function truncate(value: string, width: number): string {
  if (width <= 0) return "";
  if (value.length <= width) return value;
  if (width === 1) return "…";
  return value.slice(0, width - 1) + "…";
}

export function padRight(value: string, width: number): string {
  return truncate(value, width).padEnd(width, " ");
}

export function padLeft(value: string, width: number): string {
  return truncate(value, width).padStart(width, " ");
}

/** Collapse whitespace/newlines to a single-line preview. */
export function oneLine(text: string, max = 80): string {
  return truncate(text.replace(/\s+/g, " ").trim(), max);
}

export function pluralize(n: number, word: string): string {
  return `${formatNumber(n)} ${word}${n === 1 ? "" : "s"}`;
}
