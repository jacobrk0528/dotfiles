// Single choke point for spawning system tools, so tests can swap in a fake runner.
import { signal } from "./runtime.ts";

export type RunResult = { stdout: string; stderr: string; code: number };
export type Runner = (cmd: string[], opts?: { stdin?: string }) => Promise<RunResult>;

const bunRunner: Runner = async (cmd, opts) => {
  const s = signal();
  s.throwIfAborted();
  const proc = Bun.spawn(cmd, {
    stdin: opts?.stdin !== undefined ? new TextEncoder().encode(opts.stdin) : "ignore",
    stdout: "pipe",
    stderr: "pipe",
  });
  const abort = () => proc.kill("SIGTERM");
  s.addEventListener("abort", abort, { once: true });
  try {
    const [stdout, stderr, code] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
    ]);
    s.throwIfAborted();
    return { stdout, stderr, code };
  } finally {
    s.removeEventListener("abort", abort);
  }
};

let runner: Runner = bunRunner;

export function setRunner(r: Runner | null) {
  runner = r ?? bunRunner;
}

/** Run without throwing on a non-zero exit. */
export const runRaw: Runner = (cmd, opts) => runner(cmd, opts);

export class CommandError extends Error {
  constructor(public cmd: string[], public result: RunResult) {
    super(`${cmd[0]} exited ${result.code}: ${result.stderr.trim() || result.stdout.trim()}`);
  }
}

export async function run(cmd: string[], opts?: { stdin?: string }): Promise<string> {
  const result = await runner(cmd, opts);
  if (result.code !== 0) throw new CommandError(cmd, result);
  return result.stdout;
}

export async function runJson<T>(cmd: string[]): Promise<T> {
  return JSON.parse(await run(cmd)) as T;
}
