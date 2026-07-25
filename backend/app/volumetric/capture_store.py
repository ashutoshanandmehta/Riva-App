"""Dev-only capture persistence: banks each `/v1/scan/volumetric` upload to disk
in the real-world eval dataset layout (`backend/eval/realworld/dataset.py`), so
captures taken today can be re-scored offline once the calibrated carver exists.

OFF by default — `settings().volumetric_capture_dir` must be set. Never lets a
persistence failure break the scan response: every write is best-effort and
fails soft (logs a warning, returns None).
"""

import json
import logging
import re
from pathlib import Path

from app.volumetric.payload import CaptureSet

logger = logging.getLogger(__name__)

_SLUG_RE = re.compile(r"[^a-z0-9]+")


def _slugify(label: str | None) -> str:
    if not label:
        return "capture"
    slug = _SLUG_RE.sub("_", label.lower()).strip("_")
    return slug or "capture"


def _next_index(base_dir: Path, slug: str) -> int:
    """Deterministic, collision-free counter derived from existing sibling
    dirs sharing `slug` — no clock/random, so re-runs are stable and testable."""
    pattern = re.compile(rf"^{re.escape(slug)}_(\d+)$")
    max_index = -1
    if base_dir.exists():
        for child in base_dir.iterdir():
            if not child.is_dir():
                continue
            match = pattern.match(child.name)
            if match:
                max_index = max(max_index, int(match.group(1)))
    return max_index + 1


def save(
    capture: CaptureSet,
    manifest_raw: str,
    base_dir: str,
    label: str | None,
    grams_truth: float | None,
    hint: str | None,
) -> Path | None:
    """Writes `capture` under `base_dir/<dish_id>/` in the realworld eval
    dataset layout (frames/, arkit_poses.json, manifest.json, truth.json).

    Returns the created dish dir, or None if `base_dir` is falsy or the write
    failed for any reason (fail-soft — never raises)."""
    if not base_dir:
        return None

    try:
        base = Path(base_dir)
        slug = _slugify(label)
        dish_id = f"{slug}_{_next_index(base, slug):02d}"
        dish_dir = base / dish_id
        frames_dir = dish_dir / "frames"
        frames_dir.mkdir(parents=True)

        pose_entries = []
        for index, frame in enumerate(capture.frames):
            image_name = f"frame_{index:02d}.jpg"
            (frames_dir / image_name).write_bytes(frame.image_bytes)
            entry = {
                "file": image_name,
                "pose": frame.pose,
                "intrinsics": frame.intrinsics,
                "width": frame.width,
                "height": frame.height,
            }
            if frame.depth_bytes is not None:
                depth_name = f"depth_{index:02d}.bin"
                (frames_dir / depth_name).write_bytes(frame.depth_bytes)
                entry["depth_file"] = depth_name
            pose_entries.append(entry)

        (dish_dir / "arkit_poses.json").write_text(
            json.dumps({"tier": capture.tier, "frames": pose_entries}, indent=2)
        )
        (dish_dir / "manifest.json").write_text(manifest_raw)

        truth = {"dish_id": dish_id, "name": label or "unlabeled"}
        if grams_truth is not None and grams_truth > 0:
            truth["grams_total"] = grams_truth
        truth["hint"] = hint or capture.hint
        truth["device"] = "iphone"
        truth["arkit"] = True
        truth["tier"] = capture.tier
        truth["n_frames"] = len(capture.frames)
        (dish_dir / "truth.json").write_text(json.dumps(truth, indent=2))

        logger.info(
            "volumetric capture saved: dish_id=%s n_frames=%d dir=%s",
            dish_id,
            len(capture.frames),
            dish_dir,
        )
        return dish_dir
    except Exception as error:
        logger.warning("volumetric capture persistence failed: %s", error)
        return None
