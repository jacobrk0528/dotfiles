import { useEffect, useState } from "react";
import type { KeyEvent } from "@opentui/core";
import { describeObject, downloadObject, externalTableSql, headObject, listBuckets, listEntries, loadDataSql, type StorageEntry } from "../lib/storage";
import { theme } from "../lib/theme";
import { formatBytes, formatTimestamp, relativeTime } from "../lib/util";
import { makeTextTab } from "../state/tabs";
import type { TextTab } from "../types";
import { TreeBrowser, type TreeContext, type TreeNode } from "./TreeBrowser";

interface StorageBrowserProps {
  active: boolean;
  focused: boolean;
  width: number;
  height: number;
  projects: string[];
  activeProject?: string;
  exportDir: string;
  previewBytes: number;
  onOpenText: (tab: TextTab) => void;
  onInsertText: (text: string) => void;
  onCopy: (text: string, label: string) => void;
  onStatus: (message: string, kind?: "info" | "error" | "success") => void;
  onFocus: () => void;
}

function objectIcon(name: string): { icon: string; color: string } {
  const lower = name.toLowerCase();
  if (/\.(csv|tsv)(\.gz)?$/.test(lower)) return { icon: "▤", color: theme.green };
  if (/\.(json|jsonl|ndjson)(\.gz)?$/.test(lower)) return { icon: "{}", color: theme.orange };
  if (/\.(parquet|avro|orc)$/.test(lower)) return { icon: "▦", color: theme.cyan };
  if (/\.(sql|sqlx)$/.test(lower)) return { icon: "≡", color: theme.magenta };
  if (/\.(png|jpe?g|gif|webp|svg)$/.test(lower)) return { icon: "▣", color: theme.fgMuted };
  if (/\.(html?|txt|md|log|yaml|yml|xml)$/.test(lower)) return { icon: "·", color: theme.fg };
  return { icon: "·", color: theme.fgMuted };
}

function languageFor(name: string, contentType?: string): TextTab["language"] {
  const lower = name.toLowerCase();
  if (/\.(json|jsonl|ndjson)$/.test(lower) || contentType?.includes("json")) return "json";
  if (/\.(sql|sqlx)$/.test(lower)) return "sql";
  return "text";
}

export function StorageBrowser(props: StorageBrowserProps) {
  const { active, focused, width, height, projects, activeProject, exportDir, previewBytes, onOpenText, onInsertText, onCopy, onStatus, onFocus } = props;

  const entryNodes = (uri: string): ((force: boolean) => Promise<TreeNode[]>) => {
    return async (force) => {
      const entries = await listEntries(uri, force);
      return entries.map((e) => entryNode(e));
    };
  };

  const entryNode = (e: StorageEntry): TreeNode => {
    if (e.isPrefix) {
      return { key: `gcs:${e.uri}`, kind: "prefix", label: e.name, iconColor: theme.accent, labelColor: theme.accent, expandable: true, load: entryNodes(e.uri), data: e };
    }
    const ic = objectIcon(e.name);
    return {
      key: `gcs:${e.uri}`,
      kind: "object",
      label: e.name,
      icon: ic.icon,
      iconColor: ic.color,
      suffix: e.size !== undefined ? `  ${formatBytes(e.size)}` : "",
      expandable: false,
      data: e,
    };
  };

  const projectNode = (projectId: string): TreeNode => ({
    key: `gcs:project:${projectId}`,
    kind: "project",
    label: projectId,
    icon: "⊞",
    iconColor: theme.yellow,
    labelColor: theme.yellow,
    expandable: true,
    load: async (force) => {
      const buckets = await listBuckets(projectId, force);
      if (buckets.length === 0) return [{ key: `gcs:none:${projectId}`, kind: "info", label: "No buckets", labelColor: theme.fgDim, expandable: false }];
      return buckets.map((b) => ({
        key: `gcs:${b.uri}`,
        kind: "bucket",
        label: b.name,
        icon: "◫",
        iconColor: theme.cyan,
        suffix: b.location ? `  ${b.location.toLowerCase()}` : "",
        expandable: true,
        load: entryNodes(b.uri),
        data: { uri: b.uri, name: b.name + "/", isPrefix: true } as StorageEntry,
      }));
    },
  });

  const [roots, setRoots] = useState<TreeNode[]>(() => projects.map(projectNode));
  useEffect(() => {
    setRoots(projects.map(projectNode));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projects.join(",")]);

  const openObject = (e: StorageEntry) => {
    const tab = makeTextTab(`text:gcs:${e.uri}`, e.name, languageFor(e.name, e.contentType), {
      subtitle: e.uri,
      source: { type: "gcs", uri: e.uri, size: e.size },
      reload: async () => {
        const info = await describeObject(e.uri).catch(() => null);
        const size = info?.size ?? e.size;
        const meta: [string, string][] = [
          ["Size", formatBytes(size)],
          ["Type", info?.contentType ?? e.contentType ?? "–"],
          ["Updated", info?.updated ? formatTimestamp(Date.parse(info.updated)) : e.updated ? formatTimestamp(Date.parse(e.updated)) : "–"],
          ["Class", info?.storageClass ?? "–"],
          ["MD5", info?.md5 ?? "–"],
        ];
        const head = await headObject(e.uri, previewBytes, size);
        if (head.binary) {
          return { content: `(binary content, ${formatBytes(size)} — press d to download)`, meta };
        }
        let content = head.text;
        if (head.truncated) meta.push(["Preview", `first ${formatBytes(head.bytes)} of ${formatBytes(size)} (d downloads the whole object)`]);
        if (languageFor(e.name, info?.contentType) === "json" && !head.truncated) {
          try {
            content = JSON.stringify(JSON.parse(content), null, 2);
          } catch {
            // NDJSON or invalid JSON: show as-is
          }
        }
        return { content, meta };
      },
    });
    onOpenText(tab);
  };

  const handleActivate = (node: TreeNode) => {
    if (node.kind === "object") openObject(node.data as StorageEntry);
  };

  const handleKey = (key: KeyEvent, node: TreeNode | undefined, ctx: TreeContext): boolean => {
    void ctx;
    if (!node) return false;
    const e = node.data as StorageEntry | undefined;
    if (!e || (node.kind !== "object" && node.kind !== "prefix" && node.kind !== "bucket")) return false;
    switch (key.name) {
      case "y":
        onCopy(e.uri, e.uri);
        return true;
      case "i":
        onInsertText(`'${e.uri}'`);
        onStatus(`Inserted ${e.uri}`, "success");
        return true;
      case "x":
        onInsertText(externalTableSql(e.uri, activeProject));
        onStatus("Inserted CREATE EXTERNAL TABLE statement (edit dataset/table name)", "success");
        return true;
      case "l":
        if (key.shift) {
          onInsertText(loadDataSql(e.uri, activeProject));
          onStatus("Inserted LOAD DATA statement (edit dataset/table name)", "success");
          return true;
        }
        return false;
      case "d":
        if (node.kind !== "object" || key.ctrl) return false;
        onStatus(`Downloading ${e.name}…`);
        downloadObject(e.uri, exportDir)
          .then((path) => onStatus(`Downloaded to ${path}`, "success"))
          .catch((err) => onStatus(`Download failed: ${err.message}`, "error"));
        return true;
      default:
        return false;
    }
  };

  return (
    <TreeBrowser
      stateKey="storage"
      roots={roots}
      active={active}
      focused={focused}
      width={width}
      height={height}
      emptyText="No projects"
      onActivate={handleActivate}
      onKey={handleKey}
      onFocus={onFocus}
      onStatus={onStatus}
    />
  );
}
