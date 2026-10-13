// Keyboard via wtype (Wayland virtual keyboard), mouse via hyprctl movecursor + ydotool.
import { run } from "../exec.ts";
import { moveCursor } from "./hypr.ts";

const MODIFIERS: Record<string, string> = {
  ctrl: "ctrl",
  control: "ctrl",
  shift: "shift",
  alt: "alt",
  altgr: "altgr",
  super: "logo",
  win: "logo",
  meta: "logo",
  logo: "logo",
};

// Friendly names → XKB keysyms wtype understands.
const KEYS: Record<string, string> = {
  enter: "Return",
  return: "Return",
  esc: "Escape",
  escape: "Escape",
  tab: "Tab",
  space: "space",
  backspace: "BackSpace",
  delete: "Delete",
  del: "Delete",
  up: "Up",
  down: "Down",
  left: "Left",
  right: "Right",
  home: "Home",
  end: "End",
  pageup: "Prior",
  pagedown: "Next",
};

export function keyArgs(combo: string): string[] {
  const parts = combo.split("+").map((p) => p.trim()).filter(Boolean);
  const keyName = parts.pop();
  if (!keyName) throw new Error(`empty key combo: "${combo}"`);
  const mods = parts.map((p) => {
    const m = MODIFIERS[p.toLowerCase()];
    if (!m) throw new Error(`unknown modifier "${p}" in "${combo}"`);
    return m;
  });
  const key = KEYS[keyName.toLowerCase()] ?? (/^f\d{1,2}$/i.test(keyName) ? keyName.toUpperCase() : keyName);
  return [
    ...mods.flatMap((m) => ["-M", m]),
    "-k",
    key,
    ...mods.toReversed().flatMap((m) => ["-m", m]),
  ];
}

export const typeText = (text: string, delayMs = 0) =>
  run(["wtype", ...(delayMs ? ["-d", String(delayMs)] : []), "--", text]);

export const pressKey = (combo: string) => run(["wtype", ...keyArgs(combo)]);

// ydotool click codes: low nibble = button (0 left, 1 right, 2 middle), 0xC0 = down+up.
const BUTTONS = { left: 0, right: 1, middle: 2 } as const;
export type Button = keyof typeof BUTTONS;

export async function click(opts: { x?: number; y?: number; button?: Button; count?: number } = {}) {
  if (opts.x !== undefined && opts.y !== undefined) await moveCursor(opts.x, opts.y);
  const code = "0x" + (0xc0 + BUTTONS[opts.button ?? "left"]).toString(16).toUpperCase();
  const count = opts.count ?? 1;
  await run(["ydotool", "click", ...(count > 1 ? ["--repeat", String(count), "--next-delay", "80"] : []), code]);
}

/** Positive `amount` scrolls down. */
export async function scroll(amount: number, opts: { x?: number; y?: number } = {}) {
  if (opts.x !== undefined && opts.y !== undefined) await moveCursor(opts.x, opts.y);
  await run(["ydotool", "mousemove", "--wheel", "-x", "0", "-y", String(-Math.round(amount))]);
}

/** Hold the left button at one point and release it at another, moving in steps so apps see a drag. */
export async function drag(from: { x: number; y: number }, to: { x: number; y: number }) {
  await moveCursor(from.x, from.y);
  await run(["ydotool", "click", "0x40"]);
  const steps = 10;
  for (let i = 1; i <= steps; i++) await moveCursor(from.x + ((to.x - from.x) * i) / steps, from.y + ((to.y - from.y) * i) / steps);
  await run(["ydotool", "click", "0x80"]);
}

/**
 * A typing sequence item is either literal text or one key in braces: "{tab}", "{enter}",
 * "{ctrl+c}". Braces that don't hold a key name are literal text.
 */
export function sequenceKey(item: string): string | null {
  const m = /^\{([a-z0-9+_ ]+)\}$/i.exec(item.trim());
  return m ? m[1]!.trim() : null;
}
