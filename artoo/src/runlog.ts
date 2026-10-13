// Per-run event log at runs/<timestamp>/events.jsonl, for replaying what Jev saw and chose.
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { dataDir } from "./paths.ts";
import { redactDeep } from "./privacy.ts";

export type RunLog = { dir: string; event: (type: string, data: Record<string, unknown>) => void };

const listeners: ((dir: string) => void)[] = [];

/** Called with each new run directory (conversation.ts links them from its log). */
export function onRunLog(fn: (dir: string) => void) {
  listeners.push(fn);
}

export function openRunLog(goal: string): RunLog {
  const runsDir = process.env.JEV_PILOT_RUNS ?? join(dataDir(), "runs");
  const dir = join(runsDir, new Date().toISOString().replaceAll(":", "-"));
  mkdirSync(dir, { recursive: true });
  const file = join(dir, "events.jsonl");
  const event: RunLog["event"] = (type, data) =>
    appendFileSync(file, JSON.stringify(redactDeep({ t: Date.now(), type, ...data })) + "\n");
  event("goal", { goal });
  for (const fn of listeners) fn(dir);
  return { dir, event };
}
