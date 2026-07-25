# SAM 2 on Lightning AI — deploy guide

This runs SAM 2 (automatic mask generation) as an HTTP API on your own
Lightning AI GPU Studio, so Riva Snap's volumetric pipeline can call it
instead of (or ahead of) Replicate. It is a separate deployable — nothing
here runs inside `backend/.venv` or this repo's tests.

## 1. Start a Studio

Open [Lightning AI](https://lightning.ai) and either:
- Search the Studio templates for "Deploy an image segmentation API with
  Meta's SAM2" and clone it, or
- Start a fresh GPU Studio (any single GPU — an L4/T4-class GPU is enough
  for `sam2.1-hiera-small` on a handful of frames per request).

## 2. Copy the server files in

Copy this directory's `server.py` and `requirements.txt` into the Studio
(drag-and-drop in the Studio file browser, or `git clone`/`scp` if you keep
this repo checked out there too).

## 3. Download the SAM 2.1 checkpoint

Follow the official SAM 2 repo's (https://github.com/facebookresearch/sam2)
current checkpoint download step (`checkpoints/download_ckpts.sh`) rather
than a URL pasted here, since Meta has moved checkpoint hosting before and a
stale link would silently 404. Defaults here target `sam2.1_hiera_large.pt`
— override with `SAM2_CHECKPOINT` / `SAM2_CONFIG` if you use a different
variant (e.g. `hiera_small` for lower latency at some accuracy cost).

## 4. Install dependencies

```bash
pip install -r requirements.txt
```

This installs `litserve`, `torch`, `sam2` (from GitHub — see the comment in
`requirements.txt`), and `opencv-python-headless`.

### Known Lightning AI quirks (already solved once — don't re-solve them)

If you set this up by cloning `facebookresearch/sam2` and installing it
editable (`pip install -e .`, the official repo's own instructions), you
will likely hit the same three issues before `server.py` will load:

- **`ModuleNotFoundError` for `sam2`** — the editable install only resolves
  from the Python environment (venv/conda env) it was installed into. Run
  `server.py` with that exact interpreter/environment active, not a fresh
  shell.
- **Import errors when run from inside the cloned `sam2/` repo root** — run
  `server.py` from a directory *outside* the cloned repo (e.g. copy it next
  to wherever you already have a working `main.py` that prints "Model
  loaded!" — same directory, same environment, no changes needed).
- **Hydra can't resolve the config filename** — `SAM2_CONFIG` must be the
  package-relative path (`configs/sam2.1/sam2.1_hiera_l.yaml`), not a bare
  filename (`sam2.1_hiera_l.yaml`). This is already `server.py`'s default;
  only override it if you're on a different hiera variant.
- **`SAM2_CHECKPOINT` must be an absolute path.** `server.py` now fails
  loudly with a clear message on startup if it isn't — no need to debug a
  Hydra/torch traceback for this one anymore.

If `python main.py` already prints "Model loaded!" in some directory/env,
copy `server.py` + `requirements.txt` into that SAME directory and run it
from there with that same environment active — you've already done the hard
part.

## 5. Set the API key

In the Studio's environment/secrets settings, set:

```
LIT_SERVER_API_KEY=<a long random string you generate yourself>
```

Clients (the Riva backend) will send this back as the `X-API-Key` header.

## 6. Run the server

```bash
python server.py
```

This starts a LitServe app on port 8000 (override with `PORT`). Lightning
Studios expose a port as a public HTTPS URL from the Studio's "Ports" /
"Endpoints" panel — open port 8000 there and copy the generated URL.

## 7. Verify

Health check (LitServe exposes `/health` by default):

```bash
curl https://<your-studio-url>/health
```

Real inference (base64-encode a test JPEG and POST it):

```bash
IMG_B64=$(base64 -i test_food.jpg | tr -d '\n')
curl -X POST https://<your-studio-url>/predict \
  -H "X-API-Key: $LIT_SERVER_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"images\": [\"$IMG_B64\"], \"mode\": \"auto\", \"max_side\": 512}"
```

You should get back `{"results": [{"masks": ["<base64 png>", ...], "width": ..., "height": ...}]}`.
If `masks` is empty, check the Studio logs — `sam2_server.setup` logs the
checkpoint path and device it loaded on startup.

## 8. Wire it into the backend

Copy the Studio's public URL and the API key you set in step 5 into
`backend/.env`:

```
SAM2_ENDPOINT_URL=https://<your-studio-url>
SAM2_API_KEY=<the same LIT_SERVER_API_KEY value>
```

`app.volumetric.segmenter.get_segmenter()` picks this backend up
automatically once `SAM2_ENDPOINT_URL` is set (it takes priority over
`REPLICATE_API_TOKEN` if both are configured) — no other backend restart
step beyond picking up the new `.env` values.
