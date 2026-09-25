// Cloud Storage via `gcloud storage`.

import { basename, join } from "node:path";
import { cached, gcloudJson, runGcloud, parseGcloudError, GcloudError } from "./gcloud";

export interface Bucket {
  name: string;
  uri: string;
  location?: string;
  storageClass?: string;
  created?: string;
}

export interface StorageEntry {
  uri: string; // gs://bucket/path (no generation)
  name: string; // last path segment (with trailing slash for prefixes)
  isPrefix: boolean;
  size?: number;
  updated?: string;
  contentType?: string;
}

export interface ObjectInfo {
  uri: string;
  size?: number;
  contentType?: string;
  updated?: string;
  created?: string;
  storageClass?: string;
  md5?: string;
  generation?: string;
}

export async function listBuckets(projectId: string, force = false): Promise<Bucket[]> {
  return cached(
    `gcs:buckets:${projectId}`,
    5 * 60 * 1000,
    async () => {
      const list = await gcloudJson<any[]>(
        ["storage", "buckets", "list", `--project=${projectId}`, "--format=json(name,location,storageClass,timeCreated)"],
        "Failed to list buckets",
      );
      return list
        .map((b) => ({ name: b.name as string, uri: `gs://${b.name}/`, location: b.location, storageClass: b.storageClass, created: b.timeCreated }))
        .sort((a, b) => a.name.localeCompare(b.name));
    },
    force,
  );
}

function stripGeneration(url: string): string {
  const i = url.lastIndexOf("#");
  return i > 0 ? url.slice(0, i) : url;
}

/** One level of a bucket/prefix (prefixes first, then objects). */
export async function listEntries(uri: string, force = false): Promise<StorageEntry[]> {
  const norm = uri.endsWith("/") ? uri : uri + "/";
  return cached(
    `gcs:ls:${norm}`,
    2 * 60 * 1000,
    async () => {
      const list = await gcloudJson<any[]>(["storage", "ls", "--json", norm], `Failed to list ${norm}`);
      const entries: StorageEntry[] = [];
      for (const e of list) {
        const url = stripGeneration(e.url as string);
        if (e.type === "prefix") {
          const trimmed = url.endsWith("/") ? url.slice(0, -1) : url;
          entries.push({ uri: url, name: basename(trimmed) + "/", isPrefix: true });
        } else if (e.type === "cloud_object") {
          const m = e.metadata ?? {};
          const name = basename(url);
          if (!name) continue; // the prefix placeholder object itself
          entries.push({
            uri: url,
            name,
            isPrefix: false,
            size: m.size !== undefined ? Number(m.size) : undefined,
            updated: m.updated ?? m.timeCreated,
            contentType: m.contentType,
          });
        }
      }
      return entries.sort((a, b) => Number(b.isPrefix) - Number(a.isPrefix) || a.name.localeCompare(b.name));
    },
    force,
  );
}

export async function describeObject(uri: string): Promise<ObjectInfo> {
  const o = await gcloudJson<any>(
    ["storage", "objects", "describe", uri, "--format=json(size,content_type,update_time,creation_time,storage_class,md5_hash,generation)"],
    `Failed to describe ${uri}`,
  );
  return {
    uri,
    size: o.size !== undefined ? Number(o.size) : undefined,
    contentType: o.content_type,
    updated: o.update_time,
    created: o.creation_time,
    storageClass: o.storage_class,
    md5: o.md5_hash,
    generation: o.generation !== undefined ? String(o.generation) : undefined,
  };
}

export interface ObjectHead {
  text: string;
  binary: boolean;
  bytes: number;
  truncated: boolean;
}

/** First `maxBytes` of an object, decoded as UTF-8 when it looks like text. */
export async function headObject(uri: string, maxBytes = 64 * 1024, totalSize?: number): Promise<ObjectHead> {
  // `gcloud storage cat -r` fails when the range exceeds the object, so only
  // request a range for objects known (or suspected) to be larger.
  const useRange = totalSize === undefined || totalSize > maxBytes;
  const run = async (range: boolean) => {
    const args = ["storage", "cat", ...(range ? ["-r", `0-${maxBytes - 1}`] : []), uri];
    const proc = Bun.spawn(["gcloud", ...args], { stdout: "pipe", stderr: "pipe", stdin: "ignore" });
    const [buf, stderr, code] = await Promise.all([
      new Response(proc.stdout as ReadableStream).arrayBuffer(),
      new Response(proc.stderr as ReadableStream).text(),
      proc.exited,
    ]);
    return { bytes: new Uint8Array(buf), stderr, code };
  };
  let res = await run(useRange);
  if (res.code !== 0 && useRange && /Download not completed/i.test(res.stderr)) res = await run(false);
  if (res.code !== 0) throw new GcloudError(parseGcloudError(res.stderr, `Failed to read ${uri}`), res.stderr);
  const bytes = res.bytes.length > maxBytes ? res.bytes.slice(0, maxBytes) : res.bytes;
  let binary = false;
  for (let i = 0; i < Math.min(bytes.length, 4096); i++) {
    const b = bytes[i]!;
    if (b === 0 || (b < 7 && b !== 0) || (b > 13 && b < 32 && b !== 27)) {
      binary = true;
      break;
    }
  }
  const text = binary ? "" : new TextDecoder("utf-8", { fatal: false }).decode(bytes);
  const total = totalSize ?? res.bytes.length;
  return { text, binary, bytes: bytes.length, truncated: total > bytes.length };
}

export async function downloadObject(uri: string, destDir: string): Promise<string> {
  const dest = join(destDir, basename(uri));
  const { stderr, exitCode } = await runGcloud(["storage", "cp", uri, dest]);
  if (exitCode !== 0) throw new GcloudError(parseGcloudError(stderr, `Download failed for ${uri}`), stderr);
  return dest;
}

export function guessFormat(uri: string): "CSV" | "NEWLINE_DELIMITED_JSON" | "PARQUET" | "AVRO" | "ORC" | undefined {
  const lower = uri.toLowerCase().replace(/\.(gz|bz2|zst)$/, "");
  if (lower.endsWith(".csv") || lower.endsWith(".tsv")) return "CSV";
  if (lower.endsWith(".json") || lower.endsWith(".jsonl") || lower.endsWith(".ndjson")) return "NEWLINE_DELIMITED_JSON";
  if (lower.endsWith(".parquet")) return "PARQUET";
  if (lower.endsWith(".avro")) return "AVRO";
  if (lower.endsWith(".orc")) return "ORC";
  return undefined;
}

/** A ready-to-edit CREATE EXTERNAL TABLE statement for a file or prefix. */
export function externalTableSql(uri: string, projectId?: string): string {
  const format = guessFormat(uri) ?? "CSV";
  const pattern = uri.endsWith("/") ? `${uri}*` : uri;
  const table = uri.endsWith("/") ? basename(uri.slice(0, -1)) : basename(uri).replace(/\.[^.]+$/, "");
  const safe = (/^[0-9]/.test(table) ? "t_" : "") + (table.replace(/[^A-Za-z0-9_]/g, "_") || "external_table");
  const extra = format === "CSV" ? ",\n  skip_leading_rows = 1" : "";
  return `CREATE OR REPLACE EXTERNAL TABLE \`${projectId ?? "project"}.dataset.${safe}\`\nOPTIONS (\n  format = '${format}',\n  uris = ['${pattern}']${extra}\n);`;
}

export function loadDataSql(uri: string, projectId?: string): string {
  const format = guessFormat(uri) ?? "CSV";
  const pattern = uri.endsWith("/") ? `${uri}*` : uri;
  const table = uri.endsWith("/") ? basename(uri.slice(0, -1)) : basename(uri).replace(/\.[^.]+$/, "");
  const safe = (/^[0-9]/.test(table) ? "t_" : "") + (table.replace(/[^A-Za-z0-9_]/g, "_") || "loaded_table");
  const extra = format === "CSV" ? ",\n  skip_leading_rows = 1" : "";
  return `LOAD DATA OVERWRITE \`${projectId ?? "project"}.dataset.${safe}\`\nFROM FILES (\n  format = '${format}',\n  uris = ['${pattern}']${extra}\n);`;
}
