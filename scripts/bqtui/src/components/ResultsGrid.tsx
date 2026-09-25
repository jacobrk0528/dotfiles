import { useEffect, useMemo, useState } from "react";
import { useKeyboard } from "@opentui/react";
import type { MouseEvent } from "@opentui/core";
import type { Row } from "../lib/bq";
import { theme, typeColor } from "../lib/theme";
import { estimateCostUsd, formatBytes, formatDuration, formatNumber, padLeft, padRight, stringifyCell, truncate } from "../lib/util";
import type { QueryTab } from "../types";

export interface SortState {
  column: string;
  dir: "asc" | "desc";
}

interface ResultsGridProps {
  tab: QueryTab;
  active: boolean;
  width: number;
  height: number;
  zoomed: boolean;
  onOpenRow: (row: Row, rowIndex: number) => void;
  onCopy: (text: string, label: string) => void;
  onExport: (kind: "csv" | "json", sortedRows: Row[]) => void;
  onToggleZoom: () => void;
  onCancel: () => void;
  onFocus: () => void;
}

const NUMERIC = new Set(["INTEGER", "INT64", "FLOAT", "FLOAT64", "NUMERIC", "BIGNUMERIC"]);
const MAX_COL = 40;
const MIN_COL = 3;
const SEP = " │ ";

function firstLine(value: string): string {
  const i = value.indexOf("\n");
  return i === -1 ? value : value.slice(0, i) + "↵";
}

function compareValues(a: unknown, b: unknown): number {
  if (a === null || a === undefined) return b === null || b === undefined ? 0 : 1;
  if (b === null || b === undefined) return -1;
  const na = typeof a === "string" ? Number(a) : NaN;
  const nb = typeof b === "string" ? Number(b) : NaN;
  if (Number.isFinite(na) && Number.isFinite(nb)) return na - nb;
  return stringifyCell(a).localeCompare(stringifyCell(b));
}

export function statsLine(tab: QueryTab, elapsedNow: number): { text: string; color: string } | null {
  if (tab.runningJobId) {
    return { text: `Running… ${formatDuration(elapsedNow)}   Esc to cancel   job ${tab.runningJobId}`, color: theme.yellow };
  }
  const r = tab.result;
  if (!r) return null;
  const parts: string[] = [];
  parts.push(`${formatNumber(r.rows.length)} row${r.rows.length === 1 ? "" : "s"}${r.truncated ? ` (capped at ${formatNumber(r.rows.length)})` : ""}`);
  parts.push(formatDuration(tab.stats?.elapsedMs ?? r.elapsedMs));
  const bytes = tab.stats?.totalBytesProcessed ?? r.estimatedBytes;
  if (bytes !== undefined) parts.push(`${formatBytes(bytes)} processed (${estimateCostUsd(tab.stats?.totalBytesBilled ?? bytes)})`);
  if (tab.stats?.cacheHit) parts.push("cache hit");
  if (tab.stats?.totalSlotMs !== undefined) parts.push(`${formatDuration(tab.stats.totalSlotMs)} slot time`);
  if (tab.stats?.statementType && tab.stats.statementType !== "SELECT") parts.push(tab.stats.statementType);
  if (tab.stats?.numDmlAffectedRows !== undefined) parts.push(`${formatNumber(tab.stats.numDmlAffectedRows)} rows affected`);
  return { text: parts.join("  ·  "), color: theme.fgMuted };
}

export function ResultsGrid(props: ResultsGridProps) {
  const { tab, active, width, height, onOpenRow, onCopy, onExport, onToggleZoom, onCancel, onFocus } = props;
  const result = tab.result;
  const columns = result?.columns ?? [];
  const [rowCursor, setRowCursor] = useState(0);
  const [colCursor, setColCursor] = useState(0);
  const [rowOffset, setRowOffset] = useState(0);
  const [colOffset, setColOffset] = useState(0);
  const [sort, setSort] = useState<SortState | null>(null);
  const [tick, setTick] = useState(0);

  // Live elapsed timer while running.
  useEffect(() => {
    if (!tab.runningJobId) return;
    const id = setInterval(() => setTick((t) => t + 1), 200);
    return () => clearInterval(id);
  }, [tab.runningJobId]);

  // Reset navigation when a new result arrives.
  useEffect(() => {
    setRowCursor(0);
    setColCursor(0);
    setRowOffset(0);
    setColOffset(0);
    setSort(null);
  }, [result?.jobId]);

  const widths = useMemo(() => {
    if (!result) return [];
    const sample = result.rows.slice(0, 300);
    return result.columns.map((col) => {
      let w = Math.max(col.length, (result.columnTypes[col] ?? "").length);
      for (const row of sample) w = Math.max(w, firstLine(stringifyCell(row[col])).length);
      return Math.max(MIN_COL, Math.min(MAX_COL, w));
    });
  }, [result]);

  const sortedRows = useMemo(() => {
    if (!result) return [];
    if (!sort) return result.rows;
    const idx = result.rows.map((r, i) => i);
    idx.sort((a, b) => {
      const c = compareValues(result.rows[a]![sort.column], result.rows[b]![sort.column]);
      return sort.dir === "asc" ? c : -c;
    });
    return idx.map((i) => result.rows[i]!);
  }, [result, sort]);

  const gutter = String(Math.max(1, sortedRows.length)).length + 1;
  const bodyHeight = Math.max(1, height - 3); // stats + header name + header type
  const availWidth = Math.max(10, width - gutter - 1);

  // Which columns fit starting at colOffset.
  const visibleCols: number[] = [];
  {
    let used = 0;
    for (let i = colOffset; i < columns.length; i++) {
      const need = widths[i]! + (visibleCols.length > 0 ? SEP.length : 0);
      if (used + need > availWidth && visibleCols.length > 0) break;
      visibleCols.push(i);
      used += need;
    }
  }

  const ensureColVisible = (target: number) => {
    if (target < colOffset) {
      setColOffset(target);
      return;
    }
    // Walk offset forward until target fits.
    let off = colOffset;
    const fits = (start: number) => {
      let used = 0;
      for (let i = start; i <= target; i++) {
        used += widths[i]! + (i > start ? SEP.length : 0);
        if (used > availWidth) return false;
      }
      return true;
    };
    while (off < target && !fits(off)) off++;
    setColOffset(off);
  };

  const moveRow = (delta: number) => {
    const next = Math.max(0, Math.min(sortedRows.length - 1, rowCursor + delta));
    setRowCursor(next);
    if (next < rowOffset) setRowOffset(next);
    else if (next >= rowOffset + bodyHeight) setRowOffset(next - bodyHeight + 1);
  };
  const jumpRow = (index: number) => {
    const next = Math.max(0, Math.min(sortedRows.length - 1, index));
    setRowCursor(next);
    if (next < rowOffset) setRowOffset(next);
    else if (next >= rowOffset + bodyHeight) setRowOffset(Math.max(0, next - bodyHeight + 1));
  };
  const moveCol = (delta: number) => {
    const next = Math.max(0, Math.min(columns.length - 1, colCursor + delta));
    setColCursor(next);
    ensureColVisible(next);
  };

  useKeyboard((key) => {
    if (!active) return;
    if (tab.runningJobId) {
      if (key.name === "escape") onCancel();
      return;
    }
    if (key.name === "z") {
      onToggleZoom();
      return;
    }
    if (!result || sortedRows.length === 0) return;
    const col = columns[colCursor]!;
    switch (key.name) {
      case "j":
      case "down":
        moveRow(1);
        break;
      case "k":
      case "up":
        moveRow(-1);
        break;
      case "h":
      case "left":
        moveCol(-1);
        break;
      case "l":
      case "right":
        moveCol(1);
        break;
      case "pagedown":
        moveRow(bodyHeight);
        break;
      case "pageup":
        moveRow(-bodyHeight);
        break;
      case "d":
        if (key.ctrl) moveRow(Math.floor(bodyHeight / 2));
        break;
      case "u":
        if (key.ctrl) moveRow(-Math.floor(bodyHeight / 2));
        break;
      case "g":
        if (key.shift) jumpRow(sortedRows.length - 1);
        else jumpRow(0);
        break;
      case "home":
        jumpRow(0);
        break;
      case "end":
        jumpRow(sortedRows.length - 1);
        break;
      case "0":
        setColCursor(0);
        setColOffset(0);
        break;
      case "$":
        setColCursor(columns.length - 1);
        ensureColVisible(columns.length - 1);
        break;
      case "return":
        onOpenRow(sortedRows[rowCursor]!, rowCursor);
        break;
      case "s":
        setSort((prev) => {
          if (!prev || prev.column !== col) return { column: col, dir: "asc" };
          if (prev.dir === "asc") return { column: col, dir: "desc" };
          return null;
        });
        break;
      case "y":
        if (key.shift) {
          onCopy(
            [columns.join("\t"), ...sortedRows.map((r) => columns.map((c) => stringifyCell(r[c]).replace(/[\t\n]/g, " ")).join("\t"))].join("\n"),
            `${formatNumber(sortedRows.length)} rows (TSV)`,
          );
        } else {
          onCopy(columns.map((c) => stringifyCell(sortedRows[rowCursor]![c])).join("\t"), `row ${rowCursor + 1} (TSV)`);
        }
        break;
      case "c":
        if (!key.ctrl) onCopy(stringifyCell(sortedRows[rowCursor]![col]), `${col} of row ${rowCursor + 1}`);
        break;
      case "e":
        if (!key.ctrl) onExport(key.shift ? "json" : "csv", sortedRows);
        break;
      default:
        break;
    }
  });

  const handleScroll = (e: MouseEvent) => {
    if (!result) return;
    const dir = e.scroll?.direction;
    if (dir === "down") setRowOffset((o) => Math.min(Math.max(0, sortedRows.length - bodyHeight), o + 3));
    else if (dir === "up") setRowOffset((o) => Math.max(0, o - 3));
    else if (dir === "left") setColOffset((o) => Math.max(0, o - 1));
    else if (dir === "right") setColOffset((o) => Math.min(Math.max(0, columns.length - 1), o + 1));
  };

  const elapsedNow = tab.startedAt ? Date.now() - tab.startedAt : 0;
  const stats = statsLine(tab, elapsedNow);
  void tick;

  // ------------------------------------------------------------------ states
  if (tab.runningJobId) {
    return (
      <box style={{ flexDirection: "column", padding: 1 }} onMouseDown={onFocus}>
        <text fg={theme.yellow}>{stats?.text ?? "Running…"}</text>
      </box>
    );
  }
  if (tab.error) {
    return (
      <box style={{ flexDirection: "column", padding: 1 }} onMouseDown={onFocus}>
        <text fg={theme.red}>Query failed</text>
        <text fg={theme.fg} wrapMode="word">
          {tab.error}
        </text>
      </box>
    );
  }
  if (!result) {
    return (
      <box style={{ flexDirection: "column", padding: 1 }} onMouseDown={onFocus}>
        <text fg={theme.fgDim}>No results yet. Run a query with Ctrl+Enter or F5.</text>
      </box>
    );
  }
  if (result.rows.length === 0) {
    return (
      <box style={{ flexDirection: "column", padding: 1 }} onMouseDown={onFocus}>
        {stats ? <text fg={stats.color}>{stats.text}</text> : null}
        {result.message ? <text fg={theme.green}>{result.message}</text> : <text fg={theme.fgMuted}>Query returned no rows.</text>}
      </box>
    );
  }

  const visibleRows = sortedRows.slice(rowOffset, rowOffset + bodyHeight);
  const isNumeric = (col: string) => NUMERIC.has((result.columnTypes[col] ?? "").toUpperCase());
  const cell = (col: string, ci: number, value: unknown) => {
    const text = firstLine(stringifyCell(value));
    return isNumeric(col) ? padLeft(text, widths[ci]!) : padRight(text, widths[ci]!);
  };
  const hiddenLeft = colOffset > 0 ? `‹${colOffset} ` : "";
  const lastVisible = visibleCols[visibleCols.length - 1] ?? 0;
  const hiddenRight = lastVisible < columns.length - 1 ? ` ${columns.length - 1 - lastVisible}›` : "";

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }} onMouseDown={onFocus} onMouseScroll={handleScroll}>
      {stats ? (
        <text fg={stats.color}>
          {truncate(stats.text, width - 1)}
        </text>
      ) : null}
      {/* header: names */}
      <text bg={theme.headerBg}>
        <span fg={theme.fgDim}>{padRight(hiddenLeft, gutter)}</span>
        {visibleCols.map((ci, vi) => {
          const col = columns[ci]!;
          const sortMark = sort?.column === col ? (sort.dir === "asc" ? "▲" : "▼") : "";
          const label = sortMark ? `${truncate(col, widths[ci]! - 1)}${sortMark}` : col;
          const isCur = ci === colCursor && active;
          return (
            <span key={col} fg={isCur ? theme.yellow : theme.accent}>
              {(vi > 0 ? SEP : "") + padRight(label, widths[ci]!)}
            </span>
          );
        })}
        <span fg={theme.fgDim}>{hiddenRight}</span>
      </text>
      {/* header: types */}
      <text bg={theme.headerBg}>
        <span>{padRight("", gutter)}</span>
        {visibleCols.map((ci, vi) => {
          const col = columns[ci]!;
          const type = result.columnTypes[col] ?? "";
          return (
            <span key={col} fg={typeColor(type)}>
              {(vi > 0 ? SEP : "") + padRight(type.toLowerCase(), widths[ci]!)}
            </span>
          );
        })}
      </text>
      {visibleRows.map((row, vi) => {
        const ri = rowOffset + vi;
        const selected = ri === rowCursor;
        const bg = selected && active ? theme.selectionBg : ri % 2 === 1 ? theme.zebra : undefined;
        return (
          <text key={ri} bg={bg}>
            <span fg={selected ? theme.yellow : theme.fgDim}>{padLeft(String(ri + 1), gutter - 1) + " "}</span>
            {visibleCols.map((ci, cj) => {
              const col = columns[ci]!;
              const value = row[col];
              const isNull = value === null || value === undefined;
              const isCurCell = selected && ci === colCursor && active;
              return (
                <span
                  key={col}
                  fg={isCurCell ? theme.cursorFg : isNull ? theme.fgDim : theme.fg}
                  bg={isCurCell ? theme.cursorBg : undefined}
                >
                  {(cj > 0 ? SEP : "") + cell(col, ci, value)}
                </span>
              );
            })}
          </text>
        );
      })}
    </box>
  );
}
