// Loads guardrails.yaml: the "ask first" categories and the "never look" lists.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";

const Category = z.object({
  description: z.string(),
  labels: z.array(z.string()).default([]),
  urls: z.array(z.string()).default([]),
  commands: z.array(z.string()).default([]),
});

const File = z.object({
  jev_threshold: z.number().min(0).max(1).default(0.35),
  ask_first: z.record(z.string(), Category).default({}),
  never_look: z
    .object({
      apps: z.array(z.string()).default([]),
      sites: z.array(z.string()).default([]),
      fields: z.array(z.string()).default([]),
    })
    .default({ apps: [], sites: [], fields: [] }),
  redact: z.object({ extra_patterns: z.array(z.string()).default([]) }).default({ extra_patterns: [] }),
});

export type CategoryRules = { description: string; labels: RegExp[]; urls: RegExp[]; commands: RegExp[] };

export type Guardrails = {
  jevThreshold: number;
  askFirst: Record<string, CategoryRules>;
  hiddenApps: RegExp[];
  hiddenSites: RegExp[];
  /** Source of one combined regex, so it can also be injected into page scripts. */
  sensitiveFieldSource: string;
  redact: RegExp[];
};

const re = (s: string, flags = "i") => new RegExp(s, flags);

export function parseGuardrails(yaml: string): Guardrails {
  const f = File.parse(Bun.YAML.parse(yaml) ?? {});
  return {
    jevThreshold: f.jev_threshold,
    askFirst: Object.fromEntries(
      Object.entries(f.ask_first).map(([name, c]) => [
        name,
        { description: c.description, labels: c.labels.map((s) => re(s)), urls: c.urls.map((s) => re(s)), commands: c.commands.map((s) => re(s)) },
      ]),
    ),
    hiddenApps: f.never_look.apps.map((s) => re(s)),
    hiddenSites: f.never_look.sites.map((s) => re(s)),
    sensitiveFieldSource: f.never_look.fields.length ? f.never_look.fields.map((s) => `(?:${s})`).join("|") : "(?!)",
    redact: f.redact.extra_patterns.map((s) => re(s, "gi")),
  };
}

let cached: Guardrails | null = null;

export function guardrails(): Guardrails {
  if (cached) return cached;
  const path = process.env.JEV_PILOT_GUARDRAILS ?? join(import.meta.dir, "..", "guardrails.yaml");
  cached = parseGuardrails(readFileSync(path, "utf8"));
  return cached;
}

export function setGuardrails(g: Guardrails | null) {
  cached = g;
}

export const isHiddenApp = (windowClass: string) => guardrails().hiddenApps.some((r) => r.test(windowClass));

/** never_look sites match against host + path, e.g. `github\.com/settings/tokens`. */
export function isHiddenSite(url: string): boolean {
  let where = url;
  try {
    const u = new URL(url);
    where = u.host + u.pathname;
  } catch {}
  return guardrails().hiddenSites.some((r) => r.test(where));
}
