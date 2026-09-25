import { tokenizeSql, type TokenKind } from "../lib/sqlTokens";
import { theme } from "../lib/theme";

const KIND_COLOR: Record<TokenKind, string> = {
  keyword: theme.magenta,
  type: theme.cyan,
  function: theme.accent,
  string: theme.green,
  number: theme.orange,
  comment: theme.fgDim,
  identifier: theme.fg,
  operator: theme.yellow,
  punct: theme.fgMuted,
  variable: theme.orange,
};

interface Segment {
  text: string;
  color: string;
}

/** Split SQL into per-line colored segments (used by read-only SQL views). */
export function highlightLines(sql: string): Segment[][] {
  const tokens = tokenizeSql(sql);
  const segments: Segment[] = [];
  let pos = 0;
  for (const t of tokens) {
    if (t.start > pos) segments.push({ text: sql.slice(pos, t.start), color: theme.fg });
    segments.push({ text: sql.slice(t.start, t.end), color: KIND_COLOR[t.kind] });
    pos = t.end;
  }
  if (pos < sql.length) segments.push({ text: sql.slice(pos), color: theme.fg });

  const lines: Segment[][] = [[]];
  for (const seg of segments) {
    const parts = seg.text.split("\n");
    parts.forEach((part, i) => {
      if (i > 0) lines.push([]);
      if (part.length > 0) lines[lines.length - 1]!.push({ text: part, color: seg.color });
    });
  }
  return lines;
}

interface HighlightedSqlProps {
  sql: string;
  maxLines?: number;
  lineNumbers?: boolean;
}

export function HighlightedSql({ sql, maxLines, lineNumbers = false }: HighlightedSqlProps) {
  const lines = highlightLines(sql);
  const shown = maxLines ? lines.slice(0, maxLines) : lines;
  const width = String(lines.length).length;
  return (
    <box style={{ flexDirection: "column" }}>
      {shown.map((segs, i) => (
        <text key={i}>
          {lineNumbers ? <span fg={theme.fgDim}>{`${String(i + 1).padStart(width, " ")} │ `}</span> : null}
          {segs.length === 0 ? <span> </span> : null}
          {segs.map((s, j) => (
            <span key={j} fg={s.color}>
              {s.text}
            </span>
          ))}
        </text>
      ))}
      {maxLines && lines.length > maxLines ? (
        <text fg={theme.fgDim}>{`… ${lines.length - maxLines} more lines`}</text>
      ) : null}
    </box>
  );
}
