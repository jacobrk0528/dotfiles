// Hyprland control via hyprctl. These are the "semantic" actions that need no vision.
import { run, runJson } from "../exec.ts";
import { sleep } from "../runtime.ts";

export type Workspace = { id: number; name: string; monitor: string; windows: number; lastwindowtitle: string };
export type Client = {
  address: string;
  class: string;
  title: string;
  workspace: { id: number; name: string };
  at: [number, number];
  size: [number, number];
  focusHistoryID: number;
  pid: number;
  monitor?: number;
  mapped?: boolean;
  hidden?: boolean;
};
export type Monitor = {
  id: number;
  name: string;
  x: number;
  y: number;
  width: number;
  height: number;
  scale: number;
  focused: boolean;
  activeWorkspace: { id: number; name: string };
  specialWorkspace?: { id: number; name: string };
};

export const workspaces = () => runJson<Workspace[]>(["hyprctl", "-j", "workspaces"]);
export const clients = () => runJson<Client[]>(["hyprctl", "-j", "clients"]);
export const monitors = () => runJson<Monitor[]>(["hyprctl", "-j", "monitors"]);
export const activeWorkspace = () => runJson<Workspace>(["hyprctl", "-j", "activeworkspace"]);
// hyprctl prints `{}` when nothing is focused.
export const activeWindow = async () => {
  const w = await runJson<Partial<Client>>(["hyprctl", "-j", "activewindow"]);
  return w.address ? (w as Client) : null;
};

// Hyprland's Lua config: `hyprctl dispatch` takes one Lua dispatcher expression,
// e.g. `hl.dsp.focus({ workspace = 3 })`. Values go through `lua()` so strings are escaped.
export type LuaValue = string | number | boolean | undefined | { [key: string]: LuaValue };

export function lua(v: LuaValue): string {
  if (typeof v === "string") return JSON.stringify(v); // JSON string escapes are valid Lua
  if (typeof v === "number" || typeof v === "boolean") return String(v);
  if (v === undefined) return "nil";
  const fields = Object.entries(v).filter(([, x]) => x !== undefined);
  return `{ ${fields.map(([k, x]) => `${k} = ${lua(x)}`).join(", ")} }`;
}

/** Workspace ids stay numbers; names (e.g. "special:slack") stay strings. */
const wsValue = (ws: number | string) => (typeof ws === "string" && /^-?\d+$/.test(ws) ? Number(ws) : ws);

export async function dispatch(fn: string, ...args: LuaValue[]): Promise<void> {
  const expr = `hl.dsp.${fn}(${args.map(lua).join(", ")})`;
  const out = (await run(["hyprctl", "dispatch", expr])).trim();
  if (out !== "ok") throw new Error(`hyprctl dispatch ${expr}: ${out}`);
}

export const switchWorkspace = (ws: number | string) => dispatch("focus", { workspace: wsValue(ws) });

export const focusWindow = (selector: string) => dispatch("focus", { window: selector });
export const focusMonitor = (monitor: string) => dispatch("focus", { monitor });
export const toggleSpecial = (workspace: string) => dispatch("workspace.toggle_special", workspace.replace(/^special:/, ""));
export const cursorPosition = () => runJson<{ x: number; y: number }>(["hyprctl", "-j", "cursorpos"]);

export const focusTiming = { poll: 50, timeout: 2500, settle: 250 };

/** Reveal hidden/special workspaces and verify focus before any OS input or capture. */
export async function revealWindow(address: string): Promise<Client> {
  let win = (await clients()).find((c) => c.address === address);
  if (!win) throw new Error("The target window has closed.");
  const mons = await monitors();
  const mon = mons.find((m) => m.id === win!.monitor) ?? mons.find((m) => m.focused);
  if (!mon) throw new Error("No monitor is available.");
  const special = win.workspace.name.startsWith("special:");
  if (special && mon.specialWorkspace?.name !== win.workspace.name) {
    await focusMonitor(mon.name);
    await toggleSpecial(win.workspace.name);
  } else if (!special) {
    if (mon.specialWorkspace?.name) {
      await focusMonitor(mon.name);
      await toggleSpecial(mon.specialWorkspace.name);
    }
    if (mon.activeWorkspace.id !== win.workspace.id) await switchWorkspace(win.workspace.id);
  }
  if ((await activeWindow())?.address !== address) await focusWindow(`address:${address}`);
  const deadline = Date.now() + focusTiming.timeout;
  while (Date.now() <= deadline) {
    if ((await activeWindow())?.address === address) {
      await sleep(focusTiming.settle);
      win = (await clients()).find((c) => c.address === address);
      if (!win || win.size.some((n) => n <= 0)) throw new Error("The target window is not drawable.");
      return win;
    }
    await sleep(focusTiming.poll);
  }
  throw new Error("The target window never took focus; no input was sent.");
}

export const moveWindowToWorkspace = (ws: number | string, selector?: string, follow = false) =>
  dispatch("window.move", { window: selector, workspace: wsValue(ws), follow });

export const closeWindow = (selector: string) => dispatch("window.close", { window: selector });

/** Run a command (via sh -c), optionally pinned to a workspace via an exec window rule. */
export function exec(command: string, opts: { workspace?: number | string; silent?: boolean } = {}) {
  if (opts.workspace === undefined) return dispatch("exec_cmd", command);
  return dispatch("exec_cmd", command, { workspace: `${opts.workspace}${opts.silent ? " silent" : ""}` });
}

export const moveCursor = (x: number, y: number) => dispatch("cursor.move", { x: Math.round(x), y: Math.round(y) });
