"""The volumetric pipeline: multi-frame capture -> identify -> segment ->
[carve | fuse] -> gate -> assemble, end-to-end.

Two geometry paths share one segmentation pass:
- **Calibrated carve** (`carve.visual_hull_volume`, step 5): when the capture
  has per-frame ARKit poses + intrinsics (tier A/B) and at least two usable
  masks, this is the measured volume — no class-prior scale guess.
- **Parametric fallback** (`geometry.fuse`, Step 1): the classical,
  class-prior-seeded estimate. Used whenever poses are absent, the tier
  doesn't carry them, or the carve degrades (too few views, degenerate
  geometry, or an unexpected error) — carving must never turn into a 500.

Note: the mass plausibility gate inside `_assemble` still runs on the injected
grams (defense in depth), so each item's `plausibility` reflects it; the
volume gate here additionally contributes the `retake` verdict. Both gates
running is intended, not a bug.
"""

import logging
import time

import numpy as np

from app import preprocess, vision
from app.config import settings
from app.plausibility import resolve_class
from app.schemas import ScanResponse, VolumetricDebug
from app.volumetric import carve, geometry, segmenter
from app.volumetric.carve import CarveView, HullEstimate
from app.volumetric.gate import gate
from app.volumetric.payload import CaptureSet, Frame

logger = logging.getLogger(__name__)

# Tiers whose capture flow reliably ships per-frame ARKit poses/intrinsics.
# Tier C (no ARKit session) is parametric-only regardless of `poses_present`.
CARVE_ELIGIBLE_TIERS = frozenset({"A", "B"})

TRACE_CARVE_EXCEPTION = "volumetric.carve_exception_fallback"


def _representative_frame(frames: list[Frame]) -> Frame:
    """The sharpest frame stands in for the single-photo identification call;
    falls back to the first frame when no sharpness was reported."""
    scored = [f for f in frames if f.sharpness is not None]
    if scored:
        return max(scored, key=lambda f: f.sharpness)
    return frames[0]


def run_volumetric(capture: CaptureSet, fdc_api_key: str) -> ScanResponse:
    from app.main import _assemble, _llm  # lazy: avoids a main <-> volumetric import cycle

    frames = capture.frames

    # 1. Preprocess the representative frame for identification.
    started = time.monotonic()
    rep_frame = _representative_frame(frames)
    image_b64 = preprocess.prepare_image(rep_frame.image_bytes)
    preprocess_done = time.monotonic()
    logger.info(
        "volumetric preprocess: %d ms (frame=%s, n_frames=%d)",
        int((preprocess_done - started) * 1000),
        rep_frame.file,
        len(frames),
    )

    # 2. Identify (same Claude call the /v1/scan route makes).
    client, model = _llm()
    prompt_text = vision.load_prompt(settings().prompt_version)
    analysis = vision.analyze_image(
        client,
        model,
        image_b64,
        capture.hint,
        prompt_text,
        mode=capture.mode,
    )
    identify_done = time.monotonic()
    logger.info("volumetric identify: %d ms", int((identify_done - preprocess_done) * 1000))

    items = analysis.get("items") or []
    if analysis.get("scan_type") != "food" or not items:
        result = _assemble(analysis, fdc_api_key)
        result.volumetric = VolumetricDebug(
            tier=capture.tier,
            n_views=len(frames),
            segmenter="none",
            parametric_fallback=True,
            poses_present=capture.poses_present,
            reason="not food / no items",
        )
        return result

    # 3. Resolve the dominant item's food class. `food_class` from the LLM
    #    (required by SCAN_SCHEMA) wins over the alias scan when it names a
    #    real, non-"other" class — see plausibility.resolve_class.
    dominant_name = items[0]["name"]
    dominant_llm_class = items[0].get("food_class")
    food_class, class_rec = resolve_class(dominant_name, llm_class=dominant_llm_class)

    # 4. Segment every frame once, in a single batched call (auto by config:
    #    self-hosted SAM 2 on Lightning, then Replicate SAM 2, else
    #    classical — see segmenter.get_segmenter). One mask per frame ->
    #    single track, feeding BOTH downstream geometry paths below
    #    (multi-item tracks arrive with the SAM 2 associate step).
    seg = segmenter.get_segmenter(None)
    bgrs = [geometry.load_bgr_bytes(frame.image_bytes) for frame in frames]
    valid_indices = [i for i, bgr in enumerate(bgrs) if bgr is not None]
    batch_results = segmenter.segment_batch(seg, [bgrs[i] for i in valid_indices])
    frame_masks_by_index = dict(zip(valid_indices, batch_results))
    masks: list[np.ndarray | None] = []
    estimates = []
    for i, frame in enumerate(frames):
        frame_masks = frame_masks_by_index.get(i, [])
        mask = frame_masks[0] if frame_masks else None
        masks.append(mask)
        estimates.append(geometry.view_volume(mask, class_rec, frame.file))
    segment_done = time.monotonic()
    logger.info(
        "volumetric segment+geometry: %d ms (segmenter=%s, n_views=%d)",
        int((segment_done - identify_done) * 1000),
        seg.name,
        len(frames),
    )

    # 5. Calibrated carve when poses are present on an eligible tier, else the
    #    parametric fuse. A carve exception degrades to parametric, never 500.
    hull: HullEstimate | None = None
    if capture.poses_present and capture.tier in CARVE_ELIGIBLE_TIERS:
        carve_views = _build_carve_views(frames, masks)
        if len(carve_views) >= carve.MIN_VIEWS:
            try:
                hull = carve.visual_hull_volume(carve_views)
            except Exception as error:  # visual_hull_volume already fails soft; belt+suspenders
                logger.warning("%s: %s", TRACE_CARVE_EXCEPTION, error)
                hull = None

    analysis_copy = dict(analysis)
    g = None
    parametric_fallback = hull is None
    if hull is not None:
        g = gate(hull.volume_ml, dominant_name, hull.confidence, llm_class=dominant_llm_class)
    else:
        fused = geometry.fuse(estimates)
        if fused is not None:
            g = gate(
                fused["volume_ml"], dominant_name, fused["confidence"], llm_class=dominant_llm_class
            )

    # 5b. LLM-grams cross-check: a carved mass that grossly diverges (>3x)
    #     from the LLM's own summed gram estimate, under a weak class prior
    #     (_generic) or weak geometry (grid boundary hit or low confidence),
    #     is more likely a bad carve than a bad LLM guess — keep the LLM
    #     grams rather than overwrite them with the inflated/deflated carve
    #     mass. A known class with healthy geometry keeps trusting the carve
    #     unconditionally, even against a divergent LLM estimate.
    DIVERGENCE_RATIO = 3.0
    WEAK_CONFIDENCE = 0.25

    llm_grams = sum(float(item.get("portion_grams", 0)) for item in items)
    use_carve = g is not None and g.action != "retake" and g.mass_g
    mass_source = "carve" if use_carve else "llm"
    divergence_reason = None
    if use_carve and llm_grams > 0:
        ratio = g.mass_g / llm_grams
        weak_prior = food_class == "_generic"
        weak_geometry = (
            hull is not None and getattr(hull, "boundary_hit", False)
        ) or g.confidence <= WEAK_CONFIDENCE
        if (weak_prior or weak_geometry) and not (
            1 / DIVERGENCE_RATIO <= ratio <= DIVERGENCE_RATIO
        ):
            use_carve = False
            mass_source = "llm"
            divergence_reason = (
                f"carve mass {g.mass_g:.0f}g diverges >{DIVERGENCE_RATIO:g}x from LLM "
                f"{llm_grams:.0f}g under weak prior/geometry — LLM grams kept"
            )
    if use_carve:
        analysis_copy["items"] = _redistribute_grams(items, g.mass_g)
    fuse_done = time.monotonic()
    logger.info(
        "volumetric geometry+gate: %d ms (carved=%s, action=%s, mass_source=%s)",
        int((fuse_done - segment_done) * 1000),
        hull is not None,
        g.action if g else None,
        mass_source,
    )

    # 6. Ground + assemble (unchanged path — same as /v1/scan from here).
    result = _assemble(analysis_copy, fdc_api_key)
    reason = g.reason if g else "no usable per-view volume estimate — LLM grams kept"
    if divergence_reason:
        reason = f"{g.reason} — {divergence_reason}"
    result.volumetric = VolumetricDebug(
        tier=capture.tier,
        n_views=len(frames),
        segmenter=seg.name,
        parametric_fallback=parametric_fallback,
        poses_present=capture.poses_present,
        food_class=food_class,
        volume_ml=g.volume_ml if g else None,
        raw_volume_ml=g.raw_volume_ml if g else None,
        mass_g=g.mass_g if g else None,
        gate_action=g.action if g else None,
        mass_source=mass_source,
        reason=reason,
    )
    return result


def _build_carve_views(frames: list[Frame], masks: list[np.ndarray | None]) -> list[CarveView]:
    """Pairs each frame's mask with its pose/intrinsics into a `CarveView`,
    skipping any frame missing a usable mask, pose, intrinsics, or valid
    dimensions. `carve.visual_hull_volume` degrades to None (parametric
    fallback) if too few views survive this filter."""
    views = []
    for frame, mask in zip(frames, masks):
        if mask is None or frame.pose is None or not frame.intrinsics:
            continue
        if frame.width <= 0 or frame.height <= 0:
            continue
        try:
            pose = np.array(frame.pose, dtype=float).reshape(4, 4)
            fx = float(frame.intrinsics["fx"])
            fy = float(frame.intrinsics["fy"])
            cx = float(frame.intrinsics["cx"])
            cy = float(frame.intrinsics["cy"])
        except (KeyError, TypeError, ValueError) as error:
            logger.warning("volumetric.carve_view_invalid: frame=%s %s", frame.file, error)
            continue
        views.append(CarveView(mask, pose, fx, fy, cx, cy, frame.width, frame.height))
    return views


def _redistribute_grams(items: list[dict], total_grams: float) -> list[dict]:
    """Copies `items`, replacing each item's `portion_grams` with a share of
    `total_grams` proportional to its LLM estimate. All weight goes to the
    first (dominant) item if the LLM estimates summed to zero."""
    llm_total = sum(float(item.get("portion_grams", 0)) for item in items)
    updated = []
    for index, item in enumerate(items):
        item_copy = dict(item)
        if llm_total > 0:
            share = float(item.get("portion_grams", 0)) / llm_total
        else:
            share = 1.0 if index == 0 else 0.0
        item_copy["portion_grams"] = total_grams * share
        updated.append(item_copy)
    return updated
