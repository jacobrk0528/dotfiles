// Shared helpers for site adapters. Content scripts share one isolated world,
// so everything hangs off globalThis.__CX.
(() => {
  const CX = (globalThis.__CX ??= { adapters: [] });
  if (CX.utilLoaded) return;
  CX.utilLoaded = true;

  CX.registerAdapter = (adapter) => {
    if (!CX.adapters.some((a) => a.service === adapter.service)) CX.adapters.push(adapter);
  };

  CX.sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  CX.fetchJSON = async (url, opts = {}) => {
    const res = await fetch(url, { credentials: "include", ...opts });
    if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
    return res.json();
  };

  CX.getCookie = (name) =>
    document.cookie
      .split("; ")
      .find((c) => c.startsWith(name + "="))
      ?.slice(name.length + 1);

  CX.absUrl = (u) => {
    if (!u) return undefined;
    try {
      return new URL(u, location.origin).href;
    } catch {
      return u;
    }
  };

  // First string/number/boolean value (depth-limited) whose key matches `re`.
  CX.findKey = (obj, re, depth = 3) => {
    if (!obj || typeof obj !== "object" || depth < 0) return undefined;
    for (const [k, v] of Object.entries(obj)) {
      if (re.test(k) && v != null && typeof v !== "object" && v !== "") return String(v);
    }
    for (const v of Object.values(obj)) {
      if (v && typeof v === "object" && !Array.isArray(v)) {
        const hit = CX.findKey(v, re, depth - 1);
        if (hit !== undefined) return hit;
      }
    }
    return undefined;
  };

  const clean = (o) => Object.fromEntries(Object.entries(o).filter(([, v]) => v != null && v !== ""));

  CX.link = (type, fields) => clean({ type, ...fields });

  CX.dedupeLinks = (links) => {
    const seen = new Set();
    return links.filter((l) => {
      const key = l.url ?? l.id ?? l.name;
      if (!key || seen.has(key)) return !key && Object.keys(l).length > 1;
      seen.add(key);
      return true;
    });
  };

  CX.turn = (user, message, links = []) => ({
    user,
    message: (message ?? "").trim(),
    links: CX.dedupeLinks(links),
  });

  // Merge consecutive same-role turns (e.g. assistant text split around tool calls).
  CX.mergeTurns = (turns) => {
    const out = [];
    for (const t of turns) {
      if (!t.message && !t.links.length) continue;
      const prev = out[out.length - 1];
      if (prev && prev.user === t.user) {
        prev.message = [prev.message, t.message].filter(Boolean).join("\n\n");
        prev.links = CX.dedupeLinks([...prev.links, ...t.links]);
      } else {
        out.push({ ...t });
      }
    }
    return out;
  };

  // Keep only elements not nested inside another element of the same list.
  CX.outermost = (els) => els.filter((el) => !els.some((o) => o !== el && o.contains(el)));

  // ---- DOM -> Markdown -------------------------------------------------------

  const SKIP =
    'button, svg, style, script, noscript, template, [aria-hidden="true"], [hidden], ' +
    ".sr-only, .cdk-visually-hidden, .visually-hidden";

  const block = (s) => (s.trim() ? `\n\n${s.trim()}\n\n` : "");

  function md(node, depth) {
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue.replace(/\s+/g, " ");
    if (node.nodeType !== Node.ELEMENT_NODE || node.matches(SKIP)) return "";
    const el = node;
    const tag = el.tagName.toLowerCase();
    const kids = (d = depth) => Array.from(el.childNodes, (c) => md(c, d)).join("");

    switch (tag) {
      case "br":
        return "\n";
      case "hr":
        return block("---");
      case "img":
        return ""; // collected separately as links
      case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
        return block(`${"#".repeat(+tag[1])} ${kids().trim()}`);
      case "strong": case "b": {
        const t = kids();
        return t.trim() ? `**${t.trim()}**` : t;
      }
      case "em": case "i": {
        const t = kids();
        return t.trim() ? `*${t.trim()}*` : t;
      }
      case "code":
        return "`" + el.textContent + "`";
      case "pre": {
        const code = el.querySelector("code") ?? el;
        const lang =
          (code.className.match(/language-([\w+#.-]+)/) ?? [])[1] ??
          el.getAttribute("data-language") ??
          "";
        return block("```" + lang + "\n" + code.textContent.replace(/\n$/, "") + "\n```");
      }
      case "a": {
        const text = kids().trim();
        const href = el.href;
        if (!href || !/^https?:/.test(href)) return text;
        return `[${text || href}](${href})`;
      }
      case "blockquote":
        return block(kids().trim().split("\n").map((l) => "> " + l).join("\n"));
      case "ul": case "ol": {
        const indent = "  ".repeat(depth);
        const items = Array.from(el.children).filter((c) => c.tagName === "LI");
        const lines = items.map((li, i) => {
          const marker = tag === "ol" ? `${(+el.getAttribute("start") || 1) + i}.` : "-";
          const body = Array.from(li.childNodes, (c) => md(c, depth + 1))
            .join("")
            .trim()
            .replace(/\n{2,}/g, "\n");
          return `${indent}${marker} ${body}`;
        });
        return depth ? "\n" + lines.join("\n") : block(lines.join("\n"));
      }
      case "table": {
        const rows = Array.from(el.querySelectorAll("tr")).map((tr) =>
          Array.from(tr.children, (c) => md(c, depth).trim().replace(/\n+/g, " ").replace(/\|/g, "\\|")),
        );
        if (!rows.length) return "";
        const line = (r) => `| ${r.join(" | ")} |`;
        const sep = line(rows[0].map(() => "---"));
        return block([line(rows[0]), sep, ...rows.slice(1).map(line)].join("\n"));
      }
      case "p": case "div": case "section": case "article": case "header": case "footer":
      case "figure": case "figcaption": case "details": case "summary":
        return block(kids());
      default:
        return kids();
    }
  }

  CX.toMarkdown = (el) =>
    el
      ? md(el, 0)
          .replace(/[ \t]+\n/g, "\n")
          .replace(/\n[ \t]+(?=\n)/g, "\n")
          .replace(/\n{3,}/g, "\n\n")
          .trim()
      : "";

  // Images and outbound links inside a message element.
  CX.linksFrom = (el) => {
    if (!el) return [];
    const out = [];
    for (const img of el.querySelectorAll("img")) {
      if (img.closest(SKIP)) continue;
      const w = img.naturalWidth || img.width;
      if (w && w < 40) continue; // favicons, avatars
      const url = img.currentSrc || img.src;
      if (url) out.push(CX.link("image", { url, name: img.alt }));
    }
    for (const a of el.querySelectorAll("a[href]")) {
      if (/^https?:/.test(a.href)) out.push(CX.link("link", { url: a.href, name: a.innerText.trim() }));
    }
    return out;
  };
})();
