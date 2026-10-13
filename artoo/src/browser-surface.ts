// A Brave window as one surface. Every page the window is currently showing is a "pane":
// one normally, two in split view. Each pane is read from its live DOM and driven over CDP,
// so nothing depends on where the pane sits on screen or on the window having focus.
//
// The surface follows the window, not a tab. Reading only the tab named in the window title
// made the other half of a split view invisible, and left the surface watching a stale page
// after a tab switch.
import { join } from "node:path";
import { isHiddenSite } from "./guardrails.ts";
import { activateTab, CdpSession, connectBrowser, matchWindowTitle, targets, visibility, windowIdOf, type Target } from "./harness/cdp.ts";
import * as hypr from "./harness/hypr.ts";
import { pressKey, sequenceKey } from "./harness/input.ts";
import { snapshotPage, type PageSnapshot } from "./perceive/dom.ts";
import { redactUrl } from "./privacy.ts";
import type { RunLog } from "./runlog.ts";
import { sleep } from "./runtime.ts";
import { regionOf, type Observation, type PaneInfo, type Surface, type UiTarget } from "./surface.ts";

const MAX_TARGETS = 200;

/**
 * Shortcuts Brave itself handles. A key event injected into a page never reaches the browser,
 * so these go through the OS keyboard with the window focused. Kept to keys a page cannot
 * override anyway; ctrl+r, ctrl+1 and friends stay with the page (Sheets uses them).
 */
const BROWSER_SHORTCUT = /^(ctrl\+(shift\+)?(t|n|w|tab)|ctrl\+(pageup|pagedown)|alt\+(left|right)|f5|f11)$/;

type Tab = { id: string; target: Target; cdp?: CdpSession; asleepAt?: number; focusEmulated?: boolean };
/** How long a tab that didn't answer is left alone before it is asked again. */
const ASLEEP_MS = 10_000;
type Pane = Tab & { cdp: CdpSession; snap: PageSnapshot };

const siteOf = (url: string) => { try { return new URL(url).host || url.split(":")[0]!; } catch { return ""; } };
const EMPTY: Omit<PageSnapshot, "title" | "url"> = { vw: 1, vh: 1, elements: [], content: "(this page is still loading or could not be read; wait and look again)", focused: "" };

export async function browserSurface(win: hypr.Client, log?: RunLog): Promise<Surface | null> {
  let browser: CdpSession;
  let windowId: number | undefined;
  let anchor: Target | undefined;
  try {
    anchor = matchWindowTitle(await targets(), win.title);
    if (!anchor) return null;
    browser = await connectBrowser();
    windowId = await windowIdOf(browser, anchor.id);
  } catch {
    return null;
  }
  if (windowId === undefined) { browser.close(); return null; }

  const tabs = new Map<string, Tab>();
  let nextTab = 1;
  let panes: Pane[] = [];
  let activeId = anchor.id;
  let sequence = 0;

  /** Refresh which tabs this window holds and which of them it is showing. */
  async function sync() {
    const pages = await targets();
    const inWindow = await Promise.all(pages.map((t) => windowIdOf(browser, t.id).then((id) => id === windowId)));
    const mine = pages.filter((_, i) => inWindow[i]);
    for (const [id, tab] of tabs) {
      if (!mine.some((t) => t.id === id)) { tab.cdp?.close(); tabs.delete(id); }
    }
    for (const target of mine) {
      const tab = tabs.get(target.id);
      if (tab) tab.target = target;
      else tabs.set(target.id, { id: `t${nextTab++}`, target });
    }
    const all = [...tabs.values()];
    const wasShown = new Set(panes.map((p) => p.target.id));
    const states = await Promise.all(all.map(async (tab) => {
      const shownBefore = wasShown.has(tab.target.id);
      if (!shownBefore && tab.asleepAt && Date.now() - tab.asleepAt < ASLEEP_MS) return "asleep" as const;
      try { tab.cdp ??= await CdpSession.connect(tab.target); } catch { return "asleep" as const; }
      const state = await visibility(tab.cdp);
      tab.asleepAt = state === "asleep" ? Date.now() : undefined;
      // A pane that stops answering is navigating (a login just submitted), not gone. Dropping
      // it made the page vanish from the window for the rest of the task.
      return state === "asleep" && shownBefore ? "visible" as const : state;
    }));
    let shown = all.filter((_, i) => states[i] === "visible");
    if (!shown.length) {
      // A window on a hidden workspace reports every tab hidden; fall back to the titled one.
      const title = (await hypr.clients()).find((c) => c.address === win.address)?.title ?? win.title;
      const titled = matchWindowTitle(all.map((t) => t.target), title);
      shown = all.filter((t) => t.target.id === titled?.id && t.cdp);
    }
    for (const tab of shown) {
      if (tab.focusEmulated) continue;
      // Only one split pane has real focus; without this the other ignores keyboard input.
      await tab.cdp!.send("Emulation.setFocusEmulationEnabled", { enabled: true }).catch(() => {});
      tab.focusEmulated = true;
    }
    const byId = (a: Tab, b: Tab) => Number(a.id.slice(1)) - Number(b.id.slice(1));
    panes = await Promise.all(shown.sort(byId).map(async (tab) => {
      const snap = await snapshotPage(tab.cdp!).catch(() => ({ ...EMPTY, title: tab.target.title, url: tab.target.url }));
      return { ...tab, cdp: tab.cdp!, snap };
    }));
    if (!panes.some((p) => p.target.id === activeId)) activeId = panes[0]?.target.id ?? activeId;
  }

  const active = () => panes.find((p) => p.target.id === activeId) ?? panes[0];
  function paneOf(id?: string): Pane {
    const pane = id ? panes.find((p) => p.id === id) : active();
    if (!pane) throw new Error(id ? `pane ${id} is not visible in this window` : "the browser window is showing no readable page");
    return pane;
  }
  const use = (pane: Pane) => { activeId = pane.target.id; return pane; };

  async function reveal() {
    win = await hypr.revealWindow(win.address);
  }

  const surface: Surface = {
    kind: "browser (DOM over CDP)",
    context: async () => {
      const act = active();
      if (!act) return { page_title: anchor!.title, url: redactUrl(anchor!.url), raw_url: anchor!.url, focused: "" };
      const others = [...tabs.values()].filter((t) => !panes.some((p) => p.target.id === t.target.id));
      return {
        page_title: act.snap.title, url: redactUrl(act.snap.url), raw_url: act.snap.url, focused: act.snap.focused,
        ...(panes.length > 1 && {
          panes: panes.map((p) => `${p.id}${p === act ? " (keyboard goes here)" : ""}: "${p.snap.title}" — ${siteOf(p.snap.url)}`).join("; "),
        }),
        ...(others.length > 0 && {
          other_tabs: others.map((t) => `${t.id}: "${isHiddenSite(t.target.url) ? "(private)" : t.target.title}"`).join("; "),
        }),
      };
    },
    perceive: async () => {
      await sync();
      if (!panes.length) throw new Error("The browser window is showing no readable page.");
      const multi = panes.length > 1;
      // Split the budget so a control-heavy page (Sheets) can't crowd the other pane out.
      const cap = Math.floor(MAX_TARGETS / panes.length);
      return panes.flatMap((p) => p.snap.elements.slice(0, cap).map((e): UiTarget => ({
        id: e.id,
        row: e.row,
        pane: p.id,
        description: `${multi ? `${p.id}: ` : ""}${e.role} "${e.label}"${e.row ? ` in row [${e.row}]` : ""}${e.state ? ` [${e.state}]` : ""} (${regionOf(e.x / p.snap.vw, e.y / p.snap.vh)})`,
        label: e.label,
        x: e.x,
        y: e.y,
        typeable: e.role === "textbox" || e.role === "searchbox" || e.role === "spinbutton",
      })));
    },
    point: (x, y, id) => {
      // With two panes a bare coordinate is ambiguous; the planner has to say which screenshot.
      const pane = id ? panes.find((p) => p.id === id) : panes.length === 1 ? panes[0] : undefined;
      if (!pane) return null;
      return { pane: pane.id, description: `visual target (${x.toFixed(3)}, ${y.toFixed(3)})`, label: "visual target", x: x * pane.snap.vw, y: y * pane.snap.vh };
    },
    click: (t, opts) => use(paneOf(t.pane)).cdp.click(t.x, t.y, opts),
    hover: (t) => paneOf(t.pane).cdp.hover(t.x, t.y),
    drag: (from, to) => use(paneOf(from.pane)).cdp.drag(from.x, from.y, to.x, to.y),
    type: (t, text) => use(paneOf(t.pane)).cdp.typeInto(t.x, t.y, text),
    typeFocused: async (text, id) => {
      const { cdp } = use(paneOf(id));
      // Follow focus into shadow roots; an iframe can't be inspected from here, so trust it.
      const editable = await cdp.evaluate<boolean>(`(() => {
        let a = document.activeElement;
        while (a?.shadowRoot?.activeElement) a = a.shadowRoot.activeElement;
        if (!a || a === document.body || a === document.documentElement) return false;
        return a.isContentEditable || /^(input|textarea|iframe)$/i.test(a.tagName);
      })()`);
      if (!editable) return false;
      await cdp.key("a", "KeyA", 65, ["selectAll"]);
      await cdp.insertText(text);
      return true;
    },
    key: async (name, id) => {
      const combo = name.toLowerCase().replace(/\s+/g, "").replace(/arrow(?=up|down|left|right)/, "");
      if (BROWSER_SHORTCUT.test(combo)) {
        await reveal();
        await pressKey(combo);
        await sleep(400);
        return;
      }
      await use(paneOf(id)).cdp.press(name);
    },
    sequence: async (items, id) => {
      for (const item of items) {
        const key = sequenceKey(item);
        if (key) await surface.key(key, id);
        else await use(paneOf(id)).cdp.typeChars(item);
        await sleep(30);
      }
    },
    escape: () => paneOf().cdp.escape(),
    scroll: (amount, at, id) => {
      const pane = paneOf(at?.pane ?? id);
      // Most of a screenful, keeping a strip of overlap: a page is read in few scrolls, and
      // nothing between two views is skipped.
      return pane.cdp.scroll(at?.x ?? pane.snap.vw / 2, at?.y ?? pane.snap.vh / 2, Math.sign(amount) * Math.round(pane.snap.vh * 0.8));
    },
    switchTab: async (which) => {
      await sync();
      const q = which.trim().toLowerCase();
      const id = /^(t\d+)\b/.exec(q)?.[1];
      const all = [...tabs.values()];
      const title = (t: Tab) => t.target.title.toLowerCase();
      const partial = all.filter((t) => title(t).includes(q) || (title(t).length > 3 && q.includes(title(t))));
      const tab = all.find((t) => t.id === id) ?? all.find((t) => title(t) === q) ?? (partial.length === 1 ? partial[0] : undefined);
      if (!tab) return null;
      await activateTab(tab.target.id);
      tab.asleepAt = undefined;
      activeId = tab.target.id;
      await sleep(500);
      return tab.target.title;
    },
    openUrl: async (url) => {
      const before = new Set((await targets()).map((t) => t.id));
      const pane = active();
      // Opened from a page of this window so the tab lands here, not in whichever Brave window
      // was used last. Pages that forbid it fall back to a browser-level new tab.
      const opened = pane && await pane.cdp.evaluate<boolean>(`(() => { window.open(${JSON.stringify(url)}, "_blank", "noopener"); return true; })()`, { userGesture: true }).catch(() => false);
      if (!opened) await browser.send("Target.createTarget", { url });
      for (let i = 0; i < 20; i++) {
        await sleep(250);
        const fresh = (await targets()).find((t) => !before.has(t.id));
        if (fresh) { activeId = fresh.id; break; }
      }
      await sleep(800);
    },
    close: () => {
      for (const tab of tabs.values()) tab.cdp?.close();
      browser.close();
    },
  };
  surface.observe = async (step) => {
    const found = await surface.perceive(step);
    const id = `observation-${++sequence}`;
    const multi = panes.length > 1;
    const act = active()!;
    const infos: PaneInfo[] = [];
    for (const p of panes) {
      const image = log ? await p.cdp.screenshot(join(log.dir, `${id}${multi ? `-${p.id}` : ""}.png`)).catch(() => undefined) : undefined;
      infos.push({ id: p.id, title: p.snap.title, site: siteOf(p.snap.url), width: p.snap.vw, height: p.snap.vh, active: p === act, image });
    }
    const images = infos.flatMap((p) => (p.image ? [p.image] : []));
    const observation: Observation = {
      id, image: images[0], images, panes: infos, rawUrls: panes.map((p) => p.snap.url),
      width: panes[0]!.snap.vw, height: panes[0]!.snap.vh,
      content: multi ? panes.map((p) => `=== pane ${p.id}: ${p.snap.title} ===\n${p.snap.content}`).join("\n\n") : act.snap.content,
      context: await surface.context(), targets: found,
    };
    log?.event("observation", observation);
    return observation;
  };
  return surface;
}
