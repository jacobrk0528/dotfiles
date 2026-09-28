(() => {
  const CX = globalThis.__CX;

  const conversationId = () => location.pathname.match(/\/c\/([0-9a-f-]{36})/i)?.[1];

  // ChatGPT inserts private-use-area citation markers (e.g. citeturn0search1).
  const stripMarkers = (s) => s.replace(/[^]*/g, "").replace(/[-]/g, "");

  function messageLinks(m) {
    const links = [];
    const md = m.metadata ?? {};
    for (const a of md.attachments ?? []) {
      const type = a.mime_type?.startsWith("image/") ? "image" : "file";
      links.push(CX.link(type, { id: a.id, name: a.name, mime_type: a.mime_type }));
    }
    for (const p of m.content?.parts ?? []) {
      if (p?.content_type === "image_asset_pointer") {
        const id = p.asset_pointer?.replace(/^[a-z-]+:\/\//, "");
        if (!links.some((l) => l.id === id)) links.push(CX.link("image", { id, url: p.asset_pointer }));
      }
    }
    for (const ref of md.content_references ?? []) {
      for (const item of ref.items ?? []) {
        if (item.url) links.push(CX.link("link", { url: item.url, name: item.title }));
      }
      for (const s of ref.sources ?? []) {
        if (s.url) links.push(CX.link("link", { url: s.url, name: s.title }));
      }
    }
    for (const c of md.citations ?? []) {
      const url = c.metadata?.url;
      if (url) links.push(CX.link("link", { url, name: c.metadata.title }));
    }
    return links;
  }

  function messageText(m) {
    let text = (m.content?.parts ?? []).filter((p) => typeof p === "string").join("\n");
    for (const ref of m.metadata?.content_references ?? []) {
      if (ref.matched_text) text = text.split(ref.matched_text).join(ref.alt ?? "");
    }
    return stripMarkers(text);
  }

  async function fromApi() {
    const id = conversationId();
    if (!id) throw new Error("no conversation id in URL");
    const { accessToken } = await CX.fetchJSON("/api/auth/session");
    if (!accessToken) throw new Error("not signed in");
    const convo = await CX.fetchJSON(`/backend-api/conversation/${id}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });

    // Walk the active branch from the current leaf back to the root.
    const chain = [];
    for (let n = convo.mapping?.[convo.current_node]; n; n = convo.mapping[n.parent]) chain.unshift(n);

    const turns = [];
    let lastAssistant;
    for (const { message: m } of chain) {
      const role = m?.author?.role;
      if (role !== "user" && role !== "assistant") continue;
      if (m.metadata?.is_visually_hidden_from_conversation) continue;
      if (role === "assistant" && m.recipient && m.recipient !== "all") continue; // tool calls
      if (!["text", "multimodal_text"].includes(m.content?.content_type)) continue; // thoughts, code, etc.
      if (role === "assistant") lastAssistant = m;
      turns.push(CX.turn(role === "user" ? "user" : "model", messageText(m), messageLinks(m)));
    }

    const meta = lastAssistant?.metadata ?? {};
    return {
      model: meta.model_slug ?? convo.default_model_slug ?? null,
      effort: CX.findKey(meta, /effort/i) ?? CX.findKey(convo, /effort/i, 1) ?? null,
      turns,
    };
  }

  function fromDom() {
    const turns = [];
    let model = null;
    const nodes = CX.outermost([...document.querySelectorAll("[data-message-author-role]")]);
    for (const n of nodes) {
      const role = n.getAttribute("data-message-author-role");
      if (role !== "user" && role !== "assistant") continue;
      const scope = n.closest('article, [data-testid^="conversation-turn"]') ?? n;
      let text;
      if (role === "user") {
        text = (n.querySelector(".whitespace-pre-wrap") ?? n).innerText;
      } else {
        text = CX.toMarkdown(n.querySelector(".markdown") ?? n);
        model = n.getAttribute("data-message-model-slug") ?? model;
      }
      turns.push(CX.turn(role === "user" ? "user" : "model", text, CX.linksFrom(scope)));
    }
    return { model, effort: null, turns };
  }

  CX.registerAdapter({
    service: "chatgpt",
    matches: (loc) => /(^|\.)chatgpt\.com$|^chat\.openai\.com$/.test(loc.hostname),
    fromApi,
    fromDom,
  });
})();
