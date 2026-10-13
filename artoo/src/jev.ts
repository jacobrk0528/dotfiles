// Thin wrapper over TypeSafe's Jev: named choice questions over code-built option lists.
import { choice, noul, TypeSafeClient, type EntryType, type Questions } from "@typesafe-ai/sdk";
import { redactDeep } from "./privacy.ts";
import { addUsage } from "./usage.ts";
import { abortable } from "./runtime.ts";

/** An option Jev can pick. The key (a short label) is what Jev sees; `value` is what we act on. */
export type Option<V = unknown> = { description: string; value: V };
export type Options<V = unknown> = Record<string, Option<V>>;

export type Picked<V = unknown> = {
  key: string;
  value: V;
  confidence: number;
  probabilities: Record<string, number>;
};

export type JevClient = { systemOne: TypeSafeClient["systemOne"] };

let client: JevClient | null = null;

export function setJev(c: JevClient | null) {
  client = c;
}

const jev = () => (client ??= new TypeSafeClient());

/** The one place requests leave for TypeSafe: state and every question/option text get redacted. */
async function send(state: EntryType, questions: Questions) {
  const res = await abortable(jev().systemOne({ state: redactDeep(state), questions: redactDeep(questions) }));
  addUsage(res.model, res.usage);
  return res;
}

/** Ask several choice questions about one state in a single parallel request. */
export async function pickMany<Q extends Record<string, { question: string; options: Options }>>(
  state: EntryType,
  questions: Q,
): Promise<{ picks: { [K in keyof Q]: Picked }; model: string }> {
  const payload = Object.fromEntries(
    Object.entries(questions).map(([name, q]) => [
      name,
      choice(q.question, Object.fromEntries(Object.entries(q.options).map(([k, o]) => [k, o.description]))),
    ]),
  );
  const res = await send(state, payload);
  const picks = Object.fromEntries(
    Object.entries(questions).map(([name, q]) => {
      const a = res.answers[name];
      if (!a || a.type !== "choice") throw new Error(`Jev returned no choice for "${name}"`);
      const opt = q.options[a.choice];
      if (!opt) throw new Error(`Jev picked unknown option "${a.choice}" for "${name}"`);
      return [name, { key: a.choice, value: opt.value, confidence: a.confidence, probabilities: { ...a.probabilities } }];
    }),
  ) as { [K in keyof Q]: Picked };
  return { picks, model: res.model };
}

export async function pickOne(state: EntryType, question: string, options: Options) {
  const { picks, model } = await pickMany(state, { q: { question, options } });
  return { ...picks.q, model };
}

/** Several yes/no questions about one state in one request. Returns P(yes) per question. */
export async function askYesNo(state: EntryType, questions: Record<string, string>): Promise<Record<string, number>> {
  const res = await send(state, Object.fromEntries(Object.entries(questions).map(([k, q]) => [k, noul(q)])));
  return Object.fromEntries(
    Object.keys(questions).map((k) => {
      const a = res.answers[k];
      if (!a || a.type !== "noul") throw new Error(`Jev returned no yes/no for "${k}"`);
      return [k, a.noul];
    }),
  );
}
