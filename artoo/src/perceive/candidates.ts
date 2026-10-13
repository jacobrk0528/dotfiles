// "Code does the wide search, Jev only chooses between a few": closed option lists per param type.
import { Database } from "bun:sqlite";
import { copyFileSync, existsSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { listApps } from "../harness/apps.ts";
import type { Options } from "../jev.ts";
import { isHiddenSite } from "../guardrails.ts";
import { titleOf, type DesktopState } from "./desktop.ts";

export function workspaceOptions(desktop: DesktopState): Options<number | string> {
  const opts: Options<number | string> = {};
  const byId = new Map(desktop.workspaces.map((w) => [w.id, w]));
  for (let id = 1; id <= 10; id++) {
    const wins = desktop.clients.filter((c) => c.workspace.id === id).map((c) => c.class);
    opts[`ws${id}`] = {
      description: `Workspace ${id}${byId.has(id) ? "" : " (empty)"}${wins.length ? ` — has ${wins.join(", ")}` : ""}`,
      value: id,
    };
  }
  return opts;
}

export function windowOptions(desktop: DesktopState): Options<string> {
  const opts: Options<string> = {};
  desktop.clients.forEach((c, i) => {
    const focused = desktop.active?.address === c.address ? " (focused)" : "";
    opts[`win${i + 1}`] = {
      description: `${c.class} window "${titleOf(c)}" on workspace ${c.workspace.name}${focused}`,
      value: `address:${c.address}`,
    };
  });
  return opts;
}

export function appOptions(): Options<string> {
  const opts: Options<string> = {};
  listApps().forEach((a, i) => {
    const extra = [a.genericName, a.comment].filter(Boolean).join(" — ");
    opts[`app${i + 1}`] = { description: `${a.name}${extra ? ` (${extra})` : ""}`, value: a.id };
  });
  return opts;
}

// Seed list so common goals work before any history exists.
const COMMON_SITES: [string, string][] = [
  ["YouTube", "https://www.youtube.com"],
  ["YouTube Music", "https://music.youtube.com"],
  ["Gmail", "https://mail.google.com"],
  ["Google Calendar", "https://calendar.google.com"],
  ["Google Drive", "https://drive.google.com"],
  ["Google Maps", "https://maps.google.com"],
  ["Google Search", "https://www.google.com"],
  ["GitHub", "https://github.com"],
  ["Reddit", "https://www.reddit.com"],
  ["X (Twitter)", "https://x.com"],
  ["Twitch", "https://www.twitch.tv"],
  ["Netflix", "https://www.netflix.com"],
  ["Amazon", "https://www.amazon.com"],
  ["Spotify Web Player", "https://open.spotify.com"],
  ["Claude", "https://claude.ai"],
  ["ChatGPT", "https://chatgpt.com"],
  ["Linear", "https://linear.app"],
  ["Google Messages", "https://messages.google.com/web"],
];

const BRAVE_DIR = join(homedir(), ".config/BraveSoftware/Brave-Browser");

function braveProfiles(): string[] {
  try {
    return readdirSync(BRAVE_DIR)
      .filter((d) => d === "Default" || d.startsWith("Profile "))
      .map((d) => join(BRAVE_DIR, d));
  } catch {
    return [];
  }
}

type BookmarkNode = { type?: string; name?: string; url?: string; children?: BookmarkNode[] };

function bookmarks(profile: string): [string, string][] {
  const file = join(profile, "Bookmarks");
  if (!existsSync(file)) return [];
  const out: [string, string][] = [];
  const walk = (n: BookmarkNode) => {
    if (n.type === "url" && n.name && n.url) out.push([n.name, n.url]);
    n.children?.forEach(walk);
  };
  try {
    const roots = (JSON.parse(readFileSync(file, "utf8")).roots ?? {}) as Record<string, unknown>;
    for (const r of Object.values(roots)) if (r && typeof r === "object") walk(r as BookmarkNode);
  } catch {}
  return out;
}

function topHistory(profile: string, limit: number): [string, string][] {
  const file = join(profile, "History");
  if (!existsSync(file)) return [];
  // Brave holds a lock on the live DB; read a copy.
  const copy = join(tmpdir(), `artoo-history-${process.pid}.sqlite`);
  try {
    copyFileSync(file, copy);
    const db = new Database(copy, { readonly: true });
    const rows = db
      .query<{ title: string; url: string }, [number]>(
        "SELECT title, url FROM urls WHERE hidden = 0 AND url LIKE 'http%' ORDER BY visit_count DESC LIMIT ?",
      )
      .all(limit);
    db.close();
    return rows.map((r) => [r.title || r.url, r.url]);
  } catch {
    return [];
  } finally {
    rmSync(copy, { force: true });
  }
}

export function urlOptions(limit = 200): Options<string> {
  const profiles = braveProfiles();
  const sources: [string, string, string][] = [
    ...COMMON_SITES.map(([n, u]) => [n, u, "site"] as [string, string, string]),
    ...profiles.flatMap((p) => bookmarks(p).map(([n, u]) => [n, u, "bookmark"] as [string, string, string])),
    ...profiles.flatMap((p) => topHistory(p, 60).map(([n, u]) => [n, u, "frequently visited"] as [string, string, string])),
  ];
  const opts: Options<string> = {};
  const seen = new Set<string>();
  for (const [name, url, kind] of sources) {
    const norm = url.replace(/\/+$/, "");
    if (seen.has(norm)) continue;
    seen.add(norm);
    let host = url;
    try {
      host = new URL(url).host;
    } catch {
      continue;
    }
    // Private sites can still be opened by name, but their page titles aren't sent.
    const shown = isHiddenSite(url) ? host : name;
    opts[`url${seen.size}`] = { description: `${shown} — ${host} (${kind})`, value: url };
    if (seen.size >= limit) break;
  }
  return opts;
}
