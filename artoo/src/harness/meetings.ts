// Mute/unmute yourself inside a video call, by clicking the call's own mic button.
// Site-specific on purpose: Meet also shows host controls like "Mute Alice's microphone",
// and a generic "click the mute button" could hit one of those.
import { CdpSession, targets } from "./cdp.ts";

export type MicState = "mute" | "unmute" | "toggle";

const MEET_CALL = /^https:\/\/meet\.google\.com\/[a-z]{3}-[a-z]{4}-[a-z]{3}/;

// Runs in the Meet page. Your own mic button is labelled "Turn off/on microphone" and
// carries data-is-muted; other participants' buttons don't.
const READ = `(() => {
  const b = [...document.querySelectorAll('button,[role=button]')].find(
    (b) => /^Turn (off|on) microphone/i.test(b.getAttribute('aria-label') || '') && b.hasAttribute('data-is-muted'));
  return b ? b.getAttribute('data-is-muted') === 'true' : null;
})()`;

const CLICK = `(() => {
  const b = [...document.querySelectorAll('button,[role=button]')].find(
    (b) => /^Turn (off|on) microphone/i.test(b.getAttribute('aria-label') || '') && b.hasAttribute('data-is-muted'));
  b?.click();
})()`;

export async function setMeetingMic(state: MicState, tabUrl: RegExp = MEET_CALL): Promise<string> {
  const tab = (await targets()).find((t) => tabUrl.test(t.url));
  if (!tab) throw new Error("no Google Meet call is open in Brave");
  const cdp = await CdpSession.connect(tab);
  try {
    const muted = await cdp.evaluate<boolean | null>(READ);
    if (muted === null) throw new Error("couldn't find your mic button in the Meet call");
    const want = state === "toggle" ? !muted : state === "mute";
    if (want === muted) return `Already ${muted ? "muted" : "unmuted"} in ${tab.title}`;

    await cdp.evaluate(CLICK);
    for (let i = 0; i < 10; i++) {
      await Bun.sleep(100);
      if ((await cdp.evaluate<boolean | null>(READ)) === want) return `${want ? "Muted" : "Unmuted"} in ${tab.title}`;
    }
    // Fall back to Meet's own shortcut (ctrl+d), sent to that tab as real key input.
    await cdp.send("Input.dispatchKeyEvent", { type: "rawKeyDown", key: "d", code: "KeyD", windowsVirtualKeyCode: 68, modifiers: 2 });
    await cdp.send("Input.dispatchKeyEvent", { type: "keyUp", key: "d", code: "KeyD", windowsVirtualKeyCode: 68, modifiers: 2 });
    await Bun.sleep(400);
    if ((await cdp.evaluate<boolean | null>(READ)) === want) return `${want ? "Muted" : "Unmuted"} in ${tab.title}`;
    throw new Error("clicked Meet's mic button but the state didn't change");
  } finally {
    cdp.close();
  }
}
