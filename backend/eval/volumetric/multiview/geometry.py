"""Per-view food geometry + multi-view fusion, for UNCALIBRATED RGB views.

- Segmentation: GrabCut seeded by a centre rectangle (a stand-in for SAM 2 seeded
  by the tap anchor). Returns the food footprint mask.
- View role: inferred heuristically from mask geometry (a stand-in for ARKit
  camera pose). top = footprint, side = height, oblique = both (weaker).
- Per-view volume: parametric. Metric scale is SEEDED from the food-class footprint
  prior (refined per class), not from calibration.
- Fusion: confidence-weighted geometric mean across views; complementary roles
  (footprint from top, height from side) reinforce. Degrades to N=1 with a penalty.

Everything here is the classical fallback. SAM 2 masks, monocular/ARKit depth, and
calibrated space-carving slot in behind the same ViewEstimate/fuse interface.
"""
from dataclasses import dataclass

import cv2
import numpy as np

FILL = 0.6  # irregular-solid fill fraction (food is not a solid cylinder)


@dataclass
class ViewEstimate:
    view: str
    role: str
    volume_ml: float
    confidence: float
    footprint_cm: float
    height_cm: float


def load_bgr(path):
    return cv2.imread(str(path), cv2.IMREAD_COLOR)  # drops alpha, BGR


def segment_food(bgr, seed_xy: tuple[float, float] | None = None) -> np.ndarray | None:
    """GrabCut from a centre-rectangle seed (the tap anchor). Returns bool mask
    of the largest foreground component; None if segmentation fails."""
    h, w = bgr.shape[:2]
    rect = (int(w * 0.12), int(h * 0.10), int(w * 0.76), int(h * 0.82))
    mask = np.zeros((h, w), np.uint8)
    try:
        cv2.grabCut(bgr, mask, rect, np.zeros((1, 65)), np.zeros((1, 65)), 3,
                    cv2.GC_INIT_WITH_RECT)
    except Exception:
        return None
    fg = ((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)).astype(np.uint8)
    n, lab = cv2.connectedComponents(fg)
    if n <= 1:
        return None
    sizes = [(lab == i).sum() for i in range(1, n)]
    return lab == (int(np.argmax(sizes)) + 1)


def infer_role(mask: np.ndarray) -> str:
    ys, xs = np.where(mask)
    if len(ys) < 50:
        return "oblique"
    h, w = mask.shape
    cy = ys.mean() / h
    bw, bh = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    aspect = bh / bw
    touches_bottom = ys.max() > 0.93 * h
    if cy < 0.52 and aspect < 0.95 and not touches_bottom:
        return "top"
    if aspect > 0.8 or touches_bottom:
        return "side"
    return "oblique"


def view_volume(mask, class_rec: dict, view_name: str) -> ViewEstimate | None:
    """Parametric per-view volume. Scale seeded from the class footprint prior."""
    if mask is None:
        return None
    ys, xs = np.where(mask)
    if len(ys) < 50:
        return None
    area_px = len(ys)
    bw, bh = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    foot_typ = class_rec["footprint_cm"][1]
    height_typ = class_rec["height_cm"][1]
    role = infer_role(mask)

    # class-prior scale: the food's widest extent ~ the class's typical footprint.
    cm_per_px = foot_typ / max(bw, 1)

    if role == "top":
        footprint_cm2 = area_px * cm_per_px ** 2      # real top-projected area
        height_cm = height_typ                        # top view can't see height
        volume = footprint_cm2 * height_cm * FILL
        conf = 0.55
        footprint = (4 * footprint_cm2 / np.pi) ** 0.5
    else:  # side / oblique: width -> diameter, mask height -> stack height
        diam_cm = bw * cm_per_px
        height_cm = bh * cm_per_px * (0.85 if role == "oblique" else 1.0)
        volume = np.pi * (diam_cm / 2) ** 2 * height_cm * FILL
        conf = 0.60 if role == "side" else 0.50
        footprint = diam_cm

    return ViewEstimate(view_name, role, float(volume), conf,
                        float(footprint), float(height_cm))


def fuse(estimates: list[ViewEstimate | None]) -> dict | None:
    """Confidence-weighted geometric mean of per-view volumes. More views + tighter
    agreement -> higher confidence. N=1 works, with a penalty."""
    est = [e for e in estimates if e]
    if not est:
        return None
    vols = np.array([e.volume_ml for e in est])
    ws = np.array([e.confidence for e in est])
    logv = np.log(vols)
    volume = float(np.exp(np.sum(ws * logv) / np.sum(ws)))
    spread = float(np.std(logv)) if len(est) > 1 else 0.6  # lone view => assumed spread
    agreement = float(np.exp(-spread))
    n_factor = min(len(est) / 3.0, 1.0)
    confidence = float(np.clip(np.mean(ws) * (0.5 + 0.5 * agreement) * (0.6 + 0.4 * n_factor), 0, 1))
    return {"volume_ml": volume, "confidence": confidence, "n_views": len(est),
            "estimates": est}
