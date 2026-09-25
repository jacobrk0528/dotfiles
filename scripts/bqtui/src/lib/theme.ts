// Central palette (Tokyo Night inspired) so every component shares one look.
export const theme = {
  bg: "#0d1117",
  panel: "#11151c",
  overlay: "#1a1b26",
  border: "#2f3549",
  borderActive: "#7aa2f7",
  titleActive: "#e0af68",
  titleInactive: "#565f89",
  fg: "#c0caf5",
  fgDim: "#565f89",
  fgMuted: "#7f87a8",
  accent: "#7aa2f7",
  yellow: "#e0af68",
  green: "#9ece6a",
  red: "#f7768e",
  magenta: "#bb9af7",
  cyan: "#7dcfff",
  orange: "#ff9e64",
  selectionBg: "#33467c",
  selectionFg: "#ffffff",
  cursorBg: "#7aa2f7",
  cursorFg: "#0d1117",
  tabActiveBg: "#283457",
  tabInactiveBg: "#161a24",
  headerBg: "#1b2030",
  zebra: "#12161f",
} as const;

export const typeColor = (type: string): string => {
  const t = type.toUpperCase();
  if (["STRING", "BYTES"].includes(t)) return theme.green;
  if (["INTEGER", "INT64", "FLOAT", "FLOAT64", "NUMERIC", "BIGNUMERIC"].includes(t)) return theme.orange;
  if (["BOOLEAN", "BOOL"].includes(t)) return theme.magenta;
  if (["DATE", "DATETIME", "TIME", "TIMESTAMP", "INTERVAL"].includes(t)) return theme.cyan;
  if (["RECORD", "STRUCT", "ARRAY", "JSON", "GEOGRAPHY"].includes(t)) return theme.yellow;
  return theme.fg;
};
