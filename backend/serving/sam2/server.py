"""Self-hosted SAM 2 segmentation API, served by LitServe.

This is a SEPARATE deployable from the main Riva Snap backend. It is meant
to run on a Lightning AI GPU Studio (see README.md in this directory for the
deploy steps), NOT inside backend/.venv and NOT in this repo's CI — nothing
here is imported by `backend/app`. The client side that talks to this server
lives at `backend/app/volumetric/segmenter.py` (`Sam2HTTPSegmenter`); the
request/response JSON contract below must stay in sync with that file.

Request (POST /predict):
    {
      "images": ["<base64 jpeg>", ...],
      "mode": "auto" | "points",       # only "auto" is implemented for now
      "points": [[[x, y], ...], ...],  # optional, mode="points" only (unused today)
      "max_side": 512                  # working-resolution cap, mirrors the
                                        # classical segmenter's SEG_MAX_SIDE
    }

Response:
    {
      "results": [
        {"masks": ["<base64 grayscale PNG, 0/255>", ...], "width": w, "height": h},
        ...  # one entry per input image, same order
      ]
    }

Auth: LitServe reads the LIT_SERVER_API_KEY environment variable itself (no
constructor kwarg — there isn't one) and, when set, requires a matching
`X-API-Key` header on every request except /health. Clients
(Sam2HTTPSegmenter) send that same header. Set LIT_SERVER_API_KEY before
running this script; nothing else is needed here to enable it.
"""

import base64
import logging
import os

import cv2
import litserve as ls
import numpy as np
import torch
from sam2.automatic_mask_generator import SAM2AutomaticMaskGenerator
from sam2.build_sam import build_sam2

logger = logging.getLogger("sam2_server")
logging.basicConfig(level=logging.INFO)

# Mirrors app/volumetric/segmenter.py's MIN_AREA_FRAC / MAX_AREA_FRAC —
# filtering server-side keeps the response small (fewer masks to ship back).
MIN_AREA_FRAC = 0.01
MAX_AREA_FRAC = 0.85

# Defaults match sam2.1_hiera_large — the variant this deployable was last
# verified against on Lightning AI. Override both if you use a different
# checkpoint. Two things that bit us getting `build_sam2()` to load on
# Lightning (see README.md "Known Lightning AI quirks"):
#   - CHECKPOINT_PATH must be an ABSOLUTE path. A relative path resolves
#     against whatever directory the process happened to start in, which is
#     not always the Studio's working directory you expect.
#   - MODEL_CONFIG must be the package-relative Hydra path
#     ("configs/sam2.1/sam2.1_hiera_l.yaml"), not a bare filename — a bare
#     filename fails to resolve under an editable (`pip install -e .`) sam2
#     install, which is how the official repo tells you to install it.
CHECKPOINT_PATH = os.environ.get(
    "SAM2_CHECKPOINT", "/teamspace/studios/this_studio/sam2/checkpoints/sam2.1_hiera_large.pt"
)
MODEL_CONFIG = os.environ.get("SAM2_CONFIG", "configs/sam2.1/sam2.1_hiera_l.yaml")


def _decode_jpeg_b64(data_b64: str) -> np.ndarray | None:
    try:
        raw = base64.b64decode(data_b64)
    except Exception:
        return None
    if not raw:
        return None
    arr = cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_COLOR)
    return arr


def _resize_max_side(bgr: np.ndarray, max_side: int) -> np.ndarray:
    h, w = bgr.shape[:2]
    scale = min(1.0, max_side / max(h, w))
    if scale >= 1.0:
        return bgr
    return cv2.resize(bgr, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)


def _mask_to_png_b64(mask: np.ndarray) -> str:
    gray = (mask.astype(np.uint8)) * 255
    ok, buf = cv2.imencode(".png", gray)
    if not ok:
        return ""
    return base64.b64encode(buf).decode()


class Sam2API(ls.LitAPI):
    """One LitServe worker: holds one SAM 2 model + automatic mask generator
    on its assigned GPU device. LitServe handles the HTTP plumbing, request
    queueing, and (if configured) batching across concurrent requests — we
    don't rely on LitServe-level batching here because a single request
    already carries every frame of a scan; see `predict` below."""

    def setup(self, device: str):
        if not os.path.isabs(CHECKPOINT_PATH) or not os.path.isfile(CHECKPOINT_PATH):
            raise FileNotFoundError(
                f"SAM2_CHECKPOINT={CHECKPOINT_PATH!r} is not an absolute path to an "
                "existing file. Set SAM2_CHECKPOINT to the absolute path where you "
                "downloaded the .pt checkpoint (relative paths resolve against "
                "whatever directory this process started in, which is rarely what "
                "you expect on a Lightning Studio)."
            )
        logger.info(
            "sam2_server.setup: loading %s (%s) on %s", CHECKPOINT_PATH, MODEL_CONFIG, device
        )
        sam2_model = build_sam2(MODEL_CONFIG, CHECKPOINT_PATH, device=device)
        # Automatic mode: the only mode this task implements end-to-end.
        # points_per_side/pred_iou_thresh/stability_score_thresh mirror the
        # values already used against the Replicate meta/sam-2 endpoint in
        # app/volumetric/segmenter.py, for comparable output between backends.
        self.mask_generator = SAM2AutomaticMaskGenerator(
            sam2_model,
            points_per_side=32,
            pred_iou_thresh=0.88,
            stability_score_thresh=0.95,
        )
        # Reserved for a future point-prompted mode (mode="points"); built
        # here so a later change doesn't need to reload the checkpoint.
        from sam2.sam2_image_predictor import SAM2ImagePredictor

        self.image_predictor = SAM2ImagePredictor(sam2_model)
        self.device = device

    def decode_request(self, request):
        images_b64 = request.get("images") or []
        mode = request.get("mode", "auto")
        max_side = int(request.get("max_side", 512))
        return {"images_b64": images_b64, "mode": mode, "max_side": max_side}

    def predict(self, inputs):
        mode = inputs["mode"]
        max_side = inputs["max_side"]
        results = []
        # Sequential, not batched: SAM2AutomaticMaskGenerator does not batch
        # well across images, so a request's whole point (one HTTP round
        # trip for N frames) is realised by looping in-process rather than
        # by requiring N HTTP calls.
        for image_b64 in inputs["images_b64"]:
            bgr = _decode_jpeg_b64(image_b64)
            if bgr is None:
                results.append({"masks": [], "width": 0, "height": 0})
                continue
            bgr = _resize_max_side(bgr, max_side)
            h, w = bgr.shape[:2]
            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)

            if mode != "auto":
                # Point-prompted mode is out of scope for this task (no
                # tap-point/anchor is sent by the client yet) — fail soft to
                # an empty result rather than a 500 for an unimplemented mode.
                logger.warning("sam2_server.unsupported_mode: %s", mode)
                results.append({"masks": [], "width": w, "height": h})
                continue

            with torch.inference_mode():
                masks = self.mask_generator.generate(rgb)

            frame_area = h * w
            keep_b64 = []
            for m in masks:
                seg = m["segmentation"]  # bool array, (h, w)
                frac = float(seg.sum()) / frame_area
                if MIN_AREA_FRAC <= frac <= MAX_AREA_FRAC:
                    keep_b64.append(_mask_to_png_b64(seg))
            results.append({"masks": keep_b64, "width": w, "height": h})
        return results

    def encode_response(self, output):
        return {"results": output}


if __name__ == "__main__":
    # LitServe reads LIT_SERVER_API_KEY from the environment itself — there
    # is no `LitServer(..., api_key=...)` constructor kwarg (passing one
    # raises a TypeError on the LitServe version this was last verified
    # against). When the env var is set, LitServe wires in its own FastAPI
    # dependency requiring a matching `X-API-Key` header on every request
    # except /health; when unset, the endpoint runs unauthenticated. Just
    # set the env var before running this script.
    if not os.environ.get("LIT_SERVER_API_KEY"):
        logger.warning(
            "sam2_server.no_api_key: LIT_SERVER_API_KEY is unset — the endpoint "
            "will be unauthenticated. Set it before exposing this Studio publicly."
        )

    server = ls.LitServer(Sam2API(), accelerator="auto")
    # Default LitServe port is 8000; the Studio's public URL maps to this.
    server.run(port=int(os.environ.get("PORT", 8000)))
