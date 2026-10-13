// Where Brave saves downloads for the rest of one task. Set over a browser-level DevTools
// session: Brave drops the setting the moment that session closes, so a crashed or cancelled
// task can never leave downloads redirected. No save dialog opens either way.
import { mkdirSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, join, relative, resolve } from "node:path";
import { connectBrowser, type CdpSession } from "./harness/cdp.ts";
import { sleep } from "./runtime.ts";

const PARTIAL = /\.(crdownload|part|tmp)$/;

/** A folder path from the planner, or null unless it is inside the home directory. */
export function homeFolder(text: string | null | undefined): string | null {
  const raw = (text ?? "").trim();
  if (!raw) return null;
  const home = homedir();
  const path = resolve(raw === "~" ? home : raw.startsWith("~/") ? join(home, raw.slice(2)) : isAbsolute(raw) ? raw : join(home, raw));
  const rel = relative(home, path);
  return rel && !rel.startsWith("..") && !isAbsolute(rel) ? path : null;
}

export class DownloadFolder {
  #browser: CdpSession | null = null;
  dir: string | null = null;

  /** Create the folder if needed and send Brave's downloads there. */
  async set(dir: string) {
    mkdirSync(dir, { recursive: true });
    this.#browser ??= await connectBrowser();
    await this.#browser.send("Browser.setDownloadBehavior", { behavior: "allow", downloadPath: dir, eventsEnabled: false });
    this.dir = dir;
  }

  /** Finished files in the folder, and how many are still downloading. */
  contents(): { files: string[]; downloading: number } {
    if (!this.dir) return { files: [], downloading: 0 };
    const all = readdirSync(this.dir).filter((f) => !f.startsWith("."));
    return { files: all.filter((f) => !PARTIAL.test(f)).sort(), downloading: all.filter((f) => PARTIAL.test(f)).length };
  }

  /** Give downloads that just started a moment to land, so the next look counts them. */
  async settle(ms = 6000) {
    if (!this.dir) return;
    // A click's download can take a couple of seconds to start; wait for it to show up.
    const before = this.contents().files.length;
    for (const end = Date.now() + 3000; this.contents().files.length === before && !this.contents().downloading && Date.now() < end;) await sleep(250);
    for (const end = Date.now() + ms; this.contents().downloading && Date.now() < end;) await sleep(400);
  }

  close() {
    this.#browser?.close();
    this.#browser = null;
    this.dir = null;
  }
}
