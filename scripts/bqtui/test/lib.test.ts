import { describe, expect, test } from "bun:test";
import { resultToCsv, resultToJson, resultToTsv, rowToJson } from "../src/lib/csv";
import { tokenizeSql } from "../src/lib/sqlTokens";
import { parseBqError, stripProgress, type QueryResult } from "../src/lib/bq";
import { estimateCostUsd, formatBytes, formatDuration, oneLine, padLeft, padRight, stringifyCell, truncate } from "../src/lib/util";
import { highlightLines } from "../src/components/HighlightedSql";

const result: QueryResult = {
  jobId: "j",
  columns: ["zeta", "alpha", "s"],
  columnTypes: { zeta: "INTEGER", alpha: "STRING", s: "RECORD" },
  rows: [
    { alpha: "hi, there", zeta: "1", s: { x: "1" } },
    { alpha: 'line\nbreak "q"', zeta: null, s: null },
  ],
  truncated: false,
  elapsedMs: 10,
};

describe("csv/json export", () => {
  test("csv keeps column order, quotes commas/newlines/quotes", () => {
    const csv = resultToCsv(result);
    expect(csv.split("\n")[0]).toBe("zeta,alpha,s");
    expect(csv).toContain('1,"hi, there","{""x"":""1""}"');
    expect(csv).toContain('"line\nbreak ""q"""');
  });
  test("tsv flattens newlines and blanks nulls", () => {
    const tsv = resultToTsv(result);
    expect(tsv.split("\n")[2]).toBe('\tline break "q"\t');
  });
  test("json preserves column order and nulls", () => {
    const parsed = JSON.parse(resultToJson(result));
    expect(Object.keys(parsed[0])).toEqual(["zeta", "alpha", "s"]);
    expect(parsed[1].zeta).toBeNull();
    expect(JSON.parse(rowToJson(result, 0)).s).toEqual({ x: "1" });
  });
});

describe("sql tokenizer", () => {
  test("classifies keywords, functions, strings, numbers, comments", () => {
    const src = "SELECT COUNT(*) AS n, 'x' FROM `p.d.t` -- c\nWHERE a >= 1.5e3 /* b */ AND d = DATE '2020-01-01'";
    const kinds = tokenizeSql(src).map((t) => `${t.kind}:${src.slice(t.start, t.end)}`);
    expect(kinds).toContain("keyword:SELECT");
    expect(kinds).toContain("function:COUNT");
    expect(kinds).toContain("string:'x'");
    expect(kinds).toContain("identifier:`p.d.t`");
    expect(kinds).toContain("comment:-- c");
    expect(kinds).toContain("comment:/* b */");
    expect(kinds).toContain("number:1.5e3");
    expect(kinds).toContain("type:DATE");
    expect(kinds).toContain("operator:>=");
  });
  test("handles raw and triple-quoted strings and unterminated input", () => {
    const src = `r"a\\b" '''multi\nline''' "unterminated`;
    const toks = tokenizeSql(src);
    expect(toks.map((t) => t.kind)).toEqual(["string", "string", "string"]);
    expect(src.slice(toks[1]!.start, toks[1]!.end)).toBe("'''multi\nline'''");
  });
  test("highlightLines splits multi-line tokens per line", () => {
    const lines = highlightLines("SELECT 1 /* a\nb */ FROM t");
    expect(lines.length).toBe(2);
    expect(lines[1]!.map((s) => s.text).join("")).toBe("b */ FROM t");
  });
});

describe("bq output cleanup", () => {
  test("stripProgress removes progress text and stays linear on huge lines", () => {
    const rows = JSON.stringify(Array.from({ length: 20000 }, (_, i) => ({ id: i, name: `table_${i}` })));
    const input = `Waiting on bqjob_r1 ... (0s) Current status: RUNNING   Waiting on bqjob_r1 ... (1s) Current status: DONE   \n${rows}\n`;
    const t0 = performance.now();
    const out = stripProgress(input);
    expect(performance.now() - t0).toBeLessThan(200);
    expect(JSON.parse(out).length).toBe(20000);
    expect(stripProgress("Waiting on bqjob_r2 ... DONE   [[{\"a\":1}]]\n")).toBe('[[{"a":1}]]');
    expect(stripProgress("plain output\n")).toBe("plain output");
  });
});

describe("bq error parsing", () => {
  test("extracts the message after the job id", () => {
    const stderr = `BigQuery error in query operation: Error processing job\n'narsil:bqjob_r1_1': Table "bar" must be\nqualified with a dataset (e.g. dataset.table).`;
    expect(parseBqError(stderr)).toBe('Table "bar" must be qualified with a dataset (e.g. dataset.table).');
  });
  test("falls back cleanly", () => {
    expect(parseBqError("", "nope")).toBe("nope");
    expect(parseBqError("Waiting on bqjob_r1 ... (0s)\nSomething else\n")).toBe("Something else");
  });
});

describe("util", () => {
  test("formatting helpers", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(1020108715)).toBe("973 MiB");
    expect(formatBytes(5 * 1024 ** 4)).toBe("5.00 TiB");
    expect(formatDuration(250)).toBe("250 ms");
    expect(formatDuration(1500)).toBe("1.5 s");
    expect(formatDuration(65_000)).toBe("1m 5s");
    expect(estimateCostUsd(0)).toBe("$0.00");
    expect(estimateCostUsd(1024 ** 4)).toBe("$6.25");
    expect(estimateCostUsd(1024)).toBe("<$0.01");
  });
  test("cell/text helpers", () => {
    expect(stringifyCell(null)).toBe("NULL");
    expect(stringifyCell({ a: 1 })).toBe('{"a":1}');
    expect(truncate("abcdef", 4)).toBe("abc…");
    expect(padRight("ab", 4)).toBe("ab  ");
    expect(padLeft("ab", 4)).toBe("  ab");
    expect(oneLine("a\n  b\tc", 10)).toBe("a b c");
  });
});
