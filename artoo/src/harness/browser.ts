// Browser actions that drive the Brave windows you already have open, like a person would.
import { shellQuote } from "./apps.ts";
import * as hypr from "./hypr.ts";
import { pressKey, typeText } from "./input.ts";

const BRAVE_CLASS = /^brave-browser$/;

/** Pauses for the UI to catch up (focus change, new tab animation). Tests set these to 0. */
export const timing = { afterFocus: 150, afterNewTab: 350, focusPoll: 50, focusTimeout: 1000 };

const onWorkspace = (c: hypr.Client, ws: number | string) =>
  String(c.workspace.id) === String(ws) || c.workspace.name === String(ws);

/** Most recently focused Brave window on a workspace, if any. */
export async function braveWindowOn(ws: number | string): Promise<hypr.Client | undefined> {
  return (await hypr.clients())
    .filter((c) => BRAVE_CLASS.test(c.class) && onWorkspace(c, ws))
    .sort((a, b) => a.focusHistoryID - b.focusHistoryID)[0];
}

async function waitForFocus(address: string) {
  const deadline = Date.now() + timing.focusTimeout;
  while (Date.now() <= deadline) {
    if ((await hypr.activeWindow())?.address === address) return;
    await Bun.sleep(timing.focusPoll);
  }
  throw new Error(`window ${address} never took focus; not typing into whatever did`);
}

/**
 * Open a URL as a new tab in the Brave window on `workspace` (default: the current one),
 * the same way you would: focus it, ctrl+t, type, enter. Only if there's no Brave window
 * there does it open a new one.
 */
export async function openUrl(url: string, workspace?: number | string): Promise<"new_tab" | "new_window"> {
  const ws = workspace ?? (await hypr.activeWorkspace()).id;
  if (workspace !== undefined) await hypr.switchWorkspace(workspace);

  const win = await braveWindowOn(ws);
  if (!win) {
    // Brave is single-instance: the launcher hands off to the running browser and exits,
    // so an exec workspace rule wouldn't match. We already switched; new windows open here.
    await hypr.exec(`brave --new-window ${shellQuote(url)}`);
    return "new_window";
  }

  await hypr.focusWindow(`address:${win.address}`);
  await waitForFocus(win.address);
  await Bun.sleep(timing.afterFocus);
  await pressKey("ctrl+t");
  await Bun.sleep(timing.afterNewTab);
  await typeText(url);
  // The omnibox may inline-autocomplete a longer URL from history as selected text; drop it.
  await pressKey("delete");
  await pressKey("enter");
  return "new_tab";
}
