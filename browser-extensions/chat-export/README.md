# Chat Export

Chromium extension (Chrome, Brave, Edge, Vivaldi…) that copies the current
ChatGPT / Claude / Gemini / Grok conversation to the clipboard as JSON.

## Install

```bash
browser-ext install chat-export   # copies the path, opens <browser>://extensions
```

Then, once per browser profile: enable **Developer mode** → **Load unpacked** → paste the path.
The browser loads straight from `~/dotfiles/browser-extensions/chat-export`, so updates are
`git pull` (or `browser-ext update`) + the reload icon on the extension card. Open chat tabs are
re-injected automatically on the next toolbar click.

## Use

One click on any of:
- the small tab on the right edge of the page,
- the toolbar icon,
- `Alt+Shift+C` (change at `chrome://extensions/shortcuts`).

## Output

```json
{
  "service": "chatgpt | claude | gemini | grok",
  "model": "gpt-5 | null",
  "effort": "high | null",
  "conversation": {
    "turns": [
      { "user": "user | model", "message": "markdown text", "links": [
        { "type": "image | file | link", "url": "...", "name": "...", "id": "..." }
      ] }
    ]
  }
}
```

## How extraction works

| Site    | Primary source                                   | Fallback            |
|---------|--------------------------------------------------|---------------------|
| ChatGPT | `/backend-api/conversation/{id}` (active branch) | `[data-message-author-role]` DOM |
| Claude  | `/api/organizations/{org}/chat_conversations/{id}` | `user-message` / `.font-claude-response` DOM |
| Grok    | `/rest/app-chat/conversations/{id}/…`            | `div[id^=response-]` DOM |
| Gemini  | DOM only (auto-scrolls up to load full history)  | —                   |

These are undocumented internals and will drift. When something breaks, check the
page console for `[chat-export]` warnings, then fix the matching file in
`content/adapters/`. To debug, pick the extension's context in the DevTools
console dropdown and run `await __CX.export()`.

Adding a site = new file in `content/adapters/` calling `CX.registerAdapter({ service, matches, fromApi?, fromDom })`,
plus its host in `manifest.json` (`host_permissions` and `content_scripts.matches`).
