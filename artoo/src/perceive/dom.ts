// Page → clickable candidates, read from the live DOM over CDP.
import { guardrails } from "../guardrails.ts";
import type { CdpSession } from "../harness/cdp.ts";

export type DomElement = { id?: string; row?: string; role: string; label: string; state: string; x: number; y: number; w: number; h: number };
export type PageSnapshot = { title: string; url: string; vw: number; vh: number; elements: DomElement[]; content: string; focused: string };

// Runs in the page. Plain JS in a string so it isn't transpiled or bundled.
const COLLECT = (sensitiveFields: string) => String.raw`(() => {
  // Fields whose values never leave the page (never_look.fields in guardrails.yaml).
  const SENSITIVE = new RegExp(${JSON.stringify(sensitiveFields)}, 'i');
  const sensitive = (el) => el.type === 'password' || el.type === 'hidden' ||
    /^(cc-|one-time-code|current-password|new-password)/.test(el.autocomplete || '') ||
    SENSITIVE.test([el.name, el.id, el.getAttribute('aria-label'), el.getAttribute('placeholder'), el.autocomplete].join(' '));
  const SEL = 'a[href],button,input,select,textarea,summary,[role=button],[role=link],[role=menuitem],' +
    '[role=menuitemradio],[role=menuitemcheckbox],[role=option],[role=tab],[role=checkbox],[role=radio],' +
    '[role=switch],[role=combobox],[role=treeitem],[tabindex]:not([tabindex="-1"]),[onclick]';
  const PRIORITY = { button: 0, menuitem: 0, menuitemradio: 0, menuitemcheckbox: 0, option: 0, combobox: 0,
    radio: 1, checkbox: 1, switch: 1, tab: 1, textbox: 1, select: 1, treeitem: 2, link: 3 };
  const clean = (s) => (s || '').replace(/\s+/g, ' ').trim();
  const found = [];
  const seen = new Set();
  // Stable identities across observations without adding attributes to the app's DOM.
  const key = Symbol.for('artoo.observation-ids');
  const identities = globalThis[key] ||= { nodes: new WeakMap(), next: 0, page: crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36) };
  const identity = (el) => {
    if (!identities.nodes.has(el)) identities.nodes.set(el, identities.page + ':' + ++identities.next);
    return identities.nodes.get(el);
  };
  const rowContext = (el) => {
    let row = el.closest('tr,[role=row],mat-row,mat-mdc-row,[role=listitem]');
    if (!row) {
      // Custom-element lists often have no table roles. Find their repeated row container.
      for (let p = el.parentElement, depth = 0; p && depth < 5; p = p.parentElement, depth++) {
        const peers = p.parentElement ? [...p.parentElement.children].filter(x => x.tagName === p.tagName) : [];
        if (peers.length > 1 && clean(p.innerText).length < 900 && p.querySelectorAll('button,[role=button]').length > 1) { row = p; break; }
      }
    }
    return row ? clean(row.innerText).slice(0, 240) : '';
  };

  const roleOf = (el) => {
    const r = el.getAttribute('role');
    if (r) return r;
    const tag = el.tagName.toLowerCase();
    if (tag === 'a') return 'link';
    if (tag === 'input') return ['checkbox', 'radio'].includes(el.type) ? el.type : el.type === 'button' || el.type === 'submit' ? 'button' : 'textbox';
    if (tag === 'textarea') return 'textbox';
    if (tag === 'summary') return 'button';
    return tag === 'button' || tag === 'select' ? tag : 'clickable';
  };

  const labelOf = (el) => {
    const by = el.getAttribute('aria-labelledby');
    const labelled = by ? by.split(/\s+/).map((id) => document.getElementById(id)?.innerText).join(' ') : '';
    return clean(el.getAttribute('aria-label')) || clean(labelled) || clean(el.innerText).slice(0, 80) ||
      clean(el.getAttribute('title')) || clean(el.getAttribute('placeholder')) ||
      clean(el.querySelector?.('img[alt]')?.alt) || (!sensitive(el) ? clean(el.value).slice(0, 40) : '');
  };

  const consider = (el) => {
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') return;
    const r = el.getBoundingClientRect();
    if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.right < 0 || r.top > innerHeight || r.left > innerWidth) return;
    if (el.checkVisibility && !el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) return;
    // Skip things covered by something else (modals, menus, overlays).
    const cx = Math.min(Math.max(r.left + r.width / 2, 0), innerWidth - 1);
    const cy = Math.min(Math.max(r.top + r.height / 2, 0), innerHeight - 1);
    const top = el.getRootNode().elementFromPoint?.(cx, cy);
    if (top && top !== el && !el.contains(top) && !top.contains(el)) return;
    const label = labelOf(el);
    if (!label) return;
    const key = label + '|' + Math.round(cx / 8) + ',' + Math.round(cy / 8);
    if (seen.has(key)) return;
    seen.add(key);
    const states = [];
    for (const a of ['aria-checked', 'aria-selected', 'aria-expanded', 'aria-pressed']) {
      const v = el.getAttribute(a);
      if (v === 'true') states.push(a.slice(5));
    }
    if (el.checked) states.push('checked');
    // Current value, so Jev can tell what a field holds before changing it.
    const tag = el.tagName.toLowerCase();
    if ((tag === 'input' || tag === 'textarea') && el.value) states.push(sensitive(el) ? 'value=[private]' : 'value=' + clean(el.value).slice(0, 40));
    const role = el.getAttribute('role');
    if ((role === 'combobox' || tag === 'select') && el.getAttribute('aria-label')) {
      const shown = tag === 'select' ? el.selectedOptions?.[0]?.text : el.innerText;
      if (clean(shown)) states.push('value=' + clean(shown).slice(0, 40));
    }
    found.push({ id: identity(el), row: rowContext(el), role: roleOf(el), label, state: states.join(','), x: cx, y: cy, w: r.width, h: r.height });
  };

  const walk = (root) => {
    root.querySelectorAll(SEL).forEach(consider);
    root.querySelectorAll('*').forEach((el) => el.shadowRoot && walk(el.shadowRoot));
  };
  walk(document);
  found.sort((a, b) => (PRIORITY[a.role] ?? 2) - (PRIORITY[b.role] ?? 2));
  // Text in view, plus text that is rendered but scrolled out of view above or below. Reading
  // a long list from the off-screen text takes one look; scrolling through it took a model
  // round per screenful.
  const text = [], above = [], below = [];
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  let length = 0, offscreen = 0;
  while (walker.nextNode() && length < 24000) {
    const node = walker.currentNode;
    const el = node.parentElement;
    if (!el || /^(SCRIPT|STYLE|NOSCRIPT)$/.test(el.tagName) || sensitive(el)) continue;
    if (el.checkVisibility && !el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) continue;
    const value = clean(node.textContent);
    if (!value) continue;
    const range = document.createRange();
    range.selectNodeContents(node);
    const rects = [...range.getClientRects()].filter(r => r.width > 0 && r.height > 0);
    if (!rects.length) continue;
    if (rects.some(r => r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth)) { text.push(value); length += value.length; continue; }
    // Off to the side is a carousel or a closed drawer, not something scrolling reveals.
    const r = rects[0];
    if (offscreen >= 16000 || r.right <= 0 || r.left >= innerWidth) continue;
    (r.bottom <= 0 ? above : below).push(value); offscreen += value.length;
  }
  if (above.length || below.length) {
    text.unshift('[visible now]');
    if (above.length) text.unshift('[off-screen above: rendered, scroll up to bring it into view]', ...above);
    if (below.length) text.push('[off-screen below: rendered, scroll down to bring it into view]', ...below);
  }
  let focus = document.activeElement;
  while (focus?.shadowRoot?.activeElement) focus = focus.shadowRoot.activeElement;
  const focused = focus ? [roleOf(focus), labelOf(focus), sensitive(focus) ? '[private]' : clean(focus.value || '')].join(' ') : '';
  return { title: document.title, url: location.href, vw: innerWidth, vh: innerHeight, elements: found, content: text.join('\n'), focused };
})()`;

export const snapshotPage = (cdp: CdpSession) => cdp.evaluate<PageSnapshot>(COLLECT(guardrails().sensitiveFieldSource));
