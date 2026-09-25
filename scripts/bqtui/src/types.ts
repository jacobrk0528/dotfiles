import type { QueryResult, QueryStats, TableInfo } from "./lib/bq";

export interface QueryTab {
  id: string;
  kind: "query";
  title: string;
  /** Snapshot of the editor content (refreshed whenever the tab is left). */
  sql: string;
  savedPath?: string;
  dirty: boolean;
  result: QueryResult | null;
  stats: QueryStats | null;
  error: string | null;
  runningJobId: string | null;
  startedAt: number | null;
  /** Dry-run estimate for the current text (bytes), if computed. */
  estimate: { bytes: number; sqlHash: string } | null;
}

export interface SchemaTab {
  id: string;
  kind: "schema";
  title: string;
  projectId: string;
  datasetId: string;
  tableId: string;
  info: TableInfo | "loading" | { error: string };
}

export type TextSource =
  | { type: "gcs"; uri: string; size?: number }
  | { type: "dataform-file"; repoName: string; workspaceName: string | null; path: string }
  | { type: "dataform-action"; compilationName: string; target: string }
  | { type: "dataform-invocation"; invocationName: string; target: string }
  | { type: "studio-asset"; repoName: string };

export interface TextTab {
  id: string;
  kind: "text";
  title: string;
  subtitle?: string;
  language: "sql" | "sqlx" | "json" | "text";
  content: string | "loading" | { error: string };
  /** Label/value pairs shown above the content. */
  meta: [string, string][];
  source?: TextSource;
  /** Reloads the content (set by whoever created the tab). */
  reload?: () => Promise<{ content: string; meta?: [string, string][] }>;
}

export type Tab = QueryTab | SchemaTab | TextTab;

export type Pane = "browser" | "main" | "results";

export type SidebarSection = "bigquery" | "dataform" | "storage";
export const SIDEBAR_SECTIONS: { id: SidebarSection; label: string }[] = [
  { id: "bigquery", label: "BigQuery" },
  { id: "dataform", label: "Dataform" },
  { id: "storage", label: "Storage" },
];

export type Overlay =
  | { kind: "none" }
  | { kind: "help" }
  | { kind: "save" }
  | { kind: "open" }
  | { kind: "history" }
  | { kind: "projects" }
  | { kind: "row"; rowIndex: number }
  | { kind: "confirm-close"; tabId: string }
  | { kind: "confirm"; message: string; action: () => void }
  | { kind: "goto" };
