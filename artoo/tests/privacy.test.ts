import { afterEach, expect, test } from "bun:test";
import { check } from "../src/guard.ts";
import { parseGuardrails, setGuardrails } from "../src/guardrails.ts";
import { redact, redactDeep, redactUrl } from "../src/privacy.ts";
import { describe as describeDesktop } from "../src/perceive/desktop.ts";

afterEach(() => setGuardrails(null));

test("redacts key and token shapes", () => {
  const s = [
    "openai sk-proj-abcdefghijklmnop1234",
    "gh ghp_abcdefghijklmnopqrstuvwxyz0123",
    "aws AKIAABCDEFGHIJKLMNOP",
    "slack xoxb-1234567890-abcdef",
    "jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
    "card 4111 1111 1111 1111",
    "hex 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  ].join("\n");
  const out = redact(s);
  for (const leaked of ["sk-proj-abc", "ghp_abc", "AKIAABC", "xoxb-123", "eyJhbGci", "4111 1111", "9f86d08"]) expect(out).not.toContain(leaked);
});

test("keeps ordinary text, slugs, and non-card numbers", () => {
  const s = 'click button "Last 30 days (exclude today)" on https://github.com/some-org/a-really-long-repository-name-for-testing 220,511 views';
  expect(redact(s)).toBe(s);
});

test("URL query strings and fragments are stripped", () => {
  expect(redactUrl("https://example.com/reset?token=abc123&u=me#frag")).toBe("https://example.com/reset");
  expect(redact("see https://example.com/a?session=xyz for details")).toBe("see https://example.com/a?… for details");
});

test("redactDeep walks nested state", () => {
  expect(redactDeep({ a: ["key sk-abcdefghijklmnopqrstu"], b: { c: 3 } })).toEqual({ a: ["key [key]"], b: { c: 3 } });
});

const G = parseGuardrails(`
jev_threshold: 0.35
ask_first:
  destructive:
    description: Deletes things
    labels: ['\\b(delete|remove)\\b']
    commands: ['\\brm\\b']
  purchase:
    description: Buys things
    urls: ['/checkout']
never_look:
  apps: ['^slack$']
  sites: ['messages\\.google\\.com', 'github\\.com/settings/tokens']
redact:
  extra_patterns: ['ACME-\\d{6}']
`);

test("rule layer: tags, labels, URLs, commands", async () => {
  setGuardrails(G);
  const cats = async (i: Parameters<typeof check>[0]) => (await check(i, { jev: false })).map((h) => `${h.category}:${h.via}`);
  expect(await cats({ summary: "x", labels: ["Delete report"] })).toEqual(["destructive:rule"]);
  expect(await cats({ summary: "x", risk: ["destructive"] })).toEqual(["destructive:tag"]);
  expect(await cats({ summary: "x", url: "https://shop.com/checkout/step1" })).toEqual(["purchase:rule"]);
  expect(await cats({ summary: "x", command: "rm -rf ~/x" })).toEqual(["destructive:rule"]);
  expect(await cats({ summary: "x", labels: ["Removed items"], url: "https://shop.com/cart" })).toEqual([]);
});

test("user redact patterns apply", () => {
  setGuardrails(G);
  expect(redact("order ACME-123456 shipped")).toBe("order [redacted] shipped");
});

test("never_look windows go out as their app name only", () => {
  setGuardrails(G);
  const win = (cls: string, title: string, priv: boolean) => ({
    address: "0x1", class: cls, title, workspace: { id: 1, name: "1" }, at: [0, 0] as [number, number], size: [1, 1] as [number, number], focusHistoryID: 0, pid: 1, private: priv,
  });
  const text = describeDesktop({
    workspaces: [{ id: 1, name: "1", monitor: "m", windows: 2, lastwindowtitle: "" }],
    clients: [win("slack", "Alice (DM) - Slack", true), win("ghostty", "dotfiles", false)],
    monitors: [],
    active: null,
  });
  expect(text).not.toContain("Alice");
  expect(text).toContain('slack "(private)"');
  expect(text).toContain('ghostty "dotfiles"');
});

test("never_look sites match host and path", async () => {
  setGuardrails(G);
  const { isHiddenSite } = await import("../src/guardrails.ts");
  expect(isHiddenSite("https://messages.google.com/web/conversations/1")).toBe(true);
  expect(isHiddenSite("https://github.com/settings/tokens?type=beta")).toBe(true);
  expect(isHiddenSite("https://github.com/settings/profile")).toBe(false);
});
