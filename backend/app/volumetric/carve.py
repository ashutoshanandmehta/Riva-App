"""Calibrated visual-hull volume carver — the ARKit metric path (step 5).

Uses per-frame camera poses + intrinsics + food masks to carve a 3D voxel grid
down to the region consistent with every view's silhouette, then reports the
occupied volume directly in metric units (no class-prior scale guess). This is
the path `eval/volumetric/FINDINGS.md` recommends promoting to REQUIRED (not a
"nice to have" fallback): a single top-down frame cannot resolve pile height or
the plate/food boundary, so `geometry.fuse`'s parametric estimate stays wired
as the degrade path for when poses are absent (see `pipeline.run_volumetric`).

CAVEAT (carried from FINDINGS.md): this module's output is only as good as the
input masks. A mask that leaks onto the plate inflates every voxel a plate
pixel touches, in every view — visual-hull carving does not correct for bad
segmentation, it compounds it. SAM 2-quality masks are a hard requirement, not
a nicety. Final geometric correctness (this module only proves internal
consistency against synthetic masks) is validated against real ARKit captures
in step 6.

## Coordinate conventions (ARKit) — read this before touching the math below

- `pose` is **camera-to-world**, row-major 4x4, exactly as iOS serializes
  `frame.camera.transform` (row-major). Reshape with
  `np.array(pose).reshape(4, 4)` — never `.reshape(4, 4).T`.
- ARKit camera space: **+x right, +y up, -z forward** (the scene the camera is
  looking at is at *negative* z in its own frame). World space is
  gravity-aligned, **+y up**.
- Forward projection (world point `Xw` -> pixel `(u, v)`), the convention every
  function in this module implements and the synthetic tests generate their
  masks from:

      Xc = inv(pose) @ [Xw, 1]        # world -> camera
      xc, yc, zc = Xc[:3]
      in_front = zc < 0               # camera looks down -z
      d = -zc                         # positive depth along the view axis
      u = fx * (xc / d) + cx
      v = fy * (-yc / d) + cy         # image y grows down, camera y grows up

  The minus sign on the `v` row is not a typo — it is the camera-up-vs-
  image-down flip, and it is the single most common bug when wiring this kind
  of code. Back-projection (pixel -> world ray) is the algebraic inverse of
  the same four lines (see `_pixel_ray_world`).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

import numpy as np

logger = logging.getLogger(__name__)

# --- stable trace codes for every fail-soft exit (grep-able, never renamed) ---
TRACE_INSUFFICIENT_VIEWS = "carve.insufficient_views"  # < 2 views with a usable mask
TRACE_CENTER_UNSOLVABLE = "carve.center_unsolvable"  # ray-intersection linear solve failed
TRACE_NO_VOXELS_OCCUPIED = "carve.no_voxels_occupied"  # masks agreed on nothing in the grid
TRACE_EXCEPTION = "carve.exception"  # unexpected error anywhere in the pipeline

MIN_VIEWS = 2
DEFAULT_GRID_SIDE_M = 0.30  # starting cube side; may shrink toward ray convergence
MIN_GRID_SIDE_M = 0.10  # never shrink below a plausible single-plate-item bbox
MAX_GRID_SIDE_M = 0.45  # ceiling for the adaptive regrow-on-boundary-hit retry
DEFAULT_MARGIN_BELOW_M = 0.02  # gravity-plane cut sits this far below the lowest ray hit


@dataclass
class CarveView:
    mask: np.ndarray  # bool HxW, True = food
    pose: np.ndarray  # 4x4 camera->world, row-major semantics (see module docstring)
    fx: float
    fy: float
    cx: float
    cy: float
    width: int
    height: int


@dataclass
class HullEstimate:
    volume_ml: float
    n_views: int
    voxel_count: int
    confidence: float  # 0..1, lower for few/degenerate views
    center: tuple[float, float, float]  # world (x, y, z) of the hull centroid
    boundary_hit: bool = False  # True if the hull still touches the grid wall


def _usable_views(views: list[CarveView]) -> list[CarveView]:
    return [v for v in views if v.mask is not None and bool(v.mask.any())]


def _camera_origin(pose: np.ndarray) -> np.ndarray:
    return pose[:3, 3]


def _mask_centroid_px(mask: np.ndarray) -> tuple[float, float] | None:
    """(u, v) pixel centroid of the True region, or None if empty."""
    ys, xs = np.where(mask)
    if len(ys) == 0:
        return None
    return float(xs.mean()), float(ys.mean())


def _pixel_ray_world(view: CarveView, u: float, v: float) -> tuple[np.ndarray, np.ndarray]:
    """Back-projects pixel (u, v) to a world-space ray (origin, unit direction),
    inverting the forward-projection convention documented at module top."""
    dir_c = np.array([(u - view.cx) / view.fx, -(v - view.cy) / view.fy, -1.0])
    rot = view.pose[:3, :3]
    dir_w = rot @ dir_c
    norm = np.linalg.norm(dir_w)
    if norm < 1e-12:
        dir_w = np.array([0.0, 0.0, -1.0])
    else:
        dir_w = dir_w / norm
    origin = _camera_origin(view.pose)
    return origin, dir_w


def _triangulate_center(origins: np.ndarray, dirs: np.ndarray) -> tuple[np.ndarray | None, float]:
    """Least-squares closest point to a set of rays (origin_i, dir_i). Returns
    (center, ray_conditioning) where ray_conditioning in [0, 1] is the ratio of
    the smallest to largest eigenvalue of the accumulated normal-equations
    matrix — near 0 when the rays are close to parallel (ill-conditioned; the
    solve is still attempted via least squares, never raises)."""
    a = np.zeros((3, 3))
    b = np.zeros(3)
    for origin, direction in zip(origins, dirs):
        proj = np.outer(direction, direction)
        contrib = np.eye(3) - proj
        a += contrib
        b += contrib @ origin
    try:
        center, *_ = np.linalg.lstsq(a, b, rcond=None)
    except np.linalg.LinAlgError:
        return None, 0.0
    if not np.all(np.isfinite(center)):
        return None, 0.0
    eigvals = np.linalg.eigvalsh(a)
    max_eig = float(eigvals[-1])
    min_eig = float(max(eigvals[0], 0.0))
    conditioning = min_eig / max_eig if max_eig > 1e-9 else 0.0
    return center, float(np.clip(conditioning, 0.0, 1.0))


def _ray_closest_approach(
    origin: np.ndarray, direction: np.ndarray, point: np.ndarray
) -> np.ndarray:
    """Point on the ray (origin, direction) nearest to `point`; clips the ray
    parameter to >= 0 so a degenerate/behind-camera solve can't return a point
    physically behind the lens."""
    t = float(np.dot(point - origin, direction))
    t = max(t, 0.0)
    return origin + t * direction


def _project_points(
    view: CarveView, points_w: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Vectorized forward projection of world points (N,3) into `view`'s image
    plane. Returns (u, v, in_front) — u/v are unrounded pixel coordinates;
    in_front is True where the point is on the camera's viewing side."""
    pose_inv = np.linalg.inv(view.pose)
    homog = np.hstack([points_w, np.ones((points_w.shape[0], 1))])  # (N,4)
    cam = homog @ pose_inv.T  # (N,4), row i = inv(pose) @ [Xw_i,1]
    xc, yc, zc = cam[:, 0], cam[:, 1], cam[:, 2]
    d = -zc
    in_front = d > 1e-9
    safe_d = np.where(in_front, d, 1.0)  # avoid div-by-zero; result discarded via in_front
    u = view.fx * (xc / safe_d) + view.cx
    v = view.fy * (-yc / safe_d) + view.cy
    return u, v, in_front


def _build_voxel_grid(
    center: np.ndarray, side_m: float, grid_res: int
) -> tuple[np.ndarray, np.ndarray, float]:
    """Cell-centered voxel sampling of a cube centered at `center`. Returns
    (voxel_centers (N,3), y_index per voxel (N,) for the support-plane cut,
    voxel_volume_m3)."""
    cell = side_m / grid_res
    offsets = (np.arange(grid_res) + 0.5) * cell - side_m / 2.0
    gx, gy, gz = np.meshgrid(offsets, offsets, offsets, indexing="ij")
    voxel_centers = np.stack(
        [center[0] + gx.ravel(), center[1] + gy.ravel(), center[2] + gz.ravel()], axis=1
    )
    y_index = gy.ravel()  # same shape/order as voxel_centers; used to reshape occupancy later
    return voxel_centers, y_index, cell**3


def visual_hull_volume(
    views: list[CarveView],
    grid_res: int = 64,
    min_views_in: int | None = None,
    grid_side_m: float = DEFAULT_GRID_SIDE_M,
    margin_below_m: float = DEFAULT_MARGIN_BELOW_M,
) -> HullEstimate | None:
    """Carves a voxel grid down to the region every (or nearly every) view's
    mask agrees is food, and reports its volume. Fails soft: any degenerate
    input or internal error returns None (never raises) so the caller
    (`pipeline.run_volumetric`) can fall back to the parametric estimate.
    """
    try:
        return _visual_hull_volume(views, grid_res, min_views_in, grid_side_m, margin_below_m)
    except Exception as error:  # fail soft — a bad capture must never 500 the scan
        logger.warning("%s: unexpected carve failure: %s", TRACE_EXCEPTION, error)
        return None


def _visual_hull_volume(
    views: list[CarveView],
    grid_res: int,
    min_views_in: int | None,
    grid_side_m: float,
    margin_below_m: float,
) -> HullEstimate | None:
    usable = _usable_views(views)
    if len(usable) < MIN_VIEWS:
        logger.warning(
            "%s: %d usable view(s) (need >= %d); degrading to parametric",
            TRACE_INSUFFICIENT_VIEWS,
            len(usable),
            MIN_VIEWS,
        )
        return None

    # --- 1. scene center: least-squares intersection of mask-centroid rays ---
    origins, dirs = [], []
    for view in usable:
        centroid = _mask_centroid_px(view.mask)
        if centroid is None:
            continue
        origin, direction = _pixel_ray_world(view, *centroid)
        origins.append(origin)
        dirs.append(direction)
    if len(origins) < MIN_VIEWS:
        logger.warning(
            "%s: %d ray(s) resolved from masks (need >= %d)",
            TRACE_INSUFFICIENT_VIEWS,
            len(origins),
            MIN_VIEWS,
        )
        return None

    origins_arr = np.array(origins)
    dirs_arr = np.array(dirs)
    center, ray_conditioning = _triangulate_center(origins_arr, dirs_arr)
    if center is None:
        logger.warning("%s: ray-intersection linear solve failed", TRACE_CENTER_UNSOLVABLE)
        return None

    # --- 2. grid sizing + gravity-aligned support-plane cut (approximation;
    #        step 6 replaces this with a real ARKit plane) ---
    approach_points = np.array(
        [_ray_closest_approach(o, d, center) for o, d in zip(origins_arr, dirs_arr)]
    )
    deviations = approach_points - center
    spread_rms = float(np.sqrt(np.mean(np.sum(deviations**2, axis=1))))

    # Ray-convergence spread alone under-sizes the grid whenever the mask
    # centroid rays happen to intersect cleanly (two well-converging rays can
    # collapse `shrink_candidate` to the 0.10m floor regardless of how large
    # the object actually looks in either mask). Cross-check against each
    # usable view's own claimed angular extent — the mask bounding box,
    # converted to a metric size at the triangulated center's distance from
    # that view's camera — so the grid tracks what the masks say, not just
    # where their centroids agree.
    extents_m = []
    for view in usable:
        origin = _camera_origin(view.pose)
        dist = float(np.linalg.norm(center - origin))
        ys, xs = np.where(view.mask)
        bbox_max_px = max(float(xs.max() - xs.min()), float(ys.max() - ys.min()))
        theta = 2.0 * np.arctan(bbox_max_px / (2.0 * view.fx))
        extents_m.append(2.0 * dist * np.tan(theta / 2.0))
    median_extent_m = float(np.median(extents_m))

    shrink_candidate = max(4.0 * spread_rms, 1.5 * median_extent_m)
    side_m = float(np.clip(min(grid_side_m, shrink_candidate), MIN_GRID_SIDE_M, MAX_GRID_SIDE_M))

    lowest_hit_y = float(approach_points[:, 1].min())

    n_views = len(usable)
    if min_views_in is not None:
        threshold = min_views_in
    else:
        # At exactly 2 views there is no "one bad mask" tolerance to give:
        # n-1 would require only 1/2 views to agree, which is a UNION of the
        # two masks, not an intersection — not defensible as a visual hull.
        # Only at >= 3 views do we tolerate one degenerate mask.
        threshold = n_views if n_views == 2 else max(n_views - 1, 1)
    threshold = int(np.clip(threshold, 1, n_views))

    # --- 3/4. carve + confidence at the sized grid; adaptively regrow once if
    #          the hull touches the boundary (grid was too small for the item).
    result = _carve_at_side(
        usable,
        center,
        side_m,
        grid_res,
        lowest_hit_y,
        margin_below_m,
        n_views,
        threshold,
        ray_conditioning,
    )
    if result is None:
        return None

    if result.boundary_hit and side_m < MAX_GRID_SIDE_M:
        regrown_side_m = min(side_m * 2.0, MAX_GRID_SIDE_M)
        logger.info(
            "carve.grid_regrown: boundary hit at side_m=%.3f, retrying at side_m=%.3f",
            side_m,
            regrown_side_m,
        )
        retried = _carve_at_side(
            usable,
            center,
            regrown_side_m,
            grid_res,
            lowest_hit_y,
            margin_below_m,
            n_views,
            threshold,
            ray_conditioning,
        )
        if retried is not None:
            result = retried
            side_m = regrown_side_m

    if result.boundary_hit:
        # Still touching after the regrow: the volume is honest (it is what
        # the masks + grid agree on) but likely an underestimate of the true
        # extent. Never discard it — a None here falls back to the weaker
        # parametric path, which is worse for genuinely large items — just
        # hard-cap confidence so the gate treats it as low-trust.
        logger.warning(
            "carve.grid_boundary_hit: hull touches the %.2fm grid boundary — "
            "grid likely too small for this item; confidence capped",
            side_m,
        )
        result.confidence = min(result.confidence, 0.2)

    logger.info(
        "visual hull: n_views=%d voxel_count=%d/%d volume_ml=%.1f confidence=%.2f "
        "grid_side_m=%.3f ray_conditioning=%.3f (masks assumed clean silhouettes; "
        "see eval/volumetric/FINDINGS.md)",
        n_views,
        result.voxel_count,
        grid_res**3,
        result.volume_ml,
        result.confidence,
        side_m,
        ray_conditioning,
    )

    return result


def _carve_at_side(
    usable: list[CarveView],
    center: np.ndarray,
    side_m: float,
    grid_res: int,
    lowest_hit_y: float,
    margin_below_m: float,
    n_views: int,
    threshold: int,
    ray_conditioning: float,
) -> HullEstimate | None:
    """Builds a voxel grid of `side_m` centered at `center`, carves it against
    every usable view's mask, and scores confidence — the full carve+confidence
    step, pulled out so B2's adaptive regrow-on-boundary-hit can call it twice
    (initial size, then a doubled side) without duplicating the carve math.
    Returns None if no voxel survives the occupancy threshold (fatal for this
    side; the caller decides whether to retry or give up)."""
    plate_cutoff_y = lowest_hit_y - margin_below_m
    grid_bottom_y = center[1] - side_m / 2.0
    grid_top_y = center[1] + side_m / 2.0
    if not (grid_bottom_y < plate_cutoff_y < grid_top_y):
        # heuristic degenerated (rays converged outside the grid) — skip the
        # cut rather than carve away the whole grid or do nothing useful.
        plate_cutoff_y = grid_bottom_y

    voxel_centers, y_offsets, voxel_volume_m3 = _build_voxel_grid(center, side_m, grid_res)
    above_plate = (y_offsets + center[1]) >= plate_cutoff_y

    n_voxels = voxel_centers.shape[0]
    counts = np.zeros(n_voxels, dtype=np.int32)
    for view in usable:
        u, v, in_front = _project_points(view, voxel_centers)
        h, w = view.mask.shape
        in_bounds = in_front & (u >= 0) & (u < w) & (v >= 0) & (v < h)
        ui = np.clip(u, 0, w - 1).astype(np.int64)
        vi = np.clip(v, 0, h - 1).astype(np.int64)
        sampled = view.mask[vi, ui]
        counts += (in_bounds & sampled).astype(np.int32)

    occupied = above_plate & (counts >= threshold)
    voxel_count = int(occupied.sum())
    if voxel_count == 0:
        logger.warning(
            "%s: 0/%d voxels occupied at threshold=%d/%d views (side_m=%.3f)",
            TRACE_NO_VOXELS_OCCUPIED,
            n_voxels,
            threshold,
            n_views,
            side_m,
        )
        return None

    volume_ml = voxel_count * voxel_volume_m3 * 1e6

    occupied_grid = occupied.reshape(grid_res, grid_res, grid_res)  # (x, y, z), matches meshgrid
    boundary_hit = bool(
        occupied_grid[0, :, :].any()
        or occupied_grid[-1, :, :].any()
        or occupied_grid[:, -1, :].any()  # top only — bottom is intentionally plate-cut
        or occupied_grid[:, :, 0].any()
        or occupied_grid[:, :, -1].any()
    )
    occupied_fraction = voxel_count / n_voxels
    view_factor = min(n_views / 4.0, 1.0)
    boundary_factor = 0.5 if boundary_hit else 1.0
    occ_factor = 0.5 if (occupied_fraction > 0.9 or occupied_fraction < 1e-4) else 1.0
    confidence = float(
        np.clip(
            0.4 * view_factor + 0.3 * ray_conditioning + 0.15 * boundary_factor + 0.15 * occ_factor,
            0.0,
            1.0,
        )
    )

    return HullEstimate(
        volume_ml=float(volume_ml),
        n_views=n_views,
        voxel_count=voxel_count,
        confidence=confidence,
        center=(float(center[0]), float(center[1]), float(center[2])),
        boundary_hit=boundary_hit,
    )
