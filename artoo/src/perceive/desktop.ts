// Text snapshot of the desktop. This becomes the `state` string Jev decides over.
import { isHiddenApp, isHiddenSite } from "../guardrails.ts";
import { targets } from "../harness/cdp.ts";
import { activeWindow, clients, monitors, workspaces, type Client } from "../harness/hypr.ts";

export type DesktopState = Awaited<ReturnType<typeof snapshot>>;

/** Windows on the never_look list: their titles don't leave the machine. */
export type Window = Client & { private: boolean };

export async function snapshot() {
  const [ws, cl, mons, active, tabs] = await Promise.all([
    workspaces(),
    clients(),
    monitors(),
    activeWindow(),
    targets().catch(() => []),
  ]);
  // Brave titles windows after the active tab, so a tab on a never_look site makes its window private.
  const hiddenTabTitles = new Set(tabs.filter((t) => isHiddenSite(t.url)).map((t) => `${t.title} - Brave`));
  const mark = (c: Client): Window => ({ ...c, private: isHiddenApp(c.class) || hiddenTabTitles.has(c.title) });
  const windows = cl.map(mark);
  return { workspaces: ws, clients: windows, monitors: mons, active: active ? mark(active) : null };
}

/** What a window may be called in anything sent out. */
export const titleOf = (c: Window) => (c.private ? "(private)" : c.title);

export function describe(s: DesktopState): string {
  const lines: string[] = [];
  for (const m of s.monitors) {
    lines.push(`Monitor ${m.name} ${m.width}x${m.height}${m.focused ? " (focused)" : ""}, showing workspace ${m.activeWorkspace.name}`);
  }
  lines.push(`Focused window: ${s.active ? `${s.active.class} — "${titleOf(s.active)}"` : "none"}`);
  for (const w of [...s.workspaces].sort((a, b) => a.id - b.id)) {
    const wins = s.clients.filter((c) => c.workspace.id === w.id);
    lines.push(`Workspace ${w.name}: ${wins.length ? wins.map((c) => `${c.class} "${titleOf(c)}"`).join("; ") : "empty"}`);
  }
  return lines.join("\n");
}
