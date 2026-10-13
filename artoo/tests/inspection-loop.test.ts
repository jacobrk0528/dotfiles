import { afterEach, expect, test } from "bun:test";
import { setRunner } from "../src/exec.ts";
import { setJsonCaller, type JsonOptions } from "../src/llm.ts";
import { runOnSurface, type PlanStep } from "../src/planner.ts";
import { TaskProgress } from "../src/task-progress.ts";
import type { Observation, Surface } from "../src/surface.ts";

afterEach(() => { setJsonCaller(null); setRunner(null); });

test("edit -> read field -> back -> next row audits every item exactly once", async () => {
  const previousCdp = process.env.JEV_CDP_URL;
  process.env.JEV_CDP_URL = "http://127.0.0.1:1";
  setRunner(async () => ({ stdout: "[]", stderr: "", code: 0 }));
  let page = "list";
  const visited: string[] = [];
  const plans: any[] = [];
  const events: { type: string; data: Record<string, unknown> }[] = [];
  const names = ["sourceA", "sourceB", "sourceC"];
  const owners: Record<string, string> = { sourceA: "Jacob Krebs", sourceB: "Viewer", sourceC: "Jacob Krebs" };
  const observe = async (): Promise<Observation> => ({
    id: page, width: 100, height: 100, context: { window: "Data sources" },
    content: page === "list" ? names.join("\n") : `${page}\nData credentials:\n${owners[page]}`,
    targets: page === "list" ? names.map((name, i) => ({ id: `${name}-edit`, label: "Edit", description: 'button "Edit" (middle-center)', x: 90, y: 20 + i * 30 })) : [{ id: "back", label: "Back", description: 'button "Back"', x: 5, y: 5 }],
  });
  const surface: Surface = {
    kind: "fixture", observe, perceive: async () => (await observe()).targets, context: async () => ({ window: "Data sources" }),
    click: async (t) => {
      if (t.id === "back") page = "list";
      else { page = t.id!.replace(/-edit$/, ""); visited.push(page); }
    },
    key: async () => { throw new Error("unexpected key"); },
    typeFocused: async () => { throw new Error("audit must not type"); },
    scroll: async () => { throw new Error("all fixture rows are visible"); }, close: () => {},
  };
  setJsonCaller(async <T>(opts: JsonOptions): Promise<T> => {
    if (opts.name === "operation_effect") return { effect: "navigate", target_matches: true, reason: "open an inspection view" } as T;
    if (opts.name === "verify_desktop_result") return { supported: true, reason: "all three rows checked" } as T;
    if (opts.name !== "desktop_plan") throw new Error(`unexpected model call ${opts.name}`);
    const input = opts.input as any;
    plans.push(input.task_progress);
    const checked = input.task_progress.checked.map((x: any) => x.key);
    const pending = names.filter((n) => !checked.includes(n));
    const steps: PlanStep[] = [];
    const progress = { discovered: names, checked: [] as any[], list_complete: true };
    if (page !== "list") progress.checked.push({ key: page, result: owners[page], evidence: ["Data credentials:", owners[page]] });
    if (page !== "list" || pending.length) steps.push({ action: "click", target: page !== "list" ? "e1" : `e${names.indexOf(pending[0]!) + 1}`, text: null, key: null, direction: null, x: null, y: null, purpose: "inspect next row" });
    return { status: steps.length ? "continue" : "answer", message: steps.length ? "Inspecting" : "sourceB uses Viewer; all three sources checked.", evidence: "Recorded credential values for each source", progress, steps } as T;
  });
  try {
    const result = await runOnSurface("Check every source credential without changing anything", surface, {
      confirm: async () => { throw new Error("read-only audit should not ask"); }, print: () => {},
      log: { dir: "/unused", event: (type, data) => { events.push({ type, data }); } },
    });
    expect(result.status).toBe("answer");
    expect(result.message).toContain("sourceB uses Viewer");
    expect(visited).toEqual(names);
    expect(plans.at(-1).checked).toHaveLength(3);
    expect(events.some((e) => e.type === "task_progress" && (e.data.checked as any[]).length === 3)).toBe(true);
  } finally {
    if (previousCdp === undefined) delete process.env.JEV_CDP_URL;
    else process.env.JEV_CDP_URL = previousCdp;
  }
});

test("returning to a list cannot erase findings or complete with unchecked rows", () => {
  const p = new TaskProgress();
  p.discover(["A", "B"]);
  p.record({ key: "A", result: "Jacob Krebs", evidence: ["Jacob Krebs"], observation: "detail-A" });
  p.discover(["A", "B"]);
  p.listComplete = true;
  expect(p.snapshot().pending).toEqual(["B"]);
  expect(p.completionBlocker()).toContain("B");
  expect(p.partialSummary()).toContain("A: Jacob Krebs");
  expect(TaskProgress.supportedByText({ key: "B", result: "Viewer", evidence: ["Viewer"] }, "A Data credentials Jacob Krebs")).toBe(false);
});

// Fills rows from a list it noted in the checklist, never ticking the items off one by one.
function entryFixture(verify: (input: any) => { supported: boolean; reason: string }) {
  setRunner(async () => ({ stdout: "[]", stderr: "", code: 0 }));
  const rows = ["Sep 8 — SOFI PLUS", "Sep 8 — From Savings"];
  let typed = false;
  const observe = async (): Promise<Observation> => ({
    id: typed ? "filled" : "empty", width: 100, height: 100, context: { window: "Checkbook" },
    content: typed ? "9/8/26 SoFi Plus\n9/8/26 From Savings" : "empty rows", targets: [],
  });
  const surface: Surface = {
    kind: "fixture", observe, perceive: async () => [], context: async () => ({ window: "Checkbook" }),
    click: async () => { throw new Error("unexpected click"); },
    key: async () => { typed = true; },
    typeFocused: async () => { typed = true; return true; },
    scroll: async () => { throw new Error("unexpected scroll"); }, close: () => {},
  };
  const verifications: any[] = [];
  let plans = 0;
  setJsonCaller(async <T>(opts: JsonOptions): Promise<T> => {
    if (opts.name === "operation_effect") return { effect: "navigate", target_matches: true, reason: "fixture" } as T;
    if (opts.name === "verify_desktop_result") { verifications.push(opts); return verify(opts.input) as T; }
    if (opts.name !== "desktop_plan") throw new Error(`unexpected model call ${opts.name}`);
    plans++;
    const progress = { discovered: rows, checked: [], list_complete: true };
    if (!typed) return { status: "continue", message: "Entering rows", evidence: "", progress, steps: [{ action: "key", target: null, text: null, key: "enter", direction: null, x: null, y: null, purpose: "enter the rows" }] } as T;
    return { status: "done", message: "Filled 2 rows.", evidence: "Both rows are visible in the sheet", progress, steps: [] } as T;
  });
  const io = { confirm: async () => true, print: () => {}, log: { dir: "/unused", event: () => {} } };
  return { surface, io, verifications, plans: () => plans };
}

test("a finished action is judged by the verifier, not vetoed by unticked checklist items", async () => {
  const previousCdp = process.env.JEV_CDP_URL;
  process.env.JEV_CDP_URL = "http://127.0.0.1:1";
  const f = entryFixture(() => ({ supported: true, reason: "both rows are in the sheet" }));
  try {
    const result = await runOnSurface("fill in the sheet", f.surface, f.io);
    expect(result).toMatchObject({ status: "done", message: "Filled 2 rows." });
    // One plan to type, one to finish: no rounds wasted repeating "done".
    expect(f.plans()).toBe(2);
    expect(f.verifications).toHaveLength(1);
    expect(f.verifications[0].input.unconfirmed_items).toEqual(["Sep 8 — SOFI PLUS", "Sep 8 — From Savings"]);
    expect(f.verifications[0].instructions).toContain("unconfirmed_items");
  } finally {
    if (previousCdp === undefined) delete process.env.JEV_CDP_URL;
    else process.env.JEV_CDP_URL = previousCdp;
  }
});

test("giving up after an unconfirmed completion says what was claimed and why it wasn't accepted", async () => {
  const previousCdp = process.env.JEV_CDP_URL;
  process.env.JEV_CDP_URL = "http://127.0.0.1:1";
  const f = entryFixture(() => ({ supported: false, reason: "the second row's amount is not visible" }));
  try {
    const result = await runOnSurface("fill in the sheet", f.surface, f.io);
    expect(result.status).toBe("gave_up");
    expect(result.message).toStartWith("Filled 2 rows.");
    expect(result.message).toContain("could not be confirmed: the second row's amount is not visible");
    expect(result.message).not.toContain("Still unchecked");
    expect(result.message).not.toContain("The screen did not change");
  } finally {
    if (previousCdp === undefined) delete process.env.JEV_CDP_URL;
    else process.env.JEV_CDP_URL = previousCdp;
  }
});

// A surface that records what was pressed; the screen text changes with every key.
function keyFixture(plan: (input: any, round: number) => any) {
  setRunner(async () => ({ stdout: "[]", stderr: "", code: 0 }));
  const pressed: string[] = [];
  const inputs: any[] = [];
  const observe = async (): Promise<Observation> => ({
    id: `o${pressed.length}`, width: 100, height: 100, context: { window: "Editor" },
    content: `pressed: ${pressed.join(" ")}`, targets: [],
  });
  const surface: Surface = {
    kind: "fixture", observe, perceive: async () => [], context: async () => ({ window: "Editor" }),
    click: async () => { throw new Error("unexpected click"); },
    key: async (k) => { pressed.push(k); },
    typeFocused: async () => true,
    scroll: async () => {}, close: () => {},
  };
  setJsonCaller(async <T>(opts: JsonOptions): Promise<T> => {
    if (opts.name === "operation_effect") return { effect: "navigate", target_matches: true, reason: "fixture" } as T;
    if (opts.name === "verify_desktop_result") return { supported: true, reason: "ok" } as T;
    if (opts.name !== "desktop_plan") throw new Error(`unexpected model call ${opts.name}`);
    inputs.push(opts.input);
    return plan(opts.input, inputs.length) as T;
  });
  const io = { confirm: async () => true, print: () => {}, log: { dir: "/unused", event: () => {} } };
  return { surface, io, pressed, inputs };
}
const keyStep = (key: string): PlanStep => ({ action: "key", target: null, text: null, key, direction: null, x: null, y: null, purpose: "fixture" });
const noProgress = { discovered: [], checked: [], list_complete: false };
const withCdpOff = async (fn: () => Promise<void>) => {
  const previousCdp = process.env.JEV_CDP_URL;
  process.env.JEV_CDP_URL = "http://127.0.0.1:1";
  try { await fn(); } finally {
    if (previousCdp === undefined) delete process.env.JEV_CDP_URL;
    else process.env.JEV_CDP_URL = previousCdp;
  }
};

test("one plan can line up several operations; they run in order without re-planning", () => withCdpOff(async () => {
  const f = keyFixture((_input, round) => round === 1
    ? { status: "continue", message: "Three keys", evidence: "", notes: null, progress: noProgress, steps: [keyStep("ctrl+k"), keyStep("down"), keyStep("enter")] }
    : { status: "done", message: "Pressed them.", evidence: "all three show", notes: null, progress: noProgress, steps: [] });
  const result = await runOnSurface("press the keys", f.surface, f.io);
  expect(result.status).toBe("done");
  expect(f.pressed).toEqual(["ctrl+k", "down", "enter"]);
  // Two planner calls for three operations.
  expect(f.inputs).toHaveLength(2);
  expect(f.inputs[1].steps_done.filter((s: string) => s.startsWith("ok:"))).toHaveLength(3);
}));

test("a failed operation ends the batch and the planner is told the rest did not run", () => withCdpOff(async () => {
  const bad: PlanStep = { ...keyStep(""), key: null };
  const f = keyFixture((_input, round) => round === 1
    ? { status: "continue", message: "Keys", evidence: "", notes: null, progress: noProgress, steps: [keyStep("a"), bad, keyStep("c")] }
    : { status: "done", message: "Stopped.", evidence: "", notes: null, progress: noProgress, steps: [] });
  await runOnSurface("press the keys", f.surface, f.io);
  expect(f.pressed).toEqual(["a"]);
  expect(f.inputs[1].steps_done).toContain("failed: no key specified");
  expect(f.inputs[1].steps_done).toContain("The 1 operation(s) planned after it were not run.");
}));

test("notes come back to the planner each round, and null keeps them", () => withCdpOff(async () => {
  const f = keyFixture((_input, round) => round === 1
    ? { status: "continue", message: "Read the list", evidence: "", notes: "rows: A, B, C", progress: noProgress, steps: [keyStep("a")] }
    : round === 2
      ? { status: "continue", message: "Typing", evidence: "", notes: null, progress: noProgress, steps: [keyStep("b")] }
      : { status: "done", message: "Done.", evidence: "", notes: null, progress: noProgress, steps: [] });
  await runOnSurface("enter the rows", f.surface, f.io);
  expect(f.inputs.map((i) => i.notes)).toEqual(["", "rows: A, B, C", "rows: A, B, C"]);
}));
