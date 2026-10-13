import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { runGoal } from "../src/agent.ts";
import { setRunner } from "../src/exec.ts";
import { setJev, type JevClient } from "../src/jev.ts";

const desktop = {
  workspaces: [{ id: 1, name: "1", monitor: "DP-1", windows: 1, lastwindowtitle: "" }],
  clients: [
    { address: "0xabc", class: "twitch", title: "Twitch", workspace: { id: 1, name: "1" }, at: [0, 0], size: [10, 10], focusHistoryID: 0, pid: 1 },
  ],
  monitors: [{ id: 0, name: "DP-1", x: 0, y: 0, width: 1920, height: 1080, scale: 1, focused: true, activeWorkspace: { id: 1, name: "1" } }],
  activewindow: {},
};

let calls: string[][];
let runsDir: string;

beforeEach(() => {
  calls = [];
  runsDir = mkdtempSync(join(tmpdir(), "artoo-test-"));
  process.env.JEV_PILOT_RUNS = runsDir;
  process.env.JEV_CDP_URL = "http://127.0.0.1:1"; // never reach the real browser from tests
  setRunner(async (cmd) => {
    calls.push(cmd);
    if (cmd[0] === "hyprctl" && cmd[1] === "-j") return { stdout: JSON.stringify(desktop[cmd[2] as keyof typeof desktop]), stderr: "", code: 0 };
    return { stdout: "ok", stderr: "", code: 0 };
  });
});

afterEach(() => {
  setRunner(null);
  setJev(null);
  rmSync(runsDir, { recursive: true, force: true });
});

/**
 * Fake Jev: for each choice question, pick the first option whose key or description matches.
 * Yes/no (guard) questions answer `risk[category]`, default 0.01.
 */
function fakeJev(rules: Record<string, [RegExp, number, Record<string, number>?]>, risk: Record<string, number> = {}): JevClient {
  return {
    systemOne: (async ({ questions }: { questions: Record<string, { type: string; criteria: Record<string, string> }> }) => ({
      model: "fake",
      usage: { input_tokens: 0, output_tokens: 0 },
      answers: Object.fromEntries(
        Object.entries(questions).map(([name, q]) => {
          if (q.type === "noul") return [name, { type: "noul", noul: risk[name] ?? 0.01 }];
          const [re, confidence, probabilities] = rules[name] ?? [/^unspecified$/, 0.99];
          const key = Object.entries(q.criteria).find(([k, d]) => re.test(k) || re.test(d ?? ""))?.[0];
          if (!key) throw new Error(`fake: nothing matches ${re} for ${name}`);
          return [name, { type: "choice", choice: key, confidence, probabilities: probabilities ?? { [key]: confidence } }];
        }),
      ),
    })) as unknown as JevClient["systemOne"],
  };
}

const dispatches = () => calls.filter((c) => c[1] === "dispatch");

test("fast path opens a URL on a workspace", async () => {
  setJev(fakeJev({ action: [/^browser\.open_url$/, 0.95], url: [/youtube\.com \(site\)/, 0.99], workspace: [/^ws3$/, 0.99] }));
  const res = await runGoal("open youtube on workspace 3", { print: () => {} });
  expect(res).toMatchObject({ status: "done", action: "browser.open_url", params: { url: "https://www.youtube.com", workspace: 3 } });
  expect(dispatches()).toEqual([
    ["hyprctl", "dispatch", "hl.dsp.focus({ workspace = 3 })"],
    ["hyprctl", "dispatch", 'hl.dsp.exec_cmd("brave --new-window https://www.youtube.com")'],
  ]);
});

test("low confidence asks, and a no means nothing runs", async () => {
  setJev(fakeJev({ action: [/^workspace\.switch$/, 0.5], workspace: [/^ws2$/, 0.99] }));
  const asked: string[] = [];
  const res = await runGoal("maybe workspace two", { print: () => {}, confirm: async (m) => (asked.push(m), false) });
  expect(res.status).toBe("declined");
  expect(asked[0]).toContain("low confidence");
  expect(dispatches()).toEqual([]);
});

test("risky actions always ask, even at high confidence", async () => {
  setJev(fakeJev({ action: [/^window\.close$/, 0.99], selector: [/twitch/, 0.99] }));
  const asked: string[] = [];
  const res = await runGoal("close twitch", { print: () => {}, confirm: async (m) => (asked.push(m), true) });
  expect(asked[0]).toContain("destructive");
  expect(res.status).toBe("done");
  expect(dispatches()).toEqual([["hyprctl", "dispatch", 'hl.dsp.window.close({ window = "address:0xabc" })']]);
});

test("unroutable goals go to the planner without acting", async () => {
  setJev(fakeJev({ action: [/^needs_planner$/, 0.9] }));
  const res = await runGoal("download the latest bun release", { print: () => {} });
  expect(res.status).toBe("needs_planner");
  expect(dispatches()).toEqual([]);
});

test("dry run decides but never dispatches", async () => {
  setJev(fakeJev({ action: [/^workspace\.switch$/, 0.99], workspace: [/^ws7$/, 0.99] }));
  const res = await runGoal("go to workspace 7", { dryRun: true, print: () => {} });
  expect(res).toMatchObject({ status: "dry_run", params: { workspace: 7 } });
  expect(dispatches()).toEqual([]);
});

test("a split between the current workspace and 'unspecified' isn't low confidence", async () => {
  // The fixture's focused monitor shows workspace 1.
  setJev(fakeJev({
    action: [/^browser\.open_url$/, 0.99],
    url: [/mail\.google\.com \(site\)/, 0.99],
    workspace: [/^ws1$/, 0.48, { ws1: 0.54, unspecified: 0.46 }],
  }));
  const asked: string[] = [];
  const res = await runGoal("open gmail", { print: () => {}, confirm: async (m) => (asked.push(m), false) });
  expect(asked).toEqual([]);
  expect(res.status).toBe("done");
});

test("no matching candidate goes to the planner instead of guessing", async () => {
  setJev(fakeJev({ action: [/^app\.launch$/, 0.97], app: [/^no_match$/, 0.8] }));
  const res = await runGoal("open spotify", { print: () => {} });
  expect(res).toMatchObject({ status: "needs_planner" });
  expect(dispatches()).toEqual([]);
});

test("Jev flagging an ask-first category makes a confident action ask", async () => {
  setJev(fakeJev({ action: [/^browser\.open_url$/, 0.99], url: [/amazon\.com \(site\)/, 0.99] }, { purchase: 0.8 }));
  const asked: string[] = [];
  const res = await runGoal("buy the thing on amazon", { print: () => {}, confirm: async (m) => (asked.push(m), false) });
  expect(asked[0]).toContain("purchase (Jev 0.80)");
  expect(res.status).toBe("declined");
});
