import { theme } from "../lib/theme";
import { truncate } from "../lib/util";

export type StatusKind = "info" | "error" | "success";

interface StatusBarProps {
  message: string;
  kind: StatusKind;
  right: string;
  hints: string;
  width: number;
}

export function StatusBar({ message, kind, right, hints, width }: StatusBarProps) {
  const color = kind === "error" ? theme.red : kind === "success" ? theme.green : theme.fg;
  const rightWidth = Math.min(right.length, Math.floor(width / 2));
  const leftWidth = Math.max(10, width - rightWidth - 4);
  return (
    <box style={{ flexDirection: "column", height: 3, backgroundColor: theme.panel }} border={["top"]} borderColor={theme.border}>
      <box style={{ flexDirection: "row", height: 1, paddingLeft: 1, paddingRight: 1 }}>
        <box style={{ flexGrow: 1 }}>
          <text fg={color}>{truncate(message, leftWidth)}</text>
        </box>
        <text fg={theme.fgMuted}>{truncate(right, rightWidth)}</text>
      </box>
      <box style={{ height: 1, paddingLeft: 1 }}>
        <text fg={theme.fgDim}>{truncate(hints, width - 2)}</text>
      </box>
    </box>
  );
}
