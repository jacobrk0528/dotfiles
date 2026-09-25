// SQL formatting via sqlfluff (honours the user's ~/.sqlfluff config).

async function commandExists(cmd: string): Promise<boolean> {
  const proc = Bun.spawn(["which", cmd], { stdout: "ignore", stderr: "ignore" });
  return (await proc.exited) === 0;
}

export class FormatError extends Error {
  constructor(message: string, public readonly details: string[]) {
    super(message);
    this.name = "FormatError";
  }
}

export async function formatSql(sql: string, dialect = "bigquery"): Promise<string> {
  if (!(await commandExists("sqlfluff"))) {
    throw new FormatError("sqlfluff is not installed (pip install sqlfluff)", []);
  }
  const proc = Bun.spawn(["sqlfluff", "format", "--dialect", dialect, "-"], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  const w = proc.stdin as unknown as { write(s: string): void; end(): void };
  w.write(sql);
  w.end();
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout as ReadableStream).text(),
    new Response(proc.stderr as ReadableStream).text(),
    proc.exited,
  ]);
  if (exitCode !== 0 || !stdout.trim()) {
    const combined = (stdout + "\n" + stderr).split("\n").map((l) => l.trim()).filter(Boolean);
    const problems = combined.filter((l) => /^L:\s*\d+/.test(l) || /error/i.test(l));
    const first = problems.find((l) => /^L:\s*\d+/.test(l));
    const summary = first
      ? first.replace(/^L:\s*(\d+)\s*\|\s*P:\s*(\d+)\s*\|\s*\w+\s*\|\s*/, "L$1:$2 ")
      : "sqlfluff could not parse the query";
    throw new FormatError(summary, problems);
  }
  // sqlfluff keeps a trailing newline; the editor is happier without it.
  return stdout.replace(/\s+$/, "");
}
