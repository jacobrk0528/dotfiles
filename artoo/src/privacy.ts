// Redaction for everything that leaves the machine (Jev, the planner) or lands in run logs.
// A backstop, not a guarantee: never_look in guardrails.yaml keeps things from being read at all.
import { guardrails } from "./guardrails.ts";

const luhn = (digits: string) => {
  let sum = 0;
  for (let i = 0; i < digits.length; i++) {
    let d = Number(digits[digits.length - 1 - i]);
    if (i % 2) d = d * 2 > 9 ? d * 2 - 9 : d * 2;
    sum += d;
  }
  return sum % 10 === 0;
};

type Rule = [RegExp, string | ((m: string) => string)];

const BUILTIN: Rule[] = [
  [/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[private key]"],
  [/\bsk-(?:proj-|ant-|live-|test-)?[A-Za-z0-9_-]{16,}/g, "[key]"],
  [/\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}/g, "[key]"],
  [/\bAKIA[0-9A-Z]{16}\b/g, "[key]"],
  [/\bxox[abprs]-[A-Za-z0-9-]{10,}/g, "[key]"],
  [/\bAIza[0-9A-Za-z_-]{35}\b/g, "[key]"],
  [/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/g, "[jwt]"],
  // URL query strings and fragments often carry tokens; keep the path.
  [/(https?:\/\/[^\s?#"'<>]+)[?#][^\s"'<>]*/g, (m) => m.replace(/[?#].*$/, "?…")],
  [/\b[0-9a-f]{32,}\b/gi, "[hex]"],
  // Long opaque strings: needs letters and digits, so slugs like "my-long-blog-post-title" survive.
  [/[A-Za-z0-9+_=-]{40,}/g, (m) => (/\d/.test(m) && /[A-Za-z]/.test(m) ? "[token]" : m)],
  [/\b(?:\d[ -]?){12,18}\d\b/g, (m) => (luhn(m.replace(/\D/g, "")) ? "[card]" : m)],
];

export function redact(text: string): string {
  let out = text;
  for (const [re, rep] of BUILTIN) out = out.replace(re, rep as never);
  for (const re of guardrails().redact) out = out.replace(re, "[redacted]");
  return out;
}

/** Origin + path only: query strings and fragments are where session tokens live. */
export function redactUrl(url: string): string {
  try {
    const u = new URL(url);
    return redact(u.origin + u.pathname);
  } catch {
    return redact(url);
  }
}

export function redactDeep<T>(value: T): T {
  if (typeof value === "string") return redact(value) as T;
  if (Array.isArray(value)) return value.map(redactDeep) as T;
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, redactDeep(v)])) as T;
  }
  return value;
}
