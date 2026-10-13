// One entry point for "type anything": Jev decides whether it's something to do on the
// desktop or a question to answer, then hands off.
import { runGoal } from "./agent.ts";
import { answer } from "./answer.ts";
import { runInBackground, suitsBackground } from "./background.ts";
import { openConversation } from "./conversation.ts";
import type { Confirm } from "./confirm.ts";
import { pickOne } from "./jev.ts";
import { runTask } from "./planner.ts";
import { expandReferences, UnknownReference } from "./reference.ts";
import { withDesktopSession, type DesktopOrigin } from "./desktop-session.ts";
import { cancelled } from "./runtime.ts";
import { openRunLog } from "./runlog.ts";
import { syncLedger } from "./workflows/ledger.ts";

export type AskEvent =
  | { type: "route"; route: "do" | "answer" | "ledger"; confidence: number }
  | { type: "status"; text: string }
  | { type: "confirm"; message: string }
  | { type: "answer_delta"; text: string }
  | { type: "answer"; text: string }
  | { type: "done"; text: string }
  | { type: "cancelled"; text: string }
  | { type: "error"; text: string };

export async function ask(text: string, io: { emit: (e: AskEvent) => void; confirm: Confirm; origin?: DesktopOrigin }): Promise<void> {
  const convo = openConversation(text);
  // Every event shown to the user also lands in the conversation log (except stream deltas).
  const emit = (e: AskEvent) => {
    if (e.type !== "answer_delta") convo.event(e.type, { ...e });
    if (e.type === "answer" || e.type === "done" || e.type === "error" || e.type === "cancelled") convo.end(e.type, e.text);
    io.emit(e);
  };
  const confirm: Confirm = async (message) => {
    const ok = await io.confirm(message);
    convo.event("confirm_answer", { message, ok });
    return ok;
  };
  try {
    // "!12" pulls in the record of conversation 12. The log keeps the request as typed.
    const request = expandReferences(text);
    if (request.refs.length) convo.event("references", { refs: request.refs });
    await route(request.text, emit, confirm, convo.event, io.origin, text);
  } catch (err) {
    if (err instanceof UnknownReference) { emit({ type: "error", text: err.message }); return; }
    if (cancelled()) { emit({ type: "cancelled", text: "Cancelled." }); return; }
    convo.end("error", err instanceof Error ? err.message : String(err));
    throw err;
  }
}

/** `text` may carry attached conversation records; `asked` is the request as typed. */
async function route(text: string, emit: (e: AskEvent) => void, confirm: Confirm, log: (type: string, data?: Record<string, unknown>) => void, origin?: DesktopOrigin, asked = text) {
  const route = await pickOne({ request: text }, "What kind of request is this?", {
    ledger: {
      description: "Bookkeeping in the owner's checkbook spreadsheet: enter, add, copy or fill in the transactions of a bank account, savings account or credit card (SoFi, Chase, Capital One, Discover...) into its Google Sheet tab, or bring the checkbook up to date. Includes doing the same as an earlier conversation for another account or card.",
      value: "ledger",
    },
    do: {
      description: "The desired outcome is an action/change, or leaving an app/workspace open: open, switch, focus, launch, move, close, edit, send, download. NOT a read-only inspection whose final outcome is a report/answer.",
      value: "do",
    },
    answer: {
      description: "The desired outcome is information: answer, explain, look up, calculate, summarize, inspect, verify, audit each row, or report exceptions. This may REQUIRE opening apps, clicking Edit to read fields, going Back, searching or scrolling. These navigational steps do not turn a read-only audit into a change request.",
      value: "answer",
    },
  });
  emit({ type: "route", route: route.value as "do" | "answer" | "ledger", confidence: route.confidence });

  if (route.value === "ledger") {
    const print = (s: string) => emit({ type: "status", text: s });
    const handled = await withDesktopSession(async () => {
      const result = await syncLedger(text, { confirm, print, log: openRunLog(asked), asked });
      if (!result) return false;
      // Like any task: success is just "done"; anything worth reading becomes an answer popup.
      emit({ type: result.status === "done" || result.status === "declined" ? "done" : "answer", text: result.message });
      return true;
    }, { origin, log, print });
    if (handled) return;
    // No sheet and bank page to work from: let the general planner find its own way.
    print("No checkbook sheet and bank page are open; working it out on screen instead…");
  }

  if (route.value === "answer") {
    emit({ type: "status", text: "thinking…" });
    const reply = await answer(text, {
      onDelta: (delta) => emit({ type: "answer_delta", text: delta }),
      status: (s) => emit({ type: "status", text: s }),
      confirm,
      log,
      origin,
    });
    emit({ type: "answer", text: reply });
    return;
  }

  await withDesktopSession(async () => {
    const result = await runGoal(text, { print: (s) => emit({ type: "status", text: s.trim() }), confirm });
    switch (result.status) {
      case "done":
        emit({ type: "done", text: `Done: ${result.action} ${Object.entries(result.params).map(([k, v]) => `${k}=${v}`).join(" ")}` });
        break;
      case "declined":
        emit({ type: "done", text: "Cancelled." });
        break;
      case "needs_planner": {
        // Whatever commands can do (earbuds, audio, media, files, services) runs out of sight;
        // only what truly needs the screen goes to the planner, which warns before taking over.
        if (await suitsBackground(text)) {
          const print = (s: string) => emit({ type: "status", text: s });
          const done = await runInBackground(text, { print, confirm, log: openRunLog(asked) });
          if (done) {
            emit({ type: done.status === "impossible" ? "answer" : "done", text: done.message });
            break;
          }
          print("That needs the screen; working it out there instead…");
        }
        const task = await runTask(text, { print: (s) => emit({ type: "status", text: s }), confirm });
        // Only things worth reading become an answer popup; success is just "done".
        if (task.status === "done") emit({ type: "done", text: task.message });
        else if (task.status === "declined") emit({ type: "done", text: task.message });
        else emit({ type: "answer", text: task.message });
        break;
      }
      default:
        emit({ type: "error", text: "reason" in result ? result.reason : "failed" });
    }
  }, { origin, log, print: (s) => emit({ type: "status", text: s }) });
}
