// Shell commands under the command policy, for the answer route's run_command tool and the
// desktop planner's run_command operation.
import type { Confirm } from "./confirm.ts";
import { runRaw } from "./exec.ts";
import { check, describeHits } from "./guard.ts";
import { authorize, commandEffect } from "./policy.ts";
import { redact } from "./privacy.ts";

const OUTPUT_LIMIT = 8000;
const TIMEOUT_SECONDS = 20;

/**
 * Run one bash command line under the command policy: a recognized read-only command or
 * reversible device control (bluetoothctl connect, wpctl set-volume...) runs straight away,
 * anything else (or anything a guardrail flags) asks first. Returns the
 * redacted output, or null when the owner declined. Shared by the answer route and the
 * desktop planner, so neither has to type commands into a terminal window.
 */
export async function runShell(command: string, why: string, io: { status: (text: string) => void; confirm: Confirm; log?: (type: string, data: Record<string, unknown>) => void }): Promise<string | null> {
  const hits = await check({ summary: `run shell command: ${command}`, command });
  const ok = await authorize({
    summary: `Run \`${command}\`?\n${why}`,
    effect: hits.length ? "unknown" : commandEffect(command),
    reason: hits.length ? describeHits(hits) : "This command is not a recognized read-only operation.",
  }, io);
  if (!ok) return null;

  io.status(why);
  const { stdout, stderr, code } = await runRaw(["timeout", String(TIMEOUT_SECONDS), "bash", "-c", command]);
  let out = (stdout + (stderr ? `\n[stderr]\n${stderr}` : "")).trim();
  if (code === 124) out += `\n[timed out after ${TIMEOUT_SECONDS}s]`;
  else if (code !== 0) out += `\n[exit code ${code}]`;
  if (out.length > OUTPUT_LIMIT) out = out.slice(0, OUTPUT_LIMIT) + `\n[… ${out.length - OUTPUT_LIMIT} more characters cut]`;
  return redact(out || "(no output)");
}
