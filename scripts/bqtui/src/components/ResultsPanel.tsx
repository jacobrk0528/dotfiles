import type { QueryResult } from "../lib/bq";

interface ResultsPanelProps {
  result: QueryResult | null;
  error: string | null;
  loading: boolean;
  focused: boolean;
}

const MAX_COL_WIDTH = 28;

function formatCell(value: unknown): string {
  if (value === null || value === undefined) return "NULL";
  return String(value);
}

function computeWidths(result: QueryResult): number[] {
  return result.columns.map((col) => {
    let width = col.length;
    for (const row of result.rows) {
      width = Math.max(width, formatCell(row[col]).length);
    }
    return Math.min(width, MAX_COL_WIDTH);
  });
}

function padCell(value: string, width: number): string {
  const truncated = value.length > width ? value.slice(0, width - 1) + "…" : value;
  return truncated.padEnd(width, " ");
}

export function ResultsPanel({ result, error, loading, focused }: ResultsPanelProps) {
  if (loading) {
    return (
      <box style={{ padding: 1 }}>
        <text fg="#e0af68">Running query…</text>
      </box>
    );
  }
  if (error) {
    return (
      <box style={{ padding: 1 }}>
        <text fg="red">{error}</text>
      </box>
    );
  }
  if (!result) {
    return (
      <box style={{ padding: 1 }}>
        <text fg="#666666">Run a query (Ctrl+Enter) to see results here.</text>
      </box>
    );
  }
  if (result.rows.length === 0) {
    return (
      <box style={{ padding: 1 }}>
        <text fg="#888888">Query returned no rows.</text>
      </box>
    );
  }

  const widths = computeWidths(result);
  const headerLine = result.columns.map((col, i) => padCell(col, widths[i]!)).join(" │ ");
  const separator = widths.map((w) => "─".repeat(w)).join("─┼─");

  return (
    <scrollbox
      focused={focused}
      style={{ flexGrow: 1 }}
      rootOptions={{ backgroundColor: "#0d1117" }}
      viewportOptions={{ backgroundColor: "#0d1117" }}
    >
      <box style={{ paddingLeft: 1 }}>
        <text fg="#7aa2f7">
          <strong>{headerLine}</strong>
        </text>
      </box>
      <box style={{ paddingLeft: 1 }}>
        <text fg="#555555">{separator}</text>
      </box>
      {result.rows.map((row, i) => (
        <box key={i} style={{ paddingLeft: 1 }}>
          <text fg="#c0caf5">
            {result.columns.map((col, ci) => padCell(formatCell(row[col]), widths[ci]!)).join(" │ ")}
          </text>
        </box>
      ))}
      <box style={{ paddingLeft: 1, paddingTop: 1 }}>
        <text fg="#888888">
          {result.rows.length} row{result.rows.length === 1 ? "" : "s"}
        </text>
      </box>
    </scrollbox>
  );
}
