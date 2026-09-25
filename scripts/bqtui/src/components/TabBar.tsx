import { theme } from "../lib/theme";
import { truncate } from "../lib/util";
import type { Tab } from "../types";

interface TabBarProps {
  tabs: Tab[];
  activeId: string;
  width: number;
  onSelect: (id: string) => void;
}

function tabLabel(tab: Tab): { icon: string; title: string; suffix: string } {
  if (tab.kind === "schema") {
    return { icon: "▤", title: tab.title, suffix: "" };
  }
  if (tab.kind === "text") {
    return { icon: tab.language === "sql" || tab.language === "sqlx" ? "◇" : "·", title: tab.title, suffix: tab.content === "loading" ? " …" : "" };
  }
  const suffix = tab.runningJobId ? " ⟳" : tab.dirty ? " •" : "";
  return { icon: "≡", title: tab.title, suffix };
}

export function TabBar({ tabs, activeId, width, onSelect }: TabBarProps) {
  // Budget the title width so all tabs fit on one row when possible.
  const perTab = Math.max(8, Math.min(28, Math.floor(width / Math.max(1, tabs.length)) - 5));
  return (
    <box style={{ flexDirection: "row", height: 1, backgroundColor: theme.tabInactiveBg, width: "100%" }}>
      {tabs.map((tab, i) => {
        const active = tab.id === activeId;
        const { icon, title, suffix } = tabLabel(tab);
        return (
          <box
            key={tab.id}
            onMouseDown={() => onSelect(tab.id)}
            style={{
              paddingLeft: 1,
              paddingRight: 1,
              backgroundColor: active ? theme.tabActiveBg : theme.tabInactiveBg,
              height: 1,
            }}
          >
            <text fg={active ? theme.fg : theme.fgMuted}>
              <span fg={active ? theme.yellow : theme.fgDim}>{`${i + 1} `}</span>
              <span fg={tab.kind === "schema" ? theme.cyan : tab.kind === "text" ? theme.magenta : theme.accent}>{icon}</span>
              <span>{` ${truncate(title, perTab)}`}</span>
              <span fg={tab.kind === "query" && tab.runningJobId ? theme.yellow : theme.orange}>{suffix}</span>
            </text>
          </box>
        );
      })}
    </box>
  );
}
