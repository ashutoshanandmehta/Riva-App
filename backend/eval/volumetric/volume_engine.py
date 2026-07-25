"""Metric food volume from one registered overhead depth frame — the geometry
core of the redesign, isolated for Phase 0.

Method: estimate the table/plate plane, take food = pixels risen above it, and
integrate (height x metric pixel-footprint) over that mask. Ground-truth N5k
depth is used here so this measures the *geometry*, not a depth model.

Intrinsics are a physical prior only: N5k's exact values are unpublished, so we
use RealSense-D435 FOV at the capture resolution. A single global scale constant
(fit downstream against GT mass) absorbs the residual fx.fy uncertainty, so the
absolute focal length is not load-bearing for the go/no-go.
"""
import numpy as np

DEPTH_UNITS_PER_M = 10000.0  # N5k: 10,000 raw units = 1 metre

# RealSense D435 depth FOV (datasheet): ~87deg H x ~58deg V.
D435_HFOV_DEG = 87.0
D435_VFOV_DEG = 58.0

# Plausible depth band for the rig (metres); everything else is a sensor hole.
Z_MIN_M = 0.05
Z_MAX_M = 0.45
MIN_FOOD_HEIGHT_M = 0.004  # 4 mm: ignore plate texture / noise


def load_depth_m(path) -> np.ndarray:
    """16-bit depth PNG -> float metres (0 where invalid)."""
    import cv2

    raw = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if raw is None:
        raise FileNotFoundError(path)
    if raw.ndim == 3:  # occasionally 3-channel; depth is channel 0
        raw = raw[..., 0]
    return raw.astype(np.float64) / DEPTH_UNITS_PER_M


def _intrinsics(width: int, height: int) -> tuple[float, float]:
    fx = (width / 2.0) / np.tan(np.radians(D435_HFOV_DEG / 2.0))
    fy = (height / 2.0) / np.tan(np.radians(D435_VFOV_DEG / 2.0))
    return fx, fy


PLATE_RIM_ABOVE_TABLE_M = 0.015  # plate/food rises >1.5 cm above the table
PLATE_SURFACE_PCTILE = 75        # within the plate, food is NEARER than the surface


def _table_depth(depth_m: np.ndarray) -> float:
    """Table plane = median depth of the outer border (the rig table, not food)."""
    h, w = depth_m.shape
    b = max(2, int(0.08 * min(h, w)))
    border = np.concatenate([
        depth_m[:b, :].ravel(), depth_m[-b:, :].ravel(),
        depth_m[:, :b].ravel(), depth_m[:, -b:].ravel(),
    ])
    border = border[(border > Z_MIN_M) & (border < Z_MAX_M)]
    if border.size == 0:
        valid = depth_m[(depth_m > Z_MIN_M) & (depth_m < Z_MAX_M)]
        return float(np.percentile(valid, 90)) if valid.size else Z_MAX_M
    return float(np.median(border))


def _food_mound(mask: np.ndarray) -> np.ndarray:
    """Largest connected component, preferring the one covering the image centre —
    isolates the food mound from stray raised edges. Stand-in for SAM 2."""
    import cv2

    n, lab = cv2.connectedComponents(mask.astype(np.uint8))
    if n <= 1:
        return mask
    cy, cx = (d // 2 for d in mask.shape)
    cid = lab[cy, cx]
    if cid == 0:
        sizes = [(lab == i).sum() for i in range(1, n)]
        cid = int(np.argmax(sizes)) + 1
    return lab == cid


def compute(depth_m: np.ndarray) -> dict:
    """Food volume (mL) measured above the PLATE surface, not the table.

    Measuring above the table would count the plate's own several-cm slab as food.
    So: isolate the plate (raised above table), estimate its surface as a high
    depth percentile (food is nearer than the plate), take the food mound as the
    central raised component, and integrate height above the plate surface.
    """
    h, w = depth_m.shape
    fx, fy = _intrinsics(w, h)
    table = _table_depth(depth_m)

    valid = (depth_m > Z_MIN_M) & (depth_m < Z_MAX_M)
    plate = valid & (depth_m < table - PLATE_RIM_ABOVE_TABLE_M)
    if plate.sum() < 500:
        return {"volume_ml": 0.0, "table_m": table, "plate_ref_m": table,
                "food_px": 0, "peak_height_cm": 0.0, "resolution": (w, h)}

    plate_ref = float(np.percentile(depth_m[plate], PLATE_SURFACE_PCTILE))
    food = plate & (depth_m < plate_ref - MIN_FOOD_HEIGHT_M)
    food = _food_mound(food)

    height = plate_ref - depth_m  # above the plate surface
    px_area = (depth_m / fx) * (depth_m / fy)  # metres^2 per pixel at depth Z
    vol_m3 = float(np.sum(np.clip(height[food], 0, None) * px_area[food]))

    return {
        "volume_ml": vol_m3 * 1e6,   # m^3 -> cm^3 == mL
        "table_m": table,
        "plate_ref_m": plate_ref,
        "food_px": int(food.sum()),
        "peak_height_cm": float(height[food].max() * 100) if food.any() else 0.0,
        "resolution": (w, h),
    }


def volume_ml(path) -> float:
    return compute(load_depth_m(path))["volume_ml"]
