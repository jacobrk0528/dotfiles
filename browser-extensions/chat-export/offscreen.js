chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type !== "cx:offscreen-copy") return;
  const buf = document.getElementById("buf");
  buf.value = msg.text;
  buf.select();
  const ok = document.execCommand("copy");
  buf.value = "";
  sendResponse(ok ? { ok } : { ok, error: "execCommand('copy') returned false" });
});
