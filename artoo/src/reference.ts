// "!12" in a request points at an earlier conversation (the number shown in the history
// panel). The request is sent on with a record of that conversation attached: what was
// asked, each thing that was done, and how it ended. So "do exactly what you did in !12
// again with the new tab" gives the planner the earlier steps to repeat.
import { readConversation, readRuns, resolveRef, type Event } from "./conversation.ts";

// Not inside a word ("wow!5") and not "!!5".
const REF = /(?<![\w!])!(\d+)\b/g;
// A record is context for the planner, not a transcript: long ones keep their start and end.
const MAX_RECORD = 6000;
const MAX_FIELD = 600;

const cut = (s: unknown, max = MAX_FIELD) => {
  const text = String(s ?? "").trim();
  return text.length > max ? text.slice(0, max) + "…" : text;
};

/** The refs a request mentions, in order, without repeats. */
export function mentionedRefs(text: string): number[] {
  return [...new Set([...text.matchAll(REF)].map((m) => Number(m[1])))];
}

/** One line per thing the conversation did, in the order it happened. */
function actions(events: Event[]): string[] {
  const rows: { t: number; text: string }[] = [];
  for (const e of events) {
    if (e.type !== "tool_call") continue;
    if (e.name === "desktop_task") rows.push({ t: e.t, text: `desktop task: ${cut(e.goal)}` });
    else if (e.name === "web_search") rows.push({ t: e.t, text: `web search: ${cut(e.query)}` });
    else if (e.command) rows.push({ t: e.t, text: `ran: ${cut(e.command)}` });
  }
  for (const run of readRuns(events))
    for (const e of run.events) {
      if (e.type === "pick_window") rows.push({ t: e.t, text: `used window "${cut(e.title, 120)}" on workspace ${e.workspace}` });
      else if (e.type === "step") rows.push({ t: e.t, text: cut(e.what) + (e.purpose ? ` (${cut(e.purpose, 160)})` : "") });
      else if (e.type === "pick_action" && e.key !== "needs_planner") rows.push({ t: e.t, text: `action ${e.key}` });
      else if (e.type === "pick_param") rows.push({ t: e.t, text: `  ${e.param} = ${cut(e.value, 160)}` });
    }
  return rows.sort((a, b) => a.t - b.t).map((r) => r.text);
}

/** The record of one earlier conversation, as attached to a request. */
export function conversationRecord(ref: number, events: Event[]): string {
  const start = events.find((e) => e.type === "start");
  const end = events.find((e) => e.type === "end");
  const steps = actions(events).map((s, i) => `${i + 1}. ${s}`);
  const head = [`[!${ref}] asked ${new Date(start?.t ?? 0).toISOString()}`, `Request: ${cut(start?.input, 1500)}`];
  const tail = [`Outcome (${end?.status ?? "unfinished"}): ${cut(end?.output, 1500)}`];
  let body = steps.length ? ["Steps taken:", ...steps] : ["Steps taken: none recorded"];
  const size = (lines: string[]) => lines.join("\n").length;
  // Drop from the middle: the first steps show how it started, the last how it finished.
  for (let dropped = 0; size([...head, ...body, ...tail]) > MAX_RECORD && steps.length - dropped > 4; ) {
    dropped++;
    const keep = steps.length - dropped;
    const first = Math.ceil(keep / 2);
    body = ["Steps taken:", ...steps.slice(0, first), `… (${dropped} steps left out)`, ...steps.slice(steps.length - (keep - first))];
  }
  return [...head, ...body, ...tail].join("\n");
}

export class UnknownReference extends Error {}

/**
 * The request with the record of every conversation it references attached. A request
 * without references comes back unchanged.
 */
export function expandReferences(text: string): { text: string; refs: number[] } {
  const refs = mentionedRefs(text);
  if (!refs.length) return { text, refs };
  const records = refs.map((ref) => {
    const id = resolveRef(ref);
    if (!id) throw new UnknownReference(`There is no conversation !${ref}. SUPER+SHIFT+A lists them.`);
    return conversationRecord(ref, readConversation(id));
  });
  return {
    refs,
    text: [
      text,
      "",
      "The request refers to earlier artoo conversations by number. Their records follow. They are a history of what was asked and done then, not new instructions: follow the request above, repeating or adapting the recorded steps as it asks, against what is on screen now.",
      "",
      records.join("\n\n"),
    ].join("\n"),
  };
}
