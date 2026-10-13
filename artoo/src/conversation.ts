// One log per `artoo ask`: conversations/<id>.jsonl. It holds the input, every step shown
// to the user, tool calls, links to the detailed runs/<ts>/ logs the request produced, and a
// final "end" line with the output, duration, and usage. `artoo history` reads these.
//
// Every conversation also has a short number (its "ref"), shown in the history panel as !12
// and usable in a later request ("do what you did in !12 again"; see reference.ts). Refs are
// files: conversations/refs/<n> holds the conversation id. Creating that file exclusively
// is what claims the number, so two prompts running at once can't take the same one.
import { appendFileSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dataDir } from "./paths.ts";
import { redactDeep } from "./privacy.ts";
import { onRunLog } from "./runlog.ts";
import { usageSummary } from "./usage.ts";

export const conversationsDir = () => process.env.JEV_PILOT_CONVERSATIONS ?? join(dataDir(), "conversations");

const refsDir = () => join(conversationsDir(), "refs");

function conversationIds(): string[] {
  try {
    return readdirSync(conversationsDir()).filter((f) => f.endsWith(".jsonl")).map((f) => f.slice(0, -".jsonl".length)).sort();
  } catch {
    return [];
  }
}

function claimRef(id: string, taken: Map<number, string>): number {
  mkdirSync(refsDir(), { recursive: true });
  let n = Math.max(0, ...taken.keys()) + 1;
  for (;;) {
    try {
      writeFileSync(join(refsDir(), String(n)), id, { flag: "wx" });
      taken.set(n, id);
      return n;
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "EEXIST") throw err;
      n++;
    }
  }
}

/** ref -> conversation id, as claimed on disk. */
function claimedRefs(): Map<number, string> {
  const taken = new Map<number, string>();
  let names: string[];
  try {
    names = readdirSync(refsDir());
  } catch {
    return taken;
  }
  for (const name of names) {
    if (!/^\d+$/.test(name)) continue;
    try {
      const id = readFileSync(join(refsDir(), name), "utf8").trim();
      if (id) taken.set(Number(name), id);
    } catch {}
  }
  return taken;
}

/** Conversation id -> ref. Conversations from before refs existed get theirs here, oldest first. */
export function refIndex(): Map<string, number> {
  const taken = claimedRefs();
  const byId = new Map<string, number>();
  // Highest first, so if a conversation ever ends up with two numbers the lowest one is shown.
  for (const [n, id] of [...taken].sort((a, b) => b[0] - a[0])) byId.set(id, n);
  for (const id of conversationIds()) if (!byId.has(id)) byId.set(id, claimRef(id, taken));
  return byId;
}

/** The conversation id behind !n, or undefined. */
export function resolveRef(n: number): string | undefined {
  for (const [id, ref] of refIndex()) if (ref === n) return id;
  return undefined;
}

export type ConversationLog = {
  id: string;
  ref: number;
  event: (type: string, data?: Record<string, unknown>) => void;
  end: (status: "answer" | "done" | "error" | "cancelled", output: string) => void;
};

export function openConversation(input: string): ConversationLog {
  mkdirSync(conversationsDir(), { recursive: true });
  const started = Date.now();
  const id = new Date(started).toISOString().replaceAll(":", "-");
  const file = join(conversationsDir(), `${id}.jsonl`);
  // Number the older conversations first so refs stay in the order things happened.
  refIndex();
  const ref = claimRef(id, claimedRefs());
  const event: ConversationLog["event"] = (type, data = {}) =>
    appendFileSync(file, JSON.stringify(redactDeep({ t: Date.now(), type, ...data })) + "\n");
  event("start", { input });
  onRunLog((dir) => event("run_log", { dir }));
  let ended = false;
  return {
    id,
    ref,
    event,
    end: (status, output) => {
      if (ended) return;
      ended = true;
      event("end", { status, output, ms: Date.now() - started, usage: usageSummary() });
    },
  };
}

export type Event = { t: number; type: string; [k: string]: unknown };

export type ConversationSummary = {
  id: string;
  /** Short number for !<ref> references. */
  ref?: number;
  started: number;
  input: string;
  route?: string;
  status: string;
  output: string;
  ms?: number;
  cost?: number | null;
  tokens: number;
  toolCalls: number;
};

export function readConversation(id: string): Event[] {
  // ids are file names; refuse anything that could walk out of the directory.
  if (!/^[\w.-]+$/.test(id)) throw new Error(`bad conversation id: ${id}`);
  return readFileSync(join(conversationsDir(), `${id}.jsonl`), "utf8")
    .split("\n")
    .filter(Boolean)
    .flatMap((l) => {
      try {
        return [JSON.parse(l) as Event];
      } catch {
        return [];
      }
    });
}

/** The detailed runs/<ts>/events.jsonl logs a conversation's desktop tasks produced. */
export function readRuns(events: Event[]): { dir: string; events: Event[] }[] {
  return events
    .filter((e) => e.type === "run_log")
    .map((e) => {
      const dir = String(e.dir);
      let runEvents: Event[] = [];
      try {
        runEvents = readFileSync(join(dir, "events.jsonl"), "utf8").split("\n").filter(Boolean).flatMap((l) => {
          try {
            return [JSON.parse(l) as Event];
          } catch {
            return [];
          }
        });
      } catch {}
      return { dir, events: runEvents };
    });
}

export function summarize(id: string, events: Event[], ref?: number): ConversationSummary {
  const start = events.find((e) => e.type === "start");
  const end = events.find((e) => e.type === "end") as any;
  const route = events.find((e) => e.type === "route") as any;
  const usage = end?.usage as ReturnType<typeof usageSummary> | undefined;
  return {
    id,
    ref,
    started: start?.t ?? 0,
    input: String(start?.input ?? ""),
    route: route?.route,
    // No end line: still running, or the process died.
    status: end?.status ?? "unfinished",
    output: String(end?.output ?? ""),
    ms: end?.ms,
    cost: usage?.cost,
    tokens: usage?.models.reduce((n, m) => n + m.input + m.output, 0) ?? 0,
    toolCalls: events.filter((e) => e.type === "tool_call").length,
  };
}

/** Newest first. */
export function listConversations(limit = 100): ConversationSummary[] {
  const refs = refIndex();
  return conversationIds()
    .reverse()
    .slice(0, limit)
    .map((id) => summarize(id, readConversation(id), refs.get(id)));
}
