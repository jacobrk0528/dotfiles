// Cross-platform-ish clipboard write. Tries wl-copy (Wayland/Hyprland, the
// user's actual setup) first, then falls back to xclip/xsel/pbcopy so the
// tool doesn't hard-fail on other machines.

const CANDIDATES: { cmd: string; args: string[] }[] = [
  { cmd: "wl-copy", args: [] },
  { cmd: "xclip", args: ["-selection", "clipboard"] },
  { cmd: "xsel", args: ["--clipboard", "--input"] },
  { cmd: "pbcopy", args: [] },
];

async function commandExists(cmd: string): Promise<boolean> {
  const proc = Bun.spawn(["which", cmd], { stdout: "ignore", stderr: "ignore" });
  return (await proc.exited) === 0;
}

export async function copyToClipboard(text: string): Promise<void> {
  for (const candidate of CANDIDATES) {
    if (!(await commandExists(candidate.cmd))) continue;
    const proc = Bun.spawn([candidate.cmd, ...candidate.args], {
      stdin: "pipe",
      stdout: "ignore",
      stderr: "pipe",
    });
    proc.stdin.write(text);
    await proc.stdin.end();
    const exitCode = await proc.exited;
    if (exitCode === 0) return;
  }
  throw new Error("No clipboard utility found (tried wl-copy, xclip, xsel, pbcopy)");
}
