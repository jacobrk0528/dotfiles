// Colours come from the desktop theme (quickshell/theme.json, which
// quickshell/scripts/apply-theme also turns into tmux/theme.conf), so the
// sidebar follows theme changes. Falls back to Glacier if the file is missing.
import { readFileSync } from "node:fs";
import { join } from "node:path";

const fallback = {
  base: "#0c1218",
  surface: "#141e29",
  text: "#eeeef2",
  accent: "#8ab7e6",
  green: "#79e29c",
  yellow: "#e2d479",
  red: "#e27979",
  orange: "#e2b179",
  gray: "#8d949a",
};

function load(): typeof fallback {
  try {
    const file = join(import.meta.dir, "../../../../quickshell/theme.json");
    return { ...fallback, ...JSON.parse(readFileSync(file, "utf8")) };
  } catch {
    return fallback;
  }
}

export const theme = load();
