import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { captureOrigin, parseOrigin, withDesktopSession } from "../src/desktop-session.ts";
import { setRunner } from "../src/exec.ts";
import { focusTiming, revealWindow } from "../src/harness/hypr.ts";
import { withSignal } from "../src/runtime.ts";

let dir: string;
let current: string;
let special: string;
let commands: string[];
const originalTiming = { ...focusTiming };
const win = (address: string, cls: string, ws: number, name: string) => ({ address, class: cls, title: cls, monitor: 3, workspace: { id: ws, name }, at: [-1907, 69], size: [1894, 914], focusHistoryID: cls === "terminal" ? 0 : 1, pid: 1 });

beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "desktop-session-test-"));
  process.env.JEV_PILOT_RUNTIME = dir;
  Object.assign(focusTiming, { poll: 1, timeout: 20, settle: 0 });
  current = "0xaaa";
  special = "";
  commands = [];
  setRunner(async (cmd) => {
    if (cmd[0] !== "hyprctl") throw new Error(`unexpected command ${cmd}`);
    if (cmd[1] === "dispatch") {
      const expr = cmd[2]!;
      commands.push(expr);
      if (expr.includes("toggle_special")) special = special ? "" : "special:slack";
      const focused = /window = "address:(0x\w+)"/.exec(expr);
      if (focused) current = focused[1]!;
      return { stdout: "ok", stderr: "", code: 0 };
    }
    const wins = [win("0xaaa", "terminal", 1, "1"), win("0xbbb", "slack", -96, "special:slack")];
    const data: Record<string, unknown> = {
      clients: wins, activewindow: wins.find((w) => w.address === current) ?? {}, cursorpos: { x: -1000, y: 500 },
      monitors: [{ id: 3, name: "DP-6", focused: true, activeWorkspace: { id: 1, name: "1" }, specialWorkspace: { id: special ? -96 : 0, name: special } }],
    };
    return { stdout: JSON.stringify(data[cmd[2]!]), stderr: "", code: 0 };
  });
});
afterEach(() => {
  setRunner(null);
  Object.assign(focusTiming, originalTiming);
  delete process.env.JEV_PILOT_RUNTIME;
  rmSync(dir, { recursive: true, force: true });
});

test("reveals a special workspace once and refreshes its focused window", async () => {
  const first = await revealWindow("0xbbb");
  await revealWindow("0xbbb");
  expect(first.at[0]).toBe(-1907);
  expect(special).toBe("special:slack");
  expect(current).toBe("0xbbb");
  expect(commands.filter((c) => c.includes("toggle_special"))).toHaveLength(1);
});

test("origin can be passed by the prompt before it takes focus", async () => {
  const origin = await captureOrigin("DP-6");
  expect(parseOrigin(JSON.stringify(origin))).toEqual(origin);
  expect(origin.window).toBe("0xaaa");
  expect(() => parseOrigin('{"window":"bad"}')).toThrow();
});

test("a failed lookup restores the prior special-workspace visibility and focus", async () => {
  await expect(withDesktopSession(async () => {
    await revealWindow("0xbbb");
    throw new Error("OCR failed");
  }, { restore: true })).rejects.toThrow("OCR failed");
  expect(current).toBe("0xaaa");
  expect(special).toBe("");
  expect(commands.at(-1)).toContain("cursor.move");
});

test("cancellation still runs restoration with a separate cleanup signal", async () => {
  const controller = new AbortController();
  await expect(withSignal(controller.signal, () => withDesktopSession(async () => {
    await revealWindow("0xbbb");
    controller.abort(new Error("cancel fixture"));
    controller.signal.throwIfAborted();
  }, { restore: true }))).rejects.toThrow("cancel fixture");
  expect(current).toBe("0xaaa");
  expect(special).toBe("");
});

test("simultaneous requests cannot own desktop input together", async () => {
  let release!: () => void;
  let entered!: () => void;
  const ready = new Promise<void>((r) => { entered = r; });
  const wait = new Promise<void>((r) => { release = r; });
  const order: string[] = [];
  const first = withDesktopSession(async () => { order.push("first"); entered(); await wait; order.push("released"); });
  await ready;
  const second = withDesktopSession(async () => { order.push("second"); });
  await Bun.sleep(30);
  expect(order).toEqual(["first"]);
  release();
  await Promise.all([first, second]);
  expect(order).toEqual(["first", "released", "second"]);
});
