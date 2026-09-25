// Shared plumbing for Google Cloud APIs: access tokens from gcloud, a small
// REST helper, and a JSON-returning `gcloud` runner.

export class GcloudError extends Error {
  constructor(message: string, public readonly raw = "") {
    super(message);
    this.name = "GcloudError";
  }
}

let tokenCache: { token: string; expiresAt: number } | null = null;

export async function accessToken(): Promise<string> {
  if (tokenCache && tokenCache.expiresAt > Date.now()) return tokenCache.token;
  const proc = Bun.spawn(["gcloud", "auth", "print-access-token"], { stdout: "pipe", stderr: "pipe" });
  const [out, err, code] = await Promise.all([
    new Response(proc.stdout as ReadableStream).text(),
    new Response(proc.stderr as ReadableStream).text(),
    proc.exited,
  ]);
  const token = out.trim();
  if (code !== 0 || !token) throw new GcloudError(parseGcloudError(err, "gcloud auth print-access-token failed (run `gcloud auth login`)"), err);
  tokenCache = { token, expiresAt: Date.now() + 45 * 60 * 1000 };
  return token;
}

export function parseGcloudError(stderr: string, fallback: string): string {
  const m = stderr.match(/ERROR:\s*\([^)]*\)\s*([\s\S]*)/);
  const text = (m ? m[1] : stderr).replace(/\s+/g, " ").trim();
  return text || fallback;
}

export async function gapi<T>(url: string, init?: { method?: string; body?: unknown }): Promise<T> {
  const token = await accessToken();
  const res = await fetch(url, {
    method: init?.method ?? "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init?.body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
  const text = await res.text();
  let parsed: any = null;
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    parsed = null;
  }
  if (!res.ok) {
    const message = parsed?.error?.message ?? `${res.status} ${res.statusText}`;
    throw new GcloudError(message, text);
  }
  return (parsed ?? {}) as T;
}

/** Follow `nextPageToken` pagination, collecting `field` from every page. */
export async function gapiAll<T>(url: string, field: string, maxPages = 20): Promise<T[]> {
  const out: T[] = [];
  let pageToken: string | undefined;
  for (let i = 0; i < maxPages; i++) {
    const sep = url.includes("?") ? "&" : "?";
    const page = await gapi<any>(pageToken ? `${url}${sep}pageToken=${encodeURIComponent(pageToken)}` : url);
    out.push(...((page[field] as T[]) ?? []));
    pageToken = page.nextPageToken;
    if (!pageToken) break;
  }
  return out;
}

export async function runGcloud(args: string[]): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  const proc = Bun.spawn(["gcloud", ...args], { stdout: "pipe", stderr: "pipe", stdin: "ignore" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout as ReadableStream).text(),
    new Response(proc.stderr as ReadableStream).text(),
    proc.exited,
  ]);
  return { stdout, stderr, exitCode };
}

export async function gcloudJson<T>(args: string[], fallback = "gcloud command failed"): Promise<T> {
  const { stdout, stderr, exitCode } = await runGcloud(args);
  if (exitCode !== 0) throw new GcloudError(parseGcloudError(stderr, fallback), stderr);
  const text = stdout.trim();
  if (!text) return [] as unknown as T;
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new GcloudError(`Could not parse gcloud output: ${text.slice(0, 120)}`, stdout);
  }
}

// ---------------------------------------------------------------------------
// Tiny in-memory cache so switching sidebar sections doesn't refetch.

const cache = new Map<string, { value: unknown; expiresAt: number }>();

export async function cached<T>(key: string, ttlMs: number, fn: () => Promise<T>, force = false): Promise<T> {
  const hit = cache.get(key);
  if (!force && hit && hit.expiresAt > Date.now()) return hit.value as T;
  const value = await fn();
  cache.set(key, { value, expiresAt: Date.now() + ttlMs });
  return value;
}

export function invalidateCache(prefix: string): void {
  for (const key of cache.keys()) if (key.startsWith(prefix)) cache.delete(key);
}
