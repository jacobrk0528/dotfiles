import { useState } from "react";
import { useKeyboard } from "@opentui/react";
import { theme } from "../lib/theme";

interface SaveDialogProps {
  defaultName: string;
  width: number;
  height: number;
  onSave: (name: string) => void;
  onCancel: () => void;
}

export function SaveDialog({ defaultName, width, height, onSave, onCancel }: SaveDialogProps) {
  const [name, setName] = useState(defaultName);

  useKeyboard((key) => {
    if (key.name === "escape") {
      key.preventDefault();
      onCancel();
    }
  });

  const boxWidth = Math.min(width - 4, 60);
  return (
    <box
      title=" Save query as "
      titleColor={theme.yellow}
      border
      borderStyle="rounded"
      borderColor={theme.accent}
      zIndex={50}
      style={{
        position: "absolute",
        top: Math.max(1, Math.floor(height / 2) - 3),
        left: Math.max(2, Math.floor((width - boxWidth) / 2)),
        width: boxWidth,
        height: 6,
        backgroundColor: theme.overlay,
        flexDirection: "column",
        paddingLeft: 1,
        paddingRight: 1,
      }}
    >
      <text fg={theme.fgMuted}>Saved to ~/.config/bqtui/queries/&lt;name&gt;.sql</text>
      <input
        focused
        value={name}
        placeholder="my-query"
        onInput={setName}
        onSubmit={() => {
          if (name.trim()) onSave(name.trim());
        }}
        textColor={theme.fg}
        backgroundColor={theme.headerBg}
        focusedBackgroundColor={theme.headerBg}
        cursorColor={theme.cursorBg}
      />
      <text fg={theme.fgDim}>Enter to save · Esc to cancel</text>
    </box>
  );
}
