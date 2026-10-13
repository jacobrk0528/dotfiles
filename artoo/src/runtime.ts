// One cancellation signal follows model requests, child processes, and UI waits.
// Cleanup (notably restoring the desktop) gets its own bounded signal.
import { AsyncLocalStorage } from "node:async_hooks";

const scopes = new AsyncLocalStorage<AbortSignal>();
const controller = new AbortController();
export const signal = () => scopes.getStore() ?? controller.signal;
export const cancelled = () => controller.signal.aborted;
export const cancel = () => controller.abort(new Error("Cancelled."));
export const checkCancelled = () => signal().throwIfAborted();
export const withSignal = <T>(s: AbortSignal, fn: () => Promise<T>) => scopes.run(s, fn);
export const cleanup = <T>(fn: () => Promise<T>) => withSignal(AbortSignal.timeout(8000), fn);

export function installCancellation() {
  process.on("SIGTERM", cancel);
  process.on("SIGINT", cancel);
}

export function sleep(ms: number): Promise<void> {
  const s = signal();
  s.throwIfAborted();
  return new Promise((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(s.reason); };
    const timer = setTimeout(() => { s.removeEventListener("abort", abort); resolve(); }, ms);
    s.addEventListener("abort", abort, { once: true });
  });
}

export function abortable<T>(work: Promise<T>): Promise<T> {
  const s = signal();
  s.throwIfAborted();
  return new Promise((resolve, reject) => {
    const abort = () => reject(s.reason);
    s.addEventListener("abort", abort, { once: true });
    work.then(resolve, reject).finally(() => s.removeEventListener("abort", abort));
  });
}
