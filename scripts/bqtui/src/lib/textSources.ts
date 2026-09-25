// Rebuild a text tab's loader from its serialized source (session restore).
import { describeObject, headObject } from "./storage";
import { queryCompilationActions, queryInvocationActions, readFile, readSavedAsset, type DfRepository, type DfWorkspace } from "./dataform";
import { formatBytes, formatTimestamp, formatDuration, oneLine } from "./util";
import type { TextSource, TextTab } from "../types";

function repoFromName(name: string): DfRepository {
  const m = name.match(/^projects\/([^/]+)\/locations\/([^/]+)\/repositories\/([^/]+)/);
  return { name, id: m?.[3] ?? name, projectId: m?.[1] ?? "", location: m?.[2] ?? "", isSavedQuery: false };
}

export function reloadFor(source: TextSource | undefined, previewBytes: number): TextTab["reload"] | undefined {
  if (!source) return undefined;
  switch (source.type) {
    case "gcs":
      return async () => {
        const info = await describeObject(source.uri).catch(() => null);
        const size = info?.size ?? source.size;
        const meta: [string, string][] = [
          ["Size", formatBytes(size)],
          ["Type", info?.contentType ?? "–"],
          ["Updated", info?.updated ? formatTimestamp(Date.parse(info.updated)) : "–"],
          ["Class", info?.storageClass ?? "–"],
          ["MD5", info?.md5 ?? "–"],
        ];
        const head = await headObject(source.uri, previewBytes, size);
        if (head.binary) return { content: `(binary content, ${formatBytes(size)} — press d to download)`, meta };
        if (head.truncated) meta.push(["Preview", `first ${formatBytes(head.bytes)} of ${formatBytes(size)} (d downloads the whole object)`]);
        return { content: head.text, meta };
      };
    case "dataform-file": {
      const repo = repoFromName(source.repoName);
      const ws: DfWorkspace | null = source.workspaceName ? { name: source.workspaceName, id: source.workspaceName.split("/").pop() ?? "" } : null;
      return async () => ({ content: await readFile(repo, ws, source.path) });
    }
    case "dataform-action":
      return async () => {
        const actions = await queryCompilationActions(source.compilationName);
        const a = actions.find((x) => x.target === source.target);
        if (!a) throw new Error(`Action ${source.target} not found in compilation`);
        return {
          content: a.sql || "-- (no SQL for this action)",
          meta: [
            ["Target", a.target],
            ["Type", a.type],
            ["File", a.filePath ?? "–"],
            ["Depends on", a.dependencies.length ? a.dependencies.join(", ") : "–"],
          ],
        };
      };
    case "dataform-invocation":
      return async () => {
        const actions = await queryInvocationActions(source.invocationName);
        const a = actions.find((x) => x.target === source.target);
        if (!a) throw new Error(`Action ${source.target} not found in invocation`);
        return {
          content: a.sql || "-- (no SQL recorded)",
          meta: [
            ["Target", a.target],
            ["State", a.state],
            ["Started", a.startTime ? formatTimestamp(Date.parse(a.startTime)) : "–"],
            ["Duration", a.startTime && a.endTime ? formatDuration(Date.parse(a.endTime) - Date.parse(a.startTime)) : "–"],
            ...(a.failureReason ? ([["Failure", oneLine(a.failureReason, 400)]] as [string, string][]) : []),
          ],
        };
      };
    case "studio-asset":
      return async () => {
        const { content } = await readSavedAsset(repoFromName(source.repoName));
        try {
          return { content: JSON.stringify(JSON.parse(content), null, 2) };
        } catch {
          return { content };
        }
      };
    default:
      return undefined;
  }
}
