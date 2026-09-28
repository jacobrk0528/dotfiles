// Entry point: floating button + toolbar/shortcut listener.
(() => {
  const CX = globalThis.__CX;
  const adapter = CX.adapters.find((a) => a.matches(location));
  if (!adapter) return;

  async function exportConversation() {
    let result;
    if (adapter.fromApi) {
      try {
        result = await adapter.fromApi();
      } catch (e) {
        console.warn(`[chat-export] ${adapter.service} API failed, falling back to DOM:`, e);
      }
    }
    if (!result?.turns?.length) result = await adapter.fromDom();
    const turns = CX.mergeTurns(result.turns ?? []);
    if (!turns.length) throw new Error("no messages found on this page");
    return {
      service: adapter.service,
      model: result.model ?? null,
      effort: result.effort ?? null,
      conversation: { turns },
    };
  }

  async function copyText(text) {
    try {
      const res = await chrome.runtime.sendMessage({ type: "cx:copy", text });
      if (res?.ok) return;
      throw new Error(res?.error ?? "copy failed");
    } catch (e) {
      // Extension context gone (reloaded) or offscreen failed: try the page clipboard.
      await navigator.clipboard.writeText(text).catch(() => {
        throw e;
      });
    }
  }

  let busy = false;
  async function run() {
    if (busy) return;
    busy = true;
    ui.setBusy(true);
    try {
      const data = await exportConversation();
      await copyText(JSON.stringify(data, null, 2));
      const n = data.conversation.turns.length;
      ui.toast(`Copied ${n} turn${n === 1 ? "" : "s"} as JSON`);
    } catch (e) {
      console.error("[chat-export]", e);
      ui.toast(`Export failed: ${e.message ?? e}`, true);
    } finally {
      busy = false;
      ui.setBusy(false);
    }
  }

  // Re-injection (after an extension reload) replaces the old listener and button.
  if (CX.onMessage) chrome.runtime.onMessage.removeListener(CX.onMessage);
  CX.onMessage = (msg, _sender, sendResponse) => {
    if (msg?.type !== "cx:export") return;
    run();
    sendResponse({ ok: true });
  };
  chrome.runtime.onMessage.addListener(CX.onMessage);

  const ui = (() => {
    document.getElementById("cx-export-root")?.remove();
    const host = document.createElement("div");
    host.id = "cx-export-root";
    const root = host.attachShadow({ mode: "open" });
    root.innerHTML = `
      <style>
        :host { all: initial; }
        button {
          position: fixed; right: 0; top: 40%; z-index: 2147483647;
          width: 30px; height: 34px; padding: 0; border: 1px solid rgba(127,127,127,.35);
          border-right: none; border-radius: 8px 0 0 8px; cursor: pointer;
          background: rgba(40,40,40,.75); color: #fff; opacity: .45;
          display: grid; place-items: center; transition: opacity .15s, width .15s;
        }
        button:hover, button:focus-visible { opacity: 1; width: 36px; }
        button[data-busy] { opacity: 1; cursor: progress; }
        button[data-busy] svg { animation: pulse 1s infinite; }
        @keyframes pulse { 50% { opacity: .3; } }
        .toast {
          position: fixed; right: 44px; top: 40%; z-index: 2147483647;
          font: 13px/1.3 system-ui, sans-serif; color: #fff; background: #2e7d32;
          padding: 8px 12px; border-radius: 6px; box-shadow: 0 2px 8px rgba(0,0,0,.3);
          max-width: 320px; opacity: 0; transform: translateX(8px);
          transition: opacity .15s, transform .15s; pointer-events: none;
        }
        .toast.show { opacity: 1; transform: none; }
        .toast.error { background: #c62828; }
      </style>
      <button title="Copy conversation as JSON (Alt+Shift+C)" aria-label="Copy conversation as JSON">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
             stroke-linecap="round" stroke-linejoin="round">
          <rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
        </svg>
      </button>
      <div class="toast" role="status"></div>`;
    const btn = root.querySelector("button");
    const toastEl = root.querySelector(".toast");
    btn.addEventListener("click", run);
    document.documentElement.append(host);

    let timer;
    return {
      setBusy: (b) => btn.toggleAttribute("data-busy", b),
      toast(text, error = false) {
        toastEl.textContent = text;
        toastEl.classList.toggle("error", error);
        toastEl.classList.add("show");
        clearTimeout(timer);
        timer = setTimeout(() => toastEl.classList.remove("show"), error ? 5000 : 2200);
      },
    };
  })();

  CX.export = exportConversation; // handy for debugging from the console
})();
