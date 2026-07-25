import numpy as np
import pytest

from app.plausibility import resolve_class
from app.volumetric.geometry import (
    SEG_MAX_SIDE,
    ViewEstimate,
    fuse,
    segment_food,
    view_volume,
)


def _rect_mask(h, w, y0, y1, x0, x1):
    m = np.zeros((h, w), dtype=bool)
    m[y0:y1, x0:x1] = True
    return m


def test_fuse_returns_none_with_no_estimates():
    assert fuse([None, None]) is None


def test_fuse_single_estimate_is_passthrough():
    est = ViewEstimate("top", "top", 500.0, 0.55, 10.0, 5.0)
    fused = fuse([est])
    assert fused["n_views"] == 1
    assert fused["volume_ml"] == pytest.approx(500.0)
    assert 0 < fused["confidence"] <= 1


def test_fuse_multi_estimate_is_confidence_weighted_geometric_mean():
    a = ViewEstimate("top", "top", 400.0, 0.5, 10.0, 5.0)
    b = ViewEstimate("side", "side", 400.0, 0.5, 10.0, 5.0)
    fused = fuse([a, b])
    assert fused["n_views"] == 2
    # equal volumes -> geometric mean is exactly that volume
    assert fused["volume_ml"] == pytest.approx(400.0, rel=1e-6)


def test_fuse_degrades_gracefully_from_n1_to_multi_view_agreement():
    # more views that agree perfectly should raise confidence relative to a
    # single lone view (which carries an assumed-spread penalty).
    single = fuse([ViewEstimate("top", "top", 400.0, 0.6, 10.0, 5.0)])
    double = fuse(
        [
            ViewEstimate("top", "top", 400.0, 0.6, 10.0, 5.0),
            ViewEstimate("side", "side", 400.0, 0.6, 10.0, 5.0),
        ]
    )
    assert double["confidence"] > single["confidence"]


def test_view_volume_positive_on_synthetic_mask():
    _, rec = resolve_class("burger")
    mask = _rect_mask(200, 200, 40, 160, 40, 160)
    ve = view_volume(mask, rec, "view1")
    assert ve is not None
    assert ve.volume_ml > 0
    assert ve.role in ("top", "side", "oblique")


def test_view_volume_none_on_empty_mask():
    _, rec = resolve_class("burger")
    mask = np.zeros((100, 100), dtype=bool)
    assert view_volume(mask, rec, "view1") is None


def test_view_volume_none_on_missing_mask():
    _, rec = resolve_class("burger")
    assert view_volume(None, rec, "view1") is None


def _blob_bgr(h, w):
    """Dark frame with a bright centred blob GrabCut can foreground-segment."""
    img = np.full((h, w, 3), 30, dtype=np.uint8)
    y0, y1, x0, x1 = int(h * 0.25), int(h * 0.75), int(w * 0.25), int(w * 0.75)
    img[y0:y1, x0:x1] = 210
    return img


def test_segment_food_large_frame_returns_full_res_bool_mask():
    # A frame larger than SEG_MAX_SIDE exercises the downscale -> GrabCut ->
    # nearest-neighbour upscale path; the returned mask must be full resolution.
    h, w = 1200, 1600
    assert max(h, w) > SEG_MAX_SIDE
    mask = segment_food(_blob_bgr(h, w))
    assert mask is not None
    assert mask.shape == (h, w)
    assert mask.dtype == bool
    assert mask.any()


def test_segment_food_small_frame_uses_unchanged_full_res_path():
    # A frame within SEG_MAX_SIDE clamps scale to 1.0 (no resize) and behaves
    # exactly as before: a full-size bool mask.
    h, w = 300, 400
    assert max(h, w) <= SEG_MAX_SIDE
    mask = segment_food(_blob_bgr(h, w))
    assert mask is not None
    assert mask.shape == (h, w)
    assert mask.dtype == bool
    assert mask.any()


def test_segment_food_returns_none_on_degenerate_frame():
    # A uniform frame yields no distinct foreground component -> None (fail soft).
    assert segment_food(np.full((300, 300, 3), 128, dtype=np.uint8)) is None
