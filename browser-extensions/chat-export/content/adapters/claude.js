(() => {
  const CX = globalThis.__CX;

  const conversationId = () => location.pathname.match(/\/chat\/([0-9a-f-]{36})/i)?.[1];

  const domModel = () =>
    document.querySelector('[data-testid="model-selector-dropdown"]')?.innerText.trim() || null;

  async function orgId() {
    const fromCookie = CX.getCookie("lastActiveOrg");
    if (fromCookie) return fromCookie;
    const orgs = await CX.fetchJSON("/api/organizations");
    const org = orgs.find((o) => o.capabilities?.includes("chat")) ?? orgs[0];
    if (!org) throw new Error("no organization found");
    return org.uuid;
  }

  function messageLinks(m) {
    const links = [];
    for (const f of m.files_v2 ?? m.files ?? []) {
      const type = f.file_kind === "image" ? "image" : "file";
      const url = f.preview_url ?? f.preview_asset?.url ?? f.thumbnail_url ?? f.document_asset?.url;
      links.push(CX.link(type, { id: f.file_uuid, name: f.file_name, url: CX.absUrl(url) }));
    }
    for (const a of m.attachments ?? []) {
      links.push(CX.link("file", { id: a.id, name: a.file_name, mime_type: a.file_type, size: a.file_size }));
    }
    for (const b of m.content ?? []) {
      for (const c of b.citations ?? []) {
        if (c.url) links.push(CX.link("link", { url: c.url, name: c.title }));
      }
    }
    return links;
  }

  function messageText(m) {
    const blocks = (m.content ?? []).filter((b) => b.type === "text" && b.text);
    return blocks.length ? blocks.map((b) => b.text).join("\n\n") : (m.text ?? "");
  }

  async function fromApi() {
    const id = conversationId();
    if (!id) throw new Error("no conversation id in URL");
    const org = await orgId();
    const c = await CX.fetchJSON(
      `/api/organizations/${org}/chat_conversations/${id}?tree=True&rendering_mode=messages&render_all_tools=true`,
    );

    const msgs = c.chat_messages ?? [];
    const byId = new Map(msgs.map((m) => [m.uuid, m]));
    let chain = [];
    if (byId.has(c.current_leaf_message_uuid)) {
      for (let m = byId.get(c.current_leaf_message_uuid); m; m = byId.get(m.parent_message_uuid)) chain.unshift(m);
    } else {
      chain = [...msgs].sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
    }

    const turns = chain.map((m) =>
      CX.turn(m.sender === "human" ? "user" : "model", messageText(m), messageLinks(m)),
    );

    const settings = c.settings ?? {};
    return {
      model: c.model ?? domModel(),
      effort: CX.findKey(settings, /effort/i) ?? settings.paprika_mode ?? null,
      turns,
    };
  }

  function fromDom() {
    const sel = '[data-testid="user-message"], .font-claude-response, .font-claude-message';
    const nodes = CX.outermost([...document.querySelectorAll(sel)]);
    const turns = nodes.map((n) => {
      const isUser = n.matches('[data-testid="user-message"]');
      const scope = isUser ? (n.parentElement ?? n) : n;
      return CX.turn(isUser ? "user" : "model", CX.toMarkdown(n), CX.linksFrom(scope));
    });
    return { model: domModel(), effort: null, turns };
  }

  CX.registerAdapter({
    service: "claude",
    matches: (loc) => loc.hostname === "claude.ai",
    fromApi,
    fromDom,
  });
})();
