// Question → short answer, via the OpenAI Responses API, streamed. No desktop context is sent
// up front; the model can look things up with tools: OpenAI's hosted web search, and
// run_command for anything about this machine (tools.ts). Location goes in the instructions
// and the web search's user_location.
import { hostname } from "node:os";
import type { ConversationLog } from "./conversation.ts";
import type { Confirm } from "./confirm.ts";
import { callTool, describeLocation, location, TOOLS } from "./tools.ts";
import { addToolCall, addUsage } from "./usage.ts";
import type { DesktopOrigin } from "./desktop-session.ts";
import { signal } from "./runtime.ts";

const MAX_TURNS = 8;

export type AnswerIO = {
  onDelta?: (text: string) => void;
  status: (text: string) => void;
  confirm: Confirm;
  log: ConversationLog["event"];
  origin?: DesktopOrigin;
};

export async function answer(question: string, io: AnswerIO): Promise<string> {
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new Error("OPENAI_API_KEY isn't set in ~/dotfiles/.env");

  const loc = await location();
  const now = new Date().toLocaleString("en-US", { dateStyle: "full", timeStyle: "short", timeZone: loc?.timezone });
  const instructions = [
    "You are a quick desktop assistant. Answer in one to four short sentences of plain text. No markdown, no links.",
    "Search the web for anything current or that you aren't sure of: weather, news, scores, prices, hours.",
    "For questions about the user's apps, messages, or screen, call desktop_task with the full question and mode lookup. It can find hidden apps, navigate to the correct conversation/page, read screenshots and return a verified answer. Never tell the user to open an app you can navigate yourself. Prefer this over guessing from titles or searching private app cache files. Reading/navigation is allowed by default; all writes need explicit approval. A declined operation must not be retried another way.",
    "Report the desktop tool's verified findings faithfully. Do not add dates, ages or other details it did not verify. If a task is incomplete, report its partial findings and unchecked items instead of claiming completion.",
    `You are running on the user's own computer (hostname ${hostname()}, Arch Linux, Hyprland). For anything about ` +
       "this machine (specs, disk, memory, GPU, processes, installed software, files) use run_command " +
      "rather than guessing. Prefer read-only commands.",
    `User's approximate location: ${describeLocation(loc)}. It is ${now}.`,
  ].join("\n");
  const tools = [
    { type: "web_search", ...(loc && { user_location: { type: "approximate", ...loc } }) },
    ...TOOLS,
  ];

  let input: unknown = question;
  let previous: string | undefined;
  for (let turn = 0; turn < MAX_TURNS; turn++) {
    const { id, text, calls } = await stream(key, { instructions, tools, input, previous_response_id: previous }, io);
    if (!calls.length) {
      if (!text.trim()) throw new Error("OpenAI returned no text");
      return text.trim();
    }
    const outputs = [];
    for (const call of calls) {
      let output: string;
      try {
        output = await callTool(call.name, call.arguments, io);
      } catch (err) {
        output = `Tool failed: ${err instanceof Error ? err.message : String(err)}`;
      }
      outputs.push({ type: "function_call_output", call_id: call.call_id, output });
    }
    input = outputs;
    previous = id;
  }
  throw new Error(`gave up after ${MAX_TURNS} tool rounds`);
}

type FunctionCall = { call_id: string; name: string; arguments: string };

/** One streamed Responses request: text deltas go to onDelta, function calls come back. */
async function stream(
  key: string,
  req: { instructions: string; tools: unknown[]; input: unknown; previous_response_id?: string },
  io: AnswerIO,
): Promise<{ id: string; text: string; calls: FunctionCall[] }> {
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    signal: AbortSignal.any([signal(), AbortSignal.timeout(120_000)]),
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: process.env.OPENAI_MODEL || "gpt-5.6-luna",
      ...req,
      // Quick answers don't need thinking time; "none" is several seconds faster.
      reasoning: { effort: process.env.OPENAI_REASONING || "none" },
      stream: true,
    }),
  });
  if (!res.ok || !res.body) {
    const body = (await res.json().catch(() => null)) as any;
    throw new Error(`OpenAI ${res.status}: ${body?.error?.message ?? "request failed"}`);
  }

  // Server-sent events: "data: {json}" lines.
  let id = "";
  let text = "";
  const calls: FunctionCall[] = [];
  let buf = "";
  const decoder = new TextDecoder();
  for await (const chunk of res.body) {
    buf += decoder.decode(chunk, { stream: true });
    let nl: number;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line.startsWith("data:")) continue;
      let ev: any;
      try {
        ev = JSON.parse(line.slice(5));
      } catch {
        continue;
      }
      switch (ev.type) {
        case "response.created":
          id = ev.response.id;
          break;
        case "response.output_text.delta":
          text += ev.delta;
          io.onDelta?.(ev.delta);
          break;
        case "response.output_item.added":
          if (ev.item?.type === "web_search_call") io.status("searching the web…");
          break;
        case "response.output_item.done":
          if (ev.item?.type === "function_call") calls.push(ev.item);
          else if (ev.item?.type === "web_search_call") {
            addToolCall("web_search");
            io.log("tool_call", { name: "web_search", query: ev.item.action?.query ?? "" });
          }
          break;
        case "response.completed":
          addUsage(ev.response.model, ev.response.usage);
          break;
        case "error":
        case "response.failed":
          throw new Error(`OpenAI: ${ev.error?.message ?? ev.response?.error?.message ?? "stream failed"}`);
      }
    }
  }
  return { id, text, calls };
}
