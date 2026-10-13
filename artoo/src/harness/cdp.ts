// Minimal Chrome DevTools Protocol client for Brave (started with --remote-debugging-port=9222,
// see ~/dotfiles/brave-flags.conf). Input goes straight to the page: no screen coordinates.
import { signal } from "../runtime.ts";

const base = () => process.env.JEV_CDP_URL ?? "http://127.0.0.1:9222";

export type Target = { id: string; type: string; title: string; url: string; webSocketDebuggerUrl: string };

export async function targets(): Promise<Target[]> {
  let res: Response;
  try {
    res = await fetch(`${base()}/json/list`, { signal: AbortSignal.any([signal(), AbortSignal.timeout(3000)]) });
  } catch {
    throw new Error(`no DevTools endpoint at ${base()}. Is Brave running with --remote-debugging-port=9222?`);
  }
  return ((await res.json()) as Target[]).filter((t) => t.type === "page");
}

/** The tab a Brave window is showing: Hyprland titles windows "<tab title> - Brave". */
export function matchWindowTitle(pages: Target[], windowTitle: string): Target | undefined {
  const tabTitle = windowTitle.replace(/ - Brave$/, "");
  return pages.find((t) => t.title === tabTitle) ?? pages.find((t) => tabTitle.startsWith(t.title) || t.title.startsWith(tabTitle));
}

export async function targetForWindowTitle(windowTitle: string): Promise<Target | undefined> {
  return matchWindowTitle(await targets(), windowTitle);
}

/**
 * Browser-level connection (not tied to a tab). It answers which Brave window a tab lives
 * in, which is the only way to learn that two pages share a window (split view): a page
 * cannot see its neighbours, and the window title names just the active one.
 */
export async function connectBrowser(): Promise<CdpSession> {
  const res = await fetch(`${base()}/json/version`, { signal: AbortSignal.any([signal(), AbortSignal.timeout(3000)]) });
  const { webSocketDebuggerUrl } = (await res.json()) as { webSocketDebuggerUrl: string };
  return CdpSession.connect({ title: "browser", webSocketDebuggerUrl });
}

export async function windowIdOf(browser: CdpSession, targetId: string): Promise<number | undefined> {
  return browser.send<{ windowId: number }>("Browser.getWindowForTarget", { targetId }).then((r) => r.windowId, () => undefined);
}

/** Bring a tab to the front of its window. */
export async function activateTab(targetId: string): Promise<void> {
  await fetch(`${base()}/json/activate/${targetId}`, { signal: AbortSignal.any([signal(), AbortSignal.timeout(3000)]) });
}

const withTimeout = <T>(work: Promise<T>, ms: number, fallback: T): Promise<T> =>
  Promise.race([work.catch(() => fallback), new Promise<T>((resolve) => setTimeout(() => resolve(fallback), ms))]);

/** Sleeping/discarded tabs never answer a script; report those as "asleep" rather than waiting on them. */
export const visibility = (cdp: CdpSession) =>
  withTimeout<"visible" | "hidden" | "asleep">(cdp.evaluate<string>("document.visibilityState").then((v) => (v === "visible" ? "visible" : "hidden")), 1200, "asleep");

export class CdpSession {
  #ws: WebSocket;
  #nextId = 1;
  #pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();

  private constructor(ws: WebSocket) {
    this.#ws = ws;
    ws.addEventListener("message", (ev) => {
      const msg = JSON.parse(String(ev.data));
      const p = msg.id !== undefined ? this.#pending.get(msg.id) : undefined;
      if (!p) return;
      this.#pending.delete(msg.id);
      if (msg.error) p.reject(new Error(`CDP ${msg.error.message}`));
      else p.resolve(msg.result);
    });
    ws.addEventListener("close", () => {
      for (const p of this.#pending.values()) p.reject(new Error("CDP socket closed"));
      this.#pending.clear();
    });
  }

  static connect(target: Pick<Target, "title" | "webSocketDebuggerUrl">): Promise<CdpSession> {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(target.webSocketDebuggerUrl);
      ws.addEventListener("open", () => resolve(new CdpSession(ws)), { once: true });
      ws.addEventListener("error", () => reject(new Error(`can't connect to tab "${target.title}"`)), { once: true });
    });
  }

  send<T = any>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    const s = signal();
    s.throwIfAborted();
    const id = this.#nextId++;
    return new Promise((resolve, reject) => {
      const finish = () => { clearTimeout(timer); s.removeEventListener("abort", abort); this.#pending.delete(id); };
      const abort = () => { finish(); reject(s.reason); };
      const timer = setTimeout(() => { finish(); reject(new Error(`CDP ${method} timed out`)); }, 15000);
      s.addEventListener("abort", abort, { once: true });
      this.#pending.set(id, { resolve: (v) => { finish(); resolve(v); }, reject: (e) => { finish(); reject(e); } });
      this.#ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async screenshot(path: string) {
    const { data } = await this.send<{ data: string }>("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
    await Bun.write(path, Buffer.from(data, "base64"));
    return path;
  }

  /** `userGesture` lets the script do what only a click may (e.g. window.open without the popup blocker). */
  async evaluate<T>(expression: string, opts: { userGesture?: boolean } = {}): Promise<T> {
    const res = await this.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true, userGesture: !!opts.userGesture });
    if (res.exceptionDetails) throw new Error(`page script failed: ${res.exceptionDetails.exception?.description ?? res.exceptionDetails.text}`);
    return res.result.value as T;
  }

  async click(x: number, y: number, opts: { button?: "left" | "right" | "middle"; count?: number } = {}) {
    const button = opts.button ?? "left";
    await this.send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
    // A double click is two press/release pairs with a rising clickCount, as a real mouse sends.
    for (let n = 1; n <= (opts.count ?? 1); n++) {
      await this.send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button, clickCount: n });
      await this.send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button, clickCount: n });
    }
  }

  async hover(x: number, y: number) {
    await this.send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
  }

  /** Press at one point, move in steps (apps ignore a teleporting drag), release at the other. */
  async drag(x1: number, y1: number, x2: number, y2: number) {
    await this.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: x1, y: y1 });
    await this.send("Input.dispatchMouseEvent", { type: "mousePressed", x: x1, y: y1, button: "left", clickCount: 1 });
    const steps = 12;
    for (let i = 1; i <= steps; i++) {
      await this.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: x1 + ((x2 - x1) * i) / steps, y: y1 + ((y2 - y1) * i) / steps, button: "left", buttons: 1 });
    }
    await this.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: x2, y: y2, button: "left", clickCount: 1 });
  }

  async scroll(x: number, y: number, deltaY: number) {
    await this.send("Input.dispatchMouseEvent", { type: "mouseWheel", x, y, deltaX: 0, deltaY });
  }

  async insertText(text: string) {
    await this.send("Input.insertText", { text });
  }

  /**
   * Type at the caret without replacing anything, as real keystrokes. Canvas apps (Google
   * Sheets/Docs) start editing on key events and ignore a bare text insertion; newlines and
   * tabs become Enter/Tab so they move between cells and fields as they would by hand.
   */
  async typeChars(text: string) {
    for (const ch of text) {
      if (ch === "\n") await this.press("Enter");
      else if (ch === "\t") await this.press("Tab");
      else {
        const vk = /^[a-z0-9 ]$/i.test(ch) ? ch.toUpperCase().charCodeAt(0) : 0;
        await this.send("Input.dispatchKeyEvent", { type: "keyDown", key: ch, text: ch, unmodifiedText: ch, windowsVirtualKeyCode: vk });
        await this.send("Input.dispatchKeyEvent", { type: "keyUp", key: ch, windowsVirtualKeyCode: vk });
      }
    }
  }

  async key(key: string, code: string, keyCode: number, commands: string[] = []) {
    await this.send("Input.dispatchKeyEvent", { type: "rawKeyDown", key, code, windowsVirtualKeyCode: keyCode, commands });
    await this.send("Input.dispatchKeyEvent", { type: "keyUp", key, code, windowsVirtualKeyCode: keyCode });
  }

  /** Focus a field by clicking it, replace its contents, and let the page see real input events. */
  async typeInto(x: number, y: number, text: string) {
    await this.click(x, y);
    await this.key("a", "KeyA", 65, ["selectAll"]);
    await this.insertText(text);
  }

  escape = () => this.key("Escape", "Escape", 27);

  /**
   * One key or shortcut ("enter", "ctrl+c", "shift+tab", "f2", "x"). Enter carries text "\r"
   * so forms treat it as a real Enter. Ctrl+A/C/V/X/Z/Y carry their editing command: a
   * synthetic key event alone never triggers the browser's own clipboard/undo handling.
   */
  async press(name: string) {
    const parts = name.trim().split("+").map((p) => p.trim());
    const last = parts.pop()!;
    const modifiers = parts.reduce((n, m) => {
      const value = ({ alt: 1, ctrl: 2, control: 2, super: 4, meta: 4, shift: 8 } as Record<string, number>)[m.toLowerCase()];
      if (!value) throw new Error(`unsupported modifier "${m}"`);
      return n | value;
    }, 0);
    const named = NAMED_KEYS[last.toLowerCase()];
    let key: string, code: string, vk: number, text: string | undefined;
    if (named) [key, code, vk, text] = named;
    else if ([...last].length === 1) {
      key = modifiers & 8 ? last.toUpperCase() : last;
      code = /^[a-z]$/i.test(last) ? `Key${last.toUpperCase()}` : /^\d$/.test(last) ? `Digit${last}` : "";
      vk = /^[a-z0-9]$/i.test(last) ? last.toUpperCase().charCodeAt(0) : 0;
      text = key;
    } else throw new Error(`unsupported key "${name}"`);
    // Only plain (or shifted) keys produce text; Ctrl/Alt/Super combos are shortcuts.
    const typed = modifiers & ~8 ? undefined : text;
    const command = (modifiers & ~8) === 2 ? EDIT_COMMANDS[(modifiers & 8 ? "shift+" : "") + last.toLowerCase()] : undefined;
    await this.send("Input.dispatchKeyEvent", {
      type: typed ? "keyDown" : "rawKeyDown", key, code, windowsVirtualKeyCode: vk, modifiers,
      ...(typed ? { text: typed, unmodifiedText: typed } : {}), ...(command ? { commands: [command] } : {}),
    });
    await this.send("Input.dispatchKeyEvent", { type: "keyUp", key, code, windowsVirtualKeyCode: vk, modifiers });
  }

  close() {
    this.#ws.close();
  }
}

const EDIT_COMMANDS: Record<string, string> = { a: "selectAll", c: "copy", v: "paste", x: "cut", z: "undo", y: "redo", "shift+z": "redo" };

// name -> [key, code, virtual key code, text it types]
const NAMED_KEYS: Record<string, [string, string, number, string?]> = {
  enter: ["Enter", "Enter", 13, "\r"], return: ["Enter", "Enter", 13, "\r"], tab: ["Tab", "Tab", 9],
  escape: ["Escape", "Escape", 27], esc: ["Escape", "Escape", 27], backspace: ["Backspace", "Backspace", 8],
  delete: ["Delete", "Delete", 46], del: ["Delete", "Delete", 46], space: [" ", "Space", 32, " "],
  up: ["ArrowUp", "ArrowUp", 38], down: ["ArrowDown", "ArrowDown", 40], left: ["ArrowLeft", "ArrowLeft", 37], right: ["ArrowRight", "ArrowRight", 39],
  arrowup: ["ArrowUp", "ArrowUp", 38], arrowdown: ["ArrowDown", "ArrowDown", 40], arrowleft: ["ArrowLeft", "ArrowLeft", 37], arrowright: ["ArrowRight", "ArrowRight", 39],
  home: ["Home", "Home", 36], end: ["End", "End", 35], pageup: ["PageUp", "PageUp", 33], pagedown: ["PageDown", "PageDown", 34],
  ...Object.fromEntries(Array.from({ length: 12 }, (_, i) => [`f${i + 1}`, [`F${i + 1}`, `F${i + 1}`, 112 + i]])),
};
