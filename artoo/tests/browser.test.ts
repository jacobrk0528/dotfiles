import { afterEach, beforeEach, expect, test } from "bun:test";
import { setRunner } from "../src/exec.ts";
import { openUrl, timing } from "../src/harness/browser.ts";

const brave = (address: string, ws: number, focusHistoryID: number) => ({
  address, class: "brave-browser", title: "t", workspace: { id: ws, name: String(ws) }, at: [0, 0], size: [1, 1], focusHistoryID, pid: 1,
});

let calls: string[][];
let clients: ReturnType<typeof brave>[];
let active: string | null;
let focusWorks: boolean;

beforeEach(() => {
  Object.assign(timing, { afterFocus: 0, afterNewTab: 0, focusPoll: 1, focusTimeout: 20 });
  calls = [];
  active = "0xterm";
  focusWorks = true;
  clients = [brave("0xold", 3, 5), brave("0xrecent", 3, 2), brave("0xother", 1, 0)];
  setRunner(async (cmd) => {
    calls.push(cmd);
    const [bin, a, b] = cmd;
    if (bin === "hyprctl" && a === "-j") {
      const data = { clients, activewindow: active ? { address: active } : {}, activeworkspace: { id: 1, name: "1" } }[b as string];
      return { stdout: JSON.stringify(data), stderr: "", code: 0 };
    }
    const focused = b?.match(/hl\.dsp\.focus\(\{ window = "address:(0x\w+)" \}\)/);
    if (focused && focusWorks) active = focused[1]!;
    return { stdout: bin === "hyprctl" ? "ok" : "", stderr: "", code: 0 };
  });
});
afterEach(() => setRunner(null));

const actions = () => calls.filter((c) => !(c[0] === "hyprctl" && c[1] === "-j"));

test("reuses the most recent Brave window on the workspace: focus, ctrl+t, type, enter", async () => {
  expect(await openUrl("https://www.youtube.com", 3)).toBe("new_tab");
  expect(actions()).toEqual([
    ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = 3 })"],
    ["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0xrecent" })'],
    ["wtype", "-M", "ctrl", "-k", "t", "-m", "ctrl"],
    ["wtype", "--", "https://www.youtube.com"],
    ["wtype", "-k", "Delete"],
    ["wtype", "-k", "Return"],
  ]);
});

test("no workspace given: uses the current workspace's Brave window", async () => {
  await openUrl("https://mail.google.com");
  expect(actions()[0]).toEqual(["hyprctl", "dispatch", 'hl.dsp.focus({ window = "address:0xother" })']);
});

test("never types if the window doesn't take focus", async () => {
  focusWorks = false;
  await expect(openUrl("https://www.youtube.com", 3)).rejects.toThrow("never took focus");
  expect(actions().some((c) => c[0] === "wtype")).toBe(false);
});

test("falls back to a new window when the workspace has no Brave", async () => {
  expect(await openUrl("https://www.youtube.com", 4)).toBe("new_window");
  expect(actions()).toEqual([
    ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = 4 })"],
    ["hyprctl", "dispatch", 'hl.dsp.exec_cmd("brave --new-window https://www.youtube.com")'],
  ]);
});
