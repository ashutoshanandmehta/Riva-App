"""Pluggable food segmentation.

- ClassicalSegmenter: GrabCut, single mask, no deps/cost. The offline default.
- Sam2ReplicateSegmenter: SAM 2 automatic mask generation on Replicate — returns a
  mask PER item, which is what closes the multi-item volume gap (§11). It over-
  segments (plate, garnish, every crumb), so masks are filtered to food-item-sized
  regions; a detector (YOLO) or tap-point prompt is the accuracy refinement.
- Sam2HTTPSegmenter: the same automatic SAM 2 idea, but served by us on a
  Lightning AI GPU Studio (backend/serving/sam2/) instead of paying Replicate
  per call — one HTTP request carries every frame of a scan.

Selection is by config: set sam2_endpoint_url (+ sam2_api_key) to use the
self-hosted Lightning backend, or replicate_api_token (+ riva_sam2_model,
default `meta/sam-2`) to use Replicate — Lightning wins when both are set,
since it has no per-call billing. Neither set = the classical fallback keeps
the pipeline working offline. NOTE: the exact Replicate input/output field
names below are from the documented meta/sam-2 automatic schema and should be
confirmed against a live token — they are centralised here and in config for
easy adjustment.
"""

import base64
import logging
import urllib.request

import cv2
import httpx
import numpy as np

from app.config import settings
from app.volumetric import geometry

logger = logging.getLogger(__name__)

MIN_AREA_FRAC = 0.01  # ignore specks (crumbs, sesame seeds)
MAX_AREA_FRAC = 0.85  # ignore whole-frame / background masks


class ClassicalSegmenter:
    name = "classical"

    def segment(self, bgr) -> list[np.ndarray]:
        m = geometry.segment_food(bgr)
        return [m] if m is not None else []

    def segment_many(self, bgrs: list[np.ndarray]) -> list[list[np.ndarray]]:
        return [self.segment(bgr) for bgr in bgrs]


class Sam2ReplicateSegmenter:
    name = "sam2-replicate"

    def __init__(self, model: str | None = None):
        import replicate  # fail early if the SDK is missing

        self._replicate = replicate
        ref = model or settings().riva_sam2_model
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
            out = self._replicate.run(
                self.model,
                input={
                    "image": data_uri,
                    "points_per_side": 32,
                    "pred_iou_thresh": 0.88,
                    "stability_score_thresh": 0.95,
                },
            )
        except Exception as error:  # billing / rate-limit / API — fail soft
            logger.warning("SAM 2 call failed (%s); classical fallback for this view", error)
            return ClassicalSegmenter().segment(bgr)
        # meta/sam-2 automatic mode -> {"combined_mask": uri, "individual_masks": [uri...]}
        urls = out.get("individual_masks") if isinstance(out, dict) else out
        h, w = bgr.shape[:2]
        frame = h * w
        masks = []
        for u in urls or []:
            arr = _download_gray(str(u))
            if arr is None:
                continue
            m = cv2.resize(arr, (w, h)) > 127
            frac = m.sum() / frame
            if MIN_AREA_FRAC <= frac <= MAX_AREA_FRAC:
                masks.append(m)
        # if SAM 2 returned nothing usable, don't fail the scan
        return masks or ClassicalSegmenter().segment(bgr)

    def segment_many(self, bgrs: list[np.ndarray]) -> list[list[np.ndarray]]:
        return [self.segment(bgr) for bgr in bgrs]


def _download_gray(url: str) -> np.ndarray | None:
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            raw = r.read()
    except Exception:
        return None
    return cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_GRAYSCALE)


def _decode_gray_png(data_b64: str) -> np.ndarray | None:
    """Base64 -> grayscale array, for the masks in a Lightning response."""
    try:
        raw = base64.b64decode(data_b64)
    except Exception:
        return None
    if not raw:
        return None
    return cv2.imdecode(np.frombuffer(raw, np.uint8), cv2.IMREAD_GRAYSCALE)


def _centrality(mask: np.ndarray, h: int, w: int) -> float:
    """1.0 at the frame centre, decaying to 0.0 at a corner. Stand-in for a
    tap-point/anchor (out of scope here, §A2): with no client-provided hint
    at which region is "the food", a mask whose centroid sits near the frame
    centre is a better bet than a stray plate rim or table edge."""
    ys, xs = np.nonzero(mask)
    if ys.size == 0:
        return 0.0
    cy, cx = float(ys.mean()), float(xs.mean())
    dy, dx = (cy - h / 2) / (h / 2), (cx - w / 2) / (w / 2)
    dist = min(1.0, (dy * dy + dx * dx) ** 0.5)
    return 1.0 - dist


class Sam2HTTPSegmenter:
    """SAM 2 automatic mask generation served by a self-hosted LitServe app
    on a Lightning AI GPU Studio (backend/serving/sam2/server.py) — same idea
    as Sam2ReplicateSegmenter but without Replicate's per-call billing. The
    whole scan's frames go in a single HTTP request (`segment_many`), which
    is the point: 6 frames = 1 round trip, not 6.

    Fail-soft is batch-level: any transport error, timeout, non-2xx, or
    response-decode failure falls the ENTIRE batch back to the classical
    segmenter (a down endpoint fails every image identically, so retrying
    per-image just spends N x the timeout for nothing). A per-image gap
    inside an otherwise-successful response (SAM 2 found nothing usable in
    one particular frame) falls back per-image instead.
    """

    name = "sam2-http"

    def __init__(self, client: httpx.Client | None = None):
        s = settings()
        self.endpoint = s.sam2_endpoint_url.rstrip("/")
        self.api_key = s.sam2_api_key
        self.timeout_s = s.sam2_timeout_s
        # `client` is a test seam (httpx.MockTransport) — production callers
        # never pass one, so this always builds a real client from settings.
        self._client = client or httpx.Client(timeout=self.timeout_s)

    def segment(self, bgr) -> list[np.ndarray]:
        return self.segment_many([bgr])[0]

    def segment_many(self, bgrs: list[np.ndarray]) -> list[list[np.ndarray]]:
        if not bgrs:
            return []
        images_b64 = []
        for bgr in bgrs:
            ok, buf = cv2.imencode(".jpg", bgr)
            images_b64.append(base64.b64encode(buf).decode() if ok else "")

        headers = {"X-API-Key": self.api_key} if self.api_key else {}
        try:
            response = self._client.post(
                f"{self.endpoint}/predict",
                json={"images": images_b64, "mode": "auto", "max_side": 512},
                headers=headers,
                timeout=self.timeout_s,
            )
            response.raise_for_status()
            results = response.json()["results"]
            if len(results) != len(bgrs):
                raise ValueError(f"expected {len(bgrs)} results, got {len(results)}")
        except Exception as error:  # network, timeout, non-2xx, bad JSON — whole-batch fallback
            logger.warning("sam2_http.failed: %s", error)
            return [ClassicalSegmenter().segment(bgr) for bgr in bgrs]

        batch: list[list[np.ndarray]] = []
        for bgr, result in zip(bgrs, results):
            h, w = bgr.shape[:2]
            frame_area = h * w
            ranked: list[tuple[float, np.ndarray]] = []
            for mask_b64 in result.get("masks") or []:
                arr = _decode_gray_png(mask_b64)
                if arr is None:
                    continue
                m = cv2.resize(arr, (w, h), interpolation=cv2.INTER_NEAREST) > 127
                frac = m.sum() / frame_area
                if not (MIN_AREA_FRAC <= frac <= MAX_AREA_FRAC):
                    continue
                ranked.append((_centrality(m, h, w) * frac, m))
            if not ranked:
                # server responded but this one frame had nothing usable
                batch.append(ClassicalSegmenter().segment(bgr))
                continue
            ranked.sort(key=lambda pair: pair[0], reverse=True)
            batch.append([m for _, m in ranked])
        return batch


def segment_batch(seg, bgrs: list[np.ndarray]) -> list[list[np.ndarray]]:
    """The batch entry point pipeline.py uses. Prefers a segmenter's own
    `segment_many` (Sam2HTTPSegmenter's real single-request batching;
    ClassicalSegmenter/Sam2ReplicateSegmenter get one via a plain loop above)
    and falls back to looping over `.segment()` for any duck-typed segmenter
    (e.g. test fakes) that only implements the single-image method — there's
    no shared base class here, so this is the "default segment_many" rather
    than a mixin/ABC, to avoid restructuring classes that work today."""
    if hasattr(seg, "segment_many"):
        return seg.segment_many(bgrs)
    return [seg.segment(bgr) for bgr in bgrs]


def get_segmenter(force: str | None = None):
    """`force` = 'classical' | 'sam2' | 'sam2-http' | 'sam2-replicate' | None.

    Selection order (None = auto by config):
      1. 'classical' always wins outright.
      2. Self-hosted Lightning SAM 2 (`sam2_endpoint_url` set) — takes
         priority over Replicate when both are configured (no per-call
         billing). 'sam2' is treated as an alias that resolves to whichever
         SAM 2 backend is actually configured, so code that already passes
         force='sam2' meaning "Replicate" is unaffected unless Lightning is
         also set up, in which case Lightning is the intended upgrade.
      3. Replicate SAM 2 ('sam2-replicate', or 'sam2' when Lightning isn't
         configured, or auto when `replicate_api_token` is set).
      4. Classical, as the final fail-soft fallback.
    """
    if force == "classical":
        return ClassicalSegmenter()

    wants_sam2 = force in ("sam2", "sam2-http")
    if wants_sam2 and settings().sam2_endpoint_url:
        try:
            return Sam2HTTPSegmenter()
        except Exception as error:
            logger.warning("SAM 2 (Lightning) unavailable (%s); trying Replicate/classical", error)
    elif force is None and settings().sam2_endpoint_url:
        try:
            return Sam2HTTPSegmenter()
        except Exception as error:
            logger.warning("SAM 2 (Lightning) unavailable (%s); trying Replicate/classical", error)
    elif force == "sam2-http":
        # Lightning explicitly requested but not configured — a distinct
        # backend was named, so don't silently substitute Replicate.
        logger.warning("sam2-http requested but sam2_endpoint_url is unset; using classical")
        return ClassicalSegmenter()

    if (
        force == "sam2-replicate"
        or force == "sam2"
        or (force is None and settings().replicate_api_token)
    ):
        try:
            return Sam2ReplicateSegmenter()
        except Exception as error:
            logger.warning("SAM 2 (Replicate) unavailable (%s); using classical segmenter", error)
    return ClassicalSegmenter()
