import { useEffect, useRef, useState } from "react";
import { useKeyboard } from "@opentui/react";
import type { BoxRenderable, MouseEvent } from "@opentui/core";
import { listDatasets, listTables, type Dataset, type Table } from "../lib/bq";
import { theme } from "../lib/theme";
import { truncate } from "../lib/util";

type Loadable<T> = T | "loading" | { error: string };

interface FlatNode {
  key: string;
  kind: "project" | "dataset" | "table";
  projectId: string;
  datasetId?: string;
  tableId?: string;
  tableType?: string;
  depth: number;
  state?: Loadable<unknown>;
}

export interface TableRef {
  projectId: string;
  datasetId: string;
  tableId: string;
}

interface DatasetBrowserProps {
  active: boolean;
  focused: boolean;
  width: number;
  height: number;
  projects: string[];
  onOpenSchema: (ref: TableRef) => void;
  onPreview: (ref: TableRef) => void;
  onInsertText: (text: string) => void;
  onCopy: (text: string, label: string) => void;
  onStatus: (message: string, kind?: "info" | "error" | "success") => void;
  onOpenProjectPicker: () => void;
  onFilterActiveChange: (active: boolean) => void;
  onFocus: () => void;
}

const TABLE_ICON: Record<string, { icon: string; color: string }> = {
  TABLE: { icon: "▦", color: theme.fg },
  VIEW: { icon: "◇", color: theme.magenta },
  MATERIALIZED_VIEW: { icon: "◆", color: theme.magenta },
  EXTERNAL: { icon: "⇲", color: theme.orange },
  SNAPSHOT: { icon: "⧉", color: theme.cyan },
};

export function tableReference(ref: TableRef): string {
  return `\`${ref.projectId}.${ref.datasetId}.${ref.tableId}\``;
}

export function DatasetBrowser(props: DatasetBrowserProps) {
  const {
    active,
    focused,
    width,
    height,
    projects,
    onOpenSchema,
    onPreview,
    onInsertText,
    onCopy,
    onStatus,
    onOpenProjectPicker,
    onFilterActiveChange,
    onFocus,
  } = props;

  const [expanded, setExpanded] = useState<Set<string>>(() => new Set(projects.length > 0 ? [projects[0]!] : []));
  const [datasetsByProject, setDatasetsByProject] = useState<Record<string, Loadable<Dataset[]>>>({});
  const [tablesByDataset, setTablesByDataset] = useState<Record<string, Loadable<Table[]>>>({});
  const [cursor, setCursor] = useState(0);
  const [filter, setFilter] = useState("");
  const [filterActive, setFilterActive] = useState(false);
  const listRef = useRef<BoxRenderable>(null);
  const [scrollOffset, setScrollOffset] = useState(0);

  const loadDatasets = async (projectId: string, force = false) => {
    if (!force && datasetsByProject[projectId] && datasetsByProject[projectId] !== "loading") return;
    setDatasetsByProject((prev) => ({ ...prev, [projectId]: "loading" }));
    try {
      const ds = await listDatasets(projectId);
      setDatasetsByProject((prev) => ({ ...prev, [projectId]: ds }));
      onStatus(`${projectId}: ${ds.length} dataset${ds.length === 1 ? "" : "s"}`);
    } catch (err: any) {
      setDatasetsByProject((prev) => ({ ...prev, [projectId]: { error: err.message } }));
      onStatus(`Failed to list datasets in ${projectId}: ${err.message}`, "error");
    }
  };

  const loadTables = async (projectId: string, datasetId: string, force = false) => {
    const key = `${projectId}:${datasetId}`;
    if (!force && tablesByDataset[key] && tablesByDataset[key] !== "loading") return;
    setTablesByDataset((prev) => ({ ...prev, [key]: "loading" }));
    try {
      const tables = await listTables(projectId, datasetId);
      setTablesByDataset((prev) => ({ ...prev, [key]: tables }));
      onStatus(`${datasetId}: ${tables.length} table${tables.length === 1 ? "" : "s"}`);
    } catch (err: any) {
      setTablesByDataset((prev) => ({ ...prev, [key]: { error: err.message } }));
      onStatus(`Failed to list tables in ${datasetId}: ${err.message}`, "error");
    }
  };

  // When the active project changes, expand it.
  useEffect(() => {
    const first = projects[0];
    if (first && !expanded.has(first)) setExpanded((prev) => new Set([...prev, first]));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projects[0]]);

  // Load datasets for expanded projects (initially the active project).
  useEffect(() => {
    for (const p of projects) {
      if (expanded.has(p) && !datasetsByProject[p]) loadDatasets(p);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projects, expanded]);

  useEffect(() => {
    onFilterActiveChange(filterActive);
  }, [filterActive, onFilterActiveChange]);

  // While filtering, make sure every dataset's tables are loaded so the
  // filter can see them (a few parallel `bq ls` calls, cached afterwards).
  const filterLoadTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => {
    if (filterLoadTimer.current) clearTimeout(filterLoadTimer.current);
    if (filter.trim().length < 2) return;
    filterLoadTimer.current = setTimeout(() => {
      const pending: { projectId: string; datasetId: string }[] = [];
      for (const projectId of projects) {
        const ds = datasetsByProject[projectId];
        if (!ds) {
          loadDatasets(projectId);
          continue;
        }
        if (!Array.isArray(ds)) continue;
        for (const d of ds) {
          if (!tablesByDataset[`${projectId}:${d.datasetId}`]) pending.push({ projectId, datasetId: d.datasetId });
        }
      }
      if (pending.length === 0) return;
      onStatus(`Loading tables in ${pending.length} dataset${pending.length === 1 ? "" : "s"} for filter…`);
      let i = 0;
      const worker = async () => {
        while (i < pending.length) {
          const item = pending[i++]!;
          await loadTables(item.projectId, item.datasetId);
        }
      };
      Promise.all([worker(), worker(), worker(), worker()]).then(() => onStatus("Filter ready"));
    }, 400);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, projects, datasetsByProject]);

  // ------------------------------------------------------------ flatten tree
  const needle = filter.trim().toLowerCase();
  const matches = (s: string) => needle === "" || s.toLowerCase().includes(needle);

  const flat: FlatNode[] = [];
  for (const projectId of projects) {
    const dsState = datasetsByProject[projectId];
    const projectExpanded = expanded.has(projectId) || needle !== "";
    const children: FlatNode[] = [];
    if (projectExpanded && Array.isArray(dsState)) {
      for (const ds of dsState) {
        const dsKey = `${projectId}:${ds.datasetId}`;
        const tState = tablesByDataset[dsKey];
        const dsExpanded = expanded.has(dsKey) || (needle !== "" && Array.isArray(tState));
        const tableNodes: FlatNode[] = [];
        if (dsExpanded && Array.isArray(tState)) {
          for (const t of tState) {
            if (needle !== "" && !matches(t.tableId) && !matches(`${ds.datasetId}.${t.tableId}`)) continue;
            tableNodes.push({
              key: `${dsKey}.${t.tableId}`,
              kind: "table",
              projectId,
              datasetId: ds.datasetId,
              tableId: t.tableId,
              tableType: t.type,
              depth: 2,
            });
          }
        }
        const dsMatches = matches(ds.datasetId);
        if (needle !== "" && !dsMatches && tableNodes.length === 0) continue;
        children.push({ key: dsKey, kind: "dataset", projectId, datasetId: ds.datasetId, depth: 1, state: tState });
        children.push(...tableNodes);
      }
    }
    if (needle !== "" && children.length === 0 && !matches(projectId)) continue;
    flat.push({ key: projectId, kind: "project", projectId, depth: 0, state: dsState });
    flat.push(...children);
  }

  const clampedCursor = Math.min(cursor, Math.max(0, flat.length - 1));

  // Windowed rendering: keep the cursor inside the visible rows.
  const listHeight = Math.max(1, height - (filterActive || filter ? 1 : 0) - (flat.length > height - 1 ? 1 : 0));
  useEffect(() => {
    setScrollOffset((off) => {
      if (clampedCursor < off) return clampedCursor;
      if (clampedCursor >= off + listHeight) return clampedCursor - listHeight + 1;
      return Math.min(off, Math.max(0, flat.length - listHeight));
    });
  }, [clampedCursor, flat.length, listHeight]);

  const toggle = (node: FlatNode) => {
    const next = new Set(expanded);
    if (next.has(node.key)) next.delete(node.key);
    else {
      next.add(node.key);
      if (node.kind === "project") loadDatasets(node.projectId);
      if (node.kind === "dataset") loadTables(node.projectId, node.datasetId!);
    }
    setExpanded(next);
  };

  const refOf = (node: FlatNode): TableRef | null =>
    node.kind === "table" ? { projectId: node.projectId, datasetId: node.datasetId!, tableId: node.tableId! } : null;

  useKeyboard((key) => {
    if (!active || filterActive) return;
    const node = flat[clampedCursor];
    switch (key.name) {
      case "j":
      case "down":
        setCursor((c) => Math.min(c + 1, Math.max(0, flat.length - 1)));
        break;
      case "k":
      case "up":
        setCursor((c) => Math.max(Math.min(c, flat.length - 1) - 1, 0));
        break;
      case "pagedown":
        setCursor(Math.min(clampedCursor + 15, Math.max(0, flat.length - 1)));
        break;
      case "pageup":
        setCursor(Math.max(clampedCursor - 15, 0));
        break;
      case "d":
        if (key.ctrl) setCursor(Math.min(clampedCursor + 15, Math.max(0, flat.length - 1)));
        break;
      case "u":
        if (key.ctrl) setCursor(Math.max(clampedCursor - 15, 0));
        break;
      case "g":
        setCursor(key.shift ? Math.max(0, flat.length - 1) : 0);
        break;
      case "l":
      case "right":
        if (node && node.kind !== "table" && !expanded.has(node.key)) toggle(node);
        break;
      case "h":
      case "left":
        if (!node) break;
        if (node.kind !== "table" && expanded.has(node.key)) toggle(node);
        else {
          // jump to parent
          for (let i = clampedCursor - 1; i >= 0; i--) {
            if (flat[i]!.depth < node.depth) {
              setCursor(i);
              break;
            }
          }
        }
        break;
      case "return": {
        if (!node) break;
        const ref = refOf(node);
        if (ref) onOpenSchema(ref);
        else toggle(node);
        break;
      }
      case "p": {
        if (key.shift) {
          onOpenProjectPicker();
          break;
        }
        const ref = node ? refOf(node) : null;
        if (ref) onPreview(ref);
        break;
      }
      case "i": {
        const ref = node ? refOf(node) : null;
        if (ref) {
          onInsertText(tableReference(ref));
          onStatus(`Inserted ${ref.datasetId}.${ref.tableId} into editor`, "success");
        }
        break;
      }
      case "y": {
        const ref = node ? refOf(node) : null;
        if (ref) onCopy(tableReference(ref), `${ref.datasetId}.${ref.tableId}`);
        else if (node?.kind === "dataset") onCopy(`${node.projectId}.${node.datasetId}`, node.datasetId!);
        break;
      }
      case "r": {
        if (!node) break;
        if (node.kind === "project") loadDatasets(node.projectId, true);
        else if (node.kind === "dataset") loadTables(node.projectId, node.datasetId!, true);
        else loadTables(node.projectId, node.datasetId!, true);
        break;
      }
      case "/":
        setFilterActive(true);
        break;
      case "escape":
        if (filter) {
          setFilter("");
          onStatus("Filter cleared");
        }
        break;
      default:
        break;
    }
  });

  // Keys while typing in the filter input: Esc clears, Enter/Tab/Down return
  // to the list with the filter applied.
  useKeyboard((key) => {
    if (!filterActive) return;
    if (key.name === "escape") {
      key.preventDefault();
      setFilterActive(false);
      setFilter("");
    } else if (key.name === "return" || key.name === "tab" || key.name === "down") {
      key.preventDefault();
      setFilterActive(false);
      setCursor(0);
    }
  });

  const handleMouseDown = (e: MouseEvent) => {
    onFocus();
    const box = listRef.current as unknown as { y?: number } | null;
    const top = box?.y ?? 0;
    const idx = e.y - top + scrollOffset;
    if (idx >= 0 && idx < flat.length) setCursor(idx);
  };
  const handleScroll = (e: MouseEvent) => {
    const dir = e.scroll?.direction;
    const max = Math.max(0, flat.length - listHeight);
    if (dir === "down") setScrollOffset((o) => Math.min(max, o + 3));
    else if (dir === "up") setScrollOffset((o) => Math.max(0, o - 3));
  };

  const innerWidth = Math.max(10, width - 2);

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      {(filterActive || filter) && (
        <box style={{ height: 1, flexDirection: "row", paddingLeft: 1 }}>
          <text fg={theme.yellow}>/</text>
          <input
            focused={filterActive}
            value={filter}
            placeholder="filter tables…"
            onInput={(v) => setFilter(v)}
            onSubmit={() => setFilterActive(false)}
            textColor={theme.fg}
            backgroundColor={theme.bg}
            focusedBackgroundColor={theme.bg}
            cursorColor={theme.cursorBg}
            style={{ flexGrow: 1 }}
          />
        </box>
      )}
      <box
        ref={listRef}
        style={{ flexDirection: "column", height: listHeight, overflow: "hidden" }}
        onMouseDown={handleMouseDown}
        onMouseScroll={handleScroll}
      >
        {flat.length === 0 ? (
          <text fg={theme.fgDim}>{needle ? " no matches" : " loading…"}</text>
        ) : null}
        {flat.slice(scrollOffset, scrollOffset + listHeight).map((node, vi) => {
          const i = scrollOffset + vi;
          const selected = i === clampedCursor;
          const indent = "  ".repeat(node.depth);
          let icon = "";
          let iconColor: string = theme.fg;
          let label = "";
          let labelColor: string = theme.fg;
          let suffix = "";
          if (node.kind === "project") {
            icon = expanded.has(node.key) || needle ? "▾ ⊞" : "▸ ⊞";
            iconColor = theme.yellow;
            label = node.projectId + (node.projectId === projects[0] ? "  (active)" : "");
            labelColor = theme.yellow;
          } else if (node.kind === "dataset") {
            const open = expanded.has(node.key) || (needle !== "" && Array.isArray(node.state));
            icon = open ? "▾" : "▸";
            iconColor = theme.accent;
            label = node.datasetId!;
            labelColor = theme.accent;
          } else {
            const t = TABLE_ICON[node.tableType ?? "TABLE"] ?? TABLE_ICON.TABLE!;
            icon = " " + t.icon;
            iconColor = t.color;
            label = node.tableId!;
            labelColor = theme.fg;
          }
          if (node.state === "loading") suffix = " …";
          else if (node.state && typeof node.state === "object" && "error" in node.state) suffix = " ✗";
          const textWidth = innerWidth - indent.length - icon.length - 2;
          return (
            <box key={node.key} style={{ height: 1 }}>
              <text wrapMode="none" bg={selected && focused ? theme.selectionBg : selected ? theme.headerBg : undefined}>
                <span>{" " + indent}</span>
                <span fg={iconColor}>{icon}</span>
                <span fg={selected ? theme.selectionFg : labelColor}>{" " + truncate(label, Math.max(4, textWidth))}</span>
                <span fg={suffix === " ✗" ? theme.red : theme.fgDim}>{suffix}</span>
              </text>
            </box>
          );
        })}
        {flat.length > listHeight ? null : null}
      </box>
      {flat.length > listHeight ? (
        <box style={{ height: 1, paddingLeft: 1 }}>
          <text fg={theme.fgDim} wrapMode="none">{`${scrollOffset + 1}-${Math.min(flat.length, scrollOffset + listHeight)} of ${flat.length}`}</text>
        </box>
      ) : null}
    </box>
  );
}
