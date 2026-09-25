import { useEffect, useRef } from "react";
import { SyntaxStyle, type TextareaRenderable, type KeyEvent } from "@opentui/core";
import { tokenizeSql, type TokenKind } from "../lib/sqlTokens";
import { theme } from "../lib/theme";

const SQL_STYLE = SyntaxStyle.fromStyles({
  default: { fg: theme.fg },
  keyword: { fg: theme.magenta, bold: true },
  type: { fg: theme.cyan },
  function: { fg: theme.accent },
  string: { fg: theme.green },
  number: { fg: theme.orange },
  comment: { fg: theme.fgDim, italic: true },
  identifier: { fg: theme.fg },
  operator: { fg: theme.yellow },
  punct: { fg: theme.fgMuted },
  variable: { fg: theme.orange },
});

const STYLE_IDS: Partial<Record<TokenKind, number>> = {};
for (const kind of ["keyword", "type", "function", "string", "number", "comment", "identifier", "operator", "punct", "variable"] as TokenKind[]) {
  const id = SQL_STYLE.getStyleId(kind);
  if (id !== null && id !== undefined) STYLE_IDS[kind] = id;
}

/** Re-tokenize the whole buffer and push per-line highlight ranges. */
export function applyHighlights(ta: TextareaRenderable): void {
  const text = ta.plainText;
  ta.clearAllHighlights();
  if (!text) return;
  const tokens = tokenizeSql(text);
  const lineStarts = [0];
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") lineStarts.push(i + 1);

  let line = 0;
  for (const t of tokens) {
    const styleId = STYLE_IDS[t.kind];
    if (styleId === undefined) continue;
    while (line + 1 < lineStarts.length && lineStarts[line + 1]! <= t.start) line++;
    let l = line;
    let pos = t.start;
    while (pos < t.end) {
      const lineEnd = l + 1 < lineStarts.length ? lineStarts[l + 1]! - 1 : text.length;
      const segEnd = Math.min(t.end, lineEnd);
      if (segEnd > pos) {
        ta.addHighlight(l, { start: pos - lineStarts[l]!, end: segEnd - lineStarts[l]!, styleId });
      }
      if (segEnd >= t.end) break;
      pos = segEnd + 1;
      l++;
    }
  }
}

const KEY_BINDINGS = [
  { name: "home", action: "line-home" },
  { name: "end", action: "line-end" },
  { name: "home", shift: true, action: "select-line-home" },
  { name: "end", shift: true, action: "select-line-end" },
  { name: "home", ctrl: true, action: "buffer-home" },
  { name: "end", ctrl: true, action: "buffer-end" },
  { name: "up", ctrl: true, action: "buffer-home" },
  { name: "down", ctrl: true, action: "buffer-end" },
  { name: "z", ctrl: true, action: "undo" },
  { name: "r", ctrl: true, action: "redo" },
  { name: "a", ctrl: true, action: "select-all" },
  { name: "d", ctrl: true, shift: true, action: "delete-line" },
] as const;

interface EditorProps {
  initialSql: string;
  focused: boolean;
  editorRef: React.RefObject<TextareaRenderable | null>;
  onContentChange: () => void;
  onSubmit: () => void;
}

export function Editor({ initialSql, focused, editorRef, onContentChange, onSubmit }: EditorProps) {
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const scheduleHighlight = () => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      const ta = editorRef.current;
      if (ta) applyHighlights(ta);
    }, 30);
  };

  useEffect(() => {
    const ta = editorRef.current;
    if (ta) applyHighlights(ta);
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleKeyDown = (key: KeyEvent) => {
    if (key.name === "tab" && !key.ctrl && !key.meta) {
      key.preventDefault();
      if (!key.shift) editorRef.current?.insertText("  ");
    }
  };

  return (
    <line-number
      fg={theme.fgDim}
      bg={theme.bg}
      minWidth={3}
      paddingRight={1}
      showLineNumbers
      style={{ width: "100%", height: "100%", flexGrow: 1 }}
    >
      <textarea
        ref={editorRef}
        focused={focused}
        initialValue={initialSql}
        placeholder="-- Write BigQuery SQL here. Ctrl+Enter or F5 runs it; F1 for help."
        placeholderColor={theme.fgDim}
        syntaxStyle={SQL_STYLE}
        wrapMode="none"
        textColor={theme.fg}
        backgroundColor={theme.bg}
        focusedBackgroundColor={theme.bg}
        focusedTextColor={theme.fg}
        cursorColor={theme.cursorBg}
        selectionBg={theme.selectionBg}
        selectionFg={theme.selectionFg}
        tabIndicator="→"
        tabIndicatorColor={theme.fgDim}
        keyBindings={KEY_BINDINGS as unknown as any}
        onKeyDown={handleKeyDown}
        onContentChange={() => {
          scheduleHighlight();
          onContentChange();
        }}
        onSubmit={onSubmit}
        style={{ width: "100%", height: "100%" }}
      />
    </line-number>
  );
}
