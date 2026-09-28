// Service worker: toolbar/shortcut trigger, clipboard writes via an offscreen document.

const CONTENT_FILES = chrome.runtime.getManifest().content_scripts[0].js;

let offscreenReady;
function ensureOffscreen() {
  offscreenReady ??= (async () => {
    if (await chrome.offscreen.hasDocument()) return;
    await chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: ["CLIPBOARD"],
      justification: "Copy exported conversation JSON to the clipboard",
    });
  })().catch((e) => {
    offscreenReady = undefined;
    throw e;
  });
  return offscreenReady;
}

async function copy(text) {
  await ensureOffscreen();
  return chrome.runtime.sendMessage({ type: "cx:offscreen-copy", text });
}

function flashBadge(tabId, ok) {
  chrome.action.setBadgeBackgroundColor({ tabId, color: ok ? "#2e7d32" : "#c62828" });
  chrome.action.setBadgeText({ tabId, text: ok ? "✓" : "✗" });
  setTimeout(() => chrome.action.setBadgeText({ tabId, text: "" }), 2000);
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.type !== "cx:copy") return;
  copy(msg.text)
    .then((res) => {
      if (sender.tab) flashBadge(sender.tab.id, !!res?.ok);
      sendResponse(res ?? { ok: false, error: "no response from offscreen document" });
    })
    .catch((e) => sendResponse({ ok: false, error: String(e?.message ?? e) }));
  return true;
});

chrome.action.onClicked.addListener(async (tab) => {
  try {
    await chrome.tabs.sendMessage(tab.id, { type: "cx:export" });
  } catch {
    // Tab was open before the extension was installed/reloaded: inject and retry.
    try {
      await chrome.scripting.executeScript({ target: { tabId: tab.id }, files: CONTENT_FILES });
      await chrome.tabs.sendMessage(tab.id, { type: "cx:export" });
    } catch {
      flashBadge(tab.id, false);
    }
  }
});
