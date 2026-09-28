(() => {
  const CX = globalThis.__CX;

  const conversationId = () => location.pathname.match(/\/(?:c|chat)\/([0-9a-f-]{36})/i)?.[1];

  const domModel = () =>
    document.querySelector('button[aria-label="Model select"], #model-select-trigger')?.innerText.trim() || null;

  const assetUrl = (u) => (u ? new URL(u, "https://assets.grok.com/").href : undefined);

  function responseLinks(r) {
    const links = [];
    for (const id of r.fileAttachments ?? []) links.push(CX.link("file", { id }));
    for (const u of r.imageAttachments ?? []) links.push(CX.link("image", { url: assetUrl(u) }));
    for (const u of r.generatedImageUrls ?? []) links.push(CX.link("image", { url: assetUrl(u) }));
    for (const w of r.webSearchResults ?? []) {
      if (w.url) links.push(CX.link("link", { url: w.url, name: w.title }));
    }
    for (const x of r.xpostIds ?? []) links.push(CX.link("link", { url: `https://x.com/i/status/${x}` }));
    return links;
  }

  async function fromApi() {
    const id = conversationId();
    if (!id) throw new Error("no conversation id in URL");
    const base = `/rest/app-chat/conversations/${id}`;
    const { responseNodes = [] } = await CX.fetchJSON(`${base}/response-node?includeThreads=true`);
    if (!responseNodes.length) throw new Error("no responses");

    // Active branch: walk parents back from the last node.
    const byId = new Map(responseNodes.map((n) => [n.responseId, n]));
    const ids = [];
    for (let n = responseNodes[responseNodes.length - 1]; n; n = byId.get(n.parentResponseId)) ids.unshift(n.responseId);

    const { responses = [] } = await CX.fetchJSON(`${base}/load-responses`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ responseIds: ids }),
    });
    const order = new Map(ids.map((rid, i) => [rid, i]));
    responses.sort((a, b) => (order.get(a.responseId) ?? 0) - (order.get(b.responseId) ?? 0));

    let lastModel;
    const turns = responses.map((r) => {
      const isUser = String(r.sender).toLowerCase() === "human";
      if (!isUser) lastModel = r;
      return CX.turn(isUser ? "user" : "model", r.message, responseLinks(r));
    });

    return {
      model: lastModel?.model ?? domModel(),
      effort: CX.findKey(lastModel, /effort|reasoningMode/i, 1) ?? null,
      turns,
    };
  }

  function fromDom() {
    const nodes = CX.outermost([...document.querySelectorAll('div[id^="response-"]')]);
    const turns = nodes.map((n) => {
      const isUser = n.classList.contains("items-end");
      const body = n.querySelector(".message-bubble") ?? n;
      return CX.turn(isUser ? "user" : "model", CX.toMarkdown(body), CX.linksFrom(n));
    });
    return { model: domModel(), effort: null, turns };
  }

  CX.registerAdapter({
    service: "grok",
    matches: (loc) => loc.hostname === "grok.com",
    fromApi,
    fromDom,
  });
})();
