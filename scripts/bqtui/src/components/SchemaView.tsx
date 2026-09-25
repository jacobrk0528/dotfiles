import { useRef } from "react";
import type { ScrollBoxRenderable } from "@opentui/core";
import type { SchemaField, TableInfo } from "../lib/bq";
import { theme, typeColor } from "../lib/theme";
import { formatBytes, formatNumber, formatTimestamp, padRight, truncate } from "../lib/util";
import { HighlightedSql } from "./HighlightedSql";
import type { SchemaTab } from "../types";

interface SchemaViewProps {
  tab: SchemaTab;
  focused: boolean;
  width: number;
  scrollRef?: React.Ref<ScrollBoxRenderable>;
}

interface FlatField {
  field: SchemaField;
  depth: number;
  path: string;
}

function flattenFields(fields: SchemaField[], depth = 0, prefix = ""): FlatField[] {
  const out: FlatField[] = [];
  for (const f of fields) {
    const path = prefix ? `${prefix}.${f.name}` : f.name;
    out.push({ field: f, depth, path });
    if (f.fields && f.fields.length > 0) out.push(...flattenFields(f.fields, depth + 1, path));
  }
  return out;
}

function typeBadge(type: string): { label: string; color: string } {
  switch (type) {
    case "VIEW":
      return { label: "VIEW", color: theme.magenta };
    case "MATERIALIZED_VIEW":
      return { label: "MATERIALIZED VIEW", color: theme.magenta };
    case "EXTERNAL":
      return { label: "EXTERNAL", color: theme.orange };
    case "SNAPSHOT":
      return { label: "SNAPSHOT", color: theme.cyan };
    default:
      return { label: "TABLE", color: theme.accent };
  }
}

function DetailRow({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <text>
      <span fg={theme.fgDim}>{padRight(label, 14)}</span>
      <span fg={color ?? theme.fg}>{value}</span>
    </text>
  );
}

export function SchemaView({ tab, focused, width, scrollRef }: SchemaViewProps) {
  const localRef = useRef<ScrollBoxRenderable>(null);
  const fullName = `${tab.projectId}.${tab.datasetId}.${tab.tableId}`;

  if (tab.info === "loading") {
    return (
      <box style={{ padding: 1 }}>
        <text fg={theme.yellow}>{`Loading ${fullName}…`}</text>
      </box>
    );
  }
  if (typeof tab.info === "object" && "error" in tab.info) {
    return (
      <box style={{ padding: 1, flexDirection: "column" }}>
        <text fg={theme.red}>{`Failed to load ${fullName}`}</text>
        <text fg={theme.fgMuted}>{tab.info.error}</text>
        <text fg={theme.fgDim}>Press r to retry.</text>
      </box>
    );
  }

  const info: TableInfo = tab.info;
  const badge = typeBadge(info.type);
  const fields = flattenFields(info.schema);
  const nameWidth = Math.min(40, Math.max(12, ...fields.map((f) => f.field.name.length + f.depth * 2)));
  const typeWidth = 12;
  const modeWidth = 9;
  const descWidth = Math.max(10, width - nameWidth - typeWidth - modeWidth - 12);

  const partition = info.timePartitioning
    ? `${info.timePartitioning.type}${info.timePartitioning.field ? ` on ${info.timePartitioning.field}` : " (ingestion time)"}${
        info.timePartitioning.requirePartitionFilter ? " · filter required" : ""
      }`
    : info.rangePartitioning
      ? `RANGE on ${info.rangePartitioning.field}`
      : "none";

  return (
    <scrollbox
      ref={scrollRef ?? localRef}
      focused={focused}
      style={{ flexGrow: 1 }}
      rootOptions={{ backgroundColor: theme.bg }}
      viewportOptions={{ backgroundColor: theme.bg }}
      contentOptions={{ flexDirection: "column", paddingLeft: 1, paddingRight: 1 }}
    >
      <text>
        <span fg={badge.color}>{`[${badge.label}] `}</span>
        <span fg={theme.fg}>{fullName}</span>
      </text>
      {info.description ? <text fg={theme.fgMuted}>{truncate(info.description.replace(/\s+/g, " ").trim(), width - 4)}</text> : null}
      <text fg={theme.fgDim}>{"p preview · i insert reference · y copy name · r refresh"}</text>
      <text> </text>

      <text fg={theme.yellow}>Details</text>
      <DetailRow label="Rows" value={formatNumber(info.numRows)} />
      <DetailRow label="Size" value={formatBytes(info.numBytes)} />
      <DetailRow label="Location" value={info.location ?? "–"} />
      <DetailRow label="Partitioning" value={partition} color={info.timePartitioning || info.rangePartitioning ? theme.cyan : theme.fg} />
      {info.numPartitions !== undefined ? <DetailRow label="Partitions" value={formatNumber(info.numPartitions)} /> : null}
      <DetailRow label="Clustering" value={info.clustering?.length ? info.clustering.join(", ") : "none"} color={info.clustering?.length ? theme.cyan : theme.fg} />
      <DetailRow label="Created" value={formatTimestamp(info.creationTime)} />
      <DetailRow label="Modified" value={formatTimestamp(info.lastModifiedTime)} />
      {info.expirationTime ? <DetailRow label="Expires" value={formatTimestamp(info.expirationTime)} color={theme.orange} /> : null}
      {info.labels && Object.keys(info.labels).length > 0 ? (
        <DetailRow
          label="Labels"
          value={Object.entries(info.labels)
            .map(([k, v]) => `${k}=${v}`)
            .join(", ")}
        />
      ) : null}
      <text> </text>

      <text fg={theme.yellow}>{`Schema (${fields.length} field${fields.length === 1 ? "" : "s"})`}</text>
      <text bg={theme.headerBg}>
        <span fg={theme.accent}>{padRight("Field", nameWidth)}</span>
        <span> </span>
        <span fg={theme.accent}>{padRight("Type", typeWidth)}</span>
        <span> </span>
        <span fg={theme.accent}>{padRight("Mode", modeWidth)}</span>
        <span> </span>
        <span fg={theme.accent}>{padRight("Description", descWidth)}</span>
      </text>
      {fields.length === 0 ? <text fg={theme.fgDim}>(no schema)</text> : null}
      {fields.map((f, i) => {
        const indent = "  ".repeat(f.depth) + (f.depth > 0 ? "└ " : "");
        const desc = (f.field.description ?? "").replace(/\s+/g, " ").trim();
        return (
          <text key={f.path} bg={i % 2 === 1 ? theme.zebra : undefined}>
            <span fg={f.depth > 0 ? theme.fgMuted : theme.fg}>{padRight(indent + f.field.name, nameWidth)}</span>
            <span> </span>
            <span fg={typeColor(f.field.type)}>{padRight(f.field.type, typeWidth)}</span>
            <span> </span>
            <span fg={f.field.mode === "REQUIRED" ? theme.orange : f.field.mode === "REPEATED" ? theme.yellow : theme.fgMuted}>
              {padRight(f.field.mode, modeWidth)}
            </span>
            <span> </span>
            <span fg={theme.fgMuted}>{padRight(desc, descWidth)}</span>
          </text>
        );
      })}

      {info.viewQuery ? (
        <box style={{ flexDirection: "column", marginTop: 1 }}>
          <text fg={theme.yellow}>View definition</text>
          <HighlightedSql sql={info.viewQuery} lineNumbers />
        </box>
      ) : null}
      <text> </text>
    </scrollbox>
  );
}
