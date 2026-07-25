"""Multi-item, multi-view volumetric pipeline (uncalibrated RGB).

    discover N views -> segment (per-item masks) -> associate across views
    -> per-item multi-view volume -> fuse -> plausibility gate -> aggregate meal

With the classical segmenter (one food mask per view) this is single-item: all
views form one track. With SAM 2 (a mask per item) each item gets its own track and
its own measured volume — closing the §11 gap where the doc split one total volume
by LLM ratios. Cross-view association is a centroid/area heuristic (no pose); a
detector or ARKit-pose reprojection is the accuracy upgrade.
"""
import associate
import capture_set
import geometry
import plausibility
import segmenter as seg_mod
from tables import resolve_class


def _label_for(track_idx, n_tracks, names):
    if n_tracks == 1 and names:
        return names[0]
    if n_tracks == len(names) and names:
        return names[track_idx]
    return None  # counts disagree -> generic class


def run(capture_dir, items: list[dict] | None = None, segmenter=None,
        segmenter_force=None) -> dict:
    views = capture_set.discover_views(capture_dir)
    if not views:
        raise ValueError(f"no views found in {capture_dir}")

    # An explicit segmenter instance wins (e.g. a local GPU SAM 2 from a Colab
    # prototype); otherwise auto-select by env. Same volume/gate path either way.
    segmenter = segmenter or seg_mod.get_segmenter(segmenter_force)
    view_masks = [segmenter.segment(geometry.load_bgr(v)) for v in views]

    # One mask per view => single item across views (don't split by appearance).
    if all(len(m) == 1 for m in view_masks) and any(view_masks):
        tracks = [[(vi, m[0]) for vi, m in enumerate(view_masks) if m]]
    else:
        tracks = associate.associate(view_masks)
    if not tracks:
        raise ValueError("segmentation produced no usable mask on any view")

    names = [i["name"] for i in items] if items else []
    gated = []
    for ti, track in enumerate(tracks):
        name = _label_for(ti, len(tracks), names)
        _, rec = resolve_class(name)
        estimates = [geometry.view_volume(mask, rec, views[vi].name) for vi, mask in track]
        fused = geometry.fuse(estimates)
        if fused is None:
            continue
        g = plausibility.gate(fused["volume_ml"], name, fused["confidence"])
        gated.append((name or f"item_{ti + 1}", fused, g))

    logged = [g for _, _, g in gated if g.action != "retake"]
    meal = {
        "mass_g": round(sum(g.mass_g for g in logged if g.mass_g), 1),
        "kcal": round(sum(g.kcal for g in logged if g.kcal), 1),
        "n_items": len(gated),
        "n_logged": len(logged),
        "n_retake": sum(1 for _, _, g in gated if g.action == "retake"),
    }
    return {"views": [v.name for v in views], "segmenter": segmenter.name,
            "items": gated, "meal": meal}
