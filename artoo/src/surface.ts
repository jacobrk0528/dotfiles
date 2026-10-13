// A "surface" is where a UI task happens: a Brave tab read over CDP (the live DOM), or any
// other window read with OCR and driven with OS input. Shared by the Jev-only UI loop and
// the planner loop.
import { join } from "node:path";
import type { Confirm } from "./confirm.ts";
import { run } from "./exec.ts";
import { isHiddenSite } from "./guardrails.ts";
import { browserSurface } from "./browser-surface.ts";
import { activateTab, targets } from "./harness/cdp.ts";
import * as hypr from "./harness/hypr.ts";
import { click, drag, pressKey, scroll, sequenceKey, typeText } from "./harness/input.ts";
import { pickOne } from "./jev.ts";
import { appOptions, urlOptions, windowOptions } from "./perceive/candidates.ts";
import { openUrl } from "./harness/browser.ts";
import { findApp, launchApp } from "./harness/apps.ts";
import { snapshot, titleOf, type Window } from "./perceive/desktop.ts";
import { isUsefulLabel, ocr } from "./perceive/ocr.ts";
import { redactUrl } from "./privacy.ts";
import type { RunLog } from "./runlog.ts";
import { sessionOrigin } from "./desktop-session.ts";
import { sleep } from "./runtime.ts";

/** Something clickable, in whatever coordinate space its surface uses. */
export type UiTarget = {
  id?: string; row?: string; description: string; label: string; x: number; y: number; typeable?: boolean;
  /** Which visible page this belongs to, when a window shows more than one (browser split view). */
  pane?: string;
};

/** One visible page of a browser window. Coordinates and screenshots are per pane. */
export type PaneInfo = { id: string; title: string; site: string; width: number; height: number; active: boolean; image?: string };
export type ClickOptions = { button?: "left" | "right"; count?: number };

export type Observation = {
  id: string;
  image?: string;
  /** One screenshot per pane, in `panes` order. `image` stays the first for single-image callers. */
  images?: string[];
  panes?: PaneInfo[];
  /** Every visible page's URL, for the never_look gate. Local only; never sent. */
  rawUrls?: string[];
  width: number;
  height: number;
  content: string;
  context: Record<string, string>;
  targets: UiTarget[];
};

export type Surface = {
  kind: string;
  /** Page/window context for model state. `raw_url` is for local checks only; never send it. */
  context: () => Promise<Record<string, string>>;
  perceive: (step: number) => Promise<UiTarget[]>;
  observe?: (step: number) => Promise<Observation>;
  /** Convert normalized screenshot coordinates (of `pane`'s screenshot) to this surface's input coordinates. */
  point?: (x: number, y: number, pane?: string) => UiTarget | null;
  /** Re-focus after an approval popup took the keyboard. */
  prepare?: () => Promise<void>;
  click: (t: UiTarget, opts?: ClickOptions) => Promise<void>;
  hover?: (t: UiTarget) => Promise<void>;
  drag?: (from: UiTarget, to: UiTarget) => Promise<void>;
  /** Scroll; with `at`, scroll over that element (inner lists scroll separately from the page). */
  scroll: (amount: number, at?: UiTarget, pane?: string) => Promise<void>;
  /** Replace a field's contents. Only surfaces that know which targets are fields offer it. */
  type?: (t: UiTarget, text: string) => Promise<void>;
  /**
   * Replace the contents of whatever has keyboard focus (e.g. a field that opened on click).
   * Returns false when nothing editable has focus, so the caller doesn't report typing that went nowhere.
   */
  typeFocused: (text: string, pane?: string) => Promise<boolean>;
  /** A key or shortcut: enter, tab, escape, ctrl+c, shift+tab, f2 ... */
  key: (name: string, pane?: string) => Promise<void>;
  /** Type at the caret without replacing: literal text interleaved with "{key}" items. */
  sequence?: (items: string[], pane?: string) => Promise<void>;
  /** Bring another tab of this window to the front. Returns its title, or null if none matches. */
  switchTab?: (which: string) => Promise<string | null>;
  /** Open a URL in a new tab of this window. */
  openUrl?: (url: string) => Promise<void>;
  escape?: () => Promise<void>;
  close: () => void;
};

const BRAVE = /^brave-browser$/;
const hostOf = (url: string) => { try { return new URL(url).host || url; } catch { return url; } };

export function regionOf(fx: number, fy: number) {
  const v = fy < 0.15 ? "top" : fy > 0.85 ? "bottom" : "middle";
  const h = fx < 0.25 ? "left" : fx > 0.75 ? "right" : "center";
  return `${v}-${h}`;
}

function ocrSurface(win: Window, log: RunLog): Surface {
  const scale = 1;
  let sequence = 0;
  const prepare = async () => { win = { ...await hypr.revealWindow(win.address), private: win.private }; };
  const surface: Surface = {
    kind: "screen (vision + OCR)",
    prepare,
    context: async () => ({ window: `${win.class} "${titleOf(win)}"` }),
    perceive: async (step) => (await surface.observe!(step)).targets,
    observe: async () => {
      await prepare();
      const id = `observation-${++sequence}`;
      const shot = join(log.dir, `${id}.png`);
      await run(["grim", "-s", String(scale), "-g", `${win.at[0]},${win.at[1]} ${win.size[0]}x${win.size[1]}`, shot]);
      const els = await ocr(shot, scale, { x: win.at[0], y: win.at[1] }, false).catch((err) => {
        log.event("ocr_error", { message: String(err) });
        return [];
      });
      const targets = els.filter(isUsefulLabel).map((e) => {
        const [cx, cy] = [e.x + e.w / 2, e.y + e.h / 2];
        const region = regionOf((cx - win.at[0]) / win.size[0], (cy - win.at[1]) / win.size[1]);
        return { description: `"${e.text}" (${region})`, label: e.text, x: cx, y: cy };
      });
      const observation: Observation = {
        id, image: shot, width: win.size[0], height: win.size[1],
        content: els.map((e) => e.text).join("\n"),
        context: { window: `${win.class} "${titleOf(win)}"`, workspace: win.workspace.name }, targets,
      };
      log.event("observation", observation);
      return observation;
    },
    point: (x, y) => ({ description: `visual target (${x.toFixed(3)}, ${y.toFixed(3)})`, label: "visual target", x: win.at[0] + x * win.size[0], y: win.at[1] + y * win.size[1] }),
    click: (t, opts) => click({ x: t.x, y: t.y, button: opts?.button, count: opts?.count }),
    hover: (t) => hypr.moveCursor(t.x, t.y),
    drag: (from, to) => drag(from, to),
    // OCR can't see focus; assume the click landed in a field.
    typeFocused: async (text) => {
      await pressKey("ctrl+a");
      await typeText(text);
      return true;
    },
    key: async (name) => {
      await pressKey(name.toLowerCase().replace(/^arrow/, ""));
    },
    sequence: async (items) => {
      for (const item of items) {
        const key = sequenceKey(item);
        if (key) await pressKey(key.toLowerCase().replace(/^arrow/, ""));
        else await typeText(item);
        await sleep(40);
      }
    },
    scroll: (amount, at) => scroll(amount, at ? { x: at.x, y: at.y } : { x: win.at[0] + win.size[0] / 2, y: win.at[1] + win.size[1] / 2 }),
    close: () => {},
  };
  return surface;
}

export async function observeSurface(surface: Surface, step: number): Promise<Observation> {
  if (surface.observe) return surface.observe(step);
  return { id: String(step), width: 0, height: 0, content: "", targets: await surface.perceive(step), context: await surface.context() };
}

/**
 * Jev picks the window the goal is about; returns its surface, or null if it's a never_look
 * app and the human says no.
 */
export async function openSurface(
  goal: string,
  io: { confirm: Confirm; print: (s: string) => void; log: RunLog },
  address?: string,
): Promise<{ surface: Surface; win: Window } | null> {
  let desktop = await snapshot();
  // Background browser tabs are places a task can happen too. Without them a web app that
  // is open but not in front ("the Google Sheet") looked like an app that needed launching.
  const tabs = address ? [] : (await targets().catch(() => [])).filter((t) => !isHiddenSite(t.url)).slice(0, 120);
  const tabOptions = Object.fromEntries(tabs.map((t, i) => [`tab${i + 1}`, { description: `Brave browser tab "${t.title}" (${hostOf(t.url)})`, value: `tab:${t.id}` }]));
  const options = { ...windowOptions(desktop), ...tabOptions, none: { description: "The needed application or site is not open; launch it", value: "" } };
  const winPick = address ? { value: `address:${address}`, confidence: 1 } : await pickOne(
    { goal, origin_window: sessionOrigin()?.window ?? "", instruction: "For 'this' or 'my screen', use the originating window. Choose the app the goal needs, even on a hidden workspace." },
    "Which open window should this task be done in?", options);
  const adopt = (found?: hypr.Client) => { if (found) winPick.value = `address:${found.address}`; return !!found; };
  if (String(winPick.value).startsWith("tab:")) {
    const tab = tabs.find((t) => `tab:${t.id}` === winPick.value)!;
    io.print(`Switching to the "${tab.title}" tab…`);
    await activateTab(tab.id);
    winPick.value = "";
    for (let i = 0; i < 12 && !winPick.value; i++) {
      await sleep(250);
      desktop = await snapshot();
      adopt(desktop.clients.find((c) => BRAVE.test(c.class) && c.title.replace(/ - Brave$/, "") === tab.title));
    }
    if (!winPick.value) throw new Error(`Could not bring the "${tab.title}" tab to the front.`);
  }
  if (!winPick.value) {
    const apps = Object.fromEntries(Object.entries(appOptions()).slice(0, 240));
    const choice = await pickOne({ goal }, "What is needed for this?", {
      // Listed first and spelled out: asked for "Google Sheets", the app list alone used to
      // answer with a second browser (Chrome's profile picker) instead of a tab in Brave.
      web: { description: "A website or web app (Google Sheets, Docs, Gmail, a search, any site); open it in the Brave browser", value: "web" },
      ...apps,
      none: { description: "No installed application or website matches", value: "" },
    });
    if (choice.value === "web") {
      const site = await pickOne({ goal }, "Which site should be opened?", { ...urlOptions(200), none: { description: "None of these sites", value: "" } });
      if (!site.value) throw new Error("Could not tell which site this needs. Name the site or give its address.");
      io.print(`Opening ${hostOf(String(site.value))}…`);
      await openUrl(String(site.value));
      await sleep(1500);
      desktop = await snapshot();
      if (!adopt(desktop.active && BRAVE.test(desktop.active.class) ? desktop.active : undefined)) throw new Error("The browser did not open.");
    } else {
      const app = findApp(String(choice.value));
      if (!app) throw new Error("Could not identify an installed app for this task.");
      io.print(`Opening ${app.name}…`);
      const before = new Set(desktop.clients.map((c) => c.address));
      // Hide a scratchpad before launch so it doesn't swallow the new window.
      const mon = desktop.monitors.find((m) => m.focused);
      if (mon?.specialWorkspace?.name) await hypr.toggleSpecial(mon.specialWorkspace.name);
      await launchApp(app);
      for (let i = 0; i < 40; i++) {
        await sleep(250);
        desktop = await snapshot();
        if (adopt(desktop.clients.find((c) => !before.has(c.address)))) break;
      }
    }
  }
  let win = desktop.clients.find((c) => `address:${c.address}` === winPick.value);
  if (!win) throw new Error("picked window vanished");

  if (win.private && !(await io.confirm(`"${win.class}" is on your never_look list. Read and act inside it this once?`))) {
    return null;
  }
  win = { ...await hypr.revealWindow(win.address), private: win.private };
  const surface = (BRAVE.test(win.class) && (await browserSurface(win, io.log))) || ocrSurface(win, io.log);
  io.print(`Reading ${win.class}…`);
  io.log.event("pick_window", { title: titleOf(win), confidence: winPick.confidence, surface: surface.kind, address: win.address, workspace: win.workspace.name });
  return { surface, win };
}

/** Gate for never_look sites, checked after each (local) perceive and before anything is sent. */
export function siteGate(confirm: Confirm) {
  const allowed = new Set<string>();
  return async (rawUrl: string | undefined): Promise<boolean> => {
    if (!rawUrl || !isHiddenSite(rawUrl)) return true;
    const host = new URL(rawUrl).host;
    if (allowed.has(host)) return true;
    if (!(await confirm(`${host} is on your never_look list. Send its page contents out?`))) return false;
    allowed.add(host);
    return true;
  };
}
