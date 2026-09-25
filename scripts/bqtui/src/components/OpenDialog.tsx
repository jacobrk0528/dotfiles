import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { deleteQuery, listSavedQueries, loadQuery, type SavedQuery } from "../lib/queries";
import { theme } from "../lib/theme";
import { padRight, relativeTime, truncate } from "../lib/util";
import { HighlightedSql } from "./HighlightedSql";
import { ListView } from "./ListView";

interface OpenDialogProps {
  width: number;
  height: number;
  onOpen: (query: SavedQuery, sql: string) => void;
  onCancel: () => void;
  onStatus: (message: string, kind?: "info" | "error" | "success") => void;
}

export function OpenDialog({ width, height, onOpen, onCancel, onStatus }: OpenDialogProps) {
  const [queries, setQueries] = useState<SavedQuery[] | "loading">("loading");
  const [cursor, setCursor] = useState(0);
  const [preview, setPreview] = useState<string>("");

  const reload = () => listSavedQueries().then(setQueries);
  useEffect(() => {
    reload();
  }, []);

  const list = Array.isArray(queries) ? queries : [];
  const current = list[Math.min(cursor, Math.max(0, list.length - 1))];

  useEffect(() => {
    if (!current) {
      setPreview("");
      return;
    }
    let cancelled = false;
    loadQuery(current.path).then((sql) => {
      if (!cancelled) setPreview(sql);
    });
    return () => {
      cancelled = true;
    };
  }, [current?.path]);

  useKeyboard((key) => {
    if (key.name === "escape" || key.name === "q") {
      key.preventDefault();
      onCancel();
      return;
    }
    if (list.length === 0) return;
    if (key.name === "j" || key.name === "down") setCursor((c) => Math.min(c + 1, list.length - 1));
    else if (key.name === "k" || key.name === "up") setCursor((c) => Math.max(c - 1, 0));
    else if (key.name === "g") setCursor(key.shift ? list.length - 1 : 0);
    else if (key.name === "return" && current) {
      loadQuery(current.path).then((sql) => onOpen(current, sql));
    } else if (key.name === "d" && current) {
      deleteQuery(current.path)
        .then(() => {
          onStatus(`Deleted ${current.name}`, "success");
          setCursor((c) => Math.max(0, c - 1));
          reload();
        })
        .catch((err) => onStatus(`Delete failed: ${err.message}`, "error"));
    }
  });

  const boxWidth = Math.min(width - 4, 100);
  const boxHeight = Math.min(height - 2, 36);
  const listHeight = Math.max(3, Math.floor((boxHeight - 4) * 0.45));
  const previewHeight = boxHeight - 4 - listHeight;
  const items = list.map((q) => (
    <text key={q.path}>
      <span fg={theme.fg}>{" " + padRight(q.name, Math.min(48, boxWidth - 20))}</span>
      <span fg={theme.fgDim}>{q.modifiedMs ? relativeTime(q.modifiedMs) : ""}</span>
    </text>
  ));

  return (
    <box
      title=" Open saved query "
      titleColor={theme.yellow}
      border
      borderStyle="rounded"
      borderColor={theme.accent}
      zIndex={50}
      style={{
        position: "absolute",
        top: Math.max(1, Math.floor((height - boxHeight) / 2)),
        left: Math.max(2, Math.floor((width - boxWidth) / 2)),
        width: boxWidth,
        height: boxHeight,
        backgroundColor: theme.overlay,
        flexDirection: "column",
      }}
    >
      {queries === "loading" ? (
        <text fg={theme.yellow}> Loading…</text>
      ) : (
        <ListView items={items} cursor={cursor} height={listHeight} emptyText=" No saved queries yet — Ctrl+S saves the current tab." />
      )}
      <box style={{ height: 1, borderColor: theme.border }} border={["top"]} />
      <box style={{ height: previewHeight, paddingLeft: 1, overflow: "hidden" }}>
        {preview ? <HighlightedSql sql={preview} maxLines={previewHeight - 1} /> : <text fg={theme.fgDim}>{truncate("", 1)}</text>}
      </box>
      <text fg={theme.fgDim}>{" Enter open in new tab · d delete · Esc close"}</text>
    </box>
  );
}
