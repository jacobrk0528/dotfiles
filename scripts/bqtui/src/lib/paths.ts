import { homedir } from "node:os";
import { join } from "node:path";
import { mkdir } from "node:fs/promises";

export const CONFIG_DIR = join(homedir(), ".config", "bqtui");
export const QUERIES_DIR = join(CONFIG_DIR, "queries");
export const CONFIG_FILE = join(CONFIG_DIR, "config.json");
export const SESSION_FILE = join(CONFIG_DIR, "session.json");
export const HISTORY_FILE = join(CONFIG_DIR, "history.jsonl");
export const DEFAULT_EXPORT_DIR = join(homedir(), "Downloads");

export async function ensureDir(dir: string): Promise<void> {
  await mkdir(dir, { recursive: true });
}
