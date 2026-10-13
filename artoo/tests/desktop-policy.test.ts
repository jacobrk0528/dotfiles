import { afterEach, beforeEach, expect, test } from "bun:test";
import { setJsonCaller } from "../src/llm.ts";
import { actionEffect, authorize, isReadOnlyCommand, type Effect } from "../src/policy.ts";
import { runStep, visualTarget, type PlanStep } from "../src/planner.ts";
import type { Observation, Surface } from "../src/surface.ts";

let effect: Effect;
let observation: Observation;
let surface: Surface;
let calls: string[];
const step = (v: Partial<PlanStep>): PlanStep => ({ action: "key", target: null, text: null, key: null, direction: null, x: null, y: null, purpose: "test", ...v });
const log = { dir: "/unused", event: () => {} };

beforeEach(() => {
  effect = "navigate";
  calls = [];
  observation = { id: "1", width: 100, height: 100, content: "Bryan Search", context: { window: "Slack" }, targets: [{ label: "Search", description: 'searchbox "Search"', x: 20, y: 20, typeable: true }] };
  surface = {
    kind: "fixture", context: async () => observation.context, perceive: async () => observation.targets,
    observe: async () => structuredClone(observation),
    click: async (t) => { calls.push(`click ${t.x},${t.y}`); },
    type: async (_t, text) => { calls.push(`type ${text}`); },
    typeFocused: async (text) => { calls.push(`type ${text}`); return true; },
    key: async (key) => { calls.push(`key ${key}`); }, scroll: async () => { calls.push("scroll"); }, close: () => {},
    point: (x, y) => ({ description: "point", label: "point", x: x * 100 - 1920, y: y * 100 }),
  };
  setJsonCaller(async <T>() => ({ effect, reason: "fixture effect", target_matches: true }) as T);
});
afterEach(() => setJsonCaller(null));

test("reads/navigation are automatic; every write/destructive/unknown operation asks", async () => {
  let asked = 0;
  const io = { confirm: async () => { asked++; return false; } };
  for (const effect of ["read", "navigate"] as const) expect(await authorize({ summary: "x", effect }, io)).toBe(true);
  for (const effect of ["write", "destructive", "unknown"] as const) expect(await authorize({ summary: "x", effect }, io)).toBe(false);
  expect(asked).toBe(3);
  expect(actionEffect("audio.mic")).toBe("write");
  expect(actionEffect("keyboard.key")).toBe("unknown");
});

test("only positively recognized read-only shell commands run automatically", () => {
  for (const cmd of ["df -h", "hyprctl -j clients", "cat '/some file'", "systemctl --user status ydotool --no-pager", "find ~/Downloads/investments -maxdepth 2 -type f", "find ~/x -maxdepth 1 -type f -printf %f\\n"]) expect(isReadOnlyCommand(cmd)).toBe(true);
  for (const cmd of ["hostname new-name", "date -s tomorrow", "cat a > b", "ls; rm a", "cat $(touch x)", "bash -c 'echo hi'", "python -c 'open(\"x\",\"w\")'", "ydotool key 28:1", "systemctl --user restart ydotool", "journalctl --rotate", "find . -delete", "find . -exec rm {} +", "find . -fprint out", "ls \; rm x"]) expect(isReadOnlyCommand(cmd)).toBe(false);
});

test("typing a search query needs no approval", async () => {
  const result = await runStep(surface, step({ action: "type", target: "e1", text: "Bryan" }), structuredClone(observation), { log, print: () => {}, confirm: async () => { throw new Error("should not ask"); } });
  expect(result).toStartWith("ok:");
  expect(calls).toEqual(["type Bryan"]);
});

test("focused-field typing cannot bypass write approval", async () => {
  effect = "write";
  expect(await runStep(surface, step({ action: "type", target: "focused", text: "Hello Bryan" }), observation, { log, print: () => {}, confirm: async () => false })).toBeNull();
  expect(calls).toEqual([]);
});

test("Enter in a message composer cannot bypass send approval", async () => {
  effect = "write";
  expect(await runStep(surface, step({ key: "enter" }), observation, { log, print: () => {}, confirm: async () => false })).toBeNull();
  expect(calls).toEqual([]);
});

test("changing unrelated message content doesn't block a verified navigation shortcut", async () => {
  const original = structuredClone(observation);
  observation.content += "\nA new incoming message";
  const result = await runStep(surface, step({ key: "ctrl+k" }), original, { log, print: () => {}, confirm: async () => { throw new Error("navigation should not ask"); } });
  expect(result).toStartWith("ok:");
  expect(calls).toEqual(["key ctrl+k"]);
});

test("a mismatched focused control never executes even if the action was requested", async () => {
  setJsonCaller(async <T>() => ({ effect: "navigate", reason: "wrong control", target_matches: false }) as T);
  const result = await runStep(surface, step({ key: "enter" }), observation, { log, print: () => {}, confirm: async () => true });
  expect(result).toContain("does not match");
  expect(calls).toEqual([]);
});

test("a Send button asks even if the model would call it navigation", async () => {
  observation.targets[0] = { label: "Send", description: 'button "Send"', x: 10, y: 10 };
  expect(await runStep(surface, step({ action: "click", target: "e1" }), observation, { log, print: () => {}, confirm: async () => false })).toBeNull();
  expect(calls).toEqual([]);
});

test("approval expires when the underlying content changes", async () => {
  effect = "write";
  const result = await runStep(surface, step({ key: "enter" }), structuredClone(observation), { log, print: () => {}, confirm: async () => { observation.content = "Different recipient"; return true; } });
  expect(result).toContain("changed while awaiting approval");
  expect(calls).toEqual([]);
});

test("targets are re-grounded to fresh positions before clicking", async () => {
  const original = structuredClone(observation);
  observation.targets[0]!.x = 80;
  await runStep(surface, step({ action: "click", target: "e1" }), original, { log, print: () => {}, confirm: async () => false });
  expect(calls).toEqual(["click 80,20"]);
});

test("identical Edit labels stay distinct by node identity when the rows move", async () => {
  observation.targets = [
    { id: "row-A-edit", label: "Edit", description: 'button "Edit" (middle-center)', x: 90, y: 20 },
    { id: "row-B-edit", label: "Edit", description: 'button "Edit" (middle-center)', x: 90, y: 60 },
  ];
  const original = structuredClone(observation);
  observation.targets.reverse();
  observation.targets[1]!.y = 80;
  await runStep(surface, step({ action: "click", target: "e1" }), original, { log, print: () => {}, confirm: async () => false });
  expect(calls).toEqual(["click 90,80"]);
});

test("a neighboring Remove button in row context does not make Edit a write", async () => {
  observation.targets[0] = { id: "edit", label: "Edit", description: 'button "Edit" in row [sourceA BigQuery Edit Duplicate Remove]', x: 20, y: 20 };
  const result = await runStep(surface, step({ action: "click", target: "e1" }), observation, { log, print: () => {}, confirm: async () => { throw new Error("inspection should not ask"); } });
  expect(result).toStartWith("ok:");
});

test("visual coordinates support negative monitor offsets and reject invalid points", () => {
  expect(visualTarget(surface, step({ x: 0.5, y: 0.5 }))?.x).toBe(-1870);
  expect(visualTarget(surface, step({ x: 1.01, y: 0.5 }))).toBeNull();
  expect(visualTarget(surface, step({ x: NaN, y: 0.5 }))).toBeNull();
});
