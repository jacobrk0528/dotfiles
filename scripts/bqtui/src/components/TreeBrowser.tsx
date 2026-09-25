import { useEffect, useRef, useState } from "react";
import { useKeyboard } from "@opentui/react";
import type { BoxRenderable, KeyEvent, MouseEvent } from "@opentui/core";
import { theme } from "../lib/theme";
import { truncate } from "../lib/util";

export interface TreeNode {
  key: string;
  kind: string;
  label: string;
  icon?: string;
  iconColor?: string;
  labelColor?: string;
  suffix?: string;
  suffixColor?: string;
  expandable: boolean;
  /** Lazily loads children; result is cached until refreshed. */
  load?: (force: boolean) => Promise<TreeNode[]>;
  data?: unknown;
}

type Children = TreeNode[] | "loading" | { error: string };

export interface FlatTreeNode {
  node: TreeNode;
  depth: number;
  parentKey?: string;
}

export interface TreeContext {
  refresh: (node: TreeNode) => void;
  expand: (node: TreeNode) => void;
  collapse: (node: TreeNode) => void;
  isExpanded: (node: TreeNode) => boolean;
}

interface TreeBrowserProps {
  /** Persist expansion/cursor across unmounts (e.g. sidebar section switches). */
  stateKey: string;
  roots: TreeNode[] | "loading" | { error: string };
  active: boolean;
  focused: boolean;
  width: number;
  height: number;
  emptyText?: string;
  /** Enter on a non-expandable node (or on an expandable node when `activateExpandable`). */
  onActivate: (node: TreeNode, ctx: TreeContext) => void;
  /** Extra keys; return true when handled. */
  onKey?: (key: KeyEvent, node: TreeNode | undefined, ctx: TreeContext) => boolean;
  onFocus: () => void;
  onStatus?: (message: string, kind?: "info" | "error" | "success") => void;
}

interface PersistedState {
  expanded: Set<string>;
  children: Map<string, Children>;
  cursor: number;
  scroll: number;
}
const persisted = new Map<string, PersistedState>();

function stateFor(key: string): PersistedState {
  let s = persisted.get(key);
  if (!s) {
    s = { expanded: new Set(), children: new Map(), cursor: 0, scroll: 0 };
    persisted.set(key, s);
  }
  return s;
}

export function TreeBrowser(props: TreeBrowserProps) {
  const { stateKey, roots, active, focused, width, height, emptyText, onActivate, onKey, onFocus, onStatus } = props;
  const store = stateFor(stateKey);
  const [, force] = useState(0);
  const rerender = () => force((n) => n + 1);
  const listRef = useRef<BoxRenderable>(null);

  const loadChildren = async (node: TreeNode, forceReload = false) => {
    if (!node.load) return;
    store.children.set(node.key, "loading");
    rerender();
    try {
      const kids = await node.load(forceReload);
      store.children.set(node.key, kids);
    } catch (err: any) {
      store.children.set(node.key, { error: err.message ?? String(err) });
      onStatus?.(`${node.label}: ${err.message ?? err}`, "error");
    }
    rerender();
  };

  const ctx: TreeContext = {
    refresh: (node) => {
      if (node.expandable) {
        store.expanded.add(node.key);
        loadChildren(node, true);
      }
    },
    expand: (node) => {
      if (!node.expandable) return;
      store.expanded.add(node.key);
      if (!store.children.has(node.key)) loadChildren(node);
      rerender();
    },
    collapse: (node) => {
      store.expanded.delete(node.key);
      rerender();
    },
    isExpanded: (node) => store.expanded.has(node.key),
  };

  // Flatten.
  const flat: FlatTreeNode[] = [];
  const walk = (nodes: TreeNode[], depth: number, parentKey?: string) => {
    for (const n of nodes) {
      flat.push({ node: n, depth, parentKey });
      if (n.expandable && store.expanded.has(n.key)) {
        const kids = store.children.get(n.key);
        if (Array.isArray(kids)) walk(kids, depth + 1, n.key);
      }
    }
  };
  if (Array.isArray(roots)) walk(roots, 0);

  const cursor = Math.min(store.cursor, Math.max(0, flat.length - 1));
  const listHeight = Math.max(1, height - (flat.length > height ? 1 : 0));
  // Keep cursor visible.
  if (cursor < store.scroll) store.scroll = cursor;
  else if (cursor >= store.scroll + listHeight) store.scroll = cursor - listHeight + 1;
  store.scroll = Math.max(0, Math.min(store.scroll, Math.max(0, flat.length - listHeight)));

  const setCursor = (i: number) => {
    store.cursor = Math.max(0, Math.min(flat.length - 1, i));
    rerender();
  };

  useEffect(() => {
    // Ensure expanded nodes with no cache get loaded (e.g. after roots refresh).
    for (const f of flat) {
      if (f.node.expandable && store.expanded.has(f.node.key) && !store.children.has(f.node.key)) loadChildren(f.node);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roots]);

  useKeyboard((key) => {
    if (!active) return;
    // Read the live cursor: several keys can arrive before React re-renders.
    const cursor = Math.min(store.cursor, Math.max(0, flat.length - 1));
    const current = flat[cursor]?.node;
    switch (key.name) {
      case "j":
      case "down":
        setCursor(cursor + 1);
        return;
      case "k":
      case "up":
        setCursor(cursor - 1);
        return;
      case "pagedown":
        setCursor(cursor + listHeight);
        return;
      case "pageup":
        setCursor(cursor - listHeight);
        return;
      case "d":
        if (key.ctrl) {
          setCursor(cursor + Math.floor(listHeight / 2));
          return;
        }
        break;
      case "u":
        if (key.ctrl) {
          setCursor(cursor - Math.floor(listHeight / 2));
          return;
        }
        break;
      case "g":
        setCursor(key.shift ? flat.length - 1 : 0);
        return;
      case "l":
      case "right":
        if (current?.expandable && !store.expanded.has(current.key)) ctx.expand(current);
        return;
      case "h":
      case "left": {
        if (!current) return;
        if (current.expandable && store.expanded.has(current.key)) ctx.collapse(current);
        else {
          const depth = flat[cursor]!.depth;
          for (let i = cursor - 1; i >= 0; i--) {
            if (flat[i]!.depth < depth) {
              setCursor(i);
              break;
            }
          }
        }
        return;
      }
      case "return":
        if (!current) return;
        if (current.expandable) {
          if (store.expanded.has(current.key)) ctx.collapse(current);
          else ctx.expand(current);
          onActivate(current, ctx);
        } else onActivate(current, ctx);
        return;
      case "r":
        if (!key.ctrl && current) {
          if (current.expandable) ctx.refresh(current);
          else if (flat[cursor]!.parentKey) {
            const parent = flat.find((f) => f.node.key === flat[cursor]!.parentKey)?.node;
            if (parent) ctx.refresh(parent);
          }
          return;
        }
        break;
      default:
        break;
    }
    onKey?.(key, current, ctx);
  });

  const handleMouseDown = (e: MouseEvent) => {
    onFocus();
    const box = listRef.current as unknown as { y?: number } | null;
    const idx = e.y - (box?.y ?? 0) + store.scroll;
    if (idx >= 0 && idx < flat.length) setCursor(idx);
  };
  const handleScroll = (e: MouseEvent) => {
    const dir = e.scroll?.direction;
    const max = Math.max(0, flat.length - listHeight);
    if (dir === "down") store.scroll = Math.min(max, store.scroll + 3);
    else if (dir === "up") store.scroll = Math.max(0, store.scroll - 3);
    rerender();
  };

  const innerWidth = Math.max(10, width - 2);

  if (roots === "loading") {
    return (
      <box style={{ paddingLeft: 1 }}>
        <text fg={theme.yellow}>Loading…</text>
      </box>
    );
  }
  if (!Array.isArray(roots)) {
    return (
      <box style={{ paddingLeft: 1, flexDirection: "column" }}>
        <text fg={theme.red} wrapMode="word">
          {roots.error}
        </text>
      </box>
    );
  }

  return (
    <box style={{ flexDirection: "column", flexGrow: 1 }}>
      <box ref={listRef} style={{ flexDirection: "column", height: listHeight, overflow: "hidden" }} onMouseDown={handleMouseDown} onMouseScroll={handleScroll}>
        {flat.length === 0 ? <text fg={theme.fgDim}>{` ${emptyText ?? "(empty)"}`}</text> : null}
        {flat.slice(store.scroll, store.scroll + listHeight).map((f, vi) => {
          const i = store.scroll + vi;
          const selected = i === cursor;
          const n = f.node;
          const indent = "  ".repeat(f.depth);
          const state = n.expandable ? store.children.get(n.key) : undefined;
          const caret = n.expandable ? (store.expanded.has(n.key) ? "▾ " : "▸ ") : "  ";
          const icon = n.icon ?? "";
          let suffix = n.suffix ?? "";
          let suffixColor = n.suffixColor ?? theme.fgDim;
          if (state === "loading") suffix = " …";
          else if (state && typeof state === "object" && !Array.isArray(state)) {
            suffix = " ✗";
            suffixColor = theme.red;
          }
          const textWidth = innerWidth - indent.length - caret.length - icon.length - suffix.length - 2;
          return (
            <box key={n.key} style={{ height: 1 }}>
              <text wrapMode="none" bg={selected && focused ? theme.selectionBg : selected ? theme.headerBg : undefined}>
                <span>{" " + indent}</span>
                <span fg={theme.fgDim}>{caret}</span>
                <span fg={n.iconColor ?? theme.fg}>{icon}</span>
                <span fg={selected ? theme.selectionFg : (n.labelColor ?? theme.fg)}>{(icon ? " " : "") + truncate(n.label, Math.max(4, textWidth))}</span>
                <span fg={suffixColor}>{suffix}</span>
              </text>
            </box>
          );
        })}
      </box>
      {flat.length > listHeight ? (
        <box style={{ height: 1, paddingLeft: 1 }}>
          <text fg={theme.fgDim} wrapMode="none">{`${store.scroll + 1}-${Math.min(flat.length, store.scroll + listHeight)} of ${flat.length}`}</text>
        </box>
      ) : null}
    </box>
  );
}
