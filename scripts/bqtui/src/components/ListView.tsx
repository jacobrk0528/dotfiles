import type { ReactNode } from "react";
import { theme } from "../lib/theme";

interface ListViewProps {
  /** One rendered line per item (a <text> element or its children). */
  items: ReactNode[];
  cursor: number;
  height: number;
  emptyText?: string;
}

/** Windowed list with a highlighted cursor row. Items must be one line tall. */
export function ListView({ items, cursor, height, emptyText = "(empty)" }: ListViewProps) {
  if (items.length === 0) {
    return (
      <box style={{ height }}>
        <text fg={theme.fgDim}>{emptyText}</text>
      </box>
    );
  }
  const h = Math.max(1, height);
  let start = 0;
  if (cursor >= h) start = cursor - h + 1;
  const visible = items.slice(start, start + h);
  return (
    <box style={{ flexDirection: "column", height: h }}>
      {visible.map((item, i) => {
        const idx = start + i;
        return (
          <box key={idx} style={{ backgroundColor: idx === cursor ? theme.selectionBg : undefined, height: 1 }}>
            {item}
          </box>
        );
      })}
    </box>
  );
}
