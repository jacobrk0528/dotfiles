import { appendFileSync } from "node:fs";
import { Component, type ReactNode } from "react";
import { createCliRenderer } from "@opentui/core";
import { createRoot } from "@opentui/react";
import { App } from "./App";

const CRASH_LOG = "/tmp/agents-crash.log";
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
          <text fg="red">agents crashed while rendering:</text>
          <text>{this.state.error.message}</text>
          <text fg="#888888">{`Details in ${CRASH_LOG}. Press Ctrl+C to exit.`}</text>
        </box>
      );
    }
    return this.props.children;
  }
}

const renderer = await createCliRenderer({
  exitOnCtrlC: true,
  useKittyKeyboard: {},
  consoleMode: "disabled",
  targetFps: 30,
});

createRoot(renderer).render(
  <ErrorBoundary>
    <App />
  </ErrorBoundary>,
);
