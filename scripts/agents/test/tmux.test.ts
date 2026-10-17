import { describe, expect, test } from "bun:test";
import {
  age,
  cleanTitle,
  groupPos,
  labelFor,
  mergeOrder,
  moveSession,
  orderAgents,
  parseAgents,
  PANE_FORMAT,
} from "../src/lib/tmux";

const S = "\x1f";
const row = (...f: string[]) => f.join(S);
// pane window session idx winname pidx cmd title state at seen
const out = [
  row("%1", "@1", "narsil", "0", "claude", "0", "claude", "✳ Looker page", "done", "100", "0"),
  row("%2", "@2", "dotfiles", "0", "claude", "0", "claude", "✳ Claude Code", "", "", ""),
  row("%3", "@2", "dotfiles", "0", "claude", "1", "claude", "⠂ Tmux terms", "running", "50", "1"),
  row("%4", "@3", "dotfiles", "1", "nvim", "0", "nvim", "nvim", "", "", ""),
  row("%2", "@2", "agents-view", "2", "claude", "0", "claude", "✳ Claude Code", "", "", ""),
  row("%9", "@9", "agents", "0", "hub", "0", "bun", "agents", "", "", ""),
  row("%5", "@5", "Bc", "0", "claude", "0", "node", "✳ Fix", "attention", "10", "1"),
  row("%6", "@6", "zz", "0", "claude", "0", "claude", "myhost", "", "", ""),
].join("\n");

describe("parseAgents", () => {
  const agents = parseAgents(out, "myhost");

  test("keeps claude panes and hook-tagged panes, drops the hub and nvim", () => {
    expect(agents.map((a) => a.paneId)).toEqual(["%5", "%2", "%3", "%1", "%6"]);
  });
  test("a window linked into the viewer is named after its project", () => {
    expect(agents.find((a) => a.paneId === "%2")!.session).toBe("dotfiles");
  });
  test("untitled Claude without hook state counts as new", () => {
    const a = agents.find((a) => a.paneId === "%2")!;
    expect(a.state).toBe("new");
    expect(a.title).toBe("");
  });
  test("unseen only for finished or blocked agents", () => {
    expect(agents.find((a) => a.paneId === "%1")!.unseen).toBe(true);
    expect(agents.find((a) => a.paneId === "%3")!.unseen).toBe(false);
    expect(agents.find((a) => a.paneId === "%5")!.unseen).toBe(false);
  });
  test("labels disambiguate sessions holding several agents", () => {
    expect(agents.map((a) => labelFor(a, agents))).toEqual(["Bc", "dotfiles:0.0", "dotfiles:0.1", "narsil", "zz"]);
  });
  test("a pane still titled after the host has no topic yet", () => {
    expect(agents.find((a) => a.paneId === "%6")!.state).toBe("new");
  });
});

test("cleanTitle strips Claude's leading glyph", () => {
  expect(cleanTitle("✳ Tmux session vs window")).toBe("Tmux session vs window");
  expect(cleanTitle("⠐ 2026 plan")).toBe("2026 plan");
});

test("age", () => {
  expect(age(null)).toBe("");
  expect(age(100, 159)).toBe("59s");
  expect(age(0, 7200)).toBe("2h");
});

test("format has one field per column", () => {
  expect(PANE_FORMAT.split(S)).toHaveLength(11);
});

describe("session order", () => {
  const agents = parseAgents(out, "myhost"); // Bc, dotfiles x2, narsil, zz
  const ids = (l: typeof agents) => l.map((a) => a.paneId);

  test("ordered sessions first, the rest alphabetical, groups intact", () => {
    expect(ids(orderAgents(agents, ["narsil", "dotfiles", "gone"]))).toEqual(["%1", "%2", "%3", "%5", "%6"]);
  });
  test("moving a session swaps it with the neighbouring group", () => {
    expect(moveSession(agents, "narsil", -1)).toEqual(["Bc", "narsil", "dotfiles", "zz"]);
    expect(moveSession(agents, "Bc", -1)).toBeNull();
    expect(moveSession(agents, "zz", 1)).toBeNull();
  });
  test("sessions not running keep their saved slot", () => {
    expect(mergeOrder(["a", "gone", "b"], ["b", "a", "new"])).toEqual(["b", "gone", "a", "new"]);
  });
  test("group positions", () => {
    expect(agents.map((_, i) => groupPos(agents, i))).toEqual(["only", "first", "last", "only", "only"]);
  });
});
