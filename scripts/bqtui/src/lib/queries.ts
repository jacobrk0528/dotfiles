import { join, basename } from "node:path";
import { readdir, readFile, writeFile, unlink, stat } from "node:fs/promises";
import { QUERIES_DIR, ensureDir } from "./paths";

export interface SavedQuery {
  name: string;
  path: string;
  modifiedMs: number;
}

function sanitizeName(name: string): string {
  const trimmed = name.trim().replace(/\s+/g, "-");
  const safe = trimmed.replace(/[^a-zA-Z0-9._-]/g, "");
  return safe || `query-${Date.now()}`;
}

export async function listSavedQueries(): Promise<SavedQuery[]> {
  await ensureDir(QUERIES_DIR);
  const entries = await readdir(QUERIES_DIR);
  const result: SavedQuery[] = [];
  for (const f of entries) {
    if (!f.endsWith(".sql")) continue;
    const path = join(QUERIES_DIR, f);
    let modifiedMs = 0;
    try {
      modifiedMs = (await stat(path)).mtimeMs;
    } catch {
      // ignore
    }
    result.push({ name: f.replace(/\.sql$/, ""), path, modifiedMs });
  }
  return result.sort((a, b) => b.modifiedMs - a.modifiedMs);
}

export async function saveQuery(name: string, sql: string): Promise<string> {
  await ensureDir(QUERIES_DIR);
  const path = join(QUERIES_DIR, `${sanitizeName(name)}.sql`);
  await writeFile(path, sql.endsWith("\n") ? sql : sql + "\n", "utf8");
  return path;
}

export async function saveQueryToPath(path: string, sql: string): Promise<void> {
  await writeFile(path, sql.endsWith("\n") ? sql : sql + "\n", "utf8");
}

export async function loadQuery(path: string): Promise<string> {
  return (await readFile(path, "utf8")).replace(/\s+$/, "");
}

export async function deleteQuery(path: string): Promise<void> {
  await unlink(path);
}

export function queryNameFromPath(path: string): string {
  return basename(path).replace(/\.sql$/, "");
}

export function exportPath(exportDir: string, extension: "csv" | "json" | "tsv", label?: string): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const base = label ? sanitizeName(label) : "results";
  return join(exportDir, `bqtui-${base}-${stamp}.${extension}`);
}

export async function writeExport(path: string, content: string): Promise<void> {
  await ensureDir(join(path, ".."));
  await writeFile(path, content, "utf8");
}
