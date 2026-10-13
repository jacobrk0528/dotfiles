import { afterEach, expect, test } from "bun:test";
import { runInBackground } from "../src/background.ts";
import { setRunner } from "../src/exec.ts";
import { setJev, type JevClient } from "../src/jev.ts";
import { setJsonCaller } from "../src/llm.ts";
import { commandEffect } from "../src/policy.ts";

const log = { dir: "/unused", event: () => {} };
const never = async () => { throw new Error("should not ask"); };

// Guard checks answer every yes/no question "no".
const quietJev: JevClient = {
  systemOne: (async ({ questions }: { questions: Record<string, unknown> }) => ({
    model: "fake", usage: { input_tokens: 0, output_tokens: 0 },
    answers: Object.fromEntries(Object.keys(questions).map((k) => [k, { type: "noul", noul: 0.01 }])),
  })) as unknown as JevClient["systemOne"],
};

afterEach(() => { setJsonCaller(null); setRunner(null); setJev(null); });

test("device controls run without asking; pairing, removing and compound commands still ask", () => {
  for (const cmd of ["bluetoothctl connect 04:C8:B0:2F:27:CD", "bluetoothctl disconnect 04:C8:B0:2F:27:CD", "bluetoothctl power on", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 40%", "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "wpctl set-default 57", "pactl set-default-sink bluez_output.04_C8_B0_2F_27_CD.1", "playerctl play-pause", "playerctl -p spotify next"]) expect(commandEffect(cmd)).toBe("device");
  for (const cmd of ["bluetoothctl devices Paired", "bluetoothctl info 04:C8:B0:2F:27:CD", "bluetoothctl show", "wpctl status", "playerctl metadata", "pactl list"]) expect(commandEffect(cmd)).toBe("read");
  for (const cmd of ["bluetoothctl remove 04:C8:B0:2F:27:CD", "bluetoothctl pair 04:C8:B0:2F:27:CD", "bluetoothctl trust 04:C8:B0:2F:27:CD", "bluetoothctl connect x; rm -rf ~", "bluetoothctl connect $(cat f)", "wpctl set-volume 57 40% > /tmp/x", "pactl load-module module-null-sink", "playerctl open https://x", "blueman-manager"]) expect(commandEffect(cmd)).toBe("unknown");
});

test("connects the earbuds with background commands and no prompt", async () => {
  const ran: string[] = [];
  setJev(quietJev);
  setRunner(async (cmd) => {
    const line = cmd.at(-1)!;
    ran.push(line);
    return { stdout: line.startsWith("bluetoothctl devices") ? "Device 04:C8:B0:2F:27:CD Jacob's Pixel Buds Pro 2" : line.includes("info") ? "Connected: yes" : "Connection successful", stderr: "", code: 0 };
  });
  const replies = [
    { status: "run", command: "bluetoothctl devices Paired", why: "Find the earbuds", message: "" },
    { status: "run", command: "bluetoothctl connect 04:C8:B0:2F:27:CD", why: "Connect the earbuds", message: "" },
    { status: "run", command: "bluetoothctl info 04:C8:B0:2F:27:CD", why: "Check the connection", message: "" },
    { status: "done", command: null, why: "", evidence: "Connected: yes", message: "Your Pixel Buds are connected." },
  ];
  const inputs: any[] = [];
  setJsonCaller(async <T>(opts: { input: unknown }) => { inputs.push(opts.input); return replies.shift() as T; });
  const res = await runInBackground("connect my pixel earbuds", { print: () => {}, confirm: never, log });
  expect(res).toEqual({ status: "done", message: "Your Pixel Buds are connected." });
  expect(ran).toEqual(["bluetoothctl devices Paired", "bluetoothctl connect 04:C8:B0:2F:27:CD", "bluetoothctl info 04:C8:B0:2F:27:CD"]);
  expect(inputs.at(-1).commands_run.at(-1).output).toContain("Connected: yes");
});

test("done is refused until a command output shows it", async () => {
  setJev(quietJev);
  const ran: string[] = [];
  setRunner(async (cmd) => { ran.push(cmd.at(-1)!); return { stdout: cmd.at(-1)!.includes("connect") ? "Connection successful" : "Device 04:C8:B0:2F:27:CD Pixel Buds", stderr: "", code: 0 }; });
  const replies = [
    { status: "run", command: "bluetoothctl devices Paired", why: "Find the earbuds", evidence: null, message: "" },
    { status: "done", command: null, why: "", evidence: "Pixel Buds connected", message: "Connected." },
    { status: "run", command: "bluetoothctl connect 04:C8:B0:2F:27:CD", why: "Connect", evidence: null, message: "" },
    { status: "done", command: null, why: "", evidence: "Connection successful", message: "Connected." },
  ];
  setJsonCaller(async <T>() => replies.shift() as T);
  expect(await runInBackground("connect my earbuds", { print: () => {}, confirm: never, log })).toEqual({ status: "done", message: "Connected." });
  expect(ran).toEqual(["bluetoothctl devices Paired", "bluetoothctl connect 04:C8:B0:2F:27:CD"]);
});

test("a goal that needs a window goes back to the screen planner", async () => {
  setJsonCaller(async <T>() => ({ status: "needs_ui", command: null, why: "", message: "" }) as T);
  setRunner(async () => { throw new Error("should not run anything"); });
  expect(await runInBackground("open blueman", { print: () => {}, confirm: never, log })).toBeNull();
});

test("a command outside the list asks, and a no stops the run", async () => {
  setJev(quietJev);
  setRunner(async () => { throw new Error("should not run anything"); });
  setJsonCaller(async <T>() => ({ status: "run", command: "bluetoothctl remove 04:C8:B0:2F:27:CD", why: "Forget the earbuds", message: "" }) as T);
  let asked = 0;
  const res = await runInBackground("forget my earbuds", { print: () => {}, confirm: async () => { asked++; return false; }, log });
  expect(res?.status).toBe("declined");
  expect(asked).toBe(1);
});
