// Per-process tally of model usage (OpenAI + Jev), so a conversation log can show tokens and
// an estimated cost. Prices come from prices.yaml.
import { readFileSync } from "node:fs";
import { join } from "node:path";

export type UsageLine = { model: string; input: number; output: number; calls: number };

const lines = new Map<string, UsageLine>();
const toolCalls = new Map<string, number>();

/** Model names are tallied without their version suffix (jev-1.13.0 → jev, gpt-5.6-luna-2026-08-01 → gpt-5.6-luna). */
const baseModel = (m: string) => m.replace(/-(\d{4}-\d{2}-\d{2}|\d+(\.\d+)+)$/, "");

export function addUsage(model: string, usage?: { input_tokens?: number; output_tokens?: number } | null) {
  const key = baseModel(model);
  const line = lines.get(key) ?? { model: key, input: 0, output: 0, calls: 0 };
  line.input += usage?.input_tokens ?? 0;
  line.output += usage?.output_tokens ?? 0;
  line.calls += 1;
  lines.set(key, line);
}

export function addToolCall(name: string) {
  toolCalls.set(name, (toolCalls.get(name) ?? 0) + 1);
}

type Prices = { models: Record<string, { input: number; output: number }>; tools: Record<string, number> };

function prices(): Prices {
  try {
    const p = Bun.YAML.parse(readFileSync(join(import.meta.dir, "..", "prices.yaml"), "utf8")) as Partial<Prices>;
    return { models: p.models ?? {}, tools: p.tools ?? {} };
  } catch {
    return { models: {}, tools: {} };
  }
}

/** Totals so far, with cost in USD. `cost` is null when some model used has no price. */
export function usageSummary() {
  const p = prices();
  let cost: number | null = 0;
  const models = [...lines.values()].map((l) => {
    const price = p.models[l.model];
    const c = price ? (l.input * price.input + l.output * price.output) / 1e6 : null;
    if (c === null) cost = null;
    else if (cost !== null) cost += c;
    return { ...l, cost: c };
  });
  const tools = Object.fromEntries(toolCalls);
  for (const [name, n] of toolCalls) if (cost !== null) cost += n * (p.tools[name] ?? 0);
  return { models, tools, cost };
}
