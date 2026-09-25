import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { readHistory, type HistoryEntry } from "../lib/history";
import { theme } from "../lib/theme";
import { formatBytes, formatDuration, formatNumber, oneLine, padRight, relativeTime } from "../lib/util";
import { HighlightedSql } from "./HighlightedSql";
import { ListView } from "./ListView";

interface HistoryOverlayProps {
  width: number;
  height: number;
  onOpen: (entry: HistoryEntry) => void;
  onCancel: () => void;
}

export function HistoryOverlay({ width, height, onOpen, onCancel }: HistoryOverlayProps) {
  const [entries, setEntries] = useState<HistoryEntry[] | "loading">("loading");
  const [cursor, setCursor] = useState(0);

  useEffect(() => {
    readHistory(500).then(setEntries);
  }, []);

  const list = Array.isArray(entries) ? entries : [];
  const current = list[Math.min(cursor, Math.max(0, list.length - 1))];

  useKeyboard((key) => {
    if (key.name === "escape" || key.name === "q") {
      key.preventDefault();
      onCancel();
      return;
    }
    if (list.length === 0) return;
    if (key.name === "j" || key.name === "down") setCursor((c) => Math.min(c + 1, list.length - 1));
    else if (key.name === "k" || key.name === "up") setCursor((c) => Math.max(c - 1, 0));
    else if (key.name === "pagedown") setCursor((c) => Math.min(c + 10, list.length - 1));
    else if (key.name === "pageup") setCursor((c) => Math.max(c - 10, 0));
    else if (key.name === "g") setCursor(key.shift ? list.length - 1 : 0);
    else if (key.name === "return" && current) onOpen(current);
  });

  const boxWidth = Math.min(width - 4, 120);
  const boxHeight = Math.min(height - 2, 40);
  const listHeight = Math.max(3, Math.floor((boxHeight - 4) * 0.5));
  const previewHeight = boxHeight - 4 - listHeight;
  const sqlWidth = Math.max(10, boxWidth - 44);
  const items = list.map((e, i) => (
    <text key={i}>
      <span fg={e.ok ? theme.green : theme.red}>{e.ok ? " ✓ " : " ✗ "}</span>
      <span fg={theme.fgDim}>{padRight(relativeTime(e.ts), 8)}</span>
      <span fg={theme.fgMuted}>{padRight(e.ok ? `${formatNumber(e.rows ?? 0)} rows` : "error", 12)}</span>
      <span fg={theme.fgMuted}>{padRight(e.bytesProcessed !== undefined ? formatBytes(e.bytesProcessed) : "", 10)}</span>
      <span fg={theme.fgMuted}>{padRight(e.elapsedMs !== undefined ? formatDuration(e.elapsedMs) : "", 8)}</span>
      <span fg={theme.fg}>{oneLine(e.sql, sqlWidth)}</span>
    </text>
  ));

  return (
    <box
      title=" Query history "
      titleColor={theme.yellow}
      border
      borderStyle="rounded"
      borderColor={theme.accent}
      zIndex={50}
      style={{
        position: "absolute",
        top: Math.max(1, Math.floor((height - boxHeight) / 2)),
        left: Math.max(2, Math.floor((width - boxWidth) / 2)),
        width: boxWidth,
        height: boxHeight,
        backgroundColor: theme.overlay,
        flexDirection: "column",
      }}
    >
      {entries === "loading" ? (
        <text fg={theme.yellow}> Loading…</text>
      ) : (
        <ListView items={items} cursor={cursor} height={listHeight} emptyText=" No history yet." />
      )}
      <box style={{ height: 1, borderColor: theme.border }} border={["top"]} />
      <box style={{ height: previewHeight, paddingLeft: 1, overflow: "hidden", flexDirection: "column" }}>
        {current?.error ? <text fg={theme.red}>{oneLine(current.error, boxWidth - 4)}</text> : null}
        {current ? <HighlightedSql sql={current.sql} maxLines={previewHeight - (current.error ? 2 : 1)} /> : null}
      </box>
      <text fg={theme.fgDim}>{" Enter open in new tab · Esc close"}</text>
    </box>
  );
}
