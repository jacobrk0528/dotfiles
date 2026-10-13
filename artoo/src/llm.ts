// Structured OpenAI calls carrying desktop content. Text state is redacted;
// screenshot PNGs are attached as image inputs. Plain questions use answer.ts.
import { redactDeep } from "./privacy.ts";
import { addUsage } from "./usage.ts";
import { signal } from "./runtime.ts";

export type JsonOptions = {
  name: string;
  instructions: string;
  input: unknown;
  schema: Record<string, unknown>;
  reasoning?: string;
  model?: string;
  /** PNG paths. Images are attached after text redaction (never redact base64). */
  images?: string[];
};

type JsonCaller = <T>(opts: JsonOptions) => Promise<T>;
let caller: JsonCaller | null = null;
export const setJsonCaller = (fn: JsonCaller | null) => { caller = fn; };

/** One structured-output call: the reply is parsed JSON matching `schema` (strict). */
export async function llmJson<T>(opts: JsonOptions): Promise<T> {
  signal().throwIfAborted();
  if (caller) return caller<T>(opts);
  const key = process.env.OPENAI_API_KEY;
  if (!key) throw new Error("OPENAI_API_KEY isn't set in ~/dotfiles/.env");
  const content: unknown[] = [{ type: "input_text", text: JSON.stringify(redactDeep(opts.input)) }];
  for (const path of opts.images ?? []) {
    const bytes = await Bun.file(path).arrayBuffer();
    content.push({ type: "input_image", image_url: `data:image/png;base64,${Buffer.from(bytes).toString("base64")}`, detail: "high" });
  }
  const request = () => fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    signal: AbortSignal.any([signal(), AbortSignal.timeout(120_000)]),
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      // Planning wants a stronger model than quick answers (OPENAI_MODEL).
      model: opts.model || process.env.OPENAI_PLANNER_MODEL || process.env.OPENAI_MODEL || "gpt-5.6-luna",
      instructions: opts.instructions,
      input: [{ role: "user", content }],
      reasoning: { effort: opts.reasoning ?? process.env.OPENAI_PLANNER_REASONING ?? "medium" },
      text: { format: { type: "json_schema", name: opts.name, schema: opts.schema, strict: true } },
    }),
  });
  // One retry: the API occasionally stalls on a single request.
  const res = await request().catch(() => { signal().throwIfAborted(); return request(); });
  const body = (await res.json()) as any;
  if (body?.model) addUsage(body.model, body.usage);
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${body?.error?.message ?? "request failed"}`);
  if (body.status === "incomplete") throw new Error(`OpenAI stopped early: ${body.incomplete_details?.reason ?? "incomplete"}`);
  // The reply can hold more than one text part (e.g. a restated answer); use the last one that parses.
  const parts: string[] = (body.output ?? [])
    .flatMap((o: any) => o.content ?? [])
    .filter((c: any) => c.type === "output_text")
    .map((c: any) => c.text);
  for (const part of parts.toReversed()) {
    try {
      return JSON.parse(part) as T;
    } catch {}
  }
  const raw = parts.join("\n---\n");
  await Bun.write(`/tmp/artoo-bad-reply-${Date.now()}.txt`, raw);
  throw new Error(`planner reply wasn't JSON (${parts.length} part(s)): ${raw.slice(0, 200)}`);
}
