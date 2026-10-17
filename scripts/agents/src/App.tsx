import { useEffect, useRef, useState } from "react";
import { useKeyboard, useTerminalDimensions } from "@opentui/react";
import { theme } from "./lib/theme";
import {
  age,
  closeAgent,
  focusViewer,
  groupPos,
  labelFor,
  listAgents,
  markSeen,
  mergeOrder,
  moveSession,
  newAgent,
  openInSession,
  paneDir,
  pinWidth,
  saveOrder,
  loadOrder,
  orderAgents,
  takePicked,
  view,
  viewedWindow,
  watchedWindows,
  type Agent,
} from "./lib/tmux";

const POLL_MS = 1000;
const PREVIEW_MS = 150; // j/k previews in the viewer once the cursor settles
const SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏";
const ROW_H = 2;
const SIDEBAR_W = 36; // keep in sync with tmux/agents.sh

function glyph(a: Agent, tick: number): { ch: string; fg: string } {
  switch (a.state) {
    case "running":
      return { ch: SPINNER[tick % SPINNER.length], fg: theme.yellow };
    case "attention":
      return { ch: "!", fg: theme.red };
    case "done":
      return a.unseen ? { ch: "●", fg: theme.green } : { ch: "○", fg: theme.gray };
    case "new":
      return { ch: "◇", fg: theme.accent };
    default:
      return { ch: "·", fg: theme.gray };
  }
}

// Left-edge rail per group position: [title line, topic line].
const RAIL = {
  only: [" ", " "],
  first: ["╭", "│"],
  mid: ["│", "│"],
  last: ["│", "╰"],
} as const;

const fit = (s: string, n: number) => (n <= 0 ? "" : s.length > n ? s.slice(0, Math.max(0, n - 1)) + "…" : s);

// Whatever needs you comes first: blocked on a prompt, then finished and unread.
const urgency = (a: Agent) => (a.state === "attention" ? 2 : a.unseen ? 1 : 0);

export function App() {
  const { width: W, height: H } = useTerminalDimensions();
  const [agents, setAgentsState] = useState<Agent[]>(() => listAgents());
  const [cursor, setCursorState] = useState(0);
  const [viewed, setViewed] = useState<string | null>(null); // pane id shown in the viewer
  const [tick, setTick] = useState(0);
  const previewTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Key repeat can deliver several keys before React re-renders, so handlers
  // read these refs rather than the (possibly stale) render-time values.
  const agentsRef = useRef(agents);
  const cursorRef = useRef(0);
  const cursorPane = useRef<string | null>(null); // keeps the cursor on its agent across refreshes
  const setCursor = (n: number) => {
    cursorRef.current = n;
    cursorPane.current = agentsRef.current[n]?.paneId ?? null;
    setCursorState(n);
  };
  const setAgents = (next: Agent[]) => {
    agentsRef.current = next;
    setAgentsState(next);
    const i = next.findIndex((a) => a.paneId === cursorPane.current);
    const n = i >= 0 ? i : Math.min(cursorRef.current, Math.max(0, next.length - 1));
    cursorRef.current = n;
    setCursorState(n);
  };

  useEffect(() => {
    const poll = setInterval(() => {
      const next = listAgents();
      const watched = watchedWindows();
      for (const a of next) {
        if (a.unseen && watched.has(a.windowId)) {
          markSeen(a.paneId);
          a.unseen = false;
        }
      }
      setAgents(next);
      // Someone may have switched the viewer by hand; trust tmux over memory.
      const win = viewedWindow();
      setViewed((cur) => {
        if (!win) return null;
        if (cur && next.some((a) => a.paneId === cur && a.windowId === win)) return cur;
        return next.find((a) => a.windowId === win)?.paneId ?? null;
      });
    }, POLL_MS);
    return () => clearInterval(poll);
  }, []);

  // tmux scales panes proportionally when the hub window resizes; snap back.
  useEffect(() => {
    if (W !== SIDEBAR_W) pinWidth(SIDEBAR_W);
  }, [W]);

  const anyRunning = agents.some((a) => a.state === "running");
  useEffect(() => {
    if (!anyRunning) return;
    const t = setInterval(() => setTick((n) => n + 1), 100);
    return () => clearInterval(t);
  }, [anyRunning]);

  function show(a: Agent | undefined, focus: boolean) {
    if (!a) return;
    if (previewTimer.current) clearTimeout(previewTimer.current);
    if (view(a)) setViewed(a.paneId);
    if (focus) focusViewer();
  }

  // Open a fresh Claude and show it; the next poll puts the cursor on it once
  // the pane is running claude.
  function spawn(session: string, cwd?: string) {
    const a = newAgent(session, cwd);
    if (!a) return;
    cursorPane.current = a.paneId;
    if (view(a)) setViewed(a.paneId);
  }

  function close(a: Agent | undefined) {
    if (!a) return;
    closeAgent(a);
    setAgents(listAgents());
    show(agentsRef.current[cursorRef.current], false);
  }

  // Move the selected agent's whole session up or down the list; the cursor
  // follows it because setAgents tracks the cursor by pane.
  function reorder(a: Agent | undefined, dir: -1 | 1) {
    if (!a) return;
    const visible = moveSession(agentsRef.current, a.session, dir);
    if (!visible) return;
    const order = mergeOrder(loadOrder(), visible);
    saveOrder(order);
    setAgents(orderAgents(agentsRef.current, order));
  }

  function moveTo(i: number, preview = true) {
    const list = agentsRef.current;
    if (!list.length) return;
    const n = Math.max(0, Math.min(list.length - 1, i));
    setCursor(n);
    if (!preview) return;
    if (previewTimer.current) clearTimeout(previewTimer.current);
    previewTimer.current = setTimeout(() => show(list[n], false), PREVIEW_MS);
  }

  useKeyboard((key) => {
    const k = key.name;
    const list = agentsRef.current;
    const cur = cursorRef.current;
    const selected = list[cur];
    if (k === "J" || (k === "j" && key.shift)) reorder(selected, 1);
    else if (k === "K" || (k === "k" && key.shift)) reorder(selected, -1);
    else if (k === "j" || k === "down") moveTo(cur + 1);
    else if (k === "k" || k === "up") moveTo(cur - 1);
    else if (k === "g" && !key.shift) moveTo(0);
    else if (k === "G" || (k === "g" && key.shift)) moveTo(list.length - 1);
    else if (k === "return" || k === "l" || k === "right") show(selected, true);
    else if (k === "o") selected && openInSession(selected);
    else if (k === "x") close(selected);
    else if (k === "t" && !key.shift) selected && spawn(selected.session, paneDir(selected.paneId));
    else if (k === "N" || (k === "n" && key.shift)) {
      const session = takePicked();
      if (session) spawn(session);
    } else if (k === "n") {
      // Next agent that needs you, starting after the cursor.
      const order = list.map((_, i) => (cur + 1 + i) % list.length);
      const best = Math.max(0, ...list.map(urgency));
      const i = best > 0 ? order.find((i) => urgency(list[i]) === best) : undefined;
      if (i != null) {
        moveTo(i, false);
        show(list[i], false);
      }
    } else if (/^[1-9]$/.test(k)) {
      const i = Number(k) - 1;
      if (i < list.length) {
        moveTo(i, false);
        show(list[i], true);
      }
    }
  });

  const needYou = agents.filter((a) => a.state === "attention").length;
  const unread = agents.filter((a) => a.state === "done" && a.unseen).length;
  const running = agents.filter((a) => a.state === "running").length;

  // Header 2 lines + footer 4 lines; scroll so the cursor stays visible.
  const rows = Math.max(1, Math.floor((H - 6) / ROW_H));
  const top = Math.max(0, Math.min(cursor - Math.floor(rows / 2), agents.length - rows));
  const visible = agents.slice(top, top + rows);
  const inner = W - 2;

  return (
    <box style={{ flexDirection: "column", width: W, height: H, backgroundColor: theme.base }}>
      <box style={{ flexDirection: "row", paddingLeft: 1 }}>
        <text fg={theme.accent}>Agents</text>
        <text fg={theme.gray}>{` ${agents.length}`}</text>
      </box>
      <text>
        <span fg={theme.red}>{needYou ? ` ${needYou} need you ` : ""}</span>
        <span fg={theme.green}>{unread ? ` ${unread} done ` : ""}</span>
        <span fg={theme.yellow}>{running ? ` ${running} running` : ""}</span>
        <span fg={theme.gray}>{!needYou && !unread && !running ? " all quiet" : ""}</span>
      </text>

      <box style={{ flexDirection: "column", flexGrow: 1 }}>
        {agents.length === 0 && <text fg={theme.gray}>{" no Claude sessions in tmux"}</text>}
        {visible.map((a, vi) => {
          const i = top + vi;
          const isCursor = i === cursor;
          const isViewed = a.paneId === viewed;
          const g = glyph(a, tick);
          const label = labelFor(a, agents);
          const when = age(a.since);
          const num = i < 9 ? String(i + 1) : " "; // alt+N picks agent N
          const bg = isCursor ? theme.surface : undefined;
          const strong = a.state === "attention" || a.unseen;
          // Several agents in one session: a rail down the left edge ties
          // them together and the ":N" that tells them apart stands out.
          const pos = groupPos(agents, i);
          const rail = RAIL[pos];
          const lw = inner - 5 - when.length;
          const name = fit(label, lw).padEnd(lw);
          const cut = pos === "only" ? lw : Math.min(a.session.length, lw);
          const nameFg = strong || isCursor ? theme.text : theme.gray;
          return (
            <box
              key={a.paneId}
              style={{ flexDirection: "column", backgroundColor: bg }}
              onMouseDown={() => {
                moveTo(i, false);
                show(a, true);
              }}
            >
              <text bg={bg}>
                <span fg={theme.accent}>{isViewed ? "▌" : rail[0]}</span>
                <span fg={isCursor ? theme.text : theme.gray}>{num + " "}</span>
                <span fg={g.fg}>{g.ch}</span>
                <span fg={nameFg}>{" " + name.slice(0, cut)}</span>
                <span fg={theme.accent}>{name.slice(cut)}</span>
                <span fg={theme.gray}>{when + " "}</span>
              </text>
              <text bg={bg}>
                <span fg={theme.accent}>{rail[1]}</span>
                <span fg={theme.gray}>
                  {"    " + fit(a.title || (a.state === "new" ? "new session" : ""), inner - 4)}
                </span>
              </text>
            </box>
          );
        })}
      </box>

      <text fg={theme.gray}>{fit(" alt+j/k move    alt+1-9 show", W)}</text>
      <text fg={theme.gray}>{fit(" alt+t new here  alt+n new in…", W)}</text>
      <text fg={theme.gray}>{fit(" alt+c close     alt+u needs you", W)}</text>
      <text fg={theme.gray}>{fit(" alt+h/l focus", W)}</text>
    </box>
  );
}
