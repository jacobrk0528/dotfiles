// Everything the sidebar knows comes from tmux: agents are panes running
// Claude Code, and their state is the @agent_* pane options written by
// ~/.tmux/agent_state.sh from Claude Code hooks.
//
// The hub ("agents" session) shows an agent by LINKING its window into the
// "agents-view" session, which a nested client in the hub's right pane is
// attached to. Linking shares the window rather than copying it, so the hub and
// the project session drive the same Claude. Nothing here may ever kill a
// window: link-window -k and kill-window would destroy it in every session it
// is linked to. Only unlink-window (without -k, which refuses to drop a
// window's last link) is used to tidy the viewer.

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir, hostname } from "node:os";
import { dirname, join } from "node:path";

export const HUB = "agents";
export const VIEW = "agents-view";

export type State = "new" | "running" | "attention" | "done" | "unknown";

export interface Agent {
  paneId: string;
  windowId: string;
  session: string;
  windowIndex: number;
  windowName: string;
  paneIndex: number;
  title: string;
  state: State;
  since: number | null; // epoch seconds of the last state change
  unseen: boolean; // finished or blocked and not looked at yet
}

const SEP = "\x1f";
const FIELDS = [
  "pane_id",
  "window_id",
  "session_name",
  "window_index",
  "window_name",
  "pane_index",
  "pane_current_command",
  "pane_title",
  "@agent_state",
  "@agent_at",
  "@agent_seen",
] as const;
export const PANE_FORMAT = FIELDS.map((f) => `#{${f}}`).join(SEP);

const STATES = new Set<State>(["new", "running", "attention", "done"]);

// Claude Code titles its terminal "✳ <topic>", or "✳ Claude Code" before the
// first prompt. Drop the leading glyph so only the topic is left.
export function cleanTitle(raw: string): string {
  return raw.replace(/^[^\p{L}\p{N}]+/u, "").trim();
}

export function parseAgents(output: string, host = hostname()): Agent[] {
  const byPane = new Map<string, Agent>();
  for (const line of output.split("\n")) {
    if (!line) continue;
    const [paneId, windowId, session, windowIndex, windowName, paneIndex, command, rawTitle, rawState, at, seen] =
      line.split(SEP);
    if (session === HUB) continue;
    if (command !== "claude" && !rawState) continue;

    // tmux titles a pane after the host until its program sets one.
    const title = rawTitle === host ? "" : cleanTitle(rawTitle ?? "");
    let state: State = STATES.has(rawState as State) ? (rawState as State) : "unknown";
    // Started before the hooks existed: an untitled Claude has never had a prompt.
    if (state === "unknown" && (title === "" || title === "Claude Code")) state = "new";

    const agent: Agent = {
      paneId,
      windowId,
      session,
      windowIndex: Number(windowIndex),
      windowName,
      paneIndex: Number(paneIndex),
      title: title === "Claude Code" ? "" : title,
      state,
      since: at ? Number(at) : null,
      unseen: seen === "0" && (state === "done" || state === "attention"),
    };
    // A window linked into the viewer is listed twice; name it after its project.
    const prev = byPane.get(paneId);
    if (!prev || prev.session === VIEW) byPane.set(paneId, agent);
  }
  return [...byPane.values()].sort(
    (a, b) =>
      a.session.localeCompare(b.session, undefined, { sensitivity: "base" }) ||
      a.windowIndex - b.windowIndex ||
      a.paneIndex - b.paneIndex,
  );
}

// Put sessions in the user's order (J/K in the sidebar). Sessions missing from
// it keep parseAgents' alphabetical order after the ordered ones, and a
// session's agents always stay together in window/pane order.
export function orderAgents(agents: Agent[], order: string[]): Agent[] {
  const rank = (s: string) => {
    const i = order.indexOf(s);
    return i < 0 ? Infinity : i;
  };
  return agents
    .map((a, i) => ({ a, i }))
    .sort((x, y) => rank(x.a.session) - rank(y.a.session) || x.i - y.i)
    .map((x) => x.a);
}

// The session order after moving `session` one group up (-1) or down (+1) in
// `agents` (display order). Null when it is already at that end.
export function moveSession(agents: Agent[], session: string, dir: -1 | 1): string[] | null {
  const sessions = [...new Set(agents.map((a) => a.session))];
  const i = sessions.indexOf(session);
  const j = i + dir;
  if (i < 0 || j < 0 || j >= sessions.length) return null;
  [sessions[i], sessions[j]] = [sessions[j], sessions[i]];
  return sessions;
}

// Where an agent sits in its session's group: "only" for a session with one
// agent, else first/mid/last. Expects agents in display order.
export type GroupPos = "only" | "first" | "mid" | "last";
export function groupPos(agents: Agent[], i: number): GroupPos {
  const s = agents[i].session;
  const up = agents[i - 1]?.session === s;
  const down = agents[i + 1]?.session === s;
  return up ? (down ? "mid" : "last") : down ? "first" : "only";
}

// --- session order on disk ---------------------------------------------------
// One session name per line. Kept in a file rather than tmux so it survives a
// reboot; names of sessions not running right now keep their place.

const ORDER_FILE = join(process.env.XDG_STATE_HOME || join(homedir(), ".local/state"), "agents/order");

export function loadOrder(): string[] {
  try {
    return readFileSync(ORDER_FILE, "utf8").split("\n").filter(Boolean);
  } catch {
    return [];
  }
}

// Fold the visible sessions' new order into the saved one: stored sessions
// that aren't running hold their slots, the visible ones fill the rest.
export function mergeOrder(saved: string[], visible: string[]): string[] {
  const vis = new Set(visible);
  const base = [...saved, ...visible.filter((s) => !saved.includes(s))];
  let k = 0;
  return base.map((s) => (vis.has(s) ? visible[k++] : s));
}

export function saveOrder(order: string[]): void {
  try {
    mkdirSync(dirname(ORDER_FILE), { recursive: true });
    writeFileSync(ORDER_FILE, order.join("\n") + "\n");
  } catch {
    // the order just won't survive a restart
  }
}

// "dotfiles", or "dotfiles:0" / "dotfiles:0.1" when the session holds several agents.
export function labelFor(agent: Agent, all: Agent[]): string {
  const same = all.filter((a) => a.session === agent.session);
  if (same.length < 2) return agent.session;
  const sameWindow = same.filter((a) => a.windowId === agent.windowId).length > 1;
  return `${agent.session}:${agent.windowIndex}${sameWindow ? `.${agent.paneIndex}` : ""}`;
}

export function age(since: number | null, now = Date.now() / 1000): string {
  if (since == null) return "";
  const s = Math.max(0, Math.floor(now - since));
  if (s < 60) return `${s}s`;
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

// --- talking to tmux ---------------------------------------------------------

function tmux(...args: string[]): { ok: boolean; out: string } {
  const r = Bun.spawnSync(["tmux", ...args], { stdout: "pipe", stderr: "ignore" });
  return { ok: r.exitCode === 0, out: r.stdout.toString() };
}

export function listAgents(): Agent[] {
  return orderAgents(parseAgents(tmux("list-panes", "-a", "-F", PANE_FORMAT).out), loadOrder());
}

interface Linked {
  index: string;
  id: string;
  active: boolean;
}

function viewWindows(): Linked[] {
  return tmux("list-windows", "-t", `=${VIEW}`, "-F", "#{window_index} #{window_id} #{window_active}")
    .out.split("\n")
    .filter(Boolean)
    .map((l) => {
      const [index, id, active] = l.split(" ");
      return { index, id, active: active === "1" };
    });
}

function placeholderId(): string {
  return tmux("show", "-qv", "-t", `=${VIEW}:`, "@placeholder").out.trim();
}

// The window id the viewer currently shows, or null for the placeholder.
export function viewedWindow(): string | null {
  const active = viewWindows().find((w) => w.active);
  return active && active.id !== placeholderId() ? active.id : null;
}

// Show an agent in the hub's viewer. Returns false when the viewer is missing
// (the hub's right pane recreates it within a second).
export function view(agent: Pick<Agent, "windowId" | "paneId">): boolean {
  let linked = viewWindows();
  if (!linked.length) return false;
  if (!linked.some((w) => w.id === agent.windowId)) {
    tmux("link-window", "-d", "-s", agent.windowId, "-t", `=${VIEW}:`);
    linked = viewWindows();
  }
  const target = linked.find((w) => w.id === agent.windowId);
  if (!target) return false;
  tmux("select-window", "-t", `=${VIEW}:${target.index}`);
  tmux("select-pane", "-t", agent.paneId);
  markSeen(agent.paneId);

  const keep = placeholderId();
  for (const w of linked) {
    if (w.id !== agent.windowId && w.id !== keep) tmux("unlink-window", "-t", `=${VIEW}:${w.index}`);
  }
  return true;
}

// Start a Claude in a new window of `session`, in `cwd` or the session's own
// directory. Typed into a shell like the builders do, since `claude` is a zsh
// function and leaving the shell behind keeps the window usable after /exit.
// The builders leave window 0 ("claude") as an idle shell for this; it is used
// first when it is still idle and in the right directory.
export function newAgent(session: string, cwd?: string): { paneId: string; windowId: string } | null {
  const dir = cwd || tmux("display", "-p", "-t", `=${session}:`, "#{session_path}").out.trim();
  const slot = tmux("list-windows", "-t", `=${session}`, "-F",
    ["#{window_index}", "#{window_name}", "#{window_panes}", "#{pane_current_command}", "#{pane_current_path}", "#{pane_id}", "#{window_id}"].join(SEP))
    .out.split("\n")
    .map((l) => l.split(SEP))
    .find(([index, name, panes, cmd, path]) => index === "0" && name === "claude" && panes === "1" && cmd === "zsh" && path === dir);
  if (slot) {
    tmux("send-keys", "-t", slot[5], "claude", "Enter");
    return { paneId: slot[5], windowId: slot[6] };
  }
  const r = tmux("new-window", "-d", "-P", "-F", "#{pane_id} #{window_id}", "-t", `=${session}:`, "-n", "claude", "-c", dir);
  if (!r.ok) return null;
  const [paneId, windowId] = r.out.trim().split(" ");
  tmux("send-keys", "-t", paneId, "claude", "Enter");
  return { paneId, windowId };
}

export function paneDir(paneId: string): string {
  return tmux("display", "-p", "-t", paneId, "#{pane_current_path}").out.trim();
}

// Close an agent by killing its pane, the one deliberate kill in here. The last
// window of a session, and the builders' window 0 slot, get a fresh shell
// instead, so the project session and its layout live on.
export function closeAgent(agent: Agent): void {
  const windows = tmux("list-windows", "-t", `=${agent.session}`, "-F", "#{window_id}").out.split("\n").filter(Boolean);
  const panes = tmux("list-panes", "-t", agent.paneId, "-F", "#{pane_id}").out.split("\n").filter(Boolean);
  const slot = agent.windowIndex === 0 && agent.windowName === "claude";
  if (panes.length === 1 && (windows.length === 1 || slot)) {
    tmux("respawn-pane", "-k", "-c", paneDir(agent.paneId), "-t", agent.paneId);
    for (const o of ["@agent_state", "@agent_at", "@agent_seen"]) tmux("set", "-p", "-u", "-t", agent.paneId, o);
  } else {
    tmux("kill-pane", "-t", agent.paneId);
  }
}

// The session picked in the `agents --pick` popup, consumed once.
export function takePicked(): string {
  const s = tmux("show", "-qv", "-t", `=${HUB}:`, "@agents_new").out.trim();
  if (s) tmux("set", "-u", "-t", `=${HUB}:`, "@agents_new");
  return s;
}

export function markSeen(paneId: string): void {
  tmux("set", "-p", "-t", paneId, "@agent_seen", "1");
}

// Move keyboard focus from the sidebar to the viewer beside it.
export function focusViewer(): void {
  const me = process.env.TMUX_PANE;
  if (me) tmux("select-pane", "-R", "-t", me);
}

// Only when running as the hub's sidebar; a standalone run leaves panes alone.
export function pinWidth(cols: number): void {
  const me = process.env.TMUX_PANE;
  if (!me) return;
  const session = tmux("display", "-p", "-t", me, "#{session_name}").out.trim();
  if (session === HUB) tmux("resize-pane", "-t", me, "-x", String(cols));
}

// Leave the hub: switch the hub's own client to the agent's project session.
export function openInSession(agent: Agent): void {
  const clients = tmux("list-clients", "-t", `=${HUB}`, "-F", "#{client_activity} #{client_name}")
    .out.split("\n")
    .filter(Boolean)
    .sort()
    .map((l) => l.slice(l.indexOf(" ") + 1));
  const client = clients.at(-1);
  if (!client) return;
  tmux("switch-client", "-c", client, "-t", `=${agent.session}:${agent.windowIndex}`);
  tmux("select-pane", "-t", agent.paneId);
}

// An agent counts as looked at when some client shows its window -- except the
// hub's viewer while nobody is in the hub, since it keeps showing the last pick.
export function watchedWindows(): Set<string> {
  const hubAttached = Number(tmux("display", "-p", "-t", `=${HUB}:`, "#{session_attached}").out.trim()) > 0;
  const out = new Set<string>();
  for (const l of tmux("list-clients", "-F", "#{session_name} #{window_id}").out.split("\n")) {
    const [session, windowId] = l.split(" ");
    if (!windowId) continue;
    if (session === VIEW && !hubAttached) continue;
    out.add(windowId);
  }
  return out;
}
