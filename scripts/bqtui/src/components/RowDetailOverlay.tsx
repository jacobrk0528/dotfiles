import { useState } from "react";
import { useKeyboard } from "@opentui/react";
import type { Row } from "../lib/bq";
import { theme, typeColor } from "../lib/theme";
import { padRight, truncate } from "../lib/util";
import type { QueryTab } from "../types";

interface RowDetailOverlayProps {
  tab: QueryTab;
  row: Row;
  rowIndex: number;
  width: number;
  height: number;
  onClose: () => void;
  onCopy: (text: string, label: string) => void;
}

function pretty(value: unknown): string[] {
  if (value === null || value === undefined) return ["NULL"];
  if (typeof value === "object") return JSON.stringify(value, null, 2).split("\n");
  return String(value).split("\n");
}

interface Line {
  name: string;
  type: string;
  text: string;
  isNull: boolean;
}

export function RowDetailOverlay({ tab, row, rowIndex, width, height, onClose, onCopy }: RowDetailOverlayProps) {
  const result = tab.result!;
  const [offset, setOffset] = useState(0);
  const boxWidth = Math.min(width - 4, 120);
  const boxHeight = Math.min(height - 2, 40);
  const bodyHeight = boxHeight - 3;
  const nameWidth = Math.min(32, Math.max(8, ...result.columns.map((c) => c.length)) + 2);

  const lines: Line[] = [];
  for (const col of result.columns) {
    const type = (result.columnTypes[col] ?? "").toLowerCase();
    const parts = pretty(row[col]);
    const isNull = row[col] === null || row[col] === undefined;
    parts.forEach((text, i) => lines.push({ name: i === 0 ? col : "", type: i === 0 ? type : "", text, isNull }));
  }
  const maxOffset = Math.max(0, lines.length - bodyHeight);

  useKeyboard((key) => {
    if (key.name === "escape" || key.name === "q" || key.name === "return") {
      key.preventDefault();
      onClose();
    } else if (key.name === "j" || key.name === "down") setOffset((o) => Math.min(maxOffset, o + 1));
    else if (key.name === "k" || key.name === "up") setOffset((o) => Math.max(0, o - 1));
    else if (key.name === "pagedown") setOffset((o) => Math.min(maxOffset, o + bodyHeight));
    else if (key.name === "pageup") setOffset((o) => Math.max(0, o - bodyHeight));
    else if (key.name === "g") setOffset(key.shift ? maxOffset : 0);
    else if (key.name === "y") {
      const o: Record<string, unknown> = {};
      for (const c of result.columns) o[c] = row[c] ?? null;
      onCopy(JSON.stringify(o, null, 2), `row ${rowIndex + 1} (JSON)`);
    }
  });

  const valueWidth = Math.max(10, boxWidth - nameWidth - 16);
  const visible = lines.slice(offset, offset + bodyHeight);

  return (
    <box
      title={` Row ${rowIndex + 1} of ${result.rows.length} `}
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
        paddingLeft: 1,
        paddingRight: 1,
        overflow: "hidden",
      }}
    >
      {visible.map((l, i) => (
        <text key={offset + i} wrapMode="none">
          <span fg={theme.accent}>{padRight(l.name, nameWidth)}</span>
          <span fg={typeColor(l.type)}>{padRight(l.type, 11)}</span>
          <span fg={l.isNull ? theme.fgDim : theme.fg}>{truncate(l.text, valueWidth)}</span>
        </text>
      ))}
      <box style={{ flexGrow: 1 }} />
      <text fg={theme.fgDim} wrapMode="none">
        {`j/k scroll · y copy as JSON · Esc close${lines.length > bodyHeight ? ` · ${offset + 1}-${Math.min(lines.length, offset + bodyHeight)} of ${lines.length}` : ""}`}
      </text>
    </box>
  );
}
