"""Video -> best sharp frames. A server-side twin of the redesign's on-device
Step 3 (extract 15 evenly-spaced frames, Laplacian sharpness test, keep the best
5-6). Used to turn a captured arc clip into the multi-view frame set.
"""
from pathlib import Path

import cv2
import numpy as np

N_SAMPLE = 15   # evenly-spaced candidates
N_KEEP = 6      # sharpest to keep
MAX_EDGE = 1280  # downscale long edge (720p-ish payload)


def _sharpness(gray: np.ndarray) -> float:
    """Variance of the Laplacian — higher = sharper, lower = motion blur."""
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def extract(video_path: Path, out_dir: Path, n_keep: int = N_KEEP) -> list[Path]:
    """Sample N_SAMPLE frames, score sharpness, save the n_keep sharpest as JPEGs.
    Returns the written frame paths (sharpest first)."""
    cap = cv2.VideoCapture(str(video_path))
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 0
    if total <= 0:
        cap.release()
        raise ValueError(f"no frames in {video_path}")

    idxs = np.linspace(0, total - 1, min(N_SAMPLE, total)).astype(int)
    scored = []
    for i in idxs:
        cap.set(cv2.CAP_PROP_POS_FRAMES, int(i))
        ok, frame = cap.read()
        if not ok:
            continue
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        scored.append((_sharpness(gray), int(i), frame))
    cap.release()
    if not scored:
        raise ValueError(f"could not read frames from {video_path}")

    scored.sort(key=lambda s: -s[0])
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for rank, (score, idx, frame) in enumerate(scored[:n_keep]):
        h, w = frame.shape[:2]
        if max(h, w) > MAX_EDGE:
            scale = MAX_EDGE / max(h, w)
            frame = cv2.resize(frame, (int(w * scale), int(h * scale)))
        dest = out_dir / f"frame_{rank:02d}_src{idx:04d}.jpg"
        cv2.imwrite(str(dest), frame, [cv2.IMWRITE_JPEG_QUALITY, 90])
        written.append(dest)
    return written
