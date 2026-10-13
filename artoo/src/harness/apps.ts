// Index installed .desktop entries so the agent has a closed list of launchable apps.
import { readdirSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import { exec } from "./hypr.ts";

export type App = { id: string; name: string; genericName?: string; comment?: string; exec: string; keywords: string[] };

function appDirs(): string[] {
  const dataHome = process.env.XDG_DATA_HOME ?? join(homedir(), ".local/share");
  const dataDirs = (process.env.XDG_DATA_DIRS ?? "/usr/local/share:/usr/share").split(":");
  return [dataHome, ...dataDirs].map((d) => join(d, "applications"));
}

export function parseDesktopEntry(id: string, text: string): App | null {
  const fields: Record<string, string> = {};
  let inMain = false;
  for (const line of text.split("\n")) {
    if (line.startsWith("[")) {
      inMain = line.trim() === "[Desktop Entry]";
      continue;
    }
    if (!inMain) continue;
    const eq = line.indexOf("=");
    if (eq > 0) fields[line.slice(0, eq).trim()] ??= line.slice(eq + 1).trim();
  }
  if (fields.Type !== "Application" || !fields.Name || !fields.Exec) return null;
  if (fields.NoDisplay === "true" || fields.Hidden === "true") return null;
  return {
    id,
    name: fields.Name,
    genericName: fields.GenericName,
    comment: fields.Comment,
    // Drop field codes (%U, %f, ...) — we pass our own arguments.
    exec: fields.Exec.replace(/\s*%[a-zA-Z]/g, "").trim(),
    keywords: (fields.Keywords ?? "").split(";").filter(Boolean),
  };
}

let cache: App[] | null = null;

export function listApps(): App[] {
  if (cache) return cache;
  const seen = new Map<string, App>();
  // Earlier dirs win (user overrides system), matching XDG lookup order.
  for (const dir of appDirs()) {
    let files: string[];
    try {
      files = readdirSync(dir).filter((f) => f.endsWith(".desktop"));
    } catch {
      continue;
    }
    for (const f of files) {
      const id = basename(f, ".desktop");
      if (seen.has(id)) continue;
      try {
        const app = parseDesktopEntry(id, readFileSync(join(dir, f), "utf8"));
        if (app) seen.set(id, app);
      } catch {}
    }
  }
  cache = [...seen.values()].sort((a, b) => a.name.localeCompare(b.name));
  return cache;
}

export function findApp(idOrName: string): App | undefined {
  const q = idOrName.toLowerCase();
  const apps = listApps();
  return apps.find((a) => a.id.toLowerCase() === q) ?? apps.find((a) => a.name.toLowerCase() === q);
}

export function launchApp(app: App, opts: { args?: string[]; workspace?: number | string } = {}) {
  const cmd = [app.exec, ...(opts.args ?? []).map(shellQuote)].join(" ");
  return exec(cmd, { workspace: opts.workspace });
}

export const shellQuote = (s: string) => (/^[\w@%+=:,./-]+$/.test(s) ? s : `'${s.replaceAll("'", `'\\''`)}'`);
