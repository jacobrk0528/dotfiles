#!/usr/bin/env bun
// Usage:
//   artoo list                         list actions and their params
//   artoo act <action> [--param value]  run one action by hand
//   artoo [--dry-run] [--step] "<goal>" run a goal via the Jev fast path
//   artoo ui [--dry-run] [--step] [--max-steps N] "<goal>"  click through an app (DOM or OCR) + Jev
//   artoo ask [--json] "<anything>"      do it, or answer it (--json: event stream for the dock)
//   artoo task "<goal>"                   multi-step goal: LLM planner + Jev grounding
//   artoo ledger [--dry-run] ["<which account>"]  copy new bank/card transactions into the checkbook sheet
//   artoo history [--json] [<id>]         past `ask` conversations, or one in detail (id or its number)
import "./env.ts";
import { parseArgs } from "node:util";
import { z } from "zod";
import { actions, getAction } from "./actions.ts";
import { runGoal } from "./agent.ts";
import { ask, type AskEvent } from "./ask.ts";
import { ttyConfirm } from "./confirm.ts";
import { listConversations, readConversation, readRuns, refIndex, resolveRef, summarize } from "./conversation.ts";
import { runTask } from "./planner.ts";
import { openRunLog } from "./runlog.ts";
import { syncLedger } from "./workflows/ledger.ts";
import { runUiTask } from "./uiloop.ts";
import { actionEffect, authorize } from "./policy.ts";
import { captureOrigin, parseOrigin, withDesktopSession } from "./desktop-session.ts";
import { doctor } from "./doctor.ts";
import { installCancellation, signal } from "./runtime.ts";

function usage(): never {
  console.error(`usage:
  artoo list
  artoo act <action> [--param value ...]
  artoo [--dry-run] [--step] "<goal>"
  artoo ui [--dry-run] [--step] [--max-steps N] "<goal>"
  artoo ask [--json] "<anything>"
  artoo task "<goal>"
  artoo doctor
  artoo context [--monitor <name>]
  artoo ledger [--dry-run] ["<which account>"]
  artoo history [--json] [<id>]`);
  process.exit(2);
}

function printActions() {
  for (const a of actions) {
    const shape = a.params.shape as Record<string, z.ZodType>;
    const params = Object.entries(shape)
      .map(([k, v]) => (v.safeParse(undefined).success ? `[--${k}]` : `--${k}`))
      .join(" ");
    const risk = a.risk.length ? `  ⚠ ${a.risk.join(",")}` : "";
    console.log(`${a.name.padEnd(26)} ${params}\n${"".padEnd(26)} ${a.description}${risk}`);
  }
}

async function act(name: string | undefined, rest: string[]) {
  if (!name) usage();
  const action = getAction(name);
  if (!action) {
    console.error(`unknown action "${name}". Try: artoo list`);
    process.exit(2);
  }
  // Every param is read as a string; the zod schema does the coercion.
  const options = Object.fromEntries(Object.keys(action.params.shape).map((k) => [k, { type: "string" as const }]));
  const { values } = parseArgs({ args: rest, options, strict: true });
  const params = action.params.safeParse(values);
  if (!params.success) {
    console.error(z.prettifyError(params.error));
    process.exit(2);
  }
  if (!(await authorize({ summary: `${name} ${JSON.stringify(params.data)}`, effect: actionEffect(name) }, { confirm: ttyConfirm }))) throw new Error("Operation was not approved.");
  const result = await withDesktopSession(() => action.run(params.data));
  if (result !== undefined) console.log(typeof result === "string" ? result : JSON.stringify(result, null, 2));
}

// --json protocol: one JSON event per stdout line. A {"type":"confirm"} event is answered
// with a "y" or "n" line on stdin.
let stdinReader: ReadableStreamDefaultReader<Uint8Array> | null = null;
let stdinBuf = "";
async function readLine(): Promise<string | null> {
  stdinReader ??= Bun.stdin.stream().getReader();
  const decoder = new TextDecoder();
  while (!stdinBuf.includes("\n")) {
    const s = signal();
    s.throwIfAborted();
    const abort = () => { void stdinReader?.cancel(); };
    s.addEventListener("abort", abort, { once: true });
    const { value, done } = await stdinReader.read().finally(() => s.removeEventListener("abort", abort));
    s.throwIfAborted();
    if (done) return null;
    stdinBuf += decoder.decode(value);
  }
  const i = stdinBuf.indexOf("\n");
  const line = stdinBuf.slice(0, i);
  stdinBuf = stdinBuf.slice(i + 1);
  return line;
}

async function askCommand(rest: string[]) {
  const { values, positionals } = parseArgs({ args: rest, options: { json: { type: "boolean" }, origin: { type: "string" } }, allowPositionals: true });
  const origin = values.origin ? parseOrigin(values.origin) : undefined;
  const text = positionals.join(" ").trim();
  if (!text) usage();
  if (values.json) {
    const emit = (e: AskEvent) => console.log(JSON.stringify(e));
    try {
      await ask(text, {
        emit,
        origin,
        confirm: async (message) => {
          emit({ type: "confirm", message: message.trim() });
          return /^y(es)?$/i.test((await readLine())?.trim() ?? "");
        },
      });
    } catch (err) {
      emit({ type: "error", text: err instanceof Error ? err.message : String(err) });
      process.exit(1);
    }
    process.exit(0);
  }
  await ask(text, {
    origin,
    emit: (e) => {
      if (e.type === "status" || e.type === "answer" || e.type === "done") console.log(e.text);
      else if (e.type === "error") console.error(e.text);
    },
    confirm: ttyConfirm,
  });
}

// Long strings (desktop snapshots in run logs) are cut so the viewer stays light.
const clip = (v: unknown): unknown =>
  typeof v === "string" ? (v.length > 1500 ? v.slice(0, 1500) + "…" : v)
  : Array.isArray(v) ? v.map(clip)
  : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, clip(x)]))
  : v;

function historyCommand(rest: string[]) {
  const { values, positionals } = parseArgs({ args: rest, options: { json: { type: "boolean" } }, allowPositionals: true });
  const wanted = positionals[0];
  if (!wanted) {
    const list = listConversations();
    if (values.json) return console.log(JSON.stringify(list));
    for (const c of list) {
      const cost = c.cost == null ? "" : ` $${c.cost.toFixed(4)}`;
      console.log(`${`!${c.ref}`.padEnd(5)} ${c.id}  ${c.status.padEnd(10)} ${((c.ms ?? 0) / 1000).toFixed(1)}s${cost}  ${c.input}`);
    }
    return;
  }
  // "12" or "!12" is a conversation's number; anything else is its full id.
  const number = /^!?(\d+)$/.exec(wanted);
  const id = number ? resolveRef(Number(number[1])) : wanted;
  if (!id) throw new Error(`no conversation !${number![1]}`);
  const events = readConversation(id);
  const runs = readRuns(events).map((r) => ({ dir: r.dir, events: clip(r.events) }));
  const detail = { ...summarize(id, events, refIndex().get(id)), events: clip(events), runs };
  console.log(values.json ? JSON.stringify(detail) : JSON.stringify(detail, null, 2));
}

const [cmd, ...rest] = Bun.argv.slice(2);
installCancellation();
try {
  if (!cmd) usage();
  else if (cmd === "context") {
    const { values } = parseArgs({ args: rest, options: { monitor: { type: "string" } } });
    console.log(JSON.stringify(await captureOrigin(values.monitor)));
  }
  else if (cmd === "doctor") {
    const checks = await doctor();
    console.log(JSON.stringify(checks, null, 2));
    if (checks.some((c) => !c.ok)) process.exitCode = 1;
  }
  else if (cmd === "list") printActions();
  else if (cmd === "act") await act(rest[0], rest.slice(1));
  else if (cmd === "ask") await askCommand(rest);
  else if (cmd === "history") historyCommand(rest);
  else if (cmd === "ledger") {
    const { values, positionals } = parseArgs({ args: rest, options: { "dry-run": { type: "boolean" } }, allowPositionals: true });
    const request = positionals.join(" ").trim() || "Add the new transactions to the ledger tab in view.";
    const res = await syncLedger(request, { confirm: ttyConfirm, print: console.log, log: openRunLog(request), dryRun: values["dry-run"] });
    console.log(res ? `${res.status}: ${res.message}` : "No spreadsheet and bank page are open to work with.");
  }
  else if (cmd === "task") {
    const goal = rest.join(" ").trim();
    if (!goal) usage();
    const res = await runTask(goal);
    console.log(`${res.status}: ${res.message}`);
  }
  else if (cmd === "ui") {
    const { values, positionals } = parseArgs({
      args: rest,
      options: { "dry-run": { type: "boolean" }, step: { type: "boolean" }, "max-steps": { type: "string" } },
      allowPositionals: true,
    });
    const goal = positionals.join(" ").trim();
    if (!goal) usage();
    const res = await withDesktopSession(() => runUiTask(goal, {
      dryRun: values["dry-run"],
      step: values.step,
      maxSteps: values["max-steps"] ? Number(values["max-steps"]) : undefined,
    }));
    console.log(`${res.status} after ${res.steps.length} step(s)${res.steps.length ? ": " + res.steps.join(" → ") : ""}`);
  }
  else {
    const { values, positionals } = parseArgs({
      args: [cmd, ...rest],
      options: { "dry-run": { type: "boolean" }, step: { type: "boolean" } },
      allowPositionals: true,
    });
    const goal = positionals.join(" ").trim();
    if (!goal) usage();
    const result = values["dry-run"]
      ? await runGoal(goal, { dryRun: true, step: values.step })
      : await withDesktopSession(() => runGoal(goal, { step: values.step }));
    if ("reason" in result) {
      console.error(`${result.status}: ${result.reason}`);
      process.exit(result.status === "declined" ? 0 : 1);
    }
  }
} catch (err) {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
}
