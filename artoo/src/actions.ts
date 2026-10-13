// The action registry. One list feeds the CLI, Jev choice options, and (later) LLM tool definitions.
import { z } from "zod";
import { findApp, launchApp, listApps } from "./harness/apps.ts";
import { openUrl } from "./harness/browser.ts";
import { setMeetingMic } from "./harness/meetings.ts";
import { run } from "./exec.ts";
import * as hypr from "./harness/hypr.ts";
import { click, pressKey, scroll, typeText } from "./harness/input.ts";
import { screenshot } from "./harness/screen.ts";
import type { Options } from "./jev.ts";
import { appOptions, urlOptions, windowOptions, workspaceOptions } from "./perceive/candidates.ts";
import { describe, snapshot, type DesktopState } from "./perceive/desktop.ts";

/** Guardrail categories an action can be statically tagged with (see guardrails.yaml, M3). */
export type Risk = "destructive" | "purchase" | "subscribe" | "send_message" | "account_settings" | "install_software" | "sudo";

export type Action<P extends z.ZodObject = z.ZodObject> = {
  name: string;
  description: string;
  params: P;
  risk: Risk[];
  run: (params: z.infer<P>) => Promise<unknown>;
  /**
   * How Jev fills each param from a closed option list. An action is eligible for the
   * Jev fast path only if every required param has a picker (see agent.ts).
   */
  pickers?: { [K in keyof z.infer<P>]?: Picker };
};

export type Picker = {
  question: string;
  options: (desktop: DesktopState) => Options;
  /** Map a picked value to what it actually means, so equivalent options pool their confidence. */
  resolve?: (value: unknown, desktop: DesktopState) => unknown;
};

const pickWorkspace: Picker = {
  question: "Which workspace number does the goal explicitly name?",
  options: workspaceOptions,
  resolve: (v, d) => v ?? d.monitors.find((m) => m.focused)?.activeWorkspace.id,
};
const pickWindow: Picker = {
  question: "Which window does the goal refer to?",
  options: windowOptions,
  resolve: (v, d) => v ?? (d.active ? `address:${d.active.address}` : undefined),
};

const define = <P extends z.ZodObject>(a: Action<P>) => a as unknown as Action;

const ws = z.union([z.coerce.number().int(), z.string()]).describe("workspace id or name");

const onOff = (what: string): Picker => ({
  question: `Does the goal want the ${what} muted, unmuted, or toggled?`,
  options: () => ({
    mute: { description: `Mute the ${what}`, value: "mute" },
    unmute: { description: `Unmute the ${what}`, value: "unmute" },
    toggle: { description: `Toggle the ${what} mute`, value: "toggle" },
  }),
});

const setMute = (node: string, state: "mute" | "unmute" | "toggle") =>
  run(["wpctl", "set-mute", node, state === "mute" ? "1" : state === "unmute" ? "0" : "toggle"]);

const muteState = z.enum(["mute", "unmute", "toggle"]);

export const actions: Action[] = [
  define({
    name: "meeting.mic",
    description: "Mute or unmute myself in the meeting or video call I'm in (clicks the call's own mic button, Google Meet)",
    params: z.object({ state: muteState }),
    risk: [],
    pickers: { state: onOff("microphone") },
    run: ({ state }) => setMeetingMic(state),
  }),
  define({
    name: "audio.mic",
    description: "Mute or unmute the microphone for the whole computer at the system level (every app at once, not just a meeting)",
    params: z.object({ state: muteState }),
    risk: [],
    pickers: { state: onOff("microphone") },
    run: ({ state }) => setMute("@DEFAULT_AUDIO_SOURCE@", state),
  }),
  define({
    name: "audio.speakers",
    description: "Mute or unmute the computer's sound output (speakers or headphones)",
    params: z.object({ state: muteState }),
    risk: [],
    pickers: { state: onOff("speakers") },
    run: ({ state }) => setMute("@DEFAULT_AUDIO_SINK@", state),
  }),
  define({
    name: "audio.volume",
    description: "Turn the computer's volume up or down",
    params: z.object({ change: z.enum(["up", "down"]) }),
    risk: [],
    pickers: {
      change: {
        question: "Does the goal want the volume louder or quieter?",
        options: () => ({
          up: { description: "Louder (volume up)", value: "up" },
          down: { description: "Quieter (volume down)", value: "down" },
        }),
      },
    },
    run: ({ change }) => run(["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", change === "up" ? "10%+" : "10%-"]),
  }),
  define({
    name: "workspace.switch",
    description: "Switch the view to a numbered workspace",
    params: z.object({ workspace: ws }),
    risk: [],
    pickers: { workspace: pickWorkspace },
    run: ({ workspace }) => hypr.switchWorkspace(workspace),
  }),
  define({
    name: "window.focus",
    description: "Bring an already-open app window to the front (e.g. \"focus slack\", \"show my terminal\"), by selector class:regex, title:regex, address:0x...",
    params: z.object({ selector: z.string() }),
    risk: [],
    pickers: { selector: pickWindow },
    run: ({ selector }) => hypr.focusWindow(selector),
  }),
  define({
    name: "window.move_to_workspace",
    description: "Move a window (default: the focused one) to a workspace",
    params: z.object({ workspace: ws, selector: z.string().optional(), follow: z.stringbool().default(false) }),
    risk: [],
    pickers: { workspace: pickWorkspace, selector: pickWindow },
    run: ({ workspace, selector, follow }) => hypr.moveWindowToWorkspace(workspace, selector, follow),
  }),
  define({
    name: "window.close",
    description: "Close a window by Hyprland selector",
    params: z.object({ selector: z.string() }),
    risk: ["destructive"],
    pickers: { selector: pickWindow },
    run: ({ selector }) => hypr.closeWindow(selector),
  }),
  define({
    name: "app.launch",
    description: "Launch an installed desktop application (not a website), optionally on a specific workspace",
    params: z.object({ app: z.string().describe("desktop id or app name"), workspace: ws.optional() }),
    risk: [],
    pickers: { app: { question: "Which application does the goal want to launch?", options: appOptions }, workspace: pickWorkspace },
    run: async ({ app, workspace }) => {
      const found = findApp(app);
      if (!found) throw new Error(`no installed app matches "${app}"`);
      await launchApp(found, { workspace });
      return found;
    },
  }),
  define({
    name: "browser.open_url",
    description: "Open a website or web page (e.g. \"open youtube\", \"go to gmail on workspace 2\")",
    params: z.object({ url: z.url(), workspace: ws.optional() }),
    risk: [],
    pickers: { url: { question: "Which website or page does the goal want to open?", options: () => urlOptions() }, workspace: pickWorkspace },
    run: ({ url, workspace }) => openUrl(url, workspace),
  }),
  define({
    name: "keyboard.type",
    description: "Type literal text into the focused window",
    params: z.object({ text: z.string(), delay: z.coerce.number().int().min(0).default(0) }),
    risk: [],
    run: ({ text, delay }) => typeText(text, delay),
  }),
  define({
    name: "keyboard.key",
    description: 'Press a key combo, e.g. "enter", "ctrl+l", "super+shift+s"',
    params: z.object({ combo: z.string() }),
    risk: [],
    run: ({ combo }) => pressKey(combo),
  }),
  define({
    name: "mouse.move",
    description: "Move the cursor to absolute layout coordinates",
    params: z.object({ x: z.coerce.number(), y: z.coerce.number() }),
    risk: [],
    run: ({ x, y }) => hypr.moveCursor(x, y),
  }),
  define({
    name: "mouse.click",
    description: "Click, optionally moving to coordinates first",
    params: z.object({
      x: z.coerce.number().optional(),
      y: z.coerce.number().optional(),
      button: z.enum(["left", "right", "middle"]).default("left"),
      count: z.coerce.number().int().min(1).max(3).default(1),
    }),
    risk: [],
    run: (p) => click(p),
  }),
  define({
    name: "mouse.scroll",
    description: "Scroll the wheel; positive amount scrolls down",
    params: z.object({ amount: z.coerce.number(), x: z.coerce.number().optional(), y: z.coerce.number().optional() }),
    risk: [],
    run: ({ amount, x, y }) => scroll(amount, { x, y }),
  }),
  define({
    name: "screen.screenshot",
    description: "Save a screenshot of the screen, focused monitor, or active window",
    params: z.object({
      path: z.string().default(() => `/tmp/artoo-${Date.now()}.png`),
      target: z.enum(["screen", "monitor", "window"]).default("screen"),
    }),
    risk: [],
    run: ({ path, target }) => screenshot(path, target),
  }),
  define({
    name: "desktop.describe",
    description: "Describe monitors, workspaces, and windows as text",
    params: z.object({}),
    risk: [],
    run: async () => describe(await snapshot()),
  }),
  define({
    name: "apps.list",
    description: "List launchable applications",
    params: z.object({}),
    risk: [],
    run: async () => listApps().map((a) => `${a.id}\t${a.name}`).join("\n"),
  }),
];

export const getAction = (name: string) => actions.find((a) => a.name === name);
