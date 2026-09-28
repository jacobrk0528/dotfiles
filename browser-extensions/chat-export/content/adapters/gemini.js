(() => {
  const CX = globalThis.__CX;

  // Gemini lazy-loads older turns as you scroll up; pull them all in first.
  async function loadFullHistory() {
    const scroller = document.querySelector("infinite-scroller, #chat-history");
    if (!scroller) return;
    const restore = scroller.scrollTop;
    let last = -1;
    let stable = 0;
    for (let i = 0; i < 40 && stable < 2; i++) {
      scroller.scrollTop = 0;
      await CX.sleep(600);
      const count = document.querySelectorAll("user-query").length;
      stable = count === last ? stable + 1 : 0;
      last = count;
    }
    scroller.scrollTop = restore;
  }

  const domModel = () =>
    document
      .querySelector('[data-test-id="bard-mode-menu-button"], bard-mode-switcher button, .current-mode-title')
      ?.innerText.trim()
      .replace(/\s+/g, " ") || null;

  async function fromDom() {
    await loadFullHistory();
    const nodes = CX.outermost([...document.querySelectorAll("user-query, model-response")]);
    const turns = nodes.map((n) => {
      if (n.tagName === "USER-QUERY") {
        const lines = [...n.querySelectorAll(".query-text-line")];
        const text = lines.length
          ? lines.map((l) => l.innerText).join("\n")
          : CX.toMarkdown(n.querySelector(".query-text") ?? n);
        return CX.turn("user", text, CX.linksFrom(n));
      }
      const body = n.querySelector("message-content .markdown, message-content") ?? n;
      return CX.turn("model", CX.toMarkdown(body), CX.linksFrom(n));
    });
    return { model: domModel(), effort: null, turns };
  }

  CX.registerAdapter({
    service: "gemini",
    matches: (loc) => loc.hostname === "gemini.google.com",
    fromDom,
  });
})();
