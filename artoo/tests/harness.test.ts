import { afterEach, beforeEach, expect, test } from "bun:test";
import { getAction } from "../src/actions.ts";
import { setRunner } from "../src/exec.ts";
import { parseDesktopEntry } from "../src/harness/apps.ts";
import { lua } from "../src/harness/hypr.ts";
import { keyArgs } from "../src/harness/input.ts";
import { isUsefulLabel, toElements } from "../src/perceive/ocr.ts";

let calls: string[][];

beforeEach(() => {
  calls = [];
  setRunner(async (cmd) => {
    calls.push(cmd);
    return { stdout: cmd[0] === "hyprctl" && cmd[1] === "dispatch" ? "ok" : "", stderr: "", code: 0 };
  });
});
afterEach(() => setRunner(null));

const runAction = (name: string, raw: Record<string, unknown>) => {
  const a = getAction(name)!;
  return a.run(a.params.parse(raw));
};

test("key combos press modifiers, key, then release in reverse", () => {
  expect(keyArgs("ctrl+shift+t")).toEqual(["-M", "ctrl", "-M", "shift", "-k", "t", "-m", "shift", "-m", "ctrl"]);
  expect(keyArgs("enter")).toEqual(["-k", "Return"]);
  expect(keyArgs("super+f5")).toEqual(["-M", "logo", "-k", "F5", "-m", "logo"]);
  expect(() => keyArgs("hyper+x")).toThrow();
});

test("workspace.switch dispatches workspace", async () => {
  await runAction("workspace.switch", { workspace: "3" });
  expect(calls).toEqual([["hyprctl", "dispatch", "hl.dsp.focus({ workspace = 3 })"]]);
});

test("mouse.click moves then clicks with ydotool", async () => {
  await runAction("mouse.click", { x: "100", y: "200.4", button: "right" });
  expect(calls).toEqual([
    ["hyprctl", "dispatch", "hl.dsp.cursor.move({ x = 100, y = 200 })"],
    ["ydotool", "click", "0xC1"],
  ]);
});

test("keyboard.type passes text after --", async () => {
  await runAction("keyboard.type", { text: "-rf hello" });
  expect(calls).toEqual([["wtype", "--", "-rf hello"]]);
});

test("lua() escapes strings and drops nil fields", () => {
  expect(lua({ window: 'title:say "hi"\\n', follow: false, x: undefined })).toBe('{ window = "title:say \\"hi\\"\\\\n", follow = false }');
});

test("move keeps named workspaces as strings", async () => {
  await runAction("window.move_to_workspace", { workspace: "special:slack", selector: "address:0x1" });
  expect(calls).toEqual([["hyprctl", "dispatch", 'hl.dsp.window.move({ window = "address:0x1", workspace = "special:slack", follow = false })']]);
});

test("dispatch failures surface as errors", async () => {
  setRunner(async () => ({ stdout: "Invalid dispatcher", stderr: "", code: 0 }));
  await expect(runAction("workspace.switch", { workspace: 1 })).rejects.toThrow("Invalid dispatcher");
});

test("desktop entries: field codes stripped, hidden entries dropped", () => {
  const app = parseDesktopEntry("brave-browser", "[Desktop Entry]\nType=Application\nName=Brave\nExec=brave %U\n[Desktop Action new]\nName=New Window\n");
  expect(app).toMatchObject({ name: "Brave", exec: "brave" });
  expect(parseDesktopEntry("x", "[Desktop Entry]\nType=Application\nName=X\nExec=x\nNoDisplay=true\n")).toBeNull();
});

test("OCR boxes map back to layout coordinates and drop numeric noise", () => {
  const els = toElements(
    [
      { text: "Edit", conf: 0.99, box: [200, 100, 100, 50] },
      { text: "220,511", conf: 0.99, box: [0, 0, 10, 10] },
      { text: "Share", conf: 0.3, box: [0, 0, 10, 10] },
    ],
    2,
    { x: 1933, y: 69 },
  ).filter(isUsefulLabel);
  expect(els).toEqual([{ text: "Edit", conf: 0.99, x: 2033, y: 119, w: 50, h: 25 }]);
});
