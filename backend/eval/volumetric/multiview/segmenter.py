"""Pluggable food segmentation.

- ClassicalSegmenter: GrabCut, single mask, no deps/cost. The offline default.
- Sam2ReplicateSegmenter: SAM 2 automatic mask generation on Replicate — returns a
  mask PER item, which is what closes the multi-item volume gap (§11). It over-
  segments (plate, garnish, every crumb), so masks are filtered to food-item-sized
  regions; a detector (YOLO) or tap-point prompt is the accuracy refinement.

Selection is by env: set REPLICATE_API_TOKEN (and optionally RIVA_SAM2_MODEL,
default `meta/sam-2`) to use SAM 2; otherwise the classical fallback keeps the
pipeline working offline. NOTE: the exact Replicate input/output field names below
are from the documented meta/sam-2 automatic schema and should be confirmed against
a live token — they are centralised here and in env for easy adjustment.
"""
import base64
import os
import urllib.request

import cv2
import geometry
import numpy as np

MIN_AREA_FRAC = 0.01   # ignore specks (crumbs, sesame seeds)
MAX_AREA_FRAC = 0.85   # ignore whole-frame / background masks


class ClassicalSegmenter:
    name = "classical"

    def segment(self, bgr) -> list[np.ndarray]:
        m = geometry.segment_food(bgr)
        return [m] if m is not None else []


class Sam2ReplicateSegmenter:
    name = "sam2-replicate"

    def __init__(self, model: str | None = None):
        import replicate  # fail early if the SDK is missing
        self._replicate = replicate
        ref = model or os.environ.get("RIVA_SAM2_MODEL", "meta/sam-2")
        # replicate.run needs an explicit version for this model; resolve latest.
        if ":" not in ref:
            ref = f"{ref}:{replicate.models.get(ref).latest_version.id}"
        self.model = ref

    def segment(self, bgr) -> list[np.ndarray]:
        ok, buf = cv2.imencode(".jpg", bgr)
        if not ok:
            return []
        data_uri = "data:image/jpeg;base64," + base64.b64encode(buf).decode()
        try:
            out = self._replicate.run(self.model, input={
                "image": data_uri,
                "points_per_side": 32,
                "pred_iou_thresh": 0.88,
                "stability_score_thresh": 0.95,
            })
        except Exception as error:  # billing / rate-limit / API — fail soft
            print(f"SAM 2 call failed ({error}); classical fallback for this view")
            return ClassicalSegmenter().segment(bgr)
        # meta/sam-2 automatic mode -> {"combined_mask": uri, "individual_masks": [uri...]}
        urls = out.get("individual_masks") if isinstance(out, dict) else out
        h, w = bgr.shape[:2]
        frame = h * w
        masks = []
        for u in (urls or []):
            arr = _download_gray(str(u))
            if arr is None:
                continue
            m = cv2.resize(arr, (w, h)) > 127
            frac = m.sum() / frame
            if MIN_AREA_FRAC <= frac <= MAX_AREA_FRAC:
                masks.append(m)
        # if SAM 2 returned nothing usable, don't fail the scan
        return masks or ClassicalSegmenter().segment(bgr)


def _download_gray(url: str) -> np.ndarray | None:
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            raw = r.read()
    except Exception:
        return None
    return cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_GRAYSCALE)


def get_segmenter(force: str | None = None):
    """`force` = 'classical' | 'sam2' | None (auto by token)."""
    if force == "classical":
        return ClassicalSegmenter()
    if force == "sam2" or (force is None and os.environ.get("REPLICATE_API_TOKEN")):
        try:
            return Sam2ReplicateSegmenter()
        except Exception as error:
            print(f"SAM 2 unavailable ({error}); using classical segmenter")
    return ClassicalSegmenter()
