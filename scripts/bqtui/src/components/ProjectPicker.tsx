import { useEffect, useState } from "react";
import { useKeyboard } from "@opentui/react";
import { listProjects, type Project } from "../lib/bq";
import { theme } from "../lib/theme";
import { padRight, truncate } from "../lib/util";
import { ListView } from "./ListView";

interface ProjectPickerProps {
  pinned: string[];
  activeProject?: string;
  defaultProject?: string;
  width: number;
  height: number;
  onChange: (pinned: string[]) => void;
  onSwitch: (projectId: string) => void;
  onClose: () => void;
}

export function ProjectPicker({ pinned, activeProject, defaultProject, width, height, onChange, onSwitch, onClose }: ProjectPickerProps) {
  const [projects, setProjects] = useState<Project[] | "loading" | { error: string }>("loading");
  const [cursor, setCursor] = useState(0);

  useEffect(() => {
    listProjects()
      .then((p) => setProjects(p.sort((a, b) => a.projectId.localeCompare(b.projectId))))
      .catch((err) => setProjects({ error: err.message }));
  }, []);

  const list = Array.isArray(projects) ? projects : [];

  useKeyboard((key) => {
    if (key.name === "escape" || key.name === "q" || (key.name === "return" && list.length === 0)) {
      onClose();
      return;
    }
    if (list.length === 0) return;
    if (key.name === "j" || key.name === "down") setCursor((c) => Math.min(c + 1, list.length - 1));
    else if (key.name === "k" || key.name === "up") setCursor((c) => Math.max(c - 1, 0));
    else if (key.name === "g") setCursor(key.shift ? list.length - 1 : 0);
    else if (key.name === "return") {
      onSwitch(list[cursor]!.projectId);
    } else if (key.name === "space") {
      const id = list[cursor]!.projectId;
      if (id === activeProject) return;
      const next = pinned.includes(id) ? pinned.filter((p) => p !== id) : [...pinned, id];
      onChange(next);
    }
  });

  const boxWidth = Math.min(width - 4, 80);
  const boxHeight = Math.min(height - 2, 30);
  const items = list.map((p) => {
    const isActive = p.projectId === activeProject;
    const isDefault = p.projectId === defaultProject;
    const on = isActive || pinned.includes(p.projectId);
    return (
      <text key={p.projectId}>
        <span fg={isActive ? theme.yellow : on ? theme.green : theme.fgDim}>{isActive ? " [●] " : on ? " [x] " : " [ ] "}</span>
        <span fg={isActive ? theme.yellow : theme.fg}>{padRight(p.projectId, 34)}</span>
        <span fg={theme.fgMuted}>{truncate(p.friendlyName ?? "", boxWidth - 54)}</span>
        <span fg={theme.fgDim}>{isActive ? " active" : isDefault ? " gcloud default" : ""}</span>
      </text>
    );
  });

  return (
    <box
      title=" Projects "
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
      {projects === "loading" ? <text fg={theme.yellow}> Loading projects…</text> : null}
      {typeof projects === "object" && !Array.isArray(projects) && "error" in projects ? (
        <text fg={theme.red}>{` ${projects.error}`}</text>
      ) : null}
      {Array.isArray(projects) ? <ListView items={items} cursor={cursor} height={boxHeight - 3} /> : null}
      <text fg={theme.fgDim}>{" Enter switch active project · Space pin/unpin in browser · Esc close"}</text>
    </box>
  );
}
