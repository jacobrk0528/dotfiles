import { appendFile, readFile } from "node:fs/promises";
import { CONFIG_DIR, HISTORY_FILE, ensureDir } from "./paths";

export interface HistoryEntry {
  ts: number;
  sql: string;
  ok: boolean;
  error?: string;
  rows?: number;
  bytesProcessed?: number;
  elapsedMs?: number;
  jobId?: string;
  cacheHit?: boolean;
}

export async function appendHistory(entry: HistoryEntry): Promise<void> {
  await ensureDir(CONFIG_DIR);
  await appendFile(HISTORY_FILE, JSON.stringify(entry) + "\n", "utf8");
}

/** Newest first. */
export async function readHistory(limit = 500): Promise<HistoryEntry[]> {
  let raw = "";
  try {
    raw = await readFile(HISTORY_FILE, "utf8");
  } catch {
    return [];
  }
  const entries: HistoryEntry[] = [];
  for (const line of raw.split("\n")) {
    if (!line.trim()) continue;
    try {
      entries.push(JSON.parse(line) as HistoryEntry);
    } catch {
      // skip corrupt line
    }
  }
  return entries.reverse().slice(0, limit);
}
