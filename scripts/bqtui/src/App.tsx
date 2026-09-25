import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from "react";
import { useKeyboard, useRenderer, useTerminalDimensions } from "@opentui/react";
import type { TextareaRenderable } from "@opentui/core";
import {
  dryRun,
  fetchJobStats,
  getTableInfo,
  setActiveProject,
  startQuery,
  QueryCancelledError,
  type QueryResult,
  type Row,
  type RunningQuery,
} from "./lib/bq";
import { copyToClipboard } from "./lib/clipboard";
import { resultToCsv, resultToJson, resultToTsv } from "./lib/csv";
import { formatSql } from "./lib/format";
import { appendHistory, type HistoryEntry } from "./lib/history";
import { exportPath, saveQuery, saveQueryToPath, writeExport, type SavedQuery } from "./lib/queries";
import { saveConfig, saveSession, type Config, type Session } from "./lib/config";
import { theme } from "./lib/theme";
import { estimateCostUsd, formatBytes, formatNumber, oneLine } from "./lib/util";
import { activeTab as getActiveTab, makeQueryTab, makeSchemaTab, makeTextTab, nextTabId, tabsReducer, type TabsState } from "./state/tabs";
import { SIDEBAR_SECTIONS, type Overlay, type Pane, type QueryTab, type SchemaTab, type SidebarSection, type Tab, type TextSource, type TextTab } from "./types";
import { reloadFor } from "./lib/textSources";
import { DEFAULT_DATAFORM_REGIONS } from "./lib/dataform";
import { DatasetBrowser, tableReference, type TableRef } from "./components/DatasetBrowser";
import { DataformBrowser } from "./components/DataformBrowser";
import { StorageBrowser } from "./components/StorageBrowser";
import { TextView } from "./components/TextView";
import { Editor } from "./components/Editor";
import { ResultsGrid } from "./components/ResultsGrid";
import { SchemaView } from "./components/SchemaView";
import { TabBar } from "./components/TabBar";
import { StatusBar, type StatusKind } from "./components/StatusBar";
import { HelpOverlay } from "./components/HelpOverlay";
import { SaveDialog } from "./components/SaveDialog";
import { OpenDialog } from "./components/OpenDialog";
import { HistoryOverlay } from "./components/HistoryOverlay";
import { ProjectPicker } from "./components/ProjectPicker";
import { RowDetailOverlay } from "./components/RowDetailOverlay";
import { ConfirmDialog } from "./components/ConfirmDialog";

export interface AppProps {
  config: Config;
  session: Session | null;
  defaultProject?: string;
}

const STATUS_HEIGHT = 3;
const TABBAR_HEIGHT = 1;

function restoreTabs(session: Session | null): TabsState {
  if (!session || session.tabs.length === 0) {
    const first = makeQueryTab("query-1", "Query 1");
    return { tabs: [first], activeId: first.id, counter: 2 };
  }
  let counter = 1;
  const tabs: Tab[] = session.tabs.map((t, i) => {
    if (t.kind === "schema") return makeSchemaTab(t.projectId, t.datasetId, t.tableId);
    if (t.kind === "text") {
      const source = t.source as TextSource | undefined;
      return makeTextTab(`text:restored:${i}:${t.title}`, t.title, t.language, {
        subtitle: t.subtitle,
        meta: t.meta ?? [],
        source,
        reload: reloadFor(source, 64 * 1024),
        content: source ? "loading" : { error: "This tab could not be restored" },
      });
    }
    const m = t.title.match(/^Query (\d+)$/);
    if (m) counter = Math.max(counter, Number(m[1]) + 1);
    return makeQueryTab(`query-${i + 1}-${Date.now().toString(36)}`, t.title, t.sql, t.savedPath);
  });
  const active = tabs[Math.min(Math.max(0, session.activeIndex), tabs.length - 1)]!;
  return { tabs, activeId: active.id, counter: Math.max(counter, tabs.filter((t) => t.kind === "query").length + 1) };
}

export function App({ config: initialConfig, session, defaultProject }: AppProps) {
  const renderer = useRenderer();
  const { width: W, height: H } = useTerminalDimensions();

  const [config, setConfig] = useState<Config>(initialConfig);
  const [activeProject, setActiveProjectState] = useState<string | undefined>(initialConfig.activeProject ?? defaultProject);
  const [tabsState, dispatch] = useReducer(tabsReducer, session, restoreTabs);
  const [pane, setPane] = useState<Pane>("main");
  const [overlay, setOverlay] = useState<Overlay>({ kind: "none" });
  const [showResults, setShowResults] = useState(session?.showResults ?? true);
  const [showSidebar, setShowSidebar] = useState(session?.showSidebar ?? true);
  const [sidebarSection, setSidebarSection] = useState<SidebarSection>(session?.sidebarSection ?? "bigquery");
  const [zoomed, setZoomed] = useState(false);
  const [status, setStatusState] = useState<{ message: string; kind: StatusKind }>({ message: "Ready", kind: "info" });
  const [textInputActive, setTextInputActive] = useState(false);
  const [detailRow, setDetailRow] = useState<{ row: Row; index: number } | null>(null);

  const editorRef = useRef<TextareaRenderable | null>(null);
  const tabsRef = useRef(tabsState);
  tabsRef.current = tabsState;
  const configRef = useRef(config);
  configRef.current = config;
  const runningRef = useRef<Map<string, RunningQuery>>(new Map());
  const lastSavedRef = useRef<Map<string, string>>(new Map());
  const loadingTextRef = useRef<Set<string>>(new Set());
  const estimateTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sessionTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const active = getActiveTab(tabsState);
  const activeQuery = active?.kind === "query" ? active : null;
  const activeSchema = active?.kind === "schema" ? active : null;
  const activeText = active?.kind === "text" ? active : null;
  const projects = useMemo(() => {
    const list = activeProject ? [activeProject] : [];
    for (const p of config.pinnedProjects) if (!list.includes(p)) list.push(p);
    return list;
  }, [activeProject, config.pinnedProjects]);

  const setStatus = useCallback((message: string, kind: StatusKind = "info") => {
    setStatusState({ message, kind });
  }, []);

  useEffect(() => {
    renderer.setTerminalTitle(activeProject ? `bqtui — ${activeProject}` : "bqtui");
  }, [renderer, activeProject]);

  // Keep the bq wrapper's --project_id in sync with the active project.
  useEffect(() => {
    setActiveProject(activeProject);
  }, [activeProject]);

  const switchProject = useCallback(
    (projectId: string) => {
      setActiveProjectState(projectId);
      const next = { ...configRef.current, activeProject: projectId };
      setConfig(next);
      saveConfig(next).catch(() => undefined);
      setStatusState({ message: `Active project: ${projectId} (queries run and bill here)`, kind: "success" });
    },
    [],
  );

  // Seed "last saved" content for restored tabs so they don't all show dirty.
  useEffect(() => {
    for (const t of tabsRef.current.tabs) {
      if (t.kind === "query" && !lastSavedRef.current.has(t.id)) lastSavedRef.current.set(t.id, t.savedPath ? t.sql : "");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ------------------------------------------------------------------ helpers
  const currentSql = useCallback((): string => {
    const ta = editorRef.current;
    if (ta) return ta.plainText;
    const t = getActiveTab(tabsRef.current);
    return t?.kind === "query" ? t.sql : "";
  }, []);

  /** Persist the live editor text into the active tab before switching away. */
  const snapshotActive = useCallback(() => {
    const t = getActiveTab(tabsRef.current);
    const ta = editorRef.current;
    if (t?.kind === "query" && ta) dispatch({ type: "snapshot", id: t.id, sql: ta.plainText });
  }, []);

  const activateTab = useCallback(
    (id: string) => {
      if (id === tabsRef.current.activeId) return;
      snapshotActive();
      dispatch({ type: "activate", id });
      setPane("main");
      setDetailRow(null);
    },
    [snapshotActive],
  );

  const addQueryTab = useCallback(
    (title?: string, sql = "", savedPath?: string): QueryTab => {
      snapshotActive();
      const n = tabsRef.current.counter;
      const tab = makeQueryTab(`query-${Date.now().toString(36)}-${n}`, title ?? `Query ${n}`, sql, savedPath);
      lastSavedRef.current.set(tab.id, savedPath ? sql : "");
      dispatch({ type: "add", tab });
      setPane("main");
      return tab;
    },
    [snapshotActive],
  );

  const loadTextTab = useCallback((tab: TextTab) => {
    if (!tab.reload) return;
    dispatch({ type: "update", id: tab.id, patch: { content: "loading" } });
    tab
      .reload()
      .then((r) => dispatch({ type: "update", id: tab.id, patch: { content: r.content, meta: r.meta ?? tab.meta } }))
      .catch((err: any) => dispatch({ type: "update", id: tab.id, patch: { content: { error: err.message ?? String(err) } } }));
  }, []);

  const openTextTab = useCallback(
    (tab: TextTab) => {
      const existing = tabsRef.current.tabs.find((t) => t.id === tab.id);
      snapshotActive();
      if (existing) {
        dispatch({ type: "activate", id: tab.id });
      } else {
        dispatch({ type: "add", tab });
        loadTextTab(tab);
      }
      setPane("main");
    },
    [loadTextTab, snapshotActive],
  );

  // Restored text tabs load lazily when first shown.
  useEffect(() => {
    if (activeText && activeText.content === "loading" && activeText.reload && !loadingTextRef.current.has(activeText.id)) {
      loadingTextRef.current.add(activeText.id);
      loadTextTab(activeText);
    }
  }, [activeText?.id, activeText?.content === "loading", loadTextTab]);

  const closeTab = useCallback(
    (id: string, force = false) => {
      const t = tabsRef.current.tabs.find((x) => x.id === id);
      if (!t) return;
      if (t.kind === "query") {
        const sql = id === tabsRef.current.activeId ? currentSql() : t.sql;
        const dirty = sql.trim() !== "" && sql !== (lastSavedRef.current.get(id) ?? "");
        if (dirty && !force) {
          setOverlay({ kind: "confirm-close", tabId: id });
          return;
        }
        runningRef.current.get(id)?.cancel();
        runningRef.current.delete(id);
        lastSavedRef.current.delete(id);
      }
      dispatch({ type: "close", id });
      if (tabsRef.current.tabs.length <= 1) {
        const n = tabsRef.current.counter;
        const fresh = makeQueryTab(`query-${Date.now().toString(36)}-${n}`, `Query ${n}`);
        lastSavedRef.current.set(fresh.id, "");
        dispatch({ type: "add", tab: fresh });
      }
      setOverlay({ kind: "none" });
      setPane("main");
    },
    [currentSql],
  );

  const copy = useCallback(
    async (text: string, label: string) => {
      try {
        await copyToClipboard(text);
        setStatus(`Copied ${label} to clipboard`, "success");
      } catch (err: any) {
        setStatus(`Copy failed: ${err.message}`, "error");
      }
    },
    [setStatus],
  );

  const insertIntoEditor = useCallback(
    (text: string) => {
      const t = getActiveTab(tabsRef.current);
      if (t?.kind === "query" && editorRef.current) {
        editorRef.current.insertText(text);
        return;
      }
      const target = tabsRef.current.tabs.find((x): x is QueryTab => x.kind === "query");
      if (target) {
        dispatch({ type: "snapshot", id: target.id, sql: target.sql ? `${target.sql}\n${text}` : text });
        activateTab(target.id);
      } else {
        addQueryTab(undefined, text);
      }
    },
    [activateTab, addQueryTab],
  );

  // ------------------------------------------------------------------ queries
  const finishQuery = useCallback(
    (tabId: string, sql: string, res: QueryResult) => {
      dispatch({ type: "update", id: tabId, patch: { result: res, error: null, runningJobId: null, stats: null } });
      runningRef.current.delete(tabId);
      const summary = res.message
        ? oneLine(res.message, 80)
        : `${formatNumber(res.rows.length)} row${res.rows.length === 1 ? "" : "s"}${res.truncated ? " (capped)" : ""}`;
      setStatus(`Query finished: ${summary}`, "success");
      const entry: HistoryEntry = { ts: Date.now(), sql, ok: true, rows: res.rows.length, elapsedMs: res.elapsedMs, jobId: res.jobId };
      fetchJobStats(res.jobId)
        .then((stats) => {
          dispatch({ type: "update", id: tabId, patch: { stats } });
          appendHistory({ ...entry, bytesProcessed: stats.totalBytesProcessed, cacheHit: stats.cacheHit, elapsedMs: stats.elapsedMs ?? res.elapsedMs });
        })
        .catch(() => appendHistory(entry));
    },
    [setStatus],
  );

  const runSql = useCallback(
    (tabId: string, sql: string) => {
      if (!sql.trim()) {
        setStatus("Nothing to run: the editor is empty", "error");
        return;
      }
      if (runningRef.current.has(tabId)) {
        setStatus("A query is already running in this tab (Esc cancels it)", "error");
        return;
      }
      const running = startQuery(sql, { maxRows: configRef.current.maxRows });
      runningRef.current.set(tabId, running);
      dispatch({
        type: "update",
        id: tabId,
        patch: { runningJobId: running.jobId, startedAt: Date.now(), error: null, result: null, stats: null },
      });
      setShowResults(true);
      setStatus(`Running query… (job ${running.jobId})`);
      running.result
        .then((res) => finishQuery(tabId, sql, res))
        .catch((err: any) => {
          runningRef.current.delete(tabId);
          if (err instanceof QueryCancelledError) {
            dispatch({ type: "update", id: tabId, patch: { runningJobId: null, error: null } });
            setStatus("Query cancelled");
            return;
          }
          const message = err?.message ?? String(err);
          dispatch({ type: "update", id: tabId, patch: { runningJobId: null, error: message } });
          setStatus(`Query failed: ${oneLine(message, 120)}`, "error");
          appendHistory({ ts: Date.now(), sql, ok: false, error: message });
        });
    },
    [finishQuery, setStatus],
  );

  const runActive = useCallback(() => {
    const t = getActiveTab(tabsRef.current);
    if (t?.kind !== "query") {
      setStatus("Switch to a query tab to run SQL (Ctrl+T opens one)", "error");
      return;
    }
    const ta = editorRef.current;
    const selection = ta?.hasSelection() ? ta.getSelectedText() : "";
    const sql = selection.trim() ? selection : currentSql();
    runSql(t.id, sql);
  }, [currentSql, runSql, setStatus]);

  const cancelActive = useCallback(() => {
    const t = getActiveTab(tabsRef.current);
    if (!t || t.kind !== "query") return false;
    const running = runningRef.current.get(t.id);
    if (!running) return false;
    setStatus("Cancelling query…");
    running.cancel();
    return true;
  }, [setStatus]);

  const dryRunActive = useCallback(
    async (silent = false) => {
      const t = getActiveTab(tabsRef.current);
      if (t?.kind !== "query") return;
      const sql = currentSql();
      if (!sql.trim()) return;
      if (t.estimate?.sqlHash === sql) {
        if (!silent) setStatus(`Valid · will process ${formatBytes(t.estimate.bytes)} (${estimateCostUsd(t.estimate.bytes)})`, "success");
        return;
      }
      if (!silent) setStatus("Validating…");
      try {
        const res = await dryRun(sql);
        dispatch({ type: "update", id: t.id, patch: { estimate: { bytes: res.bytesProcessed, sqlHash: sql }, error: null } });
        if (!silent) setStatus(`Valid · will process ${formatBytes(res.bytesProcessed)} (${estimateCostUsd(res.bytesProcessed)})`, "success");
      } catch (err: any) {
        dispatch({ type: "update", id: t.id, patch: { estimate: { bytes: -1, sqlHash: sql } } });
        setStatus(`Invalid: ${oneLine(err.message, 140)}`, "error");
      }
    },
    [currentSql, setStatus],
  );

  const previewTable = useCallback(
    (ref: TableRef) => {
      const sql = `SELECT *\nFROM ${tableReference(ref)}\nLIMIT 100`;
      const tab = addQueryTab(`preview: ${ref.tableId}`, sql);
      runSql(tab.id, sql);
    },
    [addQueryTab, runSql],
  );

  const openSchema = useCallback(
    (ref: TableRef) => {
      snapshotActive();
      dispatch({ type: "add", tab: makeSchemaTab(ref.projectId, ref.datasetId, ref.tableId) });
      setPane("main");
    },
    [snapshotActive],
  );

  // Load schema info for the active schema tab when needed.
  useEffect(() => {
    if (!activeSchema || activeSchema.info !== "loading") return;
    const id = activeSchema.id;
    getTableInfo(activeSchema.projectId, activeSchema.datasetId, activeSchema.tableId)
      .then((info) => dispatch({ type: "update", id, patch: { info } }))
      .catch((err) => dispatch({ type: "update", id, patch: { info: { error: err.message } } }));
  }, [activeSchema?.id, activeSchema?.info === "loading"]);

  // ------------------------------------------------------------------ saving
  const saveActive = useCallback(async () => {
    const t = getActiveTab(tabsRef.current);
    if (t?.kind !== "query") return;
    const sql = currentSql();
    if (t.savedPath) {
      try {
        await saveQueryToPath(t.savedPath, sql);
        lastSavedRef.current.set(t.id, sql);
        dispatch({ type: "update", id: t.id, patch: { dirty: false, sql } });
        setStatus(`Saved ${t.title}`, "success");
      } catch (err: any) {
        setStatus(`Save failed: ${err.message}`, "error");
      }
    } else {
      setOverlay({ kind: "save" });
    }
  }, [currentSql, setStatus]);

  const handleSaveAs = useCallback(
    async (name: string) => {
      const t = getActiveTab(tabsRef.current);
      setOverlay({ kind: "none" });
      if (t?.kind !== "query") return;
      const sql = currentSql();
      try {
        const path = await saveQuery(name, sql);
        lastSavedRef.current.set(t.id, sql);
        dispatch({ type: "update", id: t.id, patch: { title: name, savedPath: path, dirty: false, sql } });
        setStatus(`Saved to ${path}`, "success");
      } catch (err: any) {
        setStatus(`Save failed: ${err.message}`, "error");
      }
    },
    [currentSql, setStatus],
  );

  const handleOpenSaved = useCallback(
    (q: SavedQuery, sql: string) => {
      setOverlay({ kind: "none" });
      const existing = tabsRef.current.tabs.find((t): t is QueryTab => t.kind === "query" && t.savedPath === q.path);
      if (existing) {
        activateTab(existing.id);
        setStatus(`${q.name} is already open`);
        return;
      }
      addQueryTab(q.name, sql, q.path);
      setStatus(`Opened ${q.name}`, "success");
    },
    [activateTab, addQueryTab, setStatus],
  );

  const handleOpenHistory = useCallback(
    (entry: HistoryEntry) => {
      setOverlay({ kind: "none" });
      addQueryTab(undefined, entry.sql);
      setStatus("Opened query from history in a new tab", "success");
    },
    [addQueryTab, setStatus],
  );

  const formatActive = useCallback(async () => {
    const t = getActiveTab(tabsRef.current);
    const ta = editorRef.current;
    if (t?.kind !== "query" || !ta) return;
    const sql = ta.plainText;
    if (!sql.trim()) return;
    setStatus("Formatting with sqlfluff…");
    try {
      const formatted = await formatSql(sql);
      if (formatted !== sql) ta.replaceText(formatted);
      setStatus("Formatted", "success");
    } catch (err: any) {
      setStatus(`Format failed: ${oneLine(err.message, 140)}`, "error");
    }
  }, [setStatus]);

  const copyResults = useCallback(() => {
    const t = getActiveTab(tabsRef.current);
    if (t?.kind !== "query" || !t.result || t.result.rows.length === 0) {
      setStatus("No results to copy", "error");
      return;
    }
    copy(resultToTsv(t.result), `${formatNumber(t.result.rows.length)} rows (TSV)`);
  }, [copy, setStatus]);

  const exportResults = useCallback(
    async (kind: "csv" | "json", rows: Row[]) => {
      const t = getActiveTab(tabsRef.current);
      if (t?.kind !== "query" || !t.result) return;
      const result: QueryResult = { ...t.result, rows };
      const path = exportPath(configRef.current.exportDir, kind, t.title);
      try {
        await writeExport(path, kind === "csv" ? resultToCsv(result) : resultToJson(result));
        setStatus(`Exported ${formatNumber(rows.length)} rows to ${path}`, "success");
      } catch (err: any) {
        setStatus(`Export failed: ${err.message}`, "error");
      }
    },
    [setStatus],
  );

  // ------------------------------------------------------------------ session
  const buildSession = useCallback((): Session => {
    const st = tabsRef.current;
    return {
      tabs: st.tabs.map((t) =>
        t.kind === "schema"
          ? { kind: "schema" as const, projectId: t.projectId, datasetId: t.datasetId, tableId: t.tableId }
          : t.kind === "text"
            ? { kind: "text" as const, title: t.title, subtitle: t.subtitle, language: t.language, source: t.source, meta: t.meta }
            : {
                kind: "query" as const,
                title: t.title,
                sql: t.id === st.activeId && editorRef.current ? editorRef.current.plainText : t.sql,
                savedPath: t.savedPath,
              },
      ),
      activeIndex: Math.max(0, st.tabs.findIndex((t) => t.id === st.activeId)),
      showResults,
      showSidebar,
      sidebarSection,
    };
  }, [showResults, showSidebar, sidebarSection]);

  useEffect(() => {
    if (sessionTimer.current) clearTimeout(sessionTimer.current);
    sessionTimer.current = setTimeout(() => {
      saveSession(buildSession()).catch(() => undefined);
    }, 800);
  }, [tabsState, showResults, showSidebar, sidebarSection, buildSession]);

  const quit = useCallback(async () => {
    try {
      await saveSession(buildSession());
    } catch {
      // ignore
    }
    for (const r of runningRef.current.values()) r.cancel().catch(() => undefined);
    renderer.destroy();
    process.exit(0);
  }, [buildSession, renderer]);

  const onEditorChange = useCallback(() => {
    const t = getActiveTab(tabsRef.current);
    if (t?.kind !== "query") return;
    const sql = editorRef.current?.plainText ?? "";
    const dirty = sql !== (lastSavedRef.current.get(t.id) ?? "") && sql.trim() !== "";
    if (dirty !== t.dirty) dispatch({ type: "update", id: t.id, patch: { dirty } });
    if (estimateTimer.current) clearTimeout(estimateTimer.current);
    if (sql.trim()) estimateTimer.current = setTimeout(() => dryRunActive(true), 1500);
  }, [dryRunActive]);

  // ------------------------------------------------------------------ keyboard
  useKeyboard((key) => {
    if (overlay.kind !== "none") {
      // Overlays handle their own keys; Esc is a universal fallback to close.
      if (key.name === "escape" && overlay.kind !== "save" && overlay.kind !== "open") {
        setOverlay({ kind: "none" });
        setDetailRow(null);
      }
      return;
    }
    if (textInputActive) return;
    const inEditor = pane === "main" && activeQuery !== null;

    if (key.name === "f1" || (key.name === "?" && !inEditor)) {
      setOverlay({ kind: "help" });
    } else if (key.name === "f2") {
      setShowSidebar(true);
      setPane("browser");
    } else if (key.name === "f3") {
      setPane("main");
    } else if (key.name === "f4") {
      if (activeQuery) {
        setShowResults(true);
        setPane("results");
      }
    } else if (key.name === "f5") {
      runActive();
    } else if (key.name === "f6") {
      setShowSidebar((v) => {
        if (v && pane === "browser") setPane("main");
        return !v;
      });
    } else if (key.ctrl && key.name === "h" && pane !== "browser") {
      key.preventDefault();
      setShowSidebar(true);
      setPane("browser");
    } else if (key.ctrl && key.name === "l" && pane === "browser") {
      key.preventDefault();
      setPane("main");
    } else if (key.ctrl && key.name === "j" && pane === "main" && activeQuery !== null && showResults) {
      key.preventDefault();
      setPane("results");
    } else if (key.ctrl && key.name === "k" && pane === "results") {
      key.preventDefault();
      setPane("main");
    } else if (key.ctrl && key.name === "return") {
      key.preventDefault();
      runActive();
    } else if (key.ctrl && key.name === "b") {
      key.preventDefault();
      setShowResults((v) => {
        if (v && pane === "results") setPane("main");
        return !v;
      });
    } else if (key.ctrl && key.name === "t") {
      key.preventDefault();
      addQueryTab();
    } else if (key.ctrl && (key.name === "x" || (key.name === "w" && !inEditor))) {
      key.preventDefault();
      if (active) closeTab(active.id);
    } else if (key.ctrl && key.name === "pagedown") {
      key.preventDefault();
      const id = nextTabId(tabsRef.current, 1);
      if (id) activateTab(id);
    } else if (key.ctrl && key.name === "pageup") {
      key.preventDefault();
      const id = nextTabId(tabsRef.current, -1);
      if (id) activateTab(id);
    } else if (key.meta && /^[1-9]$/.test(key.name)) {
      key.preventDefault();
      const t = tabsRef.current.tabs[Number(key.name) - 1];
      if (t) activateTab(t.id);
    } else if (key.ctrl && key.name === "s") {
      key.preventDefault();
      saveActive();
    } else if (key.ctrl && key.name === "o") {
      key.preventDefault();
      setOverlay({ kind: "open" });
    } else if (key.ctrl && key.name === "p") {
      key.preventDefault();
      setOverlay({ kind: "history" });
    } else if (key.meta && key.name === "p") {
      key.preventDefault();
      setOverlay({ kind: "projects" });
    } else if (key.ctrl && key.name === "g") {
      key.preventDefault();
      dryRunActive();
    } else if (key.ctrl && key.name === "l") {
      key.preventDefault();
      formatActive();
    } else if (key.ctrl && key.name === "y") {
      key.preventDefault();
      copyResults();
    } else if (key.ctrl && (key.name === "q" || key.name === "c")) {
      key.preventDefault();
      quit();
    } else if (key.name === "escape") {
      if (cancelActive()) key.preventDefault();
    } else if (pane === "browser" && (key.name === "tab" || key.name === "]" || key.name === "[")) {
      const idx = SIDEBAR_SECTIONS.findIndex((s) => s.id === sidebarSection);
      const delta = key.name === "[" || (key.name === "tab" && key.shift) ? -1 : 1;
      setSidebarSection(SIDEBAR_SECTIONS[(idx + delta + SIDEBAR_SECTIONS.length) % SIDEBAR_SECTIONS.length]!.id);
    } else if (pane === "browser" && /^[123]$/.test(key.name) && !key.ctrl && !key.meta) {
      setSidebarSection(SIDEBAR_SECTIONS[Number(key.name) - 1]!.id);
    } else if (!inEditor && pane === "main" && activeText) {
      if (key.name === "e" && (activeText.language === "sql" || activeText.language === "sqlx") && typeof activeText.content === "string") {
        addQueryTab(activeText.title.replace(/\.sqlx?$/, ""), activeText.content);
        setStatus("Opened a copy in a new query tab", "success");
      } else if (key.name === "y" && typeof activeText.content === "string") {
        copy(activeText.content, activeText.title);
      } else if (key.name === "r") {
        loadTextTab(activeText);
      } else if (key.name === "d" && activeText.source?.type === "gcs") {
        const uri = activeText.source.uri;
        setStatus(`Downloading ${activeText.title}…`);
        import("./lib/storage").then(({ downloadObject }) =>
          downloadObject(uri, configRef.current.exportDir)
            .then((path) => setStatus(`Downloaded to ${path}`, "success"))
            .catch((err) => setStatus(`Download failed: ${err.message}`, "error")),
        );
      }
    } else if (!inEditor && pane === "main" && activeSchema) {
      const ref: TableRef = { projectId: activeSchema.projectId, datasetId: activeSchema.datasetId, tableId: activeSchema.tableId };
      if (key.name === "p") previewTable(ref);
      else if (key.name === "i") {
        insertIntoEditor(tableReference(ref));
        setStatus(`Inserted ${ref.datasetId}.${ref.tableId} into editor`, "success");
      } else if (key.name === "y") copy(tableReference(ref), `${ref.datasetId}.${ref.tableId}`);
      else if (key.name === "r") dispatch({ type: "update", id: activeSchema.id, patch: { info: "loading" } });
    }
  });

  // ------------------------------------------------------------------ layout
  const sidebarWidth = showSidebar ? Math.min(config.sidebarWidth, Math.floor(W * 0.4)) : 0;
  const mainWidth = W - sidebarWidth;
  const contentHeight = H - STATUS_HEIGHT;
  const panelsHeight = contentHeight - TABBAR_HEIGHT;
  const resultsVisible = activeQuery !== null && showResults;
  const editorHeight = !activeQuery ? 0 : !resultsVisible ? panelsHeight : zoomed ? 0 : Math.max(5, Math.round(panelsHeight * 0.5));
  const resultsHeight = resultsVisible ? panelsHeight - editorHeight : 0;

  const hints = (() => {
    if (pane === "browser") {
      if (sidebarSection === "dataform") return "Tab section · j/k h/l · Enter open · e edit as query · c compile ws · x run/cancel · i insert · y copy · r refresh";
      if (sidebarSection === "storage") return "Tab section · j/k h/l · Enter preview · d download · y copy URI · i insert URI · x external table · L load data";
      return "Tab section · j/k h/l · Enter schema · p preview · i insert · y copy · / filter · P projects · F1 help";
    }
    if (activeText) return "j/k h/l scroll · e edit as query · y copy · r reload" + (activeText.source?.type === "gcs" ? " · d download" : "") + " · Ctrl+X close tab";
    if (pane === "results") return "j/k h/l move · Enter row · s sort · y/Y copy · e/E export · z zoom · Ctrl+B hide · F1 help";
    if (activeSchema) return "j/k scroll · p preview · i insert · y copy name · r refresh · Ctrl+X close tab · F1 help";
    return "Ctrl+Enter/F5 run · Ctrl+G dry run · Ctrl+L format · Ctrl+S save · Ctrl+T new tab · Ctrl+PgUp/PgDn tabs · F1 help";
  })();
  const rightStatus = `⊞ ${activeProject ?? "no project"} · ${tabsState.tabs.length} tab${tabsState.tabs.length === 1 ? "" : "s"} · ${pane === "browser" ? sidebarSection : pane}`;

  const editorTitle = activeQuery ? ` ${activeQuery.title}${activeQuery.dirty ? " •" : ""}${activeQuery.savedPath ? " (saved)" : ""} ` : "";
  const editorBottom = activeQuery?.estimate
    ? activeQuery.estimate.bytes < 0
      ? " ✗ invalid "
      : ` ✓ ${formatBytes(activeQuery.estimate.bytes)} · ${estimateCostUsd(activeQuery.estimate.bytes)} `
    : activeQuery && editorRef.current?.hasSelection()
      ? " selection "
      : "";

  const borderFor = (p: Pane) => (pane === p && overlay.kind === "none" ? theme.borderActive : theme.border);
  const titleFor = (p: Pane) => (pane === p && overlay.kind === "none" ? theme.titleActive : theme.titleInactive);

  return (
    <box style={{ flexDirection: "column", width: W, height: H, backgroundColor: theme.bg }}>
      <box style={{ flexDirection: "row", height: contentHeight }}>
        {showSidebar ? (
          <box
            title=" Explorer "
            titleColor={titleFor("browser")}
            border
            borderColor={borderFor("browser")}
            style={{ width: sidebarWidth, height: contentHeight, flexDirection: "column" }}
            onMouseDown={() => setPane("browser")}
          >
            <box style={{ height: 1, flexDirection: "row", paddingLeft: 1 }}>
              {SIDEBAR_SECTIONS.map((sec, i) => (
                <box key={sec.id} onMouseDown={() => setSidebarSection(sec.id)}>
                  <text wrapMode="none">
                    <span fg={sec.id === sidebarSection ? theme.yellow : theme.fgDim}>{`${i + 1}`}</span>
                    <span fg={sec.id === sidebarSection ? theme.fg : theme.fgDim} bg={sec.id === sidebarSection ? theme.tabActiveBg : undefined}>
                      {` ${sec.label} `}
                    </span>
                    <span> </span>
                  </text>
                </box>
              ))}
            </box>
            <box style={{ height: sidebarSection === "bigquery" ? contentHeight - 3 : 0, overflow: "hidden", flexDirection: "column" }}>
              <DatasetBrowser
                active={pane === "browser" && overlay.kind === "none" && sidebarSection === "bigquery"}
                focused={pane === "browser"}
                width={sidebarWidth}
                height={contentHeight - 3}
                projects={projects}
                onOpenSchema={openSchema}
                onPreview={previewTable}
                onInsertText={insertIntoEditor}
                onCopy={copy}
                onStatus={setStatus}
                onOpenProjectPicker={() => setOverlay({ kind: "projects" })}
                onFilterActiveChange={setTextInputActive}
                onFocus={() => setPane("browser")}
              />
            </box>
            {sidebarSection === "dataform" ? (
              <DataformBrowser
                active={pane === "browser" && overlay.kind === "none"}
                focused={pane === "browser"}
                width={sidebarWidth}
                height={contentHeight - 3}
                projects={projects}
                regions={config.dataformRegions ?? DEFAULT_DATAFORM_REGIONS}
                onOpenText={openTextTab}
                onOpenQuery={(title, sql) => addQueryTab(title, sql)}
                onInsertText={insertIntoEditor}
                onCopy={copy}
                onStatus={setStatus}
                onConfirm={(message, action) => setOverlay({ kind: "confirm", message, action })}
                onFocus={() => setPane("browser")}
              />
            ) : null}
            {sidebarSection === "storage" ? (
              <StorageBrowser
                active={pane === "browser" && overlay.kind === "none"}
                focused={pane === "browser"}
                width={sidebarWidth}
                height={contentHeight - 3}
                projects={projects}
                activeProject={activeProject}
                exportDir={config.exportDir}
                previewBytes={config.previewBytes ?? 64 * 1024}
                onOpenText={openTextTab}
                onInsertText={insertIntoEditor}
                onCopy={copy}
                onStatus={setStatus}
                onFocus={() => setPane("browser")}
              />
            ) : null}
          </box>
        ) : null}

        <box style={{ flexDirection: "column", width: mainWidth, height: contentHeight }}>
          <TabBar tabs={tabsState.tabs} activeId={tabsState.activeId} width={mainWidth} onSelect={activateTab} />

          {activeQuery && editorHeight > 0 ? (
            <box
              title={editorTitle}
              bottomTitle={editorBottom}
              bottomTitleAlignment="right"
              titleColor={titleFor("main")}
              border
              borderColor={borderFor("main")}
              style={{ height: editorHeight, flexDirection: "column" }}
              onMouseDown={() => setPane("main")}
            >
              <Editor
                key={activeQuery.id}
                initialSql={activeQuery.sql}
                focused={pane === "main" && overlay.kind === "none"}
                editorRef={editorRef}
                onContentChange={onEditorChange}
                onSubmit={runActive}
              />
            </box>
          ) : null}

          {activeQuery && resultsVisible ? (
            <box
              title=" Results "
              titleColor={titleFor("results")}
              border
              borderColor={borderFor("results")}
              style={{ height: resultsHeight, flexDirection: "column" }}
            >
              <ResultsGrid
                key={activeQuery.id}
                tab={activeQuery}
                active={pane === "results" && overlay.kind === "none"}
                width={mainWidth - 2}
                height={resultsHeight - 2}
                zoomed={zoomed}
                onOpenRow={(row, index) => {
                  setDetailRow({ row, index });
                  setOverlay({ kind: "row", rowIndex: index });
                }}
                onCopy={copy}
                onExport={exportResults}
                onToggleZoom={() => setZoomed((z) => !z)}
                onCancel={() => cancelActive()}
                onFocus={() => setPane("results")}
              />
            </box>
          ) : null}

          {activeText ? (
            <box
              title={` ${activeText.title} `}
              titleColor={titleFor("main")}
              border
              borderColor={borderFor("main")}
              style={{ height: panelsHeight, flexDirection: "column" }}
              onMouseDown={() => setPane("main")}
            >
              <TextView key={activeText.id} tab={activeText} active={pane === "main" && overlay.kind === "none"} width={mainWidth - 2} height={panelsHeight - 2} onFocus={() => setPane("main")} />
            </box>
          ) : null}

          {activeSchema ? (
            <box
              title={` ${activeSchema.title} `}
              titleColor={titleFor("main")}
              border
              borderColor={borderFor("main")}
              style={{ height: panelsHeight, flexDirection: "column" }}
              onMouseDown={() => setPane("main")}
            >
              <SchemaView key={activeSchema.id} tab={activeSchema} focused={pane === "main" && overlay.kind === "none"} width={mainWidth - 2} />
            </box>
          ) : null}
        </box>
      </box>

      <StatusBar message={status.message} kind={status.kind} right={rightStatus} hints={hints} width={W} />

      {overlay.kind === "help" ? <HelpOverlay width={W} height={H} onClose={() => setOverlay({ kind: "none" })} /> : null}
      {overlay.kind === "save" && activeQuery ? (
        <SaveDialog
          defaultName={/^Query \d+$/.test(activeQuery.title) ? "" : activeQuery.title}
          width={W}
          height={H}
          onSave={handleSaveAs}
          onCancel={() => setOverlay({ kind: "none" })}
        />
      ) : null}
      {overlay.kind === "open" ? (
        <OpenDialog width={W} height={H} onOpen={handleOpenSaved} onCancel={() => setOverlay({ kind: "none" })} onStatus={setStatus} />
      ) : null}
      {overlay.kind === "history" ? (
        <HistoryOverlay width={W} height={H} onOpen={handleOpenHistory} onCancel={() => setOverlay({ kind: "none" })} />
      ) : null}
      {overlay.kind === "projects" ? (
        <ProjectPicker
          pinned={config.pinnedProjects}
          activeProject={activeProject}
          defaultProject={defaultProject}
          width={W}
          height={H}
          onChange={(pinned) => {
            const next = { ...configRef.current, pinnedProjects: pinned };
            setConfig(next);
            saveConfig(next).catch(() => undefined);
          }}
          onSwitch={(id) => {
            switchProject(id);
            setOverlay({ kind: "none" });
          }}
          onClose={() => setOverlay({ kind: "none" })}
        />
      ) : null}
      {overlay.kind === "row" && activeQuery && detailRow ? (
        <RowDetailOverlay
          tab={activeQuery}
          row={detailRow.row}
          rowIndex={detailRow.index}
          width={W}
          height={H}
          onClose={() => {
            setOverlay({ kind: "none" });
            setDetailRow(null);
          }}
          onCopy={copy}
        />
      ) : null}
      {overlay.kind === "confirm" ? (
        <ConfirmDialog
          message={overlay.message}
          width={W}
          height={H}
          onYes={() => {
            const action = overlay.action;
            setOverlay({ kind: "none" });
            action();
          }}
          onNo={() => setOverlay({ kind: "none" })}
        />
      ) : null}
      {overlay.kind === "confirm-close" ? (
        <ConfirmDialog
          message="Close this tab? Its unsaved SQL will be lost."
          width={W}
          height={H}
          onYes={() => closeTab(overlay.tabId, true)}
          onNo={() => setOverlay({ kind: "none" })}
        />
      ) : null}
    </box>
  );
}
