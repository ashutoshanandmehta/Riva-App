"""Offline, deterministic tests for the calibrated visual-hull carver
(`app.volumetric.carve`) and its wiring into `pipeline.run_volumetric`.

The synthetic cameras/masks below are built from an INDEPENDENT re-derivation
of the pinhole convention documented at the top of `carve.py` (world -> camera
via `inv(pose)`, then `u = fx*(xc/d)+cx`, `v = fy*(-yc/d)+cy`) rather than by
calling into `carve`'s own projection helper. That keeps this the real
correctness gate for the geometry: if `carve.py`'s implementation ever
diverges from the documented convention, the recovered volume drifts and the
tolerance assertions below catch it.
"""

import itertools

import cv2
import numpy as np
import pytest

import app.grounding as grounding
import app.main as main
import app.vision as vision
import app.volumetric.pipeline as pipeline
from app.volumetric.carve import DEFAULT_GRID_SIDE_M, CarveView, visual_hull_volume
from app.volumetric.payload import CaptureSet, Frame

# --- synthetic-scene helpers (independent of carve.py's own math) ----------


def _look_at_pose(eye, target, up=(0.0, 1.0, 0.0)) -> np.ndarray:
    """Camera-to-world 4x4 for a camera at `eye` looking at `target`, using the
    ARKit convention documented in carve.py (+x right, +y up, -z forward)."""
    eye = np.array(eye, dtype=float)
    target = np.array(target, dtype=float)
    up = np.array(up, dtype=float)
    forward = target - eye
    forward = forward / np.linalg.norm(forward)
    right = np.cross(forward, up)
    right = right / np.linalg.norm(right)
    true_up = np.cross(right, forward)
    rot = np.column_stack([right, true_up, -forward])  # camera axes, in world coords
    pose = np.eye(4)
    pose[:3, :3] = rot
    pose[:3, 3] = eye
    return pose


def _project(pose, fx, fy, cx, cy, points_w: np.ndarray):
    """Independent transcription of the documented forward-projection
    convention: world points (N,3) -> (u, v, depth)."""
    pose_inv = np.linalg.inv(pose)
    homog = np.hstack([points_w, np.ones((points_w.shape[0], 1))])
    cam = homog @ pose_inv.T
    xc, yc, zc = cam[:, 0], cam[:, 1], cam[:, 2]
    d = -zc
    u = fx * (xc / d) + cx
    v = fy * (-yc / d) + cy
    return u, v, d


def _hull_mask(pose, fx, fy, cx, cy, width, height, surface_points_w) -> np.ndarray:
    """Rasterizes the true silhouette of a convex solid: the convex hull of its
    projected surface points. Exact for a cube (8 corners); a close
    approximation for a sphere given enough surface samples."""
    u, v, d = _project(pose, fx, fy, cx, cy, surface_points_w)
    assert np.all(d > 0), "synthetic camera must see the whole solid in front of it"
    pts = np.stack([u, v], axis=1).astype(np.float32)
    hull = cv2.convexHull(pts).reshape(-1, 2)
    mask = np.zeros((height, width), dtype=np.uint8)
    cv2.fillConvexPoly(mask, np.round(hull).astype(np.int32), 1)
    return mask.astype(bool)


def _cube_corners(center: np.ndarray, half: float) -> np.ndarray:
    return center + half * np.array(list(itertools.product([-1, 1], [-1, 1], [-1, 1])))


def _fibonacci_sphere(n: int) -> np.ndarray:
    """n roughly-uniform unit-sphere surface samples."""
    pts = []
    phi = np.pi * (3 - np.sqrt(5))
    for i in range(n):
        y = 1 - (i / float(n - 1)) * 2
        r = np.sqrt(max(1 - y * y, 0.0))
        theta = phi * i
        pts.append((np.cos(theta) * r, y, np.sin(theta) * r))
    return np.array(pts)


def _ring_views(
    surface_points_w,
    center,
    n_cams=8,
    radius=0.35,
    elevation=0.25,
    width=480,
    height=480,
    fx=600.0,
    cx=240.0,
) -> list[CarveView]:
    """`n_cams` cameras evenly spaced on a horizontal ring around `center`,
    all looking at it — the "arc around+above" ARKit capture pattern."""
    fy, cy = fx, cx
    views = []
    for i in range(n_cams):
        angle = 2 * np.pi * i / n_cams
        eye = (radius * np.cos(angle), elevation, radius * np.sin(angle))
        pose = _look_at_pose(eye, center)
        mask = _hull_mask(pose, fx, fy, cx, cy, width, height, surface_points_w)
        views.append(CarveView(mask, pose, fx, fy, cx, cy, width, height))
    return views


CUBE_SIDE_M = 0.08
CUBE_CENTER = np.array([0.0, 0.0, 0.0])


# --- core geometry gate ------------------------------------------------------


def test_cube_recovery_within_tolerance():
    """The correctness gate: an 8cm cube, viewed from 8 known poses on a ring
    around+above it, must recover its volume within ~30% (voxel-grid
    discretization + finite-view visual-hull slack, not a tight bound)."""
    corners = _cube_corners(CUBE_CENTER, CUBE_SIDE_M / 2)
    views = _ring_views(corners, CUBE_CENTER, n_cams=8)

    hull = visual_hull_volume(views, grid_res=48)

    assert hull is not None
    expected_ml = CUBE_SIDE_M**3 * 1e6  # 512 mL
    assert hull.n_views == 8
    assert hull.voxel_count > 0
    assert hull.volume_ml == pytest.approx(expected_ml, rel=0.30)
    assert 0.5 < hull.confidence <= 1.0  # 8 well-placed views should read as confident
    # centroid should land near the cube's true center
    assert np.linalg.norm(np.array(hull.center) - CUBE_CENTER) < 0.02


def test_cube_recovery_holds_at_fewer_views_and_coarser_grid():
    """Spec's suggested range (6-8 views, grid_res 32-48) should all pass —
    this is not a knife-edge result tuned to one exact configuration."""
    corners = _cube_corners(CUBE_CENTER, CUBE_SIDE_M / 2)
    expected_ml = CUBE_SIDE_M**3 * 1e6
    for n_cams in (6, 7, 8):
        for grid_res in (32, 40, 48):
            views = _ring_views(corners, CUBE_CENTER, n_cams=n_cams)
            hull = visual_hull_volume(views, grid_res=grid_res)
            assert hull is not None, (n_cams, grid_res)
            assert hull.volume_ml == pytest.approx(expected_ml, rel=0.30), (n_cams, grid_res)


def test_sphere_recovery_within_looser_tolerance():
    """Optional secondary shape check; a finite-sample convex-hull silhouette
    slightly undershoots a true sphere, hence the looser tolerance."""
    radius_m = 0.045
    surface = CUBE_CENTER + radius_m * _fibonacci_sphere(500)
    views = _ring_views(surface, CUBE_CENTER, n_cams=8)

    hull = visual_hull_volume(views, grid_res=48)

    assert hull is not None
    expected_ml = (4.0 / 3.0) * np.pi * radius_m**3 * 1e6
    assert hull.volume_ml == pytest.approx(expected_ml, rel=0.40)


# --- degenerate inputs -------------------------------------------------------


def test_single_view_returns_none():
    corners = _cube_corners(CUBE_CENTER, CUBE_SIDE_M / 2)
    views = _ring_views(corners, CUBE_CENTER, n_cams=1)
    assert visual_hull_volume(views, grid_res=32) is None


def test_empty_masks_return_none():
    empty = np.zeros((480, 480), dtype=bool)
    pose_a = _look_at_pose((0.35, 0.25, 0.0), CUBE_CENTER)
    pose_b = _look_at_pose((0.0, 0.25, 0.35), CUBE_CENTER)
    views = [
        CarveView(empty, pose_a, 600.0, 600.0, 240.0, 240.0, 480, 480),
        CarveView(empty, pose_b, 600.0, 600.0, 240.0, 240.0, 480, 480),
    ]
    assert visual_hull_volume(views, grid_res=32) is None


def test_near_parallel_rays_returns_low_confidence_not_none():
    """Two cameras 1mm apart pointed at the same target: the carve still runs
    (>= 2 views, non-empty masks) but the near-parallel rays make the scene-
    center triangulation ill-conditioned, so confidence must drop well below
    a well-placed 8-camera ring's."""
    corners = _cube_corners(CUBE_CENTER, CUBE_SIDE_M / 2)
    pose_a = _look_at_pose((0.35, 0.25, 0.0), CUBE_CENTER)
    pose_b = _look_at_pose((0.351, 0.251, 0.001), CUBE_CENTER)
    mask_a = _hull_mask(pose_a, 600.0, 600.0, 240.0, 240.0, 480, 480, corners)
    mask_b = _hull_mask(pose_b, 600.0, 600.0, 240.0, 240.0, 480, 480, corners)
    views = [
        CarveView(mask_a, pose_a, 600.0, 600.0, 240.0, 240.0, 480, 480),
        CarveView(mask_b, pose_b, 600.0, 600.0, 240.0, 240.0, 480, 480),
    ]

    near_parallel = visual_hull_volume(views, grid_res=32)
    well_conditioned = visual_hull_volume(_ring_views(corners, CUBE_CENTER, n_cams=8), grid_res=32)

    assert near_parallel is not None
    assert well_conditioned is not None
    assert near_parallel.confidence < 0.5
    assert near_parallel.confidence < well_conditioned.confidence


# --- B1/B2/B3: 2-view intersection, adaptive regrow, mask-extent sizing ----


def test_disjoint_two_view_masks_yield_no_false_positive_volume():
    """Regression for B1: two views of genuinely disjoint objects (no true
    overlap) must not carve a false-positive volume. Before the fix,
    `threshold = max(n_views - 1, 1) = 1` at n_views=2 meant "either mask
    agrees" — a union — so two unrelated silhouettes would still carve a
    (bogus) volume out of whatever each view separately claims. The strict
    2-view intersection requires both masks to agree, which disjoint objects
    can never do, so this must return None."""
    corners_a = _cube_corners(np.array([-0.3, 0.0, 0.0]), CUBE_SIDE_M / 2)
    corners_b = _cube_corners(np.array([0.3, 0.0, 0.0]), CUBE_SIDE_M / 2)
    pose_a = _look_at_pose((-0.3, 0.25, 0.35), np.array([-0.3, 0.0, 0.0]))
    pose_b = _look_at_pose((0.3, 0.25, 0.35), np.array([0.3, 0.0, 0.0]))
    mask_a = _hull_mask(pose_a, 600.0, 600.0, 240.0, 240.0, 480, 480, corners_a)
    mask_b = _hull_mask(pose_b, 600.0, 600.0, 240.0, 240.0, 480, 480, corners_b)
    views = [
        CarveView(mask_a, pose_a, 600.0, 600.0, 240.0, 240.0, 480, 480),
        CarveView(mask_b, pose_b, 600.0, 600.0, 240.0, 240.0, 480, 480),
    ]

    assert visual_hull_volume(views, grid_res=48) is None


def test_boundary_hit_regrow_recovers_volume_and_clears_boundary_flag():
    """Regression for B2: a grid forced too small for the object (explicit
    `grid_side_m=0.10` on a 15cm cube) hits the boundary on the first carve;
    the adaptive regrow (doubled side, still under MAX_GRID_SIDE_M) should
    escape the boundary and recover the true volume."""
    side = 0.05
    corners = _cube_corners(CUBE_CENTER, side / 2)
    views = _ring_views(corners, CUBE_CENTER, n_cams=8, radius=0.35, elevation=0.25)

    hull = visual_hull_volume(views, grid_res=48, grid_side_m=0.10)

    assert hull is not None
    assert hull.boundary_hit is False
    expected_ml = side**3 * 1e6
    assert hull.volume_ml == pytest.approx(expected_ml, rel=0.30)


def test_persistent_boundary_hit_caps_confidence():
    """Regression for B2: an object too large even for MAX_GRID_SIDE_M keeps
    `boundary_hit=True` after the regrow — the (honest, if underestimated)
    hull volume must still be returned (never None), with confidence hard-
    capped at 0.2 so the gate treats it as low-trust."""
    side = 0.60
    corners = _cube_corners(CUBE_CENTER, side / 2)
    views = _ring_views(corners, CUBE_CENTER, n_cams=8, radius=0.9, elevation=0.5)

    hull = visual_hull_volume(views, grid_res=48)

    assert hull is not None
    assert hull.boundary_hit is True
    assert hull.confidence <= 0.2


def test_grid_side_tracks_mask_extent_for_small_close_object():
    """Regression for B3: a small (~7cm) cube seen from a realistic close
    distance in 3 views should size the grid near 1.5x its true extent
    (mask-solid-angle sizing) rather than the coarse 0.30m default, and still
    recover its volume within a loose tolerance.

    `min_views_in=n_cams` (strict all-views-agree) isolates the grid-sizing
    fix under test from the separate n-1 view-tolerance behavior a 3-view
    carve gets by default (B1 only tightens the 2-view case) — at n=3 with
    the default 1-view tolerance, a handful of masks well off cube corners
    is enough to inflate the hull regardless of how tightly the grid is
    sized, which would make this test about view-count tolerance, not B3."""
    side = 0.07
    corners = _cube_corners(CUBE_CENTER, side / 2)
    n_cams = 3
    views = _ring_views(corners, CUBE_CENTER, n_cams=n_cams, radius=0.3, elevation=0.15)
    grid_res = 64

    hull = visual_hull_volume(views, grid_res=grid_res, min_views_in=n_cams)

    assert hull is not None
    expected_ml = side**3 * 1e6
    assert hull.volume_ml == pytest.approx(expected_ml, rel=0.30)

    # Recover the grid side actually used from the reported voxel geometry
    # (volume_ml = voxel_count * (side_m / grid_res)**3 * 1e6) and check it
    # landed near 1.5x the true extent, not near the old fixed 0.30m default.
    cell_m3 = (hull.volume_ml / 1e6) / hull.voxel_count
    recovered_side_m = cell_m3 ** (1.0 / 3.0) * grid_res
    target_side_m = 1.5 * side
    assert abs(recovered_side_m - target_side_m) < abs(recovered_side_m - DEFAULT_GRID_SIDE_M)


# --- pipeline integration: carve-vs-parametric branch, never a 500 ---------

FOOD_ANALYSIS = {
    "scan_type": "food",
    "reason": None,
    "plate": "white plate",
    "items": [
        {
            "name": "cheeseburger",
            "portion_desc": "1 burger",
            "portion_grams": 250,
            "is_liquid": False,
            "confidence": "high",
            "calories": 600,
            "protein_g": 30,
            "carb_g": 40,
            "fiber_g": 3,
            "fat_g": 30,
            "sugar_g": 5,
            "sodium_mg": 900,
            "alternatives": [],
        }
    ],
    "water": None,
}

VALID_POSE = list(np.eye(4).flatten())
VALID_INTRINSICS = {"fx": 600.0, "fy": 600.0, "cx": 240.0, "cy": 240.0}


class _FakeSegmenter:
    """One deterministic rectangular mask per frame — big enough for both
    `geometry.view_volume`'s pixel-count floor and `carve`'s usability check."""

    name = "test-fake"

    def segment(self, bgr):
        h, w = bgr.shape[:2]
        mask = np.zeros((h, w), dtype=bool)
        mask[h // 4 : 3 * h // 4, w // 4 : 3 * w // 4] = True
        return [mask]


def _fake_llm():
    return object(), "test-model"


def _frame(name: str, pose) -> Frame:
    return Frame(
        file=name,
        image_bytes=_solid_jpeg_bytes(),
        width=480,
        height=480,
        pose=pose,
        intrinsics=VALID_INTRINSICS if pose is not None else None,
        depth_bytes=None,
        sharpness=10.0,
    )


def _solid_jpeg_bytes() -> bytes:
    import io

    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGB", (480, 480), color=(200, 120, 80)).save(buffer, format="JPEG")
    return buffer.getvalue()


@pytest.fixture
def _pipeline_stubs(monkeypatch):
    monkeypatch.setattr(main, "_llm", _fake_llm)
    monkeypatch.setattr(vision, "analyze_image", lambda *a, **k: dict(FOOD_ANALYSIS))
    monkeypatch.setattr(grounding, "best_match", lambda api_key, name: (None, []))
    monkeypatch.setattr(pipeline.segmenter, "get_segmenter", lambda force=None: _FakeSegmenter())


def test_pipeline_falls_back_to_parametric_when_poses_absent(_pipeline_stubs):
    capture = CaptureSet(
        tier="B",
        mode="food",
        hint=None,
        frames=[_frame("f0.jpg", None), _frame("f1.jpg", None)],
    )
    result = pipeline.run_volumetric(capture, fdc_api_key="")
    assert result.volumetric.poses_present is False
    assert result.volumetric.parametric_fallback is True


def test_pipeline_falls_back_to_parametric_when_carve_returns_none(monkeypatch, _pipeline_stubs):
    monkeypatch.setattr(pipeline.carve, "visual_hull_volume", lambda *a, **k: None)
    capture = CaptureSet(
        tier="B",
        mode="food",
        hint=None,
        frames=[_frame("f0.jpg", VALID_POSE), _frame("f1.jpg", VALID_POSE)],
    )
    result = pipeline.run_volumetric(capture, fdc_api_key="")
    assert result.volumetric.poses_present is True
    assert result.volumetric.parametric_fallback is True


def test_pipeline_uses_carve_when_poses_present_and_hull_found(monkeypatch, _pipeline_stubs):
    fake_hull = pipeline.carve.HullEstimate(
        volume_ml=300.0, n_views=2, voxel_count=100, confidence=0.8, center=(0.0, 0.0, 0.0)
    )
    monkeypatch.setattr(pipeline.carve, "visual_hull_volume", lambda *a, **k: fake_hull)
    capture = CaptureSet(
        tier="B",
        mode="food",
        hint=None,
        frames=[_frame("f0.jpg", VALID_POSE), _frame("f1.jpg", VALID_POSE)],
    )
    result = pipeline.run_volumetric(capture, fdc_api_key="")
    assert result.volumetric.poses_present is True
    assert result.volumetric.parametric_fallback is False
    assert result.volumetric.raw_volume_ml == pytest.approx(300.0)
