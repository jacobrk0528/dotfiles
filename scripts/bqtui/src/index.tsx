import { appendFileSync } from "node:fs";
import { Component, type ReactNode } from "react";
import { createCliRenderer } from "@opentui/core";
import { createRoot } from "@opentui/react";
import { App } from "./App";
import { loadConfig, loadSession } from "./lib/config";
import { getDefaultProject } from "./lib/bq";

const CRASH_LOG = "/tmp/bqtui-crash.log";
function logCrash(label: string, err: unknown) {
  const text = err instanceof Error ? `${err.message}\n${err.stack ?? ""}` : String(err);
  try {
    appendFileSync(CRASH_LOG, `[${new Date().toISOString()}] ${label}: ${text}\n`);
  } catch {
    // ignore
  }
}
process.on("uncaughtException", (err) => logCrash("uncaughtException", err));
process.on("unhandledRejection", (err) => logCrash("unhandledRejection", err));

class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };
  static getDerivedStateFromError(error: Error) {
    return { error };
  }
  componentDidCatch(error: Error, info: { componentStack?: string }) {
    logCrash("render", `${error.message}\n${error.stack}\n${info.componentStack ?? ""}`);
  }
  render() {
    if (this.state.error) {
      return (
        <box style={{ padding: 1, flexDirection: "column" }}>
          <text fg="red">bqtui crashed while rendering:</text>
          <text>{this.state.error.message}</text>
          <text fg="#888888">{`Details in ${CRASH_LOG}. Press Ctrl+C to exit.`}</text>
        </box>
      );
    }
    return this.props.children;
  }
}

const [config, session, defaultProject] = await Promise.all([loadConfig(), loadSession(), getDefaultProject()]);

const renderer = await createCliRenderer({
  exitOnCtrlC: true,
  useKittyKeyboard: {},
  consoleMode: "disabled",
  targetFps: 60,
});

createRoot(renderer).render(
  <ErrorBoundary>
    <App config={config} session={session} defaultProject={defaultProject} />
  </ErrorBoundary>,
);
