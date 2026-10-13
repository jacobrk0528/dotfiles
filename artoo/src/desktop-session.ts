// Cross-process ownership of keyboard/mouse, plus restoration for information lookups.
import { AsyncLocalStorage } from "node:async_hooks";
import { mkdirSync, readFileSync, writeFileSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import * as hypr from "./harness/hypr.ts";
import { cancel, checkCancelled, cleanup, sleep } from "./runtime.ts";

export type DesktopOrigin = {
  window: string | null;
  monitor: string;
  monitors: { name: string; workspace: number; special: string }[];
  cursor: { x: number; y: number };
};

export async function captureOrigin(preferredMonitor?: string): Promise<DesktopOrigin> {
  const [mons, active, wins, cursor] = await Promise.all([hypr.monitors(), hypr.activeWindow(), hypr.clients(), hypr.cursorPosition()]);
  const mon = mons.find((m) => m.name === preferredMonitor) ?? mons.find((m) => m.focused) ?? mons[0];
  if (!mon) throw new Error("No desktop session is available.");
  // A layer-shell input may already hold focus. Recover the last real window on its
  // visible workspace rather than mistaking a hidden scratchpad for the source.
  const visible = mon.specialWorkspace?.id || mon.activeWorkspace.id;
  const fallback = wins.filter((w) => w.workspace.id === visible && w.focusHistoryID >= 0).sort((a, b) => a.focusHistoryID - b.focusHistoryID)[0];
  return {
    window: active?.address ?? fallback?.address ?? null,
    monitor: mon.name,
    monitors: mons.map((m) => ({ name: m.name, workspace: m.activeWorkspace.id, special: m.specialWorkspace?.name ?? "" })),
    cursor,
  };
}

export function parseOrigin(json: string): DesktopOrigin {
  const v = JSON.parse(json) as DesktopOrigin;
  if (!v || (v.window !== null && !/^0x[0-9a-f]+$/i.test(v.window)) || typeof v.monitor !== "string" ||
      !Array.isArray(v.monitors) || !v.monitors.every((m) => typeof m.name === "string" && Number.isInteger(m.workspace) && typeof m.special === "string") ||
      !Number.isFinite(v.cursor?.x) || !Number.isFinite(v.cursor?.y)) throw new Error("Invalid desktop origin.");
  return v;
}

export async function restoreOrigin(origin: DesktopOrigin): Promise<void> {
  const current = await hypr.monitors();
  for (const saved of origin.monitors) {
    const mon = current.find((m) => m.name === saved.name);
    if (!mon) continue;
    const special = mon.specialWorkspace?.name ?? "";
    if (mon.activeWorkspace.id === saved.workspace && special === saved.special) continue;
    await hypr.focusMonitor(saved.name);
    if (special && special !== saved.special) await hypr.toggleSpecial(special);
    if (mon.activeWorkspace.id !== saved.workspace) await hypr.switchWorkspace(saved.workspace);
    if (saved.special && special !== saved.special) await hypr.toggleSpecial(saved.special);
  }
  if (origin.window && (await hypr.clients()).some((w) => w.address === origin.window)) {
    await hypr.focusWindow(`address:${origin.window}`);
  } else if (current.some((m) => m.name === origin.monitor)) {
    await hypr.focusMonitor(origin.monitor);
  }
  await hypr.moveCursor(origin.cursor.x, origin.cursor.y);
}

const held = new AsyncLocalStorage<DesktopOrigin>();
let warned = false;

/** How long the owner gets between the warning and the takeover. JEV_TAKEOVER_MS=0 turns it off; tests skip it. */
const takeoverDelay = () => Number(process.env.JEV_TAKEOVER_MS ?? (process.env.NODE_ENV === "test" ? 0 : 2000));

/**
 * Before artoo first moves windows, focuses apps or clicks on the owner's screen: a
 * notification with a Stop button, then a short pause so they can finish what they were
 * doing (or stop it). Once per desktop session; work that stays in the background never
 * calls this.
 */
export async function warnTakeover(what: string, print: (s: string) => void = () => {}): Promise<void> {
  if (warned) return;
  warned = true;
  const ms = takeoverDelay();
  if (!(ms > 0)) return;
  const secs = `${Math.round(ms / 100) / 10}s`;
  print(`Taking over your screen in ${secs}…`);
  try {
    const child = Bun.spawn(
      ["notify-send", "-a", "artoo", "-i", "input-mouse", "-t", String(ms + 1500), "--action=stop=Stop", "--wait",
        `Taking over your screen in ${secs}`, what.length > 140 ? `${what.slice(0, 140)}…` : what],
      { stdout: "pipe", stderr: "ignore" },
    );
    child.unref();
    new Response(child.stdout).text().then((out) => { if (out.trim() === "stop") cancel(); }, () => {});
    // The Stop button works while the notification is up; then the waiting process goes.
    setTimeout(() => child.kill(), ms + 2000).unref();
  } catch {}
  await sleep(ms);
}
export const sessionOrigin = () => held.getStore();

async function acquire(print: (s: string) => void): Promise<() => void> {
  const parent = process.env.JEV_PILOT_RUNTIME ?? process.env.XDG_RUNTIME_DIR ?? tmpdir();
  const dir = join(parent, `artoo-desktop-${process.getuid?.() ?? "user"}.lock`);
  const owner = join(dir, "owner.json");
  const token = crypto.randomUUID();
  let announced = false;
  while (true) {
    checkCancelled();
    try {
      mkdirSync(dir, { mode: 0o700 });
      writeFileSync(owner, JSON.stringify({ pid: process.pid, token }), { mode: 0o600 });
      return () => {
        try { if (JSON.parse(readFileSync(owner, "utf8")).token === token) rmSync(dir, { recursive: true }); } catch {}
      };
    } catch (err: any) {
      if (err.code !== "EEXIST") throw err;
      try {
        const { pid } = JSON.parse(readFileSync(owner, "utf8"));
        if (!Number.isInteger(pid) || pid < 1) throw new Error("Invalid lock owner");
        try { process.kill(pid, 0); } catch (err: any) {
          if (err.code === "ESRCH") { rmSync(dir, { recursive: true }); continue; }
        }
      } catch {
        // Another process can be between mkdir and writing its owner file.
        try { if (Date.now() - statSync(dir).mtimeMs > 5000) { rmSync(dir, { recursive: true }); continue; } } catch {}
      }
      if (!announced) { print("Waiting for the other desktop task…"); announced = true; }
      await sleep(150);
    }
  }
}

export async function withDesktopSession<T>(
  fn: () => Promise<T>,
  opts: { restore?: boolean; origin?: DesktopOrigin; print?: (s: string) => void; log?: (type: string, data: Record<string, unknown>) => void } = {},
): Promise<T> {
  if (held.getStore()) return fn();
  const print = opts.print ?? (() => {});
  const release = await acquire(print);
  let origin: DesktopOrigin | undefined;
  try {
    origin = opts.origin ?? await captureOrigin();
    opts.log?.("desktop_origin", { origin, restore: !!opts.restore });
    return await held.run(origin, fn);
  } finally {
    try {
      if (opts.restore && origin) {
        print("Returning to your workspace…");
        await cleanup(() => restoreOrigin(origin!));
        opts.log?.("desktop_restored", { window: origin.window, monitor: origin.monitor });
      }
    } catch (err) {
      const message = `Could not restore the original desktop: ${err instanceof Error ? err.message : String(err)}`;
      print(message);
      opts.log?.("restore_error", { message });
    } finally { release(); warned = false; }
  }
}
