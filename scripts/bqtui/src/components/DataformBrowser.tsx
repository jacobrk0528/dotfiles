import { useEffect, useState } from "react";
import type { KeyEvent } from "@opentui/core";
import {
  cancelInvocation,
  consoleUrl,
  createCompilation,
  createInvocation,
  listCompilations,
  listConfigs,
  listInvocations,
  listRepositories,
  listWorkspaces,
  queryCompilationActions,
  queryDirectory,
  queryInvocationActions,
  readFile,
  readSavedAsset,
  type DfAction,
  type DfCompilation,
  type DfInvocation,
  type DfInvocationAction,
  type DfRepository,
  type DfWorkspace,
} from "../lib/dataform";
import { invalidateCache } from "../lib/gcloud";
import { theme } from "../lib/theme";
import { formatDuration, formatTimestamp, oneLine, relativeTime } from "../lib/util";
import { makeTextTab } from "../state/tabs";
import type { TextTab } from "../types";
import { TreeBrowser, type TreeContext, type TreeNode } from "./TreeBrowser";

interface DataformBrowserProps {
  active: boolean;
  focused: boolean;
  width: number;
  height: number;
  projects: string[];
  regions: string[];
  onOpenText: (tab: TextTab) => void;
  onOpenQuery: (title: string, sql: string) => void;
  onInsertText: (text: string) => void;
  onCopy: (text: string, label: string) => void;
  onStatus: (message: string, kind?: "info" | "error" | "success") => void;
  onConfirm: (message: string, action: () => void) => void;
  onFocus: () => void;
}

const ACTION_ICON: Record<string, { icon: string; color: string }> = {
  VIEW: { icon: "◇", color: theme.magenta },
  TABLE: { icon: "▦", color: theme.fg },
  INCREMENTAL: { icon: "▤", color: theme.cyan },
  MATERIALIZED_VIEW: { icon: "◆", color: theme.magenta },
  ASSERTION: { icon: "✓", color: theme.green },
  OPERATIONS: { icon: "⚙", color: theme.orange },
  DECLARATION: { icon: "⇲", color: theme.fgMuted },
  UNKNOWN: { icon: "?", color: theme.fgDim },
};

function stateStyle(state: string): { icon: string; color: string } {
  switch (state) {
    case "SUCCEEDED":
      return { icon: "✓", color: theme.green };
    case "FAILED":
      return { icon: "✗", color: theme.red };
    case "RUNNING":
      return { icon: "⟳", color: theme.yellow };
    case "CANCELLED":
    case "CANCELING":
      return { icon: "⊘", color: theme.fgDim };
    case "SKIPPED":
    case "DISABLED":
      return { icon: "–", color: theme.fgDim };
    default:
      return { icon: "·", color: theme.fgMuted };
  }
}

function fileLanguage(path: string): TextTab["language"] {
  if (path.endsWith(".sqlx") || path.endsWith(".sql")) return path.endsWith(".sqlx") ? "sqlx" : "sql";
  if (path.endsWith(".json")) return "json";
  return "text";
}

function timeRange(start?: string, end?: string): string {
  if (!start) return "";
  const s = Date.parse(start);
  const e = end ? Date.parse(end) : undefined;
  return `${relativeTime(s)}${e ? ` · ${formatDuration(e - s)}` : ""}`;
}

export function DataformBrowser(props: DataformBrowserProps) {
  const { active, focused, width, height, projects, regions, onOpenText, onOpenQuery, onInsertText, onCopy, onStatus, onConfirm, onFocus } = props;
  const [, bump] = useState(0);
  const rerender = () => bump((n) => n + 1);

  // ---------------------------------------------------------------- node builders
  const fileNodes = (repo: DfRepository, ws: DfWorkspace | null, path: string): (() => Promise<TreeNode[]>) => {
    return async () => {
      const entries = await queryDirectory(repo, ws, path);
      return entries
        .filter((e) => !e.path.split("/").pop()?.startsWith(".") && !e.path.startsWith("node_modules"))
        .map((e) => {
          const name = e.path.split("/").pop() ?? e.path;
          return e.isDir
            ? { key: `df:dir:${ws?.name ?? repo.name}:${e.path}`, kind: "dir", label: name, iconColor: theme.accent, labelColor: theme.accent, expandable: true, load: fileNodes(repo, ws, e.path), data: { repo, ws, path: e.path } }
            : {
                key: `df:file:${ws?.name ?? repo.name}:${e.path}`,
                kind: "file",
                label: name,
                icon: name.endsWith(".sqlx") ? "◇" : name.endsWith(".js") ? "λ" : "·",
                iconColor: name.endsWith(".sqlx") ? theme.magenta : theme.fgMuted,
                expandable: false,
                data: { repo, ws, path: e.path },
              };
        });
    };
  };

  const compilationNode = (repo: DfRepository, c: DfCompilation): TreeNode => ({
    key: `df:cr:${c.name}`,
    kind: "compilation",
    label: `${c.createTime ? formatTimestamp(Date.parse(c.createTime)) : c.id.slice(0, 8)}  ${c.workspace ? `ws:${c.workspace}` : c.releaseConfig ? `release:${c.releaseConfig}` : c.gitCommitish ?? ""}`,
    icon: c.errorCount > 0 ? "✗" : "●",
    iconColor: c.errorCount > 0 ? theme.red : theme.green,
    suffix: c.errorCount > 0 ? ` ${c.errorCount} error${c.errorCount === 1 ? "" : "s"}` : "",
    suffixColor: theme.red,
    expandable: true,
    load: async (force) => {
      const actions = await queryCompilationActions(c.name, force);
      const nodes: TreeNode[] = actions.map((a) => {
        const st = ACTION_ICON[a.type] ?? ACTION_ICON.UNKNOWN!;
        return {
          key: `df:cra:${c.name}:${a.target}`,
          kind: "action",
          label: a.target,
          icon: st.icon,
          iconColor: st.color,
          labelColor: a.disabled ? theme.fgDim : theme.fg,
          suffix: a.disabled ? " disabled" : "",
          expandable: false,
          data: { repo, compilation: c, action: a },
        };
      });
      if (c.errors.length > 0) {
        nodes.unshift(
          ...c.errors.slice(0, 20).map((e, i) => ({
            key: `df:crerr:${c.name}:${i}`,
            kind: "compile-error",
            label: `${e.path ? e.path + ": " : ""}${oneLine(e.message, 200)}`,
            icon: "✗",
            iconColor: theme.red,
            labelColor: theme.red,
            expandable: false,
            data: { repo, compilation: c, error: e },
          })),
        );
      }
      return nodes;
    },
    data: { repo, compilation: c },
  });

  const invocationNode = (repo: DfRepository, inv: DfInvocation): TreeNode => {
    const st = stateStyle(inv.state);
    return {
      key: `df:wi:${inv.name}`,
      kind: "invocation",
      label: `${inv.startTime ? formatTimestamp(Date.parse(inv.startTime)) : inv.id}  ${inv.state.toLowerCase()}`,
      icon: st.icon,
      iconColor: st.color,
      labelColor: inv.state === "FAILED" ? theme.red : inv.state === "RUNNING" ? theme.yellow : theme.fg,
      suffix: inv.startTime ? `  ${timeRange(inv.startTime, inv.endTime)}` : "",
      expandable: true,
      load: async (force) => {
        const actions = await queryInvocationActions(inv.name, force);
        return actions.map((a) => {
          const s = stateStyle(a.state);
          return {
            key: `df:wia:${inv.name}:${a.target}`,
            kind: "invocation-action",
            label: a.target,
            icon: s.icon,
            iconColor: s.color,
            labelColor: a.state === "FAILED" ? theme.red : theme.fg,
            suffix: a.startTime && a.endTime ? `  ${formatDuration(Date.parse(a.endTime) - Date.parse(a.startTime))}` : "",
            expandable: false,
            data: { repo, invocation: inv, action: a },
          };
        });
      },
      data: { repo, invocation: inv },
    };
  };

  const repoNode = (repo: DfRepository): TreeNode => ({
    key: `df:repo:${repo.name}`,
    kind: "repo",
    label: `${repo.displayName ?? repo.id}`,
    icon: "⎇",
    iconColor: theme.yellow,
    labelColor: theme.yellow,
    suffix: `  ${repo.location}${repo.gitUrl ? " · git" : ""}`,
    expandable: true,
    load: async () => [
      {
        key: `df:wsroot:${repo.name}`,
        kind: "folder",
        label: "Workspaces",
        iconColor: theme.accent,
        labelColor: theme.accent,
        expandable: true,
        load: async (force) => {
          const ws = await listWorkspaces(repo, force);
          return ws.map((w) => ({
            key: `df:ws:${w.name}`,
            kind: "workspace",
            label: w.id,
            icon: "⌂",
            iconColor: theme.cyan,
            expandable: true,
            load: fileNodes(repo, w, ""),
            data: { repo, ws: w },
          }));
        },
        data: { repo },
      },
      // Git-hosted repositories can only be browsed through workspaces.
      ...(repo.gitUrl
        ? []
        : [
            {
              key: `df:head:${repo.name}`,
              kind: "folder",
              label: "Files @ HEAD",
              iconColor: theme.accent,
              labelColor: theme.accent,
              expandable: true,
              load: fileNodes(repo, null, ""),
              data: { repo },
            } as TreeNode,
          ]),
      {
        key: `df:crroot:${repo.name}`,
        kind: "folder",
        label: "Compilations",
        iconColor: theme.accent,
        labelColor: theme.accent,
        expandable: true,
        load: async (force) => (await listCompilations(repo, 15, force)).map((c) => compilationNode(repo, c)),
        data: { repo },
      },
      {
        key: `df:wiroot:${repo.name}`,
        kind: "folder",
        label: "Invocations",
        iconColor: theme.accent,
        labelColor: theme.accent,
        expandable: true,
        load: async (force) => (await listInvocations(repo, 15, force)).map((i) => invocationNode(repo, i)),
        data: { repo },
      },
      {
        key: `df:cfgroot:${repo.name}`,
        kind: "folder",
        label: "Schedules",
        iconColor: theme.accent,
        labelColor: theme.accent,
        expandable: true,
        load: async (force) => {
          const cfgs = await listConfigs(repo, force);
          return cfgs.map((c) => ({
            key: `df:cfg:${repo.name}:${c.kind}:${c.id}`,
            kind: "config",
            label: `${c.kind === "release" ? "release" : "workflow"} ${c.id}${c.cronSchedule ? `  ⏱ ${c.cronSchedule}${c.timeZone ? ` ${c.timeZone}` : ""}` : ""}${c.gitCommitish ? `  @${c.gitCommitish}` : ""}${c.releaseConfig ? `  ← ${c.releaseConfig}` : ""}`,
            icon: c.kind === "release" ? "⇪" : "⏱",
            iconColor: theme.orange,
            expandable: false,
            data: { repo, config: c },
          }));
        },
        data: { repo },
      },
    ],
    data: { repo },
  });

  const projectNode = (projectId: string): TreeNode => ({
    key: `df:project:${projectId}`,
    kind: "project",
    label: projectId,
    icon: "⊞",
    iconColor: theme.yellow,
    labelColor: theme.yellow,
    expandable: true,
    load: async (force) => {
      const repos = await listRepositories(projectId, regions, force);
      const real = repos.filter((r) => !r.isSavedQuery);
      const saved = repos.filter((r) => r.assetType === "sql");
      const other = repos.filter((r) => r.isSavedQuery && r.assetType !== "sql");
      const nodes: TreeNode[] = real.map(repoNode);
      if (saved.length > 0) {
        nodes.push({
          key: `df:saved:${projectId}`,
          kind: "folder",
          label: `Saved queries (BigQuery Studio)`,
          iconColor: theme.accent,
          labelColor: theme.accent,
          suffix: `  ${saved.length}`,
          expandable: true,
          load: async () =>
            saved.map((r) => ({
              key: `df:sq:${r.name}`,
              kind: "saved-query",
              label: r.displayName ?? r.id,
              icon: "≡",
              iconColor: theme.green,
              expandable: false,
              data: { repo: r },
            })),
        });
      }
      if (other.length > 0) {
        nodes.push({
          key: `df:other:${projectId}`,
          kind: "folder",
          label: `Notebooks & canvases`,
          iconColor: theme.accent,
          labelColor: theme.accent,
          suffix: `  ${other.length}`,
          expandable: true,
          load: async () =>
            other.map((r) => ({
              key: `df:asset:${r.name}`,
              kind: "asset",
              label: `${r.displayName ?? r.id}`,
              icon: "▣",
              iconColor: theme.fgMuted,
              suffix: `  ${r.assetType}`,
              expandable: false,
              data: { repo: r },
            })),
        });
      }
      if (nodes.length === 0) {
        nodes.push({ key: `df:none:${projectId}`, kind: "info", label: "No Dataform repositories in scanned regions", labelColor: theme.fgDim, expandable: false });
      }
      return nodes;
    },
  });

  const [roots, setRoots] = useState<TreeNode[]>(() => projects.map(projectNode));
  useEffect(() => {
    setRoots(projects.map(projectNode));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projects.join(","), regions.join(",")]);

  // ---------------------------------------------------------------- actions
  const openFile = (repo: DfRepository, ws: DfWorkspace | null, path: string) => {
    const tab = makeTextTab(`text:df-file:${ws?.name ?? repo.name}:${path}`, path.split("/").pop() ?? path, fileLanguage(path), {
      subtitle: `${repo.displayName ?? repo.id}${ws ? ` · workspace ${ws.id}` : ` · ${repo.defaultBranch ?? "HEAD"}`} · ${path}`,
      source: { type: "dataform-file", repoName: repo.name, workspaceName: ws?.name ?? null, path },
      reload: async () => ({ content: await readFile(repo, ws, path) }),
    });
    onOpenText(tab);
  };

  const openAction = (repo: DfRepository, c: DfCompilation, a: DfAction) => {
    const tab = makeTextTab(`text:df-action:${c.name}:${a.target}`, a.target.split(".").pop() ?? a.target, "sql", {
      subtitle: `${repo.displayName ?? repo.id} · compiled ${a.type.toLowerCase()} · ${a.filePath ?? ""}`,
      meta: [
        ["Target", a.target],
        ["Type", a.type],
        ["File", a.filePath ?? "–"],
        ["Depends on", a.dependencies.length ? a.dependencies.join(", ") : "–"],
        ["Compiled", c.createTime ? formatTimestamp(Date.parse(c.createTime)) : c.id],
      ],
      source: { type: "dataform-action", compilationName: c.name, target: a.target },
      reload: async () => ({ content: a.sql || "-- (no SQL for this action)" }),
    });
    onOpenText(tab);
  };

  const openInvocationAction = (repo: DfRepository, inv: DfInvocation, a: DfInvocationAction) => {
    const tab = makeTextTab(`text:df-inv:${inv.name}:${a.target}`, a.target.split(".").pop() ?? a.target, "sql", {
      subtitle: `${repo.displayName ?? repo.id} · invocation ${inv.id} · ${a.state.toLowerCase()}`,
      meta: [
        ["Target", a.target],
        ["State", a.state],
        ["Started", a.startTime ? formatTimestamp(Date.parse(a.startTime)) : "–"],
        ["Duration", a.startTime && a.endTime ? formatDuration(Date.parse(a.endTime) - Date.parse(a.startTime)) : "–"],
        ...(a.failureReason ? ([["Failure", oneLine(a.failureReason, 400)]] as [string, string][]) : []),
      ],
      source: { type: "dataform-invocation", invocationName: inv.name, target: a.target },
      reload: async () => ({ content: a.sql || "-- (no SQL recorded)" }),
    });
    onOpenText(tab);
  };

  const openSavedQuery = async (repo: DfRepository) => {
    onStatus(`Loading ${repo.displayName ?? repo.id}…`);
    try {
      const { content } = await readSavedAsset(repo);
      onOpenQuery(repo.displayName ?? repo.id, content);
      onStatus(`Opened saved query "${repo.displayName ?? repo.id}" in a new tab`, "success");
    } catch (err: any) {
      onStatus(`Could not load saved query: ${err.message}`, "error");
    }
  };

  const openAsset = (repo: DfRepository) => {
    const tab = makeTextTab(`text:studio:${repo.name}`, repo.displayName ?? repo.id, "json", {
      subtitle: `BigQuery Studio ${repo.assetType} · ${repo.location}`,
      source: { type: "studio-asset", repoName: repo.name },
      reload: async () => {
        const { content } = await readSavedAsset(repo);
        try {
          return { content: JSON.stringify(JSON.parse(content), null, 2) };
        } catch {
          return { content };
        }
      },
    });
    onOpenText(tab);
  };

  const handleActivate = (node: TreeNode) => {
    const d = node.data as any;
    switch (node.kind) {
      case "file":
        openFile(d.repo, d.ws, d.path);
        break;
      case "action":
        openAction(d.repo, d.compilation, d.action);
        break;
      case "invocation-action":
        openInvocationAction(d.repo, d.invocation, d.action);
        break;
      case "saved-query":
        openSavedQuery(d.repo);
        break;
      case "asset":
        openAsset(d.repo);
        break;
      case "compile-error":
        onStatus(`${d.error.path ?? ""} ${d.error.message}`, "error");
        break;
      default:
        break;
    }
  };

  const handleKey = (key: KeyEvent, node: TreeNode | undefined, ctx: TreeContext): boolean => {
    if (!node) return false;
    const d = (node.data ?? {}) as any;
    if (key.name === "y") {
      if (node.kind === "repo") onCopy(consoleUrl(d.repo), "console URL");
      else if (node.kind === "action" || node.kind === "invocation-action") onCopy(`\`${d.action.target}\``, d.action.target);
      else if (node.kind === "file" || node.kind === "dir") onCopy(d.path, d.path);
      else if (node.kind === "invocation") onCopy(d.invocation.id, "invocation id");
      else if (node.kind === "compilation") onCopy(d.compilation.id, "compilation id");
      else if (node.kind === "saved-query" || node.kind === "asset") onCopy(d.repo.displayName ?? d.repo.id, "name");
      return true;
    }
    if (key.name === "i" && (node.kind === "action" || node.kind === "invocation-action")) {
      onInsertText(`\`${d.action.target}\``);
      onStatus(`Inserted ${d.action.target}`, "success");
      return true;
    }
    if (key.name === "e") {
      if (node.kind === "action") {
        onOpenQuery(d.action.target.split(".").pop(), d.action.sql);
        return true;
      }
      if (node.kind === "invocation-action") {
        onOpenQuery(d.action.target.split(".").pop(), d.action.sql);
        return true;
      }
    }
    if (key.name === "c" && node.kind === "workspace") {
      onStatus(`Compiling workspace ${d.ws.id}…`);
      createCompilation(d.repo, d.ws)
        .then((c) => {
          invalidateCache(`df:cr:${d.repo.name}`);
          if (c.errorCount > 0) onStatus(`Compiled with ${c.errorCount} error${c.errorCount === 1 ? "" : "s"}: ${oneLine(c.errors[0]?.message ?? "", 100)}`, "error");
          else onStatus(`Compiled ${d.ws.id} successfully (see Compilations)`, "success");
          rerender();
        })
        .catch((err) => onStatus(`Compile failed: ${err.message}`, "error"));
      return true;
    }
    if (key.name === "x") {
      if (node.kind === "compilation") {
        const c: DfCompilation = d.compilation;
        if (c.errorCount > 0) {
          onStatus("This compilation has errors; fix them before running", "error");
          return true;
        }
        onConfirm(`Run all actions from compilation ${c.id.slice(0, 8)} in ${d.repo.displayName ?? d.repo.id}?`, () => {
          onStatus("Starting workflow invocation…");
          createInvocation(d.repo, c.name)
            .then((inv) => {
              invalidateCache(`df:wi:${d.repo.name}`);
              onStatus(`Invocation ${inv.id} started (${inv.state.toLowerCase()}). Refresh Invocations with r.`, "success");
            })
            .catch((err) => onStatus(`Could not start invocation: ${err.message}`, "error"));
        });
        return true;
      }
      if (node.kind === "invocation" && d.invocation.state === "RUNNING") {
        onConfirm(`Cancel running invocation ${d.invocation.id}?`, () => {
          cancelInvocation(d.invocation.name)
            .then(() => {
              invalidateCache(`df:wi:${d.repo.name}`);
              onStatus("Cancellation requested", "success");
            })
            .catch((err) => onStatus(`Cancel failed: ${err.message}`, "error"));
        });
        return true;
      }
    }
    void ctx;
    return false;
  };

  return (
    <TreeBrowser
      stateKey="dataform"
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
