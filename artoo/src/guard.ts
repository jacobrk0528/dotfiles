// "Ask first" check for an action about to run: deterministic rules, then one Jev yes/no per
// category. Either layer can flag it; the caller asks the human.
import { guardrails } from "./guardrails.ts";
import { askYesNo } from "./jev.ts";

export type GuardInput = {
  /** One line saying what's about to happen, e.g. `click button "Apply" on datastudio.google.com`. */
  summary: string;
  /** Labels of the thing being acted on (button text, etc.). */
  labels?: string[];
  /** Static risk tags from the action registry. */
  risk?: string[];
  url?: string;
  command?: string;
};

export type GuardHit = { category: string; via: "tag" | "rule" | "jev"; detail: string };

export async function check(input: GuardInput, opts: { jev?: boolean } = {}): Promise<GuardHit[]> {
  const g = guardrails();
  const hits: GuardHit[] = [];

  for (const [name, c] of Object.entries(g.askFirst)) {
    if (input.risk?.includes(name)) hits.push({ category: name, via: "tag", detail: "action is tagged" });
    const label = input.labels?.find((l) => c.labels.some((r) => r.test(l)));
    if (label) hits.push({ category: name, via: "rule", detail: `label "${label}"` });
    if (input.url && c.urls.some((r) => r.test(input.url!))) hits.push({ category: name, via: "rule", detail: "page URL" });
    if (input.command && c.commands.some((r) => r.test(input.command!))) hits.push({ category: name, via: "rule", detail: "command" });
  }

  if (opts.jev !== false && Object.keys(g.askFirst).length) {
    const questions = Object.fromEntries(
      Object.entries(g.askFirst).map(([name, c]) => [name, `Would doing this action do the following: ${c.description}?`]),
    );
    const probs = await askYesNo({ action: input.summary, ...(input.url ? { page: input.url } : {}) }, questions);
    for (const [name, p] of Object.entries(probs)) {
      if (p > g.jevThreshold && !hits.some((h) => h.category === name)) {
        hits.push({ category: name, via: "jev", detail: `Jev ${p.toFixed(2)}` });
      }
    }
  }
  return hits;
}

export const describeHits = (hits: GuardHit[]) =>
  [...new Set(hits.map((h) => h.category))]
    .map((c) => `${c} (${hits.filter((h) => h.category === c).map((h) => h.detail).join(", ")})`)
    .join("; ");
