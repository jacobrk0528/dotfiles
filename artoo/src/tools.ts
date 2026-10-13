// Tools for the answer route (answer.ts): local facts the model can't know on its own.
// Everything a tool returns goes to OpenAI, so it's redacted first (privacy.ts).
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { Confirm } from "./confirm.ts";
import { runTask } from "./planner.ts";
import { runShell } from "./shell.ts";
import type { DesktopOrigin } from "./desktop-session.ts";

export type Location = { city?: string; region?: string; country?: string; timezone?: string };

const LOCATION_CACHE = join(homedir(), ".cache", "artoo", "location.json");
const LOCATION_TTL = 6 * 60 * 60 * 1000;

/**
 * Approximate location: JEV_CITY / JEV_REGION / JEV_COUNTRY / JEV_TIMEZONE from .env win;
 * otherwise an IP lookup (ipinfo.io), cached for six hours. On a VPN the IP lookup reports
 * the VPN server's city, so set the env vars if that matters.
 */
export async function location(): Promise<Location | undefined> {
  const { JEV_CITY: city, JEV_REGION: region, JEV_COUNTRY: country, JEV_TIMEZONE: timezone } = process.env;
  if (city || region || country || timezone) return { city, region, country, timezone };
  try {
    const cached = JSON.parse(readFileSync(LOCATION_CACHE, "utf8"));
    if (Date.now() - cached.t < LOCATION_TTL) return cached.location;
  } catch {}
  try {
    const res = await fetch("https://ipinfo.io/json", { signal: AbortSignal.timeout(3000) });
    const { city, region, country, timezone } = (await res.json()) as Location;
    const loc = { city, region, country, timezone };
    mkdirSync(join(homedir(), ".cache", "artoo"), { recursive: true });
    writeFileSync(LOCATION_CACHE, JSON.stringify({ t: Date.now(), location: loc }));
    return loc;
  } catch {
    return undefined;
  }
}

export const describeLocation = (l?: Location) =>
  l ? [l.city, l.region, l.country].filter(Boolean).join(", ") + (l.timezone ? ` (${l.timezone})` : "") : "unknown";

/** Function tools in Responses API shape. */
export const TOOLS = [
  {
    type: "function",
    name: "desktop_task",
    description: "Inspect and use the user's real desktop to answer a question or complete a task. Finds apps across all monitors and hidden/special workspaces, opens them, reads screenshots, searches, clicks, types and scrolls. Use for Slack/messages, browser/app content, 'what is on my screen', or any question requiring navigation. It can open the correct conversation even if another one is selected. Reading and navigation are automatic; writes always ask. Returns a verified answer/result. lookup restores the original workspace/window afterward.",
    parameters: {
      type: "object", additionalProperties: false, required: ["goal", "mode"],
      properties: {
        goal: { type: "string", description: "The full user goal, including the person/app and what to read or do" },
        mode: { type: "string", enum: ["lookup", "action"], description: "lookup for information requests; action when the user wants a lasting navigation/action result" },
      },
    },
    strict: true,
  },
  {
    type: "function",
    name: "run_command",
    description:
      "Run a shell command (bash) on the user's computer and get its output. Use it for anything about this machine: " +
      "hardware specs, disk space, memory, processes, installed software, network, files, Hyprland windows and monitors. " +
      "Use a single read-only command when possible. Writes and commands not recognized as read-only ask first. Use desktop_task for reading/operating apps instead of inspecting app caches or scripting keyboard input.",
    parameters: {
      type: "object",
      properties: {
        command: { type: "string", description: "The bash command line" },
        why: { type: "string", description: "A few words on what this finds out or does, shown to the user" },
      },
      required: ["command", "why"],
      additionalProperties: false,
    },
    strict: true,
  },
];

type ToolIO = { status: (text: string) => void; confirm: Confirm; log: (type: string, data: Record<string, unknown>) => void; origin?: DesktopOrigin };

export async function callTool(name: string, rawArgs: string, io: ToolIO): Promise<string> {
  if (name === "desktop_task") {
    const { goal, mode } = JSON.parse(rawArgs) as { goal: string; mode: string };
    if (!goal?.trim() || !["lookup", "action"].includes(mode)) throw new Error("Invalid desktop task");
    io.log("tool_call", { name, goal, mode });
    io.status("Inspecting the desktop…");
    const result = await runTask(goal, { confirm: io.confirm, print: io.status, origin: io.origin, restore: mode === "lookup" });
    io.log("tool_result", { name, ...result });
    return JSON.stringify(result);
  }
  if (name !== "run_command") return `Unknown tool ${name}`;
  const { command, why } = JSON.parse(rawArgs) as { command: string; why: string };
  io.log("tool_call", { name, command, why });
  const out = await runShell(command, why, io);
  if (out === null) return "The user declined to run this command. Do not retry it another way.";
  io.log("tool_result", { name, output: out.slice(0, 2000) });
  return out;
}
