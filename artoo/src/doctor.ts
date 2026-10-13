import { accessSync, constants, existsSync } from "node:fs";
import { join } from "node:path";
import { runRaw } from "./exec.ts";

export async function doctor() {
  const checks: { name: string; ok: boolean; detail: string }[] = [];
  for (const bin of ["hyprctl", "grim", "wtype", "ydotool", "uv"]) {
    const path = Bun.which(bin);
    checks.push({ name: bin, ok: !!path, detail: path ?? "not installed" });
  }
  const desktop = await runRaw(["hyprctl", "-j", "monitors"]);
  checks.push({ name: "desktop", ok: desktop.code === 0, detail: desktop.code === 0 ? "Hyprland IPC available" : desktop.stderr.trim() });
  let writable = false;
  try { accessSync("/dev/uinput", constants.W_OK); writable = true; } catch {}
  checks.push({ name: "uinput", ok: writable, detail: writable ? "user has device access" : "no write access to /dev/uinput" });
  const socket = process.env.YDOTOOL_SOCKET ?? join(process.env.XDG_RUNTIME_DIR ?? `/run/user/${process.getuid?.()}`, ".ydotool_socket");
  const service = await runRaw(["systemctl", "--user", "is-active", "ydotool.service"]);
  checks.push({ name: "mouse", ok: existsSync(socket) && service.code === 0, detail: `${service.stdout.trim()}; socket ${existsSync(socket) ? "present" : "missing"}: ${socket}` });
  return checks;
}
