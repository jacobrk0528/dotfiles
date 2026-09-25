import type { QueryTab, SchemaTab, Tab, TextTab } from "../types";

export interface TabsState {
  tabs: Tab[];
  activeId: string;
  counter: number;
}

export type TabsAction =
  | { type: "add"; tab: Tab; activate?: boolean }
  | { type: "close"; id: string }
  | { type: "activate"; id: string }
  | { type: "update"; id: string; patch: Partial<QueryTab> | Partial<SchemaTab> | Partial<TextTab> }
  | { type: "snapshot"; id: string; sql: string }
  | { type: "restore"; tabs: Tab[]; activeId: string; counter: number }
  | { type: "move"; id: string; delta: number };

export function makeQueryTab(id: string, title: string, sql = "", savedPath?: string): QueryTab {
  return {
    id,
    kind: "query",
    title,
    sql,
    savedPath,
    dirty: false,
    result: null,
    stats: null,
    error: null,
    runningJobId: null,
    startedAt: null,
    estimate: null,
  };
}

export function makeSchemaTab(projectId: string, datasetId: string, tableId: string): SchemaTab {
  return {
    id: `schema:${projectId}.${datasetId}.${tableId}`,
    kind: "schema",
    title: `${datasetId}.${tableId}`,
    projectId,
    datasetId,
    tableId,
    info: "loading",
  };
}

export function makeTextTab(id: string, title: string, language: TextTab["language"], init: Partial<TextTab> = {}): TextTab {
  return {
    id,
    kind: "text",
    title,
    language,
    content: "loading",
    meta: [],
    ...init,
  };
}

export function tabsReducer(state: TabsState, action: TabsAction): TabsState {
  switch (action.type) {
    case "add": {
      if (state.tabs.some((t) => t.id === action.tab.id)) {
        return action.activate === false ? state : { ...state, activeId: action.tab.id };
      }
      const activeIndex = state.tabs.findIndex((t) => t.id === state.activeId);
      const tabs = [...state.tabs];
      tabs.splice(activeIndex + 1, 0, action.tab);
      return {
        ...state,
        tabs,
        activeId: action.activate === false ? state.activeId : action.tab.id,
        counter: action.tab.kind === "query" ? state.counter + 1 : state.counter,
      };
    }
    case "close": {
      const index = state.tabs.findIndex((t) => t.id === action.id);
      if (index === -1) return state;
      const tabs = state.tabs.filter((t) => t.id !== action.id);
      let activeId = state.activeId;
      if (activeId === action.id) {
        const neighbor = tabs[Math.max(0, index - 1)] ?? tabs[0];
        activeId = neighbor ? neighbor.id : "";
      }
      return { ...state, tabs, activeId };
    }
    case "activate":
      return state.tabs.some((t) => t.id === action.id) ? { ...state, activeId: action.id } : state;
    case "update":
      return {
        ...state,
        tabs: state.tabs.map((t) => (t.id === action.id ? ({ ...t, ...action.patch } as Tab) : t)),
      };
    case "snapshot":
      return {
        ...state,
        tabs: state.tabs.map((t) => (t.id === action.id && t.kind === "query" && t.sql !== action.sql ? { ...t, sql: action.sql } : t)),
      };
    case "restore":
      return { tabs: action.tabs, activeId: action.activeId, counter: action.counter };
    case "move": {
      const index = state.tabs.findIndex((t) => t.id === action.id);
      const target = index + action.delta;
      if (index === -1 || target < 0 || target >= state.tabs.length) return state;
      const tabs = [...state.tabs];
      const [tab] = tabs.splice(index, 1);
      tabs.splice(target, 0, tab!);
      return { ...state, tabs };
    }
    default:
      return state;
  }
}

export function activeTab(state: TabsState): Tab | undefined {
  return state.tabs.find((t) => t.id === state.activeId);
}

export function nextTabId(state: TabsState, delta: number): string | undefined {
  if (state.tabs.length === 0) return undefined;
  const index = state.tabs.findIndex((t) => t.id === state.activeId);
  const next = (index + delta + state.tabs.length) % state.tabs.length;
  return state.tabs[next]?.id;
}
