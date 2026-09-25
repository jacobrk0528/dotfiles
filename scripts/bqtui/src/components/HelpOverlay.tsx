import { useKeyboard } from "@opentui/react";
import { theme } from "../lib/theme";
import { padRight, truncate } from "../lib/util";

const SECTIONS: { title: string; keys: [string, string][] }[] = [
  {
    title: "Global",
    keys: [
      ["F1  ?", "This help"],
      ["F2 / F3 / F4", "Focus explorer / editor / results"],
      ["Ctrl+H/J/K/L", "Move focus left/down/up/right between panes"],
      ["Tab (explorer)", "Switch BigQuery / Dataform / Storage"],
      ["F6", "Toggle explorer sidebar"],
      ["Ctrl+B", "Toggle results panel"],
      ["Ctrl+T", "New query tab"],
      ["Ctrl+X", "Close tab (Ctrl+W outside the editor)"],
      ["Ctrl+PgUp/PgDn", "Previous / next tab"],
      ["Alt+1…9", "Jump to tab N"],
      ["Alt+P", "Switch active project / pin projects"],
      ["Ctrl+O / Ctrl+S", "Open saved query / save"],
      ["Ctrl+P", "Query history"],
      ["Ctrl+Y", "Copy all results (TSV)"],
      ["Ctrl+Q", "Quit (tabs are restored next launch)"],
    ],
  },
  {
    title: "Editor",
    keys: [
      ["Ctrl+Enter  F5", "Run query (or just the selection)"],
      ["Alt+Enter", "Run query (fallback in old terminals)"],
      ["Ctrl+G", "Dry run: validate + bytes + cost"],
      ["Ctrl+L", "Format SQL with sqlfluff"],
      ["Esc", "Cancel running query"],
      ["Ctrl+Z / Ctrl+R", "Undo / redo"],
      ["Ctrl+A", "Select all"],
      ["Shift+arrows", "Select text"],
      ["Home / End", "Line start / end"],
      ["Tab", "Insert two spaces"],
    ],
  },
  {
    title: "Explorer",
    keys: [
      ["j/k  ↑/↓", "Move"],
      ["h/l  ←/→", "Collapse / expand (h jumps to parent)"],
      ["Enter", "Open table schema / toggle node"],
      ["p", "Preview table (SELECT * LIMIT 100)"],
      ["i", "Insert table reference into editor"],
      ["y", "Copy table reference"],
      ["/", "Filter tables (Esc clears)"],
      ["r", "Refresh node"],
      ["P", "Switch active project / pin projects"],
      ["g / G", "First / last"],
    ],
  },
  {
    title: "Results",
    keys: [
      ["j/k  h/l", "Move rows / columns"],
      ["g / G", "First / last row"],
      ["0 / $", "First / last column"],
      ["PgUp / PgDn", "Page"],
      ["Enter", "Row detail"],
      ["s", "Sort by column (asc → desc → off)"],
      ["y / Y", "Copy row / copy all (TSV)"],
      ["c", "Copy cell"],
      ["e / E", "Export CSV / JSON to ~/Downloads"],
      ["z", "Zoom results panel"],
    ],
  },
  {
    title: "Schema / text tabs",
    keys: [
      ["j/k  h/l", "Scroll"],
      ["p", "Preview table (schema tab)"],
      ["e", "Edit SQL in a new query tab"],
      ["i / y", "Insert / copy reference or content"],
      ["d", "Download (Storage object)"],
      ["r", "Reload"],
    ],
  },
  {
    title: "Explorer sections",
    keys: [
      ["Tab  1/2/3", "BigQuery · Dataform · Storage"],
      ["Dataform: Enter", "Open file / compiled SQL / saved query"],
      ["Dataform: c", "Compile workspace"],
      ["Dataform: x", "Run compilation · cancel invocation"],
      ["Storage: Enter", "Preview object"],
      ["Storage: d", "Download to export dir"],
      ["Storage: x / L", "Insert EXTERNAL TABLE / LOAD DATA SQL"],
      ["Storage: i / y", "Insert / copy gs:// URI"],
    ],
  },
];

export function HelpOverlay({ width, height, onClose }: { width: number; height: number; onClose: () => void }) {
  useKeyboard((key) => {
    if (key.name === "escape" || key.name === "q" || key.name === "?" || key.name === "f1") {
      key.preventDefault();
      onClose();
    }
  });

  const boxWidth = Math.min(width - 4, 118);
  const boxHeight = Math.min(height - 2, 40);
  const colWidth = Math.floor((boxWidth - 6) / 2);
  const keyWidth = 17;
  const left = SECTIONS.slice(0, 3);
  const right = SECTIONS.slice(3);
  const renderSection = (s: (typeof SECTIONS)[number]) => (
    <box key={s.title} style={{ flexDirection: "column", marginBottom: 1 }}>
      <box style={{ height: 1 }}>
        <text fg={theme.yellow} wrapMode="none">
          {s.title}
        </text>
      </box>
      {s.keys.map(([k, d]) => (
        <box key={k} style={{ height: 1 }}>
          <text wrapMode="none">
            <span fg={theme.accent}>{padRight(k, keyWidth)}</span>
            <span fg={theme.fg}>{truncate(d, colWidth - keyWidth - 1)}</span>
          </text>
        </box>
      ))}
    </box>
  );
  return (
    <box
      title=" bqtui — keyboard reference "
      titleColor={theme.yellow}
      border
      borderStyle="rounded"
      borderColor={theme.accent}
      zIndex={100}
      style={{
        position: "absolute",
        top: Math.max(1, Math.floor((height - boxHeight) / 2)),
        left: Math.max(2, Math.floor((width - boxWidth) / 2)),
        width: boxWidth,
        height: boxHeight,
        backgroundColor: theme.overlay,
        flexDirection: "column",
        paddingLeft: 1,
        paddingRight: 1,
        overflow: "hidden",
      }}
    >
      <box style={{ flexDirection: "row", flexGrow: 1, overflow: "hidden" }}>
        <box style={{ flexDirection: "column", width: colWidth }}>{left.map(renderSection)}</box>
        <box style={{ flexDirection: "column", width: colWidth, marginLeft: 2 }}>{right.map(renderSection)}</box>
      </box>
      <text fg={theme.fgDim} wrapMode="none">
        Esc closes · Queries run in the active project shown in the status bar
      </text>
    </box>
  );
}
