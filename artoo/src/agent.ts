// Goal → action. M2 is the Jev fast path: one action picked from the registry, params picked
// from closed candidate lists. Anything else is reported as needing the planner (M4).
import type { z } from "zod";
import { actions, type Action } from "./actions.ts";
import { ttyConfirm, type Confirm } from "./confirm.ts";
import { check, describeHits } from "./guard.ts";
import { pickMany, type Options, type Picked } from "./jev.ts";
import { describe, snapshot } from "./perceive/desktop.ts";
import { openRunLog } from "./runlog.ts";
import { actionEffect, authorize } from "./policy.ts";

export const CONFIDENCE_THRESHOLD = 0.75;
const NEEDS_PLANNER = "needs_planner";
const UNSPECIFIED = "unspecified";
const NO_MATCH = "no_match";
const NO_MATCH_VALUE = "\u0000no_match";

const isOptional = (schema: z.ZodType) => schema.safeParse(undefined).success;

export function fastPathActions(): Action[] {
  return actions.filter((a) => {
    if (!a.pickers) return false;
    const shape = a.params.shape as Record<string, z.ZodType>;
    return Object.entries(shape).every(([k, v]) => isOptional(v) || k in a.pickers!);
  });
}

export type GoalResult =
  | { status: "done" | "dry_run"; action: string; params: Record<string, unknown> }
  | { status: "needs_planner" | "declined" | "failed"; reason: string };

export async function runGoal(
  goal: string,
  opts: { dryRun?: boolean; step?: boolean; confirm?: Confirm; print?: (s: string) => void } = {},
): Promise<GoalResult> {
  const print = opts.print ?? console.log;
  const confirm = opts.confirm ?? ttyConfirm;
  const log = openRunLog(goal);

  const desktop = await snapshot();
  const state = { goal, desktop: describe(desktop) };
  log.event("state", state);

  // 1. Which action?
  const eligible = fastPathActions();
  const actionOptions: Options<Action | null> = Object.fromEntries(
    eligible.map((a) => [a.name, { description: a.description, value: a }]),
  );
  actionOptions[NEEDS_PLANNER] = {
    description: "None of these alone: needs several steps, searching for something, typing free text, clicking inside an app, or something else",
    value: null,
  };
  const first = await pickMany(state, {
    action: { question: "Which single action fully accomplishes the goal?", options: actionOptions },
  });
  const actionPick = first.picks.action as Picked<Action | null>;
  log.event("pick_action", { model: first.model, ...summarize(actionPick) });

  const action = actionPick.value;
  if (!action) {
    const reason = `Jev routed this to the planner (${fmt(actionPick.confidence)}); multi-step goals land in M4`;
    log.event("result", { status: "needs_planner" });
    return { status: "needs_planner", reason };
  }

  // 2. Fill every picker-backed param in one parallel request.
  const shape = action.params.shape as Record<string, z.ZodType>;
  const questions = Object.fromEntries(
    Object.entries(action.pickers ?? {}).map(([param, picker]) => {
      const options = picker!.options(desktop);
      if (isOptional(shape[param]!)) {
        options[UNSPECIFIED] = { description: "The goal doesn't mention this at all (use the default)", value: undefined };
      }
      options[NO_MATCH] = { description: "None of these match what the goal asks for", value: NO_MATCH_VALUE };
      return [param, { question: picker!.question, options }];
    }),
  );
  const paramPicks: Record<string, Picked> = {};
  if (Object.keys(questions).length) {
    const res = await pickMany({ ...state, action: `${action.name}: ${action.description}` }, questions);
    for (const [k, p] of Object.entries(res.picks)) {
      // Options that resolve to the same thing (e.g. "unspecified" and the current workspace)
      // aren't competing, so confidence is their combined probability.
      const resolve = action.pickers?.[k]?.resolve ?? ((v: unknown) => v);
      const same = (v: unknown) => JSON.stringify(resolve(v, desktop)) === JSON.stringify(resolve(p.value, desktop));
      const opts = questions[k]!.options;
      const agreed = Object.entries(p.probabilities).reduce((sum, [key, prob]) => (same(opts[key]?.value) ? sum + prob : sum), 0);
      paramPicks[k] = { ...p, confidence: Math.max(p.confidence, Math.min(1, agreed)) };
      log.event("pick_param", { param: k, value: p.value, agreed, ...summarize(p) });
    }
  }
  const unmatched = Object.entries(paramPicks).filter(([, p]) => p.value === NO_MATCH_VALUE).map(([k]) => k);
  if (unmatched.length) {
    log.event("result", { status: "needs_planner", unmatched });
    return { status: "needs_planner", reason: `no candidate matches for ${unmatched.join(", ")} (${action.name})` };
  }
  const raw = Object.fromEntries(
    Object.entries(paramPicks).filter(([, p]) => p.value !== undefined).map(([k, p]) => [k, p.value]),
  );
  const parsed = action.params.safeParse(raw);
  if (!parsed.success) {
    log.event("result", { status: "failed", error: parsed.error.message });
    return { status: "failed", reason: `picked params don't validate: ${parsed.error.message}` };
  }
  const params = parsed.data as Record<string, unknown>;

  // 3. Show the decision, then gate it.
  const confidences = [`action ${fmt(actionPick.confidence)}`, ...Object.entries(paramPicks).map(([k, p]) => `${k} ${fmt(p.confidence)}`)];
  // Show what Jev picked in words (e.g. the window's description), not raw values like addresses.
  const shown = Object.entries(params).map(([k, v]) => {
    const pick = paramPicks[k];
    const desc = pick && pick.key !== UNSPECIFIED ? questions[k]?.options[pick.key]?.description : undefined;
    return desc ? `${k}: ${desc}` : `${k}=${v}`;
  });
  print(`→ ${action.name}${shown.length ? "  " + shown.join(" · ") : ""}`);
  print(`  confidence: ${confidences.join(", ")}`);

  if (opts.dryRun) {
    log.event("result", { status: "dry_run", action: action.name, params });
    return { status: "dry_run", action: action.name, params };
  }

  const reasons: string[] = [];
  const low = [actionPick, ...Object.values(paramPicks)].some((p) => p.confidence < CONFIDENCE_THRESHOLD);
  if (low) reasons.push("low confidence");
  const summary = `${action.name} ${Object.entries(params).map(([k, v]) => `${k}=${v}`).join(" ")}`;
  const hits = await check({ summary, risk: action.risk, url: typeof params.url === "string" ? params.url : undefined });
  if (hits.length) {
    log.event("guard", { hits });
    reasons.push(`ask first: ${describeHits(hits)}`);
  }
  if (opts.step) reasons.push("step mode");
  if (reasons.length && !(await confirm(`Run it? (${reasons.join("; ")})`))) {
    log.event("result", { status: "declined", reasons });
    return { status: "declined", reason: reasons.join("; ") };
  }

  if (!reasons.length && !(await authorize({ summary, effect: actionEffect(action.name) }, { confirm, log: log.event }))) {
    log.event("result", { status: "declined" });
    return { status: "declined", reason: "operation not approved" };
  }

  await action.run(params);
  log.event("result", { status: "done", action: action.name, params });
  return { status: "done", action: action.name, params };
}

const fmt = (c: number) => c.toFixed(2);

function summarize(p: Picked) {
  const top = Object.entries(p.probabilities)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3);
  return { key: p.key, confidence: p.confidence, top };
}
