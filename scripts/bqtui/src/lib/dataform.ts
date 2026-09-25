// Dataform via its REST API (there is no `gcloud dataform` command group).
// Also surfaces BigQuery Studio saved queries, which are single-file Dataform
// repositories under the hood.

import { cached, gapi, gapiAll } from "./gcloud";

const API = "https://dataform.googleapis.com/v1beta1";
export const DEFAULT_DATAFORM_REGIONS = ["us-central1", "us-east1", "us-east4", "us-west1", "europe-west1", "europe-west2"];

export interface DfRepository {
  name: string; // projects/p/locations/l/repositories/id
  id: string;
  projectId: string;
  location: string;
  displayName?: string;
  /** Set for BigQuery Studio single-file assets: "sql", "notebook", "data-canvas", ... */
  assetType?: string;
  isSavedQuery: boolean;
  gitUrl?: string;
  defaultBranch?: string;
  createTime?: string;
}

export interface DfWorkspace {
  name: string;
  id: string;
}

export interface DfEntry {
  path: string;
  isDir: boolean;
}

export interface DfCompilation {
  name: string;
  id: string;
  createTime?: string;
  workspace?: string;
  releaseConfig?: string;
  gitCommitish?: string;
  errorCount: number;
  errors: { message: string; path?: string }[];
}

export type DfActionType = "VIEW" | "TABLE" | "INCREMENTAL" | "MATERIALIZED_VIEW" | "ASSERTION" | "OPERATIONS" | "DECLARATION" | "UNKNOWN";

export interface DfAction {
  target: string; // db.schema.name
  filePath?: string;
  type: DfActionType;
  sql: string;
  dependencies: string[];
  disabled: boolean;
}

export interface DfInvocation {
  name: string;
  id: string;
  state: string;
  startTime?: string;
  endTime?: string;
  compilationResult?: string;
  workflowConfig?: string;
}

export interface DfInvocationAction {
  target: string;
  state: string;
  startTime?: string;
  endTime?: string;
  sql: string;
  failureReason?: string;
}

export interface DfConfig {
  id: string;
  kind: "release" | "workflow";
  gitCommitish?: string;
  cronSchedule?: string;
  timeZone?: string;
  releaseConfig?: string;
}

function idOf(name: string): string {
  return name.split("/").pop() ?? name;
}

function mapRepo(r: any, projectId: string, location: string): DfRepository {
  return {
    name: r.name,
    id: idOf(r.name),
    projectId,
    location,
    displayName: r.displayName,
    assetType: r.labels?.["single-file-asset-type"],
    isSavedQuery: r.labels?.["single-file-asset-type"] !== undefined,
    gitUrl: r.gitRemoteSettings?.url,
    defaultBranch: r.gitRemoteSettings?.effectiveDefaultBranch ?? r.gitRemoteSettings?.defaultBranch,
    createTime: r.createTime,
  };
}

/** Scan several regions concurrently; regions without access are skipped. */
export async function listRepositories(projectId: string, regions: string[], force = false): Promise<DfRepository[]> {
  return cached(
    `df:repos:${projectId}:${regions.join(",")}`,
    5 * 60 * 1000,
    async () => {
      const perRegion = await Promise.all(
        regions.map(async (loc) => {
          try {
            const repos = await gapiAll<any>(`${API}/projects/${projectId}/locations/${loc}/repositories?pageSize=100`, "repositories");
            return repos.map((r) => mapRepo(r, projectId, loc));
          } catch {
            return [];
          }
        }),
      );
      return perRegion.flat().sort((a, b) => (a.displayName ?? a.id).localeCompare(b.displayName ?? b.id));
    },
    force,
  );
}

export async function listWorkspaces(repo: DfRepository, force = false): Promise<DfWorkspace[]> {
  return cached(
    `df:ws:${repo.name}`,
    5 * 60 * 1000,
    async () => {
      const ws = await gapiAll<any>(`${API}/${repo.name}/workspaces?pageSize=100`, "workspaces");
      return ws.map((w) => ({ name: w.name, id: idOf(w.name) }));
    },
    force,
  );
}

/** Directory listing for a workspace, or for the repository's git HEAD when workspace is null. */
export async function queryDirectory(repo: DfRepository, workspace: DfWorkspace | null, path: string, force = false): Promise<DfEntry[]> {
  const base = workspace ? workspace.name : repo.name;
  const url = `${API}/${base}:queryDirectoryContents?pageSize=1000${path ? `&path=${encodeURIComponent(path)}` : ""}`;
  return cached(
    `df:dir:${base}:${path}`,
    2 * 60 * 1000,
    async () => {
      const entries = await gapiAll<any>(url, "directoryEntries");
      return entries
        .map((e) => ({ path: (e.file ?? e.directory) as string, isDir: e.directory !== undefined }))
        .filter((e) => e.path)
        .sort((a, b) => Number(b.isDir) - Number(a.isDir) || a.path.localeCompare(b.path));
    },
    force,
  );
}

export async function readFile(repo: DfRepository, workspace: DfWorkspace | null, path: string): Promise<string> {
  const base = workspace ? workspace.name : repo.name;
  const res = await gapi<any>(`${API}/${base}:readFile?path=${encodeURIComponent(path)}`);
  const b64 = res.fileContents ?? res.contents ?? "";
  return Buffer.from(b64, "base64").toString("utf8");
}

export async function listCompilations(repo: DfRepository, limit = 15, force = false): Promise<DfCompilation[]> {
  return cached(
    `df:cr:${repo.name}`,
    60 * 1000,
    async () => {
      const page = await gapi<any>(`${API}/${repo.name}/compilationResults?pageSize=${limit}`);
      const list = (page.compilationResults ?? []) as any[];
      return list
        .map((c) => ({
          name: c.name,
          id: idOf(c.name),
          createTime: c.createTime,
          workspace: c.workspace ? idOf(c.workspace) : undefined,
          releaseConfig: c.releaseConfig ? idOf(c.releaseConfig) : undefined,
          gitCommitish: c.gitCommitish,
          errorCount: (c.compilationErrors ?? []).length,
          errors: ((c.compilationErrors ?? []) as any[]).map((e) => ({ message: e.message, path: e.path })),
        }))
        .sort((a, b) => (b.createTime ?? "").localeCompare(a.createTime ?? ""));
    },
    force,
  );
}

function classify(a: any): DfActionType {
  if (a.relation) {
    const t = a.relation.relationType as string | undefined;
    if (t === "VIEW" || t === "TABLE" || t === "INCREMENTAL_TABLE" || t === "MATERIALIZED_VIEW") return t === "INCREMENTAL_TABLE" ? "INCREMENTAL" : t;
    return "TABLE";
  }
  if (a.assertion) return "ASSERTION";
  if (a.operations) return "OPERATIONS";
  if (a.declaration) return "DECLARATION";
  return "UNKNOWN";
}

function targetName(t: any): string {
  if (!t) return "?";
  return [t.database, t.schema, t.name].filter(Boolean).join(".");
}

export async function queryCompilationActions(compilationName: string, force = false): Promise<DfAction[]> {
  return cached(
    `df:cra:${compilationName}`,
    10 * 60 * 1000,
    async () => {
      const actions = await gapiAll<any>(`${API}/${compilationName}:query?pageSize=200`, "compilationResultActions", 50);
      return actions
        .map((a) => {
          const type = classify(a);
          let sql = "";
          if (a.relation) sql = a.relation.selectQuery ?? "";
          else if (a.assertion) sql = a.assertion.selectQuery ?? "";
          else if (a.operations) sql = ((a.operations.queries ?? []) as string[]).join("\n\n");
          const deps = ((a.relation?.dependencyTargets ?? a.assertion?.dependencyTargets ?? a.operations?.dependencyTargets ?? []) as any[]).map(targetName);
          return {
            target: targetName(a.target),
            filePath: a.filePath,
            type,
            sql: sql.replace(/^\s*\n/, ""),
            dependencies: deps,
            disabled: Boolean(a.relation?.disabled ?? a.assertion?.disabled ?? a.operations?.disabled),
          };
        })
        .sort((a, b) => (a.filePath ?? a.target).localeCompare(b.filePath ?? b.target));
    },
    force,
  );
}

export async function createCompilation(repo: DfRepository, workspace: DfWorkspace): Promise<DfCompilation> {
  const c = await gapi<any>(`${API}/${repo.name}/compilationResults`, { method: "POST", body: { workspace: workspace.name } });
  return {
    name: c.name,
    id: idOf(c.name),
    createTime: c.createTime,
    workspace: workspace.id,
    errorCount: (c.compilationErrors ?? []).length,
    errors: ((c.compilationErrors ?? []) as any[]).map((e) => ({ message: e.message, path: e.path })),
  };
}

export async function listInvocations(repo: DfRepository, limit = 15, force = false): Promise<DfInvocation[]> {
  return cached(
    `df:wi:${repo.name}`,
    30 * 1000,
    async () => {
      const page = await gapi<any>(`${API}/${repo.name}/workflowInvocations?pageSize=${limit}`);
      const list = (page.workflowInvocations ?? []) as any[];
      return list
        .map((w) => ({
          name: w.name,
          id: idOf(w.name),
          state: w.state ?? "UNKNOWN",
          startTime: w.invocationTiming?.startTime,
          endTime: w.invocationTiming?.endTime,
          compilationResult: w.compilationResult ? idOf(w.compilationResult) : undefined,
          workflowConfig: w.workflowConfig ? idOf(w.workflowConfig) : undefined,
        }))
        .sort((a, b) => (b.startTime ?? "").localeCompare(a.startTime ?? ""));
    },
    force,
  );
}

export async function queryInvocationActions(invocationName: string, force = false): Promise<DfInvocationAction[]> {
  return cached(
    `df:wia:${invocationName}`,
    30 * 1000,
    async () => {
      const actions = await gapiAll<any>(`${API}/${invocationName}:query?pageSize=200`, "workflowInvocationActions", 50);
      return actions.map((a) => ({
        target: targetName(a.target),
        state: a.state ?? "UNKNOWN",
        startTime: a.invocationTiming?.startTime,
        endTime: a.invocationTiming?.endTime,
        sql: a.bigqueryAction?.sqlScript ?? "",
        failureReason: a.failureReason,
      }));
    },
    force,
  );
}

export async function createInvocation(repo: DfRepository, compilationName: string): Promise<DfInvocation> {
  const w = await gapi<any>(`${API}/${repo.name}/workflowInvocations`, { method: "POST", body: { compilationResult: compilationName } });
  return { name: w.name, id: idOf(w.name), state: w.state ?? "RUNNING", startTime: w.invocationTiming?.startTime };
}

export async function cancelInvocation(invocationName: string): Promise<void> {
  await gapi(`${API}/${invocationName}:cancel`, { method: "POST", body: {} });
}

export async function listConfigs(repo: DfRepository, force = false): Promise<DfConfig[]> {
  return cached(
    `df:cfg:${repo.name}`,
    5 * 60 * 1000,
    async () => {
      const [rel, wf] = await Promise.all([
        gapiAll<any>(`${API}/${repo.name}/releaseConfigs?pageSize=100`, "releaseConfigs").catch(() => []),
        gapiAll<any>(`${API}/${repo.name}/workflowConfigs?pageSize=100`, "workflowConfigs").catch(() => []),
      ]);
      return [
        ...rel.map((r: any) => ({ id: idOf(r.name), kind: "release" as const, gitCommitish: r.gitCommitish, cronSchedule: r.cronSchedule, timeZone: r.timeZone })),
        ...wf.map((w: any) => ({
          id: idOf(w.name),
          kind: "workflow" as const,
          cronSchedule: w.cronSchedule,
          timeZone: w.timeZone,
          releaseConfig: w.releaseConfig ? idOf(w.releaseConfig) : undefined,
        })),
      ];
    },
    force,
  );
}

/** Content of a BigQuery Studio single-file asset (saved query SQL, or raw JSON for notebooks/canvases). */
export async function readSavedAsset(repo: DfRepository): Promise<{ path: string; content: string }> {
  const entries = await queryDirectory(repo, null, "");
  const file = entries.find((e) => !e.isDir && e.path === "content.sql") ?? entries.find((e) => !e.isDir);
  if (!file) throw new Error("Asset has no content file");
  return { path: file.path, content: await readFile(repo, null, file.path) };
}

export function consoleUrl(repo: DfRepository): string {
  return `https://console.cloud.google.com/bigquery/dataform/locations/${repo.location}/repositories/${repo.id}?project=${repo.projectId}`;
}
