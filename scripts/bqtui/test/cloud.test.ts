import { describe, expect, test } from "bun:test";
import { externalTableSql, guessFormat, loadDataSql } from "../src/lib/storage";
import { parseGcloudError } from "../src/lib/gcloud";
import { tabsReducer, makeQueryTab, makeTextTab, makeSchemaTab } from "../src/state/tabs";

describe("storage SQL helpers", () => {
  test("guesses formats from extensions, including compressed", () => {
    expect(guessFormat("gs://b/x.csv")).toBe("CSV");
    expect(guessFormat("gs://b/x.jsonl.gz")).toBe("NEWLINE_DELIMITED_JSON");
    expect(guessFormat("gs://b/x.parquet")).toBe("PARQUET");
    expect(guessFormat("gs://b/x.avro")).toBe("AVRO");
    expect(guessFormat("gs://b/x.html")).toBeUndefined();
  });
  test("external table statement uses a prefix wildcard and a safe name", () => {
    const sql = externalTableSql("gs://stock-ledgers/2026/", "narsil");
    expect(sql).toContain("`narsil.dataset.t_2026`");
    expect(sql).toContain("uris = ['gs://stock-ledgers/2026/*']");
    expect(sql).toContain("skip_leading_rows = 1");
    const parquet = externalTableSql("gs://b/data/events.parquet");
    expect(parquet).toContain("format = 'PARQUET'");
    expect(parquet).not.toContain("skip_leading_rows");
    expect(parquet).toContain("`project.dataset.events`");
  });
  test("load data statement", () => {
    expect(loadDataSql("gs://b/orders-2026.csv", "p")).toContain("LOAD DATA OVERWRITE `p.dataset.orders_2026`");
  });
});

describe("gcloud error parsing", () => {
  test("strips the ERROR prefix", () => {
    expect(parseGcloudError("ERROR: (gcloud.storage.ls) One or more URLs matched no objects.\n", "x")).toBe("One or more URLs matched no objects.");
    expect(parseGcloudError("", "fallback")).toBe("fallback");
  });
});

describe("tabs reducer", () => {
  test("add/activate/close keep a sane active tab", () => {
    let state = { tabs: [makeQueryTab("q1", "Query 1")], activeId: "q1", counter: 2 };
    state = tabsReducer(state, { type: "add", tab: makeSchemaTab("p", "d", "t") });
    expect(state.activeId).toBe("schema:p.d.t");
    state = tabsReducer(state, { type: "add", tab: makeTextTab("text:x", "x", "sql") });
    expect(state.tabs.map((t) => t.id)).toEqual(["q1", "schema:p.d.t", "text:x"]);
    state = tabsReducer(state, { type: "close", id: "text:x" });
    expect(state.activeId).toBe("schema:p.d.t");
    // adding an existing id just activates it
    state = tabsReducer(state, { type: "add", tab: makeQueryTab("q1", "dup") });
    expect(state.tabs.length).toBe(2);
    expect(state.activeId).toBe("q1");
    state = tabsReducer(state, { type: "snapshot", id: "q1", sql: "SELECT 1" });
    expect((state.tabs[0] as any).sql).toBe("SELECT 1");
  });
});
