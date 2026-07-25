"""Builds sam2_prototype.ipynb (regenerable source of truth).
    python build_notebook.py   # writes sam2_prototype.ipynb next to this file
The notebook is self-contained (no private-repo clone) so it runs on free Colab/
Kaggle GPU. Its volume + gate logic mirrors the repo's geometry.py / plausibility.py;
tuned params graduate back into those modules.
"""
import json
from pathlib import Path

MD = "markdown"
CODE = "code"


def cell(kind, text):
    src = text.strip("\n").splitlines(keepends=True)
    base = {"cell_type": kind, "metadata": {}, "source": src}
    if kind == CODE:
        base["execution_count"] = None
        base["outputs"] = []
    return base


CELLS = [
    (MD, """
# Riva Scan — SAM 2 volumetric prototype (free GPU)

Tune SAM 2 for the multi-view volumetric flow on **free Colab/Kaggle GPU**, before
paying for a hosted endpoint.

**Practical split**
- *Here (free):* tune SAM 2 masks → per-view volume → the plausibility gate; define the metric.
- *Later (Replicate credit / Modal / RunPod):* the hosted endpoint the FastAPI backend calls, once validated.

This mirrors `backend/eval/volumetric/multiview/` — tuned params/logic port straight into
`geometry.py` / `plausibility.py`, and the winning SAM 2 config graduates behind the
existing `Segmenter` interface.

**Runtime → Change runtime type → GPU** (a free T4 is plenty).
"""),
    (CODE, """
import torch
print("CUDA:", torch.cuda.is_available(),
      torch.cuda.get_device_name(0) if torch.cuda.is_available() else "(no GPU — enable it)")
%pip -q install ultralytics transformers pillow opencv-python-headless matplotlib
"""),
    (MD, """
## 1. Load your views
Upload the N views of **one item** (e.g. the 3 burger shots). On Kaggle, set `IMG_DIR`
to your dataset path instead of uploading.
"""),
    (CODE, """
import glob, os
from pathlib import Path
import cv2, numpy as np
try:
    from google.colab import files
    paths = sorted(files.upload().keys())
except Exception:
    IMG_DIR = "/kaggle/input/your-dataset"   # <-- set on Kaggle
    paths = sorted(glob.glob(os.path.join(IMG_DIR, "*")))
imgs = [cv2.cvtColor(cv2.imread(p), cv2.COLOR_BGR2RGB) for p in paths]
print(f"{len(imgs)} view(s):", [Path(p).name for p in paths])
"""),
    (MD, """
## 2. SAM 2
- **Tap-prompt** (one click → the tapped dish): matches the redesign's tap-to-anchor and
  avoids over-segmentation. This is the recommended mode for a single dish.
- **Automatic** (segment everything): a mask per region → good for multi-item plates, but
  over-segments a single composite item (bun / patty / lettuce …).
"""),
    (CODE, """
from ultralytics import SAM
sam = SAM("sam2_b.pt")   # auto-downloads SAM 2 base weights
"""),
    (CODE, """
import matplotlib.pyplot as plt

def tap_mask(img, xy=None):
    h, w = img.shape[:2]
    x, y = xy or (w // 2, h // 2)          # app sends normalised (x,y); centre here
    r = sam(img, points=[[x, y]], labels=[1], verbose=False)
    return r[0].masks.data[0].cpu().numpy().astype(bool)

tap_masks = [tap_mask(im) for im in imgs]
fig, ax = plt.subplots(1, len(imgs), figsize=(4 * len(imgs), 4)); ax = np.atleast_1d(ax)
for i, (im, m) in enumerate(zip(imgs, tap_masks)):
    ov = im.copy(); ov[m] = (0.4 * ov[m] + 0.6 * np.array([0, 255, 0])).astype(np.uint8)
    ax[i].imshow(ov); ax[i].set_title(f"{Path(paths[i]).name}  {int(m.sum())}px"); ax[i].axis("off")
plt.show()
"""),
    (CODE, """
# Automatic mode (multi-item): filter to food-item-sized masks (same 1%..85% rule as segmenter.py)
auto = sam(imgs[0], verbose=False)[0]
raw = auto.masks.data.cpu().numpy().astype(bool) if auto.masks is not None else np.empty((0,))
frame = imgs[0].shape[0] * imgs[0].shape[1]
food = [m for m in raw if 0.01 <= m.sum() / frame <= 0.85]
print(f"{len(raw)} raw masks -> {len(food)} food-item-sized (over-segments a single dish; use tap-prompt or a YOLO seed)")
"""),
    (MD, """
## 2b. Detector-seeded SAM 2 (YOLO → boxes → one mask per item)
This is the fix for automatic over-segmentation and the doc's **YOLOv11** role: a detector
proposes one box per object, SAM 2 turns each box into a clean per-item mask. YOLO's cutlery
detections (fork/knife, known real length) double as a **scale anchor** to refine metric scale
beyond the food-class prior. COCO's food classes are sparse — swap in a food-trained detector
for production; here it demonstrates the seed → box-prompt → per-item-mask flow.
"""),
    (CODE, """
from ultralytics import YOLO
det = YOLO("yolo11x.pt")   # auto-downloads
r = det(imgs[0], verbose=False)[0]
names = r.names
boxes = r.boxes.xyxy.cpu().numpy()
classes = [names[int(c)] for c in r.boxes.cls.cpu().numpy()]
print("detections:", list(zip(classes, boxes.round().astype(int).tolist())))

FOOD_CLASSES = {"sandwich", "pizza", "donut", "cake", "hot dog", "broccoli",
                "carrot", "apple", "banana", "orange", "bowl", "cup"}
REF_CLASSES = {"fork", "knife", "spoon"}
item_boxes = [b for b, c in zip(boxes, classes) if c in FOOD_CLASSES] or list(boxes)
refs = [c for c in classes if c in REF_CLASSES]

# SAM 2 seeded by detector boxes -> one clean mask per item (no over-segmentation)
seg = sam(imgs[0], bboxes=item_boxes, verbose=False)[0]
det_masks = seg.masks.data.cpu().numpy().astype(bool) if seg.masks is not None else []
print(f"{len(item_boxes)} item box(es) -> {len(det_masks)} SAM 2 mask(s); scale refs found: {refs}")

ov = imgs[0].copy()
for m in det_masks:
    ov[m] = (0.4 * ov[m] + 0.6 * np.array([255, 120, 0])).astype(np.uint8)
plt.imshow(ov); plt.title(f"{len(det_masks)} detector-seeded item mask(s)"); plt.axis("off"); plt.show()
# For prod: run this per view, then associate masks across views (see pipeline.py / associate.py).
"""),
    (MD, """
## 3. View → volume + plausibility gate
Mirrors the repo's `geometry.view_volume` / `fuse` and `plausibility.gate`. Uncalibrated
RGB → parametric footprint×height, scale seeded from the food-class prior. **Tune `FILL`,
the class priors, and the view-role logic here, then port to `geometry.py`.**
"""),
    (CODE, """
FILL = 0.6
# compact mirror of backend/app/food_classes.json (extend as needed)
CLASSES = {
    "burger": {"footprint_cm": 11, "height_cm": 7, "density": 0.55, "kcal_100g": 250, "vol_ml": (150, 1300)},
    "rice":   {"footprint_cm": 13, "height_cm": 4, "density": 0.85, "kcal_100g": 130, "vol_ml": (80, 900)},
    "_generic": {"footprint_cm": 12, "height_cm": 5, "density": 0.6, "kcal_100g": 180, "vol_ml": (30, 1500)},
}

def view_volume(mask, rec):
    ys, xs = np.where(mask)
    if len(ys) < 50:
        return None
    bw = xs.max() - xs.min() + 1; bh = ys.max() - ys.min() + 1
    cm_per_px = rec["footprint_cm"] / max(bw, 1)          # class-prior scale seed
    aspect = bh / bw
    if aspect < 0.95:                                     # ~top-down: footprint x class height
        area_cm2 = len(ys) * cm_per_px ** 2
        return area_cm2 * rec["height_cm"] * FILL
    diam = bw * cm_per_px; height = bh * cm_per_px        # side/oblique: cylinder
    return np.pi * (diam / 2) ** 2 * height * FILL

def gate(vol_ml, rec):
    lo, hi = rec["vol_ml"]
    if vol_ml < lo / 3 or vol_ml > hi * 3:
        return "retake", vol_ml, None, None
    action, v = "log", vol_ml
    if vol_ml < lo: action, v = "clamp", lo
    elif vol_ml > hi: action, v = "clamp", hi
    mass = v * rec["density"]; kcal = mass / 100 * rec["kcal_100g"]
    return action, v, mass, kcal

FOOD_CLASS = "burger"   # <-- set to your item (or wire Claude/YOLO here)
rec = CLASSES.get(FOOD_CLASS, CLASSES["_generic"])
vols = [v for v in (view_volume(m, rec) for m in tap_masks) if v]
fused = float(np.exp(np.mean(np.log(vols)))) if vols else 0.0   # geometric mean
action, v, mass, kcal = gate(fused, rec)
print(f"per-view mL: {[round(x) for x in vols]}")
print(f"fused {fused:.0f} mL -> gate={action} vol={v:.0f} mL "
      f"mass={mass:.0f} g kcal={kcal:.0f}" if mass else f"fused {fused:.0f} mL -> {action}")
"""),
    (MD, """
## 4. (Optional) Depth Anything V2 — real depth
Monocular depth is *relative* (scale/shift ambiguous) → needs a scale anchor (container
preset / reference object / ARKit pose) before it becomes metric volume. Shown for exploration.
"""),
    (CODE, """
from transformers import pipeline as hf_pipeline
from PIL import Image
depth = hf_pipeline("depth-estimation", model="depth-anything/Depth-Anything-V2-Small-hf",
                    device=0 if torch.cuda.is_available() else -1)
d = np.array(depth(Image.fromarray(imgs[0]))["depth"])
plt.imshow(d); plt.title("relative depth (unitless)"); plt.colorbar(); plt.axis("off"); plt.show()
print("NOTE: relative/monocular — no metric scale until anchored (preset / reference / ARKit pose).")
"""),
    (MD, """
## 5. Success metric + graduation
- **Quantify** on a weighed-mass set (`backend/eval/realworld/`) or N5k: grams MAPE, R², calorie MAPE.
- **Targets** (`../METRICS.md`): beat the V1 LLM (~23% grams / ~43% cal); aim ≤15–20% grams;
  trained N5k volume-assisted mass ≈ 13.7% is the ceiling.
- **Graduate:** port tuned params into `geometry.py` / `plausibility.py`; wrap the winning SAM 2
  config as the hosted endpoint (Replicate `meta/sam-2`, or your own on Modal/RunPod) behind the
  existing `Segmenter` interface — no pipeline changes needed.
- **Tap-prompt > automatic** for single dishes; seed multi-item with a detector (YOLO) or per-item taps.
"""),
]

nb = {
    "cells": [cell(k, t) for k, t in CELLS],
    "metadata": {
        "accelerator": "GPU",
        "colab": {"provenance": [], "gpuType": "T4"},
        "kernelspec": {"display_name": "Python 3", "name": "python3"},
        "language_info": {"name": "python"},
    },
    "nbformat": 4,
    "nbformat_minor": 5,
}

out = Path(__file__).with_name("sam2_prototype.ipynb")
out.write_text(json.dumps(nb, indent=1))
print(f"wrote {out} ({len(nb['cells'])} cells)")
