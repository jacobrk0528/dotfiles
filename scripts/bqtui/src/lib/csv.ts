import type { QueryResult } from "./bq";
import { stringifyCell } from "./util";

function escapeCsvField(value: unknown): string {
  const str = value === null || value === undefined ? "" : stringifyCell(value);
  if (/[",\n\r]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

export function resultToCsv(result: QueryResult): string {
  const lines: string[] = [];
  lines.push(result.columns.map(escapeCsvField).join(","));
  for (const row of result.rows) {
    lines.push(result.columns.map((col) => escapeCsvField(row[col])).join(","));
  }
  return lines.join("\n") + "\n";
}

/** Tab-separated, handy for pasting straight into a spreadsheet. */
export function resultToTsv(result: QueryResult): string {
  const lines: string[] = [];
  lines.push(result.columns.join("\t"));
  for (const row of result.rows) {
    lines.push(
      result.columns
        .map((col) => (row[col] === null || row[col] === undefined ? "" : stringifyCell(row[col]).replace(/[\t\n\r]/g, " ")))
        .join("\t"),
    );
  }
  return lines.join("\n") + "\n";
}

/** JSON array of objects with keys in column order. */
export function resultToJson(result: QueryResult): string {
  const ordered = result.rows.map((row) => {
    const o: Record<string, unknown> = {};
    for (const col of result.columns) o[col] = row[col] ?? null;
    return o;
  });
  return JSON.stringify(ordered, null, 2) + "\n";
}

export function rowToTsv(result: QueryResult, rowIndex: number): string {
  const row = result.rows[rowIndex];
  if (!row) return "";
  return result.columns.map((col) => stringifyCell(row[col])).join("\t");
}

export function rowToJson(result: QueryResult, rowIndex: number): string {
  const row = result.rows[rowIndex];
  if (!row) return "";
  const o: Record<string, unknown> = {};
  for (const col of result.columns) o[col] = row[col] ?? null;
  return JSON.stringify(o, null, 2);
}
