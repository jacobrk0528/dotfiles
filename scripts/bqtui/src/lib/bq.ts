// Thin wrapper around the `bq` CLI. We shell out rather than using the
// BigQuery API client so this reuses whatever auth/project config the user
// already has set up for `bq` (gcloud ADC, ~/.bigqueryrc, etc.).

import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

export interface Project {
  projectId: string;
  friendlyName?: string;
}

export interface Dataset {
  projectId: string;
  datasetId: string;
  location?: string;
}

export interface Table {
  projectId: string;
  datasetId: string;
  tableId: string;
  type: string; // TABLE | VIEW | MATERIALIZED_VIEW | EXTERNAL | SNAPSHOT
  partitioning?: string;
}

export interface SchemaField {
  name: string;
  type: string;
  mode: string;
  description?: string;
  fields?: SchemaField[];
}

export interface TableInfo {
  projectId: string;
  datasetId: string;
  tableId: string;
  type: string;
  description?: string;
  schema: SchemaField[];
  numRows?: number;
  numBytes?: number;
  numPartitions?: number;
  creationTime?: number;
  lastModifiedTime?: number;
  expirationTime?: number;
  location?: string;
  timePartitioning?: { type: string; field?: string; expirationMs?: number; requirePartitionFilter?: boolean };
  rangePartitioning?: { field: string };
  clustering?: string[];
  viewQuery?: string;
  labels?: Record<string, string>;
}

export interface QueryStats {
  jobId: string;
  totalBytesProcessed?: number;
  totalBytesBilled?: number;
  cacheHit?: boolean;
  totalSlotMs?: number;
  elapsedMs?: number;
  statementType?: string;
  numDmlAffectedRows?: number;
  ddlOperationPerformed?: string;
  ddlTargetTable?: string;
}

export type Row = Record<string, unknown>;

export interface QueryResult {
  jobId: string;
  columns: string[];
  columnTypes: Record<string, string>;
  rows: Row[];
  /** Non-row output from bq (e.g. DDL/DML confirmation text). */
  message?: string;
  /** True when rows hit the max_rows cap and more probably exist. */
  truncated: boolean;
  elapsedMs: number;
  /** Bytes estimate from the dry run (available before job stats arrive). */
  estimatedBytes?: number;
}

export interface DryRunResult {
  bytesProcessed: number;
  schema: SchemaField[];
  statementType?: string;
}

export class BqError extends Error {
  constructor(message: string, public readonly raw: string) {
    super(message);
    this.name = "BqError";
  }
}

export class QueryCancelledError extends Error {
  constructor() {
    super("Query cancelled");
    this.name = "QueryCancelledError";
  }
}

// ---------------------------------------------------------------------------
// Active project (used for query execution/billing and unqualified names)

let activeProject: string | undefined;
export function setActiveProject(projectId: string | undefined): void {
  activeProject = projectId;
}
export function getActiveProject(): string | undefined {
  return activeProject;
}

// ---------------------------------------------------------------------------
// Process plumbing

interface BqProcess {
  proc: ReturnType<typeof Bun.spawn>;
  done: Promise<{ stdout: string; stderr: string; exitCode: number }>;
}

function spawnBq(args: string[], stdin?: string): BqProcess {
  const globalFlags = activeProject ? [`--project_id=${activeProject}`] : [];
  const proc = Bun.spawn(["bq", "--headless", ...globalFlags, ...args], {
    stdout: "pipe",
    stderr: "pipe",
    stdin: stdin === undefined ? "ignore" : "pipe",
    env: { ...process.env, PYTHONUNBUFFERED: "1" },
  });
  if (stdin !== undefined) {
    const w = proc.stdin as unknown as { write(s: string): void; end(): void };
    w.write(stdin);
    w.end();
  }
  const done = (async () => {
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout as ReadableStream).text(),
      new Response(proc.stderr as ReadableStream).text(),
      proc.exited,
    ]);
    return { stdout, stderr, exitCode };
  })();
  return { proc, done };
}

async function runBq(args: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  return spawnBq(args).done;
}

/**
 * bq prints "Waiting on bqjob_... Current status: DONE" progress text to
 * stdout for scripts (and to stdout for errors in --headless mode). Strip it
 * without regex backtracking: outputs can be single 100KB+ JSON lines.
 */
export function stripProgress(text: string): string {
  if (!text.includes("Waiting on bqjob_")) return text.trim();
  const lines = text.split("\n").map((line) => {
    if (!line.includes("Waiting on bqjob_")) return line;
    const starts = [line.indexOf("["), line.indexOf("{")].filter((i) => i >= 0);
    return starts.length > 0 ? line.slice(Math.min(...starts)) : "";
  });
  return lines.join("\n").trim();
}

/** Turn bq's multi-line stderr into a single readable message. */
export function parseBqError(stderr: string, fallback = "bq command failed"): string {
  const cleaned = stripProgress(stderr);
  if (!cleaned) return fallback;
  // Typical: "BigQuery error in query operation: Error processing job\n'proj:bqjob_...': <message>"
  const m = cleaned.match(/Error processing job\s*'[^']*':\s*([\s\S]*)/);
  if (m) return m[1]!.replace(/\s+/g, " ").trim();
  const m2 = cleaned.match(/BigQuery error in \w+ operation:\s*([\s\S]*)/);
  if (m2) return m2[1]!.replace(/\s+/g, " ").trim();
  return cleaned.replace(/\s+/g, " ").trim();
}

function parseJsonOutput(stdout: string): unknown {
  const cleaned = stripProgress(stdout);
  if (!cleaned) return null;
  try {
    return JSON.parse(cleaned);
  } catch {
    // Find the first JSON-looking start and try from there.
    const idx = Math.min(...["[", "{"].map((c) => cleaned.indexOf(c)).filter((i) => i >= 0));
    if (Number.isFinite(idx)) {
      try {
        return JSON.parse(cleaned.slice(idx));
      } catch {
        return null;
      }
    }
    return null;
  }
}

function toNumber(v: unknown): number | undefined {
  if (v === undefined || v === null || v === "") return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
}

function tableRef(projectId: string | undefined, datasetId: string, tableId?: string): string {
  const ds = projectId ? `${projectId}:${datasetId}` : datasetId;
  return tableId ? `${ds}.${tableId}` : ds;
}

// ---------------------------------------------------------------------------
// Project / dataset / table metadata

export async function getDefaultProject(): Promise<string | undefined> {
  try {
    const rc = await readFile(join(homedir(), ".bigqueryrc"), "utf8");
    const m = rc.match(/^\s*project_id\s*=\s*(\S+)/m);
    if (m) return m[1];
  } catch {
    // no rc file
  }
  try {
    const proc = Bun.spawn(["gcloud", "config", "get-value", "project"], { stdout: "pipe", stderr: "ignore" });
    const out = (await new Response(proc.stdout as ReadableStream).text()).trim();
    if ((await proc.exited) === 0 && out && out !== "(unset)") return out;
  } catch {
    // gcloud missing
  }
  return undefined;
}

export async function listProjects(): Promise<Project[]> {
  const { stdout, stderr, exitCode } = await runBq(["ls", "--format=json", "--projects", "--max_results=1000"]);
  if (exitCode !== 0) throw new BqError(parseBqError(stderr + "\n" + stdout, "Failed to list projects"), stderr);
  const parsed = (parseJsonOutput(stdout) as any[]) ?? [];
  return parsed
    .map((p) => ({ projectId: p.projectReference?.projectId ?? p.id, friendlyName: p.friendlyName }))
    .filter((p) => p.projectId);
}

export async function listDatasets(projectId?: string): Promise<Dataset[]> {
  const args = ["ls", "--format=json", "--max_results=1000"];
  if (projectId) args.push(`--project_id=${projectId}`);
  const { stdout, stderr, exitCode } = await runBq(args);
  if (exitCode !== 0) throw new BqError(parseBqError(stderr + "\n" + stdout, "Failed to list datasets"), stderr);
  const parsed = (parseJsonOutput(stdout) as any[]) ?? [];
  return parsed
    .map((d) => ({
      datasetId: d.datasetReference?.datasetId as string,
      projectId: (d.datasetReference?.projectId as string) ?? projectId ?? "",
      location: d.location as string | undefined,
    }))
    .filter((d) => d.datasetId)
    .sort((a, b) => a.datasetId.localeCompare(b.datasetId, undefined, { sensitivity: "base" }));
}

export async function listTables(projectId: string | undefined, datasetId: string): Promise<Table[]> {
  const { stdout, stderr, exitCode } = await runBq([
    "ls",
    "--format=json",
    "--max_results=10000",
    tableRef(projectId, datasetId),
  ]);
  if (exitCode !== 0) throw new BqError(parseBqError(stderr + "\n" + stdout, `Failed to list tables in ${datasetId}`), stderr);
  const parsed = (parseJsonOutput(stdout) as any[]) ?? [];
  return parsed
    .map((t) => ({
      projectId: (t.tableReference?.projectId as string) ?? projectId ?? "",
      datasetId: (t.tableReference?.datasetId as string) ?? datasetId,
      tableId: t.tableReference?.tableId as string,
      type: (t.type as string) || "TABLE",
      partitioning: t.timePartitioning?.type as string | undefined,
    }))
    .filter((t) => t.tableId)
    .sort((a, b) => a.tableId.localeCompare(b.tableId, undefined, { sensitivity: "base" }));
}

function mapSchemaFields(fields: any[] | undefined): SchemaField[] {
  return (fields ?? []).map((f) => ({
    name: f.name as string,
    type: (f.type as string) ?? "STRING",
    mode: (f.mode as string) || "NULLABLE",
    description: f.description as string | undefined,
    fields: f.fields ? mapSchemaFields(f.fields) : undefined,
  }));
}

export async function getTableInfo(projectId: string | undefined, datasetId: string, tableId: string): Promise<TableInfo> {
  const { stdout, stderr, exitCode } = await runBq(["show", "--format=json", tableRef(projectId, datasetId, tableId)]);
  if (exitCode !== 0) throw new BqError(parseBqError(stderr + "\n" + stdout, `Failed to describe ${datasetId}.${tableId}`), stderr);
  const p = (parseJsonOutput(stdout) as any) ?? {};
  return {
    projectId: p.tableReference?.projectId ?? projectId ?? "",
    datasetId: p.tableReference?.datasetId ?? datasetId,
    tableId: p.tableReference?.tableId ?? tableId,
    type: p.type ?? "TABLE",
    description: p.description,
    schema: mapSchemaFields(p.schema?.fields),
    numRows: toNumber(p.numRows),
    numBytes: toNumber(p.numBytes),
    numPartitions: toNumber(p.numPartitions),
    creationTime: toNumber(p.creationTime),
    lastModifiedTime: toNumber(p.lastModifiedTime),
    expirationTime: toNumber(p.expirationTime),
    location: p.location,
    timePartitioning: p.timePartitioning
      ? {
          type: p.timePartitioning.type,
          field: p.timePartitioning.field,
          expirationMs: toNumber(p.timePartitioning.expirationMs),
          requirePartitionFilter: p.requirePartitionFilter ?? p.timePartitioning.requirePartitionFilter,
        }
      : undefined,
    rangePartitioning: p.rangePartitioning ? { field: p.rangePartitioning.field } : undefined,
    clustering: p.clustering?.fields,
    viewQuery: p.view?.query ?? p.materializedView?.query,
    labels: p.labels,
  };
}

// ---------------------------------------------------------------------------
// Queries

export async function dryRun(sql: string): Promise<DryRunResult> {
  const { stdout, stderr, exitCode } = await runBq([
    "query",
    "--use_legacy_sql=false",
    "--dry_run",
    "--format=json",
    sql,
  ]);
  if (exitCode !== 0) throw new BqError(parseBqError(stderr + "\n" + stdout, "Dry run failed"), stderr);
  const p = (parseJsonOutput(stdout) as any) ?? {};
  const q = p.statistics?.query ?? {};
  return {
    bytesProcessed: toNumber(q.totalBytesProcessed ?? p.statistics?.totalBytesProcessed) ?? 0,
    schema: mapSchemaFields(q.schema?.fields),
    statementType: q.statementType,
  };
}

export async function fetchJobStats(jobId: string): Promise<QueryStats> {
  const { stdout, stderr, exitCode } = await runBq(["show", "--format=json", "-j", jobId]);
  if (exitCode !== 0) throw new BqError(parseBqError(stderr + "\n" + stdout, "Failed to fetch job stats"), stderr);
  const p = (parseJsonOutput(stdout) as any) ?? {};
  const s = p.statistics ?? {};
  const q = s.query ?? {};
  const start = toNumber(s.startTime);
  const end = toNumber(s.endTime);
  return {
    jobId,
    totalBytesProcessed: toNumber(q.totalBytesProcessed ?? s.totalBytesProcessed),
    totalBytesBilled: toNumber(q.totalBytesBilled),
    cacheHit: q.cacheHit,
    totalSlotMs: toNumber(q.totalSlotMs ?? s.totalSlotMs),
    elapsedMs: start !== undefined && end !== undefined ? end - start : undefined,
    statementType: q.statementType,
    numDmlAffectedRows: toNumber(q.numDmlAffectedRows),
    ddlOperationPerformed: q.ddlOperationPerformed,
    ddlTargetTable: q.ddlTargetTable
      ? `${q.ddlTargetTable.datasetId}.${q.ddlTargetTable.tableId}`
      : undefined,
  };
}

export async function cancelJob(jobId: string): Promise<void> {
  await runBq(["cancel", "--nosync", jobId]);
}

export function newJobId(): string {
  const stamp = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
  const rand = Math.random().toString(36).slice(2, 8);
  return `bqtui_${stamp}_${rand}`;
}

export interface RunningQuery {
  jobId: string;
  result: Promise<QueryResult>;
  cancel: () => Promise<void>;
}

/**
 * Start a query. Runs a concurrent dry run purely to learn the result
 * schema (bq's JSON output sorts keys alphabetically, which loses SELECT
 * column order) and a bytes estimate.
 */
export function startQuery(sql: string, options: { maxRows: number }): RunningQuery {
  const jobId = newJobId();
  const startedAt = Date.now();
  let cancelled = false;
  let rejectCancel: ((err: Error) => void) | undefined;
  const cancelSignal = new Promise<never>((_, reject) => {
    rejectCancel = reject;
  });

  const main = spawnBq([
    "query",
    "--use_legacy_sql=false",
    "--format=json",
    `--max_rows=${options.maxRows}`,
    `--job_id=${jobId}`,
    sql,
  ]);
  const dry = dryRun(sql).catch(() => null);

  const work = (async (): Promise<QueryResult> => {
    const { stdout, stderr, exitCode } = await main.done;
    if (cancelled) throw new QueryCancelledError();
    if (exitCode !== 0) throw new BqError(parseBqError(stderr + "\n" + stdout, "Query failed"), stderr);
    const elapsedMs = Date.now() - startedAt;

    const dryResult = await dry;
    const schema = dryResult?.schema ?? [];
    const parsed = parseJsonOutput(stdout);

    // Script queries return an array of per-statement results; use the last.
    let rows: Row[] = [];
    if (Array.isArray(parsed)) {
      if (parsed.length > 0 && Array.isArray(parsed[parsed.length - 1])) {
        for (let i = parsed.length - 1; i >= 0; i--) {
          if (Array.isArray(parsed[i]) && parsed[i].length > 0) {
            rows = parsed[i] as Row[];
            break;
          }
        }
      } else {
        rows = parsed as Row[];
      }
    }

    const rowKeys = rows.length > 0 ? Object.keys(rows[0]!) : [];
    const schemaNames = schema.map((f) => f.name);
    const columns =
      schemaNames.length > 0 && rowKeys.every((k) => schemaNames.includes(k))
        ? schemaNames.filter((n) => rows.length === 0 || rowKeys.includes(n))
        : rowKeys;
    const columnTypes: Record<string, string> = {};
    for (const f of schema) columnTypes[f.name] = f.mode === "REPEATED" ? `ARRAY<${f.type}>` : f.type;

    const message = parsed === null && stripProgress(stdout) ? stripProgress(stdout) : undefined;

    return {
      jobId,
      columns,
      columnTypes,
      rows,
      message,
      truncated: rows.length >= options.maxRows,
      elapsedMs,
      estimatedBytes: dryResult?.bytesProcessed,
    };
  })();
  // Swallow the late rejection of the abandoned branch after a cancel.
  work.catch(() => undefined);

  return {
    jobId,
    result: Promise.race([work, cancelSignal]),
    cancel: async () => {
      if (cancelled) return;
      cancelled = true;
      rejectCancel?.(new QueryCancelledError());
      try {
        main.proc.kill("SIGKILL");
      } catch {
        // already exited
      }
      // Ask BigQuery to stop the job server-side too; don't block the UI on it.
      cancelJob(jobId).catch(() => undefined);
    },
  };
}

/** Convenience wrapper used by non-interactive callers/tests. */
export async function runQuery(sql: string, maxRows = 1000): Promise<QueryResult> {
  return startQuery(sql, { maxRows }).result;
}
