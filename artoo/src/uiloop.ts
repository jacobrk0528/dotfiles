// UI loop: perceive → Jev picks the next click (or done/stuck) → act → repeat.
// Perception comes from a "surface": the live DOM over CDP for Brave windows, OCR otherwise.
// No LLM: this tests how far Jev alone gets on click-only tasks inside an app.
import { ttyConfirm, type Confirm } from "./confirm.ts";
import { pickOne, type Options } from "./jev.ts";
import { openRunLog } from "./runlog.ts";
import { openSurface, siteGate, type UiTarget } from "./surface.ts";
import { observeSurface } from "./surface.ts";
import { runStep } from "./planner.ts";
import { sleep } from "./runtime.ts";

const SETTLE_MS = 1500;
const MAX_TARGETS = 200;
/** Below this, Jev is guessing; ask before acting. */
const ASK_BELOW = 0.4;

/** Values Jev may type: numbers and quoted text taken from the goal. Free-form text needs the planner. */
export function goalLiterals(goal: string): string[] {
  const quoted = [...goal.matchAll(/["“']([^"”']+)["”']/g)].map((m) => m[1]!);
  const numbers = goal.match(/\b\d+(?:\.\d+)?\b/g) ?? [];
  return [...new Set([...quoted, ...numbers])];
}

type Step =
  | { kind: "click"; t: UiTarget }
  | { kind: "type"; t: UiTarget; text: string }
  | { kind: "scroll"; amount: number }
  | { kind: "escape" }
  | { kind: "done" }
  | { kind: "stuck" };

export type UiResult = { status: "done" | "stuck" | "declined" | "max_steps" | "dry_run"; steps: string[] };

export async function runUiTask(
  goal: string,
  opts: { maxSteps?: number; step?: boolean; dryRun?: boolean; confirm?: Confirm; print?: (s: string) => void } = {},
): Promise<UiResult> {
  const print = opts.print ?? console.log;
  const confirm = opts.confirm ?? ttyConfirm;
  const maxSteps = opts.maxSteps ?? 12;
  const log = openRunLog(goal);
  const history: string[] = [];
  const literals = goalLiterals(goal);

  const opened = await openSurface(goal, { confirm, print, log });
  if (!opened) {
    log.event("result", { status: "declined", reason: "never_look app" });
    return { status: "declined", steps: [] };
  }
  const { surface } = opened;
  const siteOk = siteGate(confirm);

  try {
    for (let i = 1; i <= maxSteps; i++) {
      const observation = await observeSurface(surface, i);
      const found = observation.targets.slice(0, MAX_TARGETS);
      // Perceiving is local; stop here, before anything is sent, if this is a never_look site.
      const { raw_url: rawUrl, ...context } = await surface.context();
      if (!(await siteOk(rawUrl))) {
        log.event("result", { status: "declined", reason: "never_look site", history });
        return { status: "declined", steps: history };
      }
      const options: Options<Step> = {};
      found.forEach((t, n) => {
        // Clicking a text field on its own rarely finishes anything, and Jev over-picks it
        // when a "type X into it" option exists. Offer only the typing options then.
        const typing = t.typeable && surface.type && literals.length > 0;
        if (!typing) options[`e${n + 1}`] = { description: `Click ${t.description}`, value: { kind: "click", t } };
        if (typing) {
          literals.forEach((text, m) => {
            options[`e${n + 1}_t${m + 1}`] = { description: `Type "${text}" into ${t.description}`, value: { kind: "type", t, text } };
          });
        }
      });
      if (surface.escape) options.escape = { description: "Press Escape to close the open menu or dialog", value: { kind: "escape" } };
      options.scroll_down = { description: "Scroll down to reveal more", value: { kind: "scroll", amount: 5 } };
      options.scroll_up = { description: "Scroll up to reveal more", value: { kind: "scroll", amount: -5 } };
      options.done = { description: "The goal is fully accomplished; nothing left to do", value: { kind: "done" } };
      options.stuck = { description: "Nothing visible helps make progress on the goal", value: { kind: "stuck" } };
      // Jev takes at most 255 options; drop the lowest-priority plain clicks (the list is priority-sorted).
      const over = Object.keys(options).length - 255;
      if (over > 0) for (const k of Object.keys(options).filter((k) => /^e\d+$/.test(k)).slice(-over)) delete options[k];

      const state = { goal, ...context, steps_taken: history.length ? history : ["none yet"] };
      const pick = await pickOne(state, "What is the single next thing to do to make progress on the goal?", options);
      const step = pick.value as Step;
      const top = Object.entries(pick.probabilities)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 4)
        .map(([k, p]) => `${options[k]?.description ?? k} ${p.toFixed(2)}`);
      log.event("ui_pick", { step: i, key: pick.key, confidence: pick.confidence, top, targets: found.length });

      const label =
        step.kind === "click"
          ? `click ${step.t.description}`
          : step.kind === "type"
            ? `type "${step.text}" into ${step.t.description}`
            : step.kind === "scroll"
              ? `scroll ${step.amount > 0 ? "down" : "up"}`
              : step.kind;
      print(`step ${i}: ${label}  [${pick.confidence.toFixed(2)}]  (${found.length} targets)`);
      print(`         next best: ${top.slice(1).join(" · ")}`);

      if (opts.dryRun) return { status: "dry_run", steps: [label] };
      if (step.kind === "done" || step.kind === "stuck") {
        log.event("result", { status: step.kind, history });
        return { status: step.kind, steps: history };
      }
      if (history.filter((h) => h === label).length >= 2) {
        print("same action a third time; calling it stuck");
        return { status: "stuck", steps: history };
      }
      const why = [
        opts.step && "step mode",
        pick.confidence < ASK_BELOW && "low confidence",
      ].filter(Boolean);
      if (why.length && !(await confirm(`  do it? (${why.join("; ")})`))) {
        log.event("result", { status: "declined", history });
        return { status: "declined", steps: history };
      }

      const result = await runStep(surface, {
        action: step.kind === "escape" ? "key" : step.kind,
        target: step.kind === "click" || step.kind === "type" ? `e${found.indexOf(step.t) + 1}` : null,
        text: step.kind === "type" ? step.text : null,
        key: step.kind === "escape" ? "escape" : null,
        direction: step.kind === "scroll" ? (step.amount > 0 ? "down" : "up") : null,
        x: null, y: null, purpose: goal,
      }, observation, { confirm, print, log });
      if (result === null) return { status: "declined", steps: history };
      if (result.startsWith("failed")) { history.push(result); continue; }
      history.push(label);
      await sleep(SETTLE_MS);
    }
    return { status: "max_steps", steps: history };
  } finally {
    surface.close();
  }
}
