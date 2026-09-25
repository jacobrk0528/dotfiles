import { useKeyboard } from "@opentui/react";
import { theme } from "../lib/theme";

interface ConfirmDialogProps {
  message: string;
  width: number;
  height: number;
  onYes: () => void;
  onNo: () => void;
}

export function ConfirmDialog({ message, width, height, onYes, onNo }: ConfirmDialogProps) {
  useKeyboard((key) => {
    if (key.name === "y" || key.name === "return") {
      key.preventDefault();
      onYes();
    } else if (key.name === "n" || key.name === "escape") {
      key.preventDefault();
      onNo();
    }
  });
  const boxWidth = Math.min(width - 4, Math.max(30, message.length + 6));
  return (
    <box
      border
      borderStyle="rounded"
      borderColor={theme.orange}
      zIndex={60}
      style={{
        position: "absolute",
        top: Math.max(1, Math.floor(height / 2) - 2),
        left: Math.max(2, Math.floor((width - boxWidth) / 2)),
        width: boxWidth,
        height: 4,
        backgroundColor: theme.overlay,
        flexDirection: "column",
        paddingLeft: 1,
      }}
    >
      <text fg={theme.fg}>{message}</text>
      <text fg={theme.fgDim}>y / Enter confirm · n / Esc cancel</text>
    </box>
  );
}
