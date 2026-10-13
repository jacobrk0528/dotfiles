import { afterEach, beforeEach, expect, test } from "bun:test";
import { sequenceKey } from "../src/harness/input.ts";
import { setJsonCaller } from "../src/llm.ts";
import { runStep, webUrl, type Io, type PlanStep } from "../src/planner.ts";
import type { Observation, Surface } from "../src/surface.ts";

let judgement: { effect: string; always_ask?: boolean; repeatable?: string };
let observation: Observation;
let surface: Surface;
let calls: string[];
let asked: string[];
const step = (v: Partial<PlanStep>): PlanStep => ({ action: "key", target: null, text: null, key: null, direction: null, x: null, y: null, purpose: "test", ...v });
const io = (approvedEdits?: Set<string>, answer = true): Io => ({
  log: { dir: "/unused", event: () => {} }, print: () => {}, approvedEdits,
  confirm: async (message) => { asked.push(message); return answer; },
});

beforeEach(() => {
  judgement = { effect: "navigate" };
  calls = [];
  asked = [];
  // A split view: the bank on the left, the sheet on the right.
  observation = {
    id: "1", width: 800, height: 800, content: "=== pane t1 ===\nbank\n\n=== pane t2 ===\nsheet",
    context: { raw_url: "https://bank.example/checking", panes: "t1; t2" },
    panes: [
      { id: "t1", title: "Checking", site: "bank.example", width: 800, height: 800, active: true },
      { id: "t2", title: "Checkbook", site: "docs.google.com", width: 800, height: 800, active: false },
    ],
    targets: [{ id: "more", pane: "t1", label: "View more", description: 't1: button "View more"', x: 400, y: 700 }],
  };
  surface = {
    kind: "fixture", context: async () => observation.context, perceive: async () => observation.targets,
    observe: async () => structuredClone(observation),
    point: (x, y, pane) => (pane ? { pane, description: "point", label: "point", x: x * 800, y: y * 800 } : null),
    click: async (t, opts) => { calls.push(`click ${t.pane} ${t.x},${t.y}${opts?.count === 2 ? " double" : ""}${opts?.button === "right" ? " right" : ""}`); },
    hover: async (t) => { calls.push(`hover ${t.pane}`); },
    drag: async (from, to) => { calls.push(`drag ${from.x},${from.y} -> ${to.x},${to.y}`); },
    typeFocused: async (text, pane) => { calls.push(`type ${pane} ${text}`); return true; },
    key: async (key, pane) => { calls.push(`key ${pane} ${key}`); },
    sequence: async (items, pane) => { calls.push(`keys ${pane} ${items.join("")}`); },
    scroll: async (amount, at, pane) => { calls.push(`scroll ${at?.pane ?? pane} ${amount}`); },
    close: () => {},
  };
  setJsonCaller(async <T>() => ({ reason: "fixture", target_matches: true, ...judgement }) as T);
});
afterEach(() => setJsonCaller(null));

test("sequence items are literal text unless they are one key in braces", () => {
  expect(sequenceKey("{tab}")).toBe("tab");
  expect(sequenceKey("{ctrl+c}")).toBe("ctrl+c");
  expect(sequenceKey("9/8/26")).toBeNull();
  expect(sequenceKey("{not a key!}")).toBeNull();
  expect(sequenceKey("a {tab} b")).toBeNull();
});

test("open_url takes web addresses only", () => {
  expect(webUrl("https://docs.google.com/spreadsheets")).toBe("https://docs.google.com/spreadsheets");
  expect(webUrl("sheets.google.com")).toBe("https://sheets.google.com/");
  for (const bad of ["file:///etc/passwd", "javascript:alert(1)", "Google Sheets", "", null]) expect(webUrl(bad)).toBeNull();
});

test("a visual point in a split view must name its pane", async () => {
  const blind = await runStep(surface, step({ action: "click", target: "cell A752", x: 0.1, y: 0.9 }), observation, io());
  expect(blind).toContain("set pane");
  expect(calls).toEqual([]);
  expect(await runStep(surface, step({ action: "click", target: "cell A752", x: 0.1, y: 0.9, pane: "t2" }), observation, io())).toStartWith("ok:");
  expect(calls).toEqual(["click t2 80,720"]);
});

test("a pane that is not on screen is refused before anything is sent", async () => {
  expect(await runStep(surface, step({ key: "enter", pane: "t9" }), observation, io())).toContain("pane t9 is not visible");
  expect(calls).toEqual([]);
});

test("pointer variants reach the surface as double, right, hover and drag", async () => {
  const at = { target: "e1" } as const;
  await runStep(surface, step({ action: "double_click", ...at }), observation, io());
  await runStep(surface, step({ action: "right_click", ...at }), observation, io());
  await runStep(surface, step({ action: "hover", ...at }), observation, io());
  await runStep(surface, step({ action: "drag", ...at, to_x: 0.25, to_y: 0.5 }), observation, io());
  expect(calls).toEqual(["click t1 400,700 double", "click t1 400,700 right", "hover t1", "drag 400,700 -> 200,400"]);
  expect(await runStep(surface, step({ action: "drag", ...at }), observation, io())).toContain("to_x/to_y");
});

test("a scroll with a pane but no resolvable target scrolls that pane", async () => {
  expect(await runStep(surface, step({ action: "scroll", direction: "down", pane: "t1", target: null }), observation, io())).toStartWith("ok:");
  expect(calls).toEqual(["scroll t1 5"]);
});

test("a key sequence goes to the named pane", async () => {
  const row = ["9/8/26", "{tab}", "Discover", "{tab}", "{tab}", "401.64", "{enter}"];
  expect(await runStep(surface, step({ action: "keys", pane: "t2", sequence: row }), observation, io())).toStartWith("ok:");
  expect(calls).toEqual(["keys t2 9/8/26{tab}Discover{tab}{tab}401.64{enter}"]);
  expect(await runStep(surface, step({ action: "keys", pane: "t2", sequence: [] }), observation, io())).toContain("non-empty sequence");
});

test("a plain edit is approved once per place, then continues without asking", async () => {
  judgement = { effect: "write", always_ask: false };
  const approved = new Set<string>();
  const row = step({ action: "keys", pane: "t2", sequence: ["x", "{enter}"] });
  expect(await runStep(surface, row, observation, io(approved))).toStartWith("ok:");
  expect(asked).toHaveLength(1);
  expect(asked[0]).toContain("docs.google.com");
  expect(await runStep(surface, row, observation, io(approved))).toStartWith("ok:");
  expect(asked).toHaveLength(1);
  // The yes was for the sheet. The bank in the other pane is a different place.
  expect(await runStep(surface, step({ action: "keys", pane: "t1", sequence: ["x"] }), observation, io(approved))).toStartWith("ok:");
  expect(asked).toHaveLength(2);
});

test("a plain download is approved once per site, separately from edits there", async () => {
  judgement = { effect: "write", always_ask: false, repeatable: "download" };
  const approved = new Set<string>();
  const icon = step({ action: "click", target: "e1" });
  expect(await runStep(surface, icon, observation, io(approved))).toStartWith("ok:");
  expect(asked[0]).toContain("further downloads from bank.example");
  expect(await runStep(surface, icon, observation, io(approved))).toStartWith("ok:");
  expect(asked).toHaveLength(1);
  // Approving downloads from the bank doesn't approve typing into it.
  judgement = { effect: "write", always_ask: false };
  await runStep(surface, step({ action: "keys", pane: "t1", sequence: ["x"] }), observation, io(approved));
  expect(asked).toHaveLength(2);
});

test("a declined edit runs nothing and grants no standing approval", async () => {
  judgement = { effect: "write", always_ask: false };
  const approved = new Set<string>();
  expect(await runStep(surface, step({ action: "keys", pane: "t2", sequence: ["x"] }), observation, io(approved, false))).toBeNull();
  expect(calls).toEqual([]);
  expect(approved.size).toBe(0);
});

test("sends, payments and anything unjudged ask every time, even after a plain edit was approved", async () => {
  const approved = new Set(["docs.google.com"]);
  for (const j of [{ effect: "write", always_ask: true }, { effect: "write" }, { effect: "destructive", always_ask: false }, { effect: "unknown", always_ask: false }]) {
    judgement = j;
    await runStep(surface, step({ key: "enter", pane: "t2" }), observation, io(approved));
  }
  expect(asked).toHaveLength(4);
});

test("without a task-level approval set every write asks", async () => {
  judgement = { effect: "write", always_ask: false };
  const row = step({ action: "keys", pane: "t2", sequence: ["x"] });
  await runStep(surface, row, observation, io());
  await runStep(surface, row, observation, io());
  expect(asked).toHaveLength(2);
});

test("download folders must stay inside the home directory", async () => {
  const { homeFolder } = await import("../src/downloads.ts");
  const { homedir } = await import("node:os");
  expect(homeFolder("~/Downloads/investments/roth_ira/statements")).toBe(`${homedir()}/Downloads/investments/roth_ira/statements`);
  expect(homeFolder("Downloads/x")).toBe(`${homedir()}/Downloads/x`);
  for (const bad of ["/etc", "~/../root", "~", "", null, "/tmp/x"]) expect(homeFolder(bad)).toBeNull();
});
