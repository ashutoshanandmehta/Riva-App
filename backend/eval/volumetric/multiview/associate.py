"""Associate per-view masks into per-item tracks across N views.

Uncalibrated views => no epipolar geometry to correspond masks. Heuristic: match
by normalised centroid + relative area (greedy nearest, thresholded). A stand-in
for proper cross-view correspondence (appearance embeddings / ARKit-pose reprojection).

Single item per view (classical segmenter) collapses to one track trivially.
"""
import numpy as np

MATCH_THRESH = 0.35  # max feature distance to join a mask to an existing track


def _feat(mask: np.ndarray) -> np.ndarray | None:
    ys, xs = np.where(mask)
    if len(ys) == 0:
        return None
    h, w = mask.shape
    return np.array([xs.mean() / w, ys.mean() / h, (mask.sum() / (h * w)) ** 0.5])


def associate(view_masks: list[list[np.ndarray]]) -> list[list[tuple[int, np.ndarray]]]:
    """view_masks[i] = masks in view i. Returns tracks; each track is a list of
    (view_index, mask), at most one mask per view."""
    tracks: list[dict] = []  # {feat, members:[(vi,mask)]}
    for vi, masks in enumerate(view_masks):
        feats = [(_feat(m), m) for m in masks]
        feats = [(f, m) for f, m in feats if f is not None]
        used_tracks = set()
        for f, m in feats:
            best, best_d = None, MATCH_THRESH
            for ti, tr in enumerate(tracks):
                if ti in used_tracks:
                    continue
                d = float(np.linalg.norm(tr["feat"] - f))
                if d < best_d:
                    best, best_d = ti, d
            if best is None:
                tracks.append({"feat": f, "members": [(vi, m)]})
                used_tracks.add(len(tracks) - 1)
            else:
                tr = tracks[best]
                tr["members"].append((vi, m))
                # running-average the feature
                tr["feat"] = (tr["feat"] * (len(tr["members"]) - 1) + f) / len(tr["members"])
                used_tracks.add(best)
    # biggest/most-supported tracks first
    tracks.sort(key=lambda t: -len(t["members"]))
    return [t["members"] for t in tracks]
