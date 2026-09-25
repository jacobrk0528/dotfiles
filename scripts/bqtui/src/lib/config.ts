import { readFile, writeFile } from "node:fs/promises";
import { CONFIG_DIR, CONFIG_FILE, SESSION_FILE, DEFAULT_EXPORT_DIR, ensureDir } from "./paths";

export interface Config {
  /** Project queries run in (billing project). Defaults to the bq/gcloud default. */
  activeProject?: string;
  /** Projects shown in the browser in addition to the active project. */
  pinnedProjects: string[];
  /** Max rows fetched/displayed per query. */
  maxRows: number;
  /** Directory for CSV/JSON exports. */
  exportDir: string;
  /** Width of the dataset browser sidebar in columns. */
  sidebarWidth: number;
  /** Regions scanned for Dataform repositories. */
  dataformRegions: string[];
  /** Bytes fetched when previewing a Cloud Storage object. */
  previewBytes: number;
}

const DEFAULT_CONFIG: Config = {
  pinnedProjects: [],
  maxRows: 1000,
  exportDir: DEFAULT_EXPORT_DIR,
  sidebarWidth: 36,
  dataformRegions: ["us-central1", "us-east1", "us-east4", "us-west1", "europe-west1", "europe-west2"],
  previewBytes: 64 * 1024,
};

export async function loadConfig(): Promise<Config> {
  try {
    const raw = await readFile(CONFIG_FILE, "utf8");
    const parsed = JSON.parse(raw) as Partial<Config>;
    return { ...DEFAULT_CONFIG, ...parsed };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

export async function saveConfig(config: Config): Promise<void> {
  await ensureDir(CONFIG_DIR);
  await writeFile(CONFIG_FILE, JSON.stringify(config, null, 2) + "\n", "utf8");
}

// ---------------------------------------------------------------------------
// Session: which tabs were open, restored on next launch.

export interface SessionQueryTab {
  kind: "query";
  title: string;
  sql: string;
  savedPath?: string;
}

export interface SessionSchemaTab {
  kind: "schema";
  projectId: string;
  datasetId: string;
  tableId: string;
}

export interface SessionTextTab {
  kind: "text";
  title: string;
  subtitle?: string;
  language: "sql" | "sqlx" | "json" | "text";
  source?: unknown;
  meta?: [string, string][];
}

export type SessionTab = SessionQueryTab | SessionSchemaTab | SessionTextTab;

export interface Session {
  tabs: SessionTab[];
  activeIndex: number;
  showResults: boolean;
  showSidebar: boolean;
  sidebarSection?: "bigquery" | "dataform" | "storage";
}

export async function loadSession(): Promise<Session | null> {
  try {
    const raw = await readFile(SESSION_FILE, "utf8");
    const parsed = JSON.parse(raw) as Session;
    if (!Array.isArray(parsed.tabs)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export async function saveSession(session: Session): Promise<void> {
  await ensureDir(CONFIG_DIR);
  await writeFile(SESSION_FILE, JSON.stringify(session, null, 2) + "\n", "utf8");
}
