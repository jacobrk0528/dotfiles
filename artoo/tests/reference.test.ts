import { afterEach, beforeEach, expect, test } from "bun:test";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { listConversations, openConversation, refIndex, resolveRef } from "../src/conversation.ts";
import { expandReferences, mentionedRefs, UnknownReference } from "../src/reference.ts";

let dir: string;
beforeEach(() => {
  dir = mkdtempSync(join(tmpdir(), "artoo-convo-"));
  process.env.JEV_PILOT_CONVERSATIONS = dir;
});
afterEach(() => {
  delete process.env.JEV_PILOT_CONVERSATIONS;
  rmSync(dir, { recursive: true, force: true });
});

const legacy = (id: string, input: string) =>
  writeFileSync(join(dir, `${id}.jsonl`), JSON.stringify({ t: Date.parse("2026-10-01T00:00:00Z"), type: "start", input }) + "\n");

test("older conversations are numbered oldest first, and numbers stay put", () => {
  legacy("2026-10-01T10-00-00.000Z", "first");
  legacy("2026-10-02T10-00-00.000Z", "second");
  expect(refIndex().get("2026-10-01T10-00-00.000Z")).toBe(1);
  expect(refIndex().get("2026-10-02T10-00-00.000Z")).toBe(2);
  const convo = openConversation("third");
  expect(convo.ref).toBe(3);
  expect(resolveRef(3)).toBe(convo.id);
  // Deleting a conversation doesn't renumber the rest.
  rmSync(join(dir, "2026-10-01T10-00-00.000Z.jsonl"));
  expect(resolveRef(2)).toBe("2026-10-02T10-00-00.000Z");
  expect(listConversations().map((c) => c.ref)).toEqual([3, 2]);
});

test("a new conversation in a fresh directory is !1", () => {
  expect(openConversation("hello").ref).toBe(1);
});

test("mentionedRefs finds !N but not punctuation", () => {
  expect(mentionedRefs("do what you did in !12 again, like !3 and !12")).toEqual([12, 3]);
  expect(mentionedRefs("wow!5 that's great!! 100% !")).toEqual([]);
});

test("a reference attaches the earlier request, steps and outcome", () => {
  const runDir = join(dir, "run");
  mkdirSync(runDir);
  writeFileSync(join(runDir, "events.jsonl"), [
    { t: 20, type: "pick_window", title: "Checkbook - Google Sheets", workspace: 2 },
    { t: 30, type: "step", what: "keys → 9/8/26⇥Discover⏎", purpose: "enter the first row", effect: "write" },
  ].map((e) => JSON.stringify(e)).join("\n"));
  writeFileSync(join(dir, "2026-10-01T10-00-00.000Z.jsonl"), [
    { t: 10, type: "start", input: "add the transactions to the sheet" },
    { t: 15, type: "run_log", dir: runDir },
    { t: 40, type: "end", status: "done", output: "Added 3 rows." },
  ].map((e) => JSON.stringify(e)).join("\n"));

  const out = expandReferences("do exactly what you did in !1 again with the new tab");
  expect(out.refs).toEqual([1]);
  expect(out.text.startsWith("do exactly what you did in !1 again with the new tab\n")).toBe(true);
  expect(out.text).toContain("Request: add the transactions to the sheet");
  expect(out.text).toContain('1. used window "Checkbook - Google Sheets" on workspace 2');
  expect(out.text).toContain("2. keys → 9/8/26⇥Discover⏎ (enter the first row)");
  expect(out.text).toContain("Outcome (done): Added 3 rows.");
});

test("no reference leaves the request alone; an unknown one is an error", () => {
  expect(expandReferences("focus slack")).toEqual({ text: "focus slack", refs: [] });
  expect(() => expandReferences("redo !99")).toThrow(UnknownReference);
});
