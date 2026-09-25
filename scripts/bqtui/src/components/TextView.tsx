import { useEffect, useMemo, useState } from "react";
import { useKeyboard } from "@opentui/react";
import type { MouseEvent } from "@opentui/core";
import { theme } from "../lib/theme";
import { padRight, truncate } from "../lib/util";
import { highlightLines } from "./HighlightedSql";
import type { TextTab } from "../types";

interface TextViewProps {
  tab: TextTab;
  active: boolean;
  width: number;
  height: number;
  onFocus: () => void;
}

interface Segment {
  text: string;
  color: string;
}

function jsonLines(text: string): Segment[][] {
  return text.split("\n").map((line) => {
    // light JSON coloring: keys, strings, numbers, literals
    const segs: Segment[] = [];
    const re = /("(?:[^"\\]|\\.)*")(\s*:)?|(-?\d+(?:\.\d+)?(?:e[+-]?\d+)?)|(true|false|null)|([{}\[\],])|(\s+)|(.)/gi;
    let m: RegExpExecArray | null;
    while ((m = re.exec(line))) {
      if (m[1] !== undefined) segs.push({ text: m[1] + (m[2] ?? ""), color: m[2] ? theme.accent : theme.green });
      else if (m[3] !== undefined) segs.push({ text: m[3], color: theme.orange });
      else if (m[4] !== undefined) segs.push({ text: m[4], color: theme.magenta });
      else if (m[5] !== undefined) segs.push({ text: m[5], color: theme.fgMuted });
      else segs.push({ text: m[0], color: theme.fg });
    }
    return segs;
  });
}

function sqlxLines(text: string): Segment[][] {
  // sqlx = a JS-ish `config { ... }` block plus SQL; highlight the SQL part with the SQL tokenizer.
  const lines = text.split("\n");
  const out: Segment[][] = [];
  let inConfig = false;
  let depth = 0;
  const sqlChunk: string[] = [];
  const flushSql = () => {
    if (sqlChunk.length === 0) return;
    out.push(...highlightLines(sqlChunk.join("\n")));
    sqlChunk.length = 0;
  };
  for (const line of lines) {
    if (!inConfig && /^\s*(config|js|pre_operations|post_operations)\s*\{/.test(line)) {
      flushSql();
      inConfig = true;
      depth = 0;
    }
    if (inConfig) {
      depth += (line.match(/\{/g) ?? []).length - (line.match(/\}/g) ?? []).length;
      out.push([{ text: line, color: theme.cyan }]);
      if (depth <= 0) inConfig = false;
    } else sqlChunk.push(line);
  }
  flushSql();
  return out;
}

export function TextView({ tab, active, width, height, onFocus }: TextViewProps) {
  const [offset, setOffset] = useState(0);
  const [hOffset, setHOffset] = useState(0);
  useEffect(() => {
    setOffset(0);
    setHOffset(0);
  }, [tab.id]);

  const content = typeof tab.content === "string" ? tab.content : "";
  const lines = useMemo<Segment[][]>(() => {
    if (!content) return [];
    if (tab.language === "sql") return highlightLines(content);
    if (tab.language === "sqlx") return sqlxLines(content);
    if (tab.language === "json") return jsonLines(content);
    return content.split("\n").map((l) => [{ text: l, color: theme.fg }]);
  }, [content, tab.language]);

  const metaHeight = tab.meta.length + (tab.subtitle ? 1 : 0) + (tab.meta.length || tab.subtitle ? 1 : 0);
  const bodyHeight = Math.max(1, height - metaHeight - 1);
  const maxOffset = Math.max(0, lines.length - bodyHeight);
  const gutter = String(Math.max(1, lines.length)).length + 1;
  const bodyWidth = Math.max(10, width - gutter - 2);

  useKeyboard((key) => {
    if (!active) return;
    switch (key.name) {
      case "j":
      case "down":
        setOffset((o) => Math.min(maxOffset, o + 1));
        break;
      case "k":
      case "up":
        setOffset((o) => Math.max(0, o - 1));
        break;
      case "l":
      case "right":
        setHOffset((o) => o + 8);
        break;
      case "h":
      case "left":
        setHOffset((o) => Math.max(0, o - 8));
        break;
      case "0":
        setHOffset(0);
        break;
      case "pagedown":
        setOffset((o) => Math.min(maxOffset, o + bodyHeight));
        break;
      case "pageup":
        setOffset((o) => Math.max(0, o - bodyHeight));
        break;
      case "d":
        if (key.ctrl) setOffset((o) => Math.min(maxOffset, o + Math.floor(bodyHeight / 2)));
        break;
      case "u":
        if (key.ctrl) setOffset((o) => Math.max(0, o - Math.floor(bodyHeight / 2)));
        break;
      case "g":
        setOffset(key.shift ? maxOffset : 0);
        break;
      case "home":
        setOffset(0);
        break;
      case "end":
        setOffset(maxOffset);
        break;
      default:
        break;
    }
  });

  const handleScroll = (e: MouseEvent) => {
    const dir = e.scroll?.direction;
    if (dir === "down") setOffset((o) => Math.min(maxOffset, o + 3));
    else if (dir === "up") setOffset((o) => Math.max(0, o - 3));
  };

  const labelWidth = Math.min(18, Math.max(6, ...tab.meta.map(([k]) => k.length)) + 2);

  return (
    <box style={{ flexDirection: "column", flexGrow: 1, overflow: "hidden" }} onMouseDown={onFocus} onMouseScroll={handleScroll}>
      {tab.subtitle ? (
        <text fg={theme.fgMuted} wrapMode="none">
          {" " + truncate(tab.subtitle, width - 2)}
        </text>
      ) : null}
      {tab.meta.map(([k, v]) => (
        <text key={k} wrapMode="none">
          <span fg={theme.fgDim}>{" " + padRight(k, labelWidth)}</span>
          <span fg={theme.fg}>{truncate(v, width - labelWidth - 3)}</span>
        </text>
      ))}
      {tab.meta.length || tab.subtitle ? <text> </text> : null}
      {tab.content === "loading" ? <text fg={theme.yellow}> Loading…</text> : null}
      {typeof tab.content === "object" ? (
        <text fg={theme.red} wrapMode="word">
          {" " + tab.content.error}
        </text>
      ) : null}
      {typeof tab.content === "string" && lines.length === 0 ? <text fg={theme.fgDim}> (empty)</text> : null}
      {lines.slice(offset, offset + bodyHeight).map((segs, vi) => {
        const i = offset + vi;
        // apply horizontal offset by trimming leading characters across segments
        let skip = hOffset;
        let used = 0;
        const parts: Segment[] = [];
        for (const s of segs) {
          let t = s.text;
          if (skip > 0) {
            const take = Math.min(skip, t.length);
            t = t.slice(take);
            skip -= take;
          }
          if (!t) continue;
          const room = bodyWidth - used;
          if (room <= 0) break;
          const shown = t.length > room ? t.slice(0, room) : t;
          parts.push({ text: shown, color: s.color });
          used += shown.length;
          if (used >= bodyWidth) break;
        }
        return (
          <text key={i} wrapMode="none">
            <span fg={theme.fgDim}>{`${String(i + 1).padStart(gutter - 1, " ")} `}</span>
            {parts.length === 0 ? <span> </span> : null}
            {parts.map((p, j) => (
              <span key={j} fg={p.color}>
                {p.text}
              </span>
            ))}
          </text>
        );
      })}
      <box style={{ flexGrow: 1 }} />
      <text fg={theme.fgDim} wrapMode="none">
        {` ${lines.length ? `${offset + 1}-${Math.min(lines.length, offset + bodyHeight)} of ${lines.length} lines` : ""}${hOffset ? ` · col ${hOffset + 1}` : ""}`}
      </text>
    </box>
  );
}
