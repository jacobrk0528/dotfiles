// Screenshots via grim. Geometry comes from hyprctl so we can grab a single monitor or window.
import { run } from "../exec.ts";
import { activeWindow, monitors } from "./hypr.ts";

export type ShotTarget = "screen" | "monitor" | "window";

export async function screenshot(path: string, target: ShotTarget = "screen"): Promise<string> {
  const args = ["grim"];
  if (target === "monitor") {
    const mon = (await monitors()).find((m) => m.focused);
    if (!mon) throw new Error("no focused monitor");
    args.push("-o", mon.name);
  } else if (target === "window") {
    const win = await activeWindow();
    if (!win) throw new Error("no active window");
    args.push("-g", `${win.at[0]},${win.at[1]} ${win.size[0]}x${win.size[1]}`);
  }
  await run([...args, path]);
  return path;
}
