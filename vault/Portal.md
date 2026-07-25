# Portal

The web frontends in `backend/web/`, served by the FastAPI app itself (static
mount at `/`, so a phone only needs the host address — same origin, no
base-URL config).

## Public scanner — `index.html` at `/`

- The **default, live** web frontend. Sign-in was removed: it is a **public,
  no-auth test tool**, open to anyone with the URL.
- Posts photos to `POST /v1/scan` (anonymous). **Writes nothing to the DB** —
  it never calls `/v1/log`. Persistence is the iOS app's job.
- Renders the result card: MATCHED badge (USDA-grounded), calories, protein,
  Edit and Accept. Shows a "Heads up" mode-mismatch banner but always renders
  the real detected content.
- Deliberate framing: the web page is a test tool; the iOS app is the product.
- Cost note: this makes `/v1/scan` an open, anonymous endpoint on paid Claude +
  USDA keys (see `Security.md`).

## Riva Snap V2 — `v2.html` at `/v2.html`

- **Local/uncommitted** — not deployed.
- CalorieMama-backed redesign: calm sage-white / clementine palette, Bricolage
  Grotesque + Space Mono, drag/drop + camera, lock-reticle preview, a "Top
  match" plus "Not quite? It might be…" alternates list.
- Posts to `POST /v2/scan` (the server-side CalorieMama proxy). CalorieMama is
  an identifier only — good for naming, unreliable for macros (see
  `Services.md`).
