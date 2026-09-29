# TODO

## Host attachments on the homelab so exports carry fetchable URLs

**Goal:** every image or file in an export gets a public URL that another AI model can
fetch later for context. Files expire after a TTL (default 7 days).

**Current state:** `links` entries hold whatever the site exposes, which is often only an
ID (ChatGPT: `{ id, name, mime_type }`) or a URL that needs the site's session (Claude
previews, Grok assets, `blob:` URLs on Gemini). None of these are usable outside the browser.

### Extension side
- [ ] Resolve each link to downloadable bytes while still on the page (session cookies apply):
  - ChatGPT: `GET /backend-api/files/download/{id}` (Bearer token), which returns a signed `download_url`
  - Claude: `files_v2[].preview_url` / `document_asset.url` (same-origin, cookie auth)
  - Grok: `assets.grok.com/...` URLs; the `fileAttachments` IDs need a lookup endpoint
  - Gemini: DOM `<img>` src; `blob:` URLs are read via `fetch(blob)` in the content script
  - Fallback: DOM `<img>` / `<a download>` inside the message element
- [ ] Upload the bytes to the homelab service (auth token kept in `chrome.storage`, set from an options page)
- [ ] Replace or extend each link with the hosted URL, for example
      `{ type, name, mime_type, url: "https://files.jkrebs.net/<id>/<name>", expires_at }`
- [ ] Options page: server URL, token, default TTL (7d), on/off toggle
- [ ] Don't block the copy: upload in parallel; if uploads fail, still copy the JSON with the original links

### Server side
- [ ] Small upload service: `POST /upload` (token-auth, `ttl` param) returns an unguessable URL
      (random ID ≥128 bits); `GET /<id>/<name>` is public and read-only
- [ ] Store `expires_at` per file; a cleanup job deletes expired files (and maybe caps total disk use)
- [ ] Deduplicate by content hash so re-exporting a conversation doesn't re-upload
- [ ] Pick a homelab guest for it (the `homelab-fleet` skill has recommendations)
- [ ] Public route through the Cloudflare `homelab` tunnel. The GET path must be **outside
      Cloudflare Access** (like `ha-google`) or models can't fetch it. Keep `/upload` behind
      the token and/or Access.
- [ ] Serve the correct `Content-Type` so models render images and PDFs natively
