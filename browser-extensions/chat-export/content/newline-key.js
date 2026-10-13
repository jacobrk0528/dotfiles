// Ctrl+J in the prompt box inserts a newline (same as Shift+Enter) instead of
// opening the browser's Downloads page.
(() => {
  if (globalThis.__cxNewlineKey) return;
  globalThis.__cxNewlineKey = true;

  function isEditable(el) {
    return el?.isContentEditable || el?.tagName === "TEXTAREA";
  }

  function shiftEnter(type, target) {
    const ev = new KeyboardEvent(type, {
      key: "Enter", code: "Enter", keyCode: 13, which: 13,
      shiftKey: true, bubbles: true, cancelable: true, composed: true,
    });
    target.dispatchEvent(ev);
    return ev.defaultPrevented;
  }

  window.addEventListener(
    "keydown",
    (e) => {
      if (e.key.toLowerCase() !== "j" || !e.ctrlKey || e.shiftKey || e.altKey || e.metaKey) return;
      const el = document.activeElement;
      if (!isEditable(el)) return;
      e.preventDefault();
      e.stopImmediatePropagation();

      // The site's editor (ProseMirror on ChatGPT/Claude, Quill on Gemini) handles a
      // synthetic Shift+Enter and calls preventDefault. If nothing handled it,
      // insert the newline ourselves, since synthetic events have no default action.
      const handled = shiftEnter("keydown", el);
      shiftEnter("keyup", el);
      if (handled) return;
      if (el.tagName === "TEXTAREA") document.execCommand("insertText", false, "\n");
      else document.execCommand("insertLineBreak");
    },
    true,
  );
})();
