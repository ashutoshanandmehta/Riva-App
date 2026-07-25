"""Predictors turn a dish's frames + truth into a nutrition estimate. A predictor
is any callable: (frames: list[Path], truth: dict) -> dict with at least
{"grams": float}, optionally {"kcal", "items", "name"}.

`v1_llm` is the current shipping pipeline (Claude vision + USDA grounding) run on
the sharpest frame — the real-world BASELINE the volumetric pipeline must beat.

`volumetric` re-scores a banked ARKit capture (written by
`app.volumetric.capture_store.save` when `VOLUMETRIC_CAPTURE_DIR` is set)
through the full volumetric pipeline offline, so accuracy changes can be
measured on this harness without a new phone capture each time.
"""

import json
import os
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[2]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))


def _load_backend_env() -> None:
    """Make the harness cwd-independent: load backend/.env into the environment
    (pydantic reads .env relative to cwd, which isn't backend/ when run here)."""
    env = BACKEND / ".env"
    if not env.exists():
        return
    for line in env.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, val = line.partition("=")
        os.environ.setdefault(key.strip(), val.strip())


def v1_llm(frames: list[Path], truth: dict) -> dict:
    """Baseline: single-frame Claude scan + USDA grounding (the shipping pipeline)."""
    from app import preprocess, vision  # noqa: E402
    from app.config import settings  # noqa: E402
    from app.main import _assemble  # noqa: E402

    if not frames:
        return {"grams": None}
    _load_backend_env()
    config = settings()
    client = vision.make_client(config)
    model = vision.resolve_model(config)
    prompt = vision.load_prompt(config.prompt_version)

    image_b64 = preprocess.prepare_image(frames[0].read_bytes())  # sharpest frame
    analysis = vision.analyze_image(client, model, image_b64, truth.get("hint"), prompt)
    result = _assemble(analysis, config.fdc_api_key)

    grams = sum(i.portion_grams for i in result.items) or None
    return {
        "grams": grams,
        "kcal": result.totals.calories if result.items else None,
        "items": [i.name for i in result.items],
        "name": result.items[0].name if result.items else None,
    }


def _load_arkit_frames(dish_dir: Path) -> tuple[list, str]:
    """Rebuilds `Frame` objects from a banked capture's `arkit_poses.json` —
    the authoritative index mapping renamed `frames/frame_NN.jpg` files to
    their pose/intrinsics (`manifest.json` keeps the ORIGINAL client
    filenames and is not usable for this)."""
    from app.volumetric.payload import Frame  # noqa: E402

    poses = json.loads((dish_dir / "arkit_poses.json").read_text())
    frames_dir = dish_dir / "frames"
    frames = []
    for entry in poses["frames"]:
        depth_file = entry.get("depth_file")
        frames.append(
            Frame(
                file=entry["file"],
                image_bytes=(frames_dir / entry["file"]).read_bytes(),
                width=entry["width"],
                height=entry["height"],
                pose=entry.get("pose"),
                intrinsics=entry.get("intrinsics"),
                depth_bytes=(frames_dir / depth_file).read_bytes() if depth_file else None,
                sharpness=None,
            )
        )
    return frames, poses["tier"]


def _load_still_frames(frames: list[Path]) -> list:
    """Fallback for stills-only dishes with no ARKit session: no poses/
    intrinsics, so the pipeline runs the parametric-only ("C") path."""
    from app.volumetric.payload import Frame  # noqa: E402

    return [
        Frame(
            file=path.name,
            image_bytes=path.read_bytes(),
            width=0,
            height=0,
            pose=None,
            intrinsics=None,
            depth_bytes=None,
            sharpness=None,
        )
        for path in frames
    ]


def volumetric(frames: list[Path], truth: dict) -> dict:
    """Re-scores a banked ARKit capture through the full volumetric pipeline
    (`app.volumetric.pipeline.run_volumetric`) offline, so accuracy changes
    can be measured on this harness without a new phone capture each time."""
    from app.config import settings  # noqa: E402
    from app.volumetric import pipeline  # noqa: E402
    from app.volumetric.payload import CaptureSet  # noqa: E402

    if not frames:
        return {"grams": None}
    _load_backend_env()

    dish_dir = frames[0].parent.parent
    poses_file = dish_dir / "arkit_poses.json"
    if poses_file.exists():
        capture_frames, tier = _load_arkit_frames(dish_dir)
    else:
        capture_frames, tier = _load_still_frames(frames), "C"

    capture = CaptureSet(tier=tier, mode="food", hint=truth.get("hint"), frames=capture_frames)
    result = pipeline.run_volumetric(capture, settings().fdc_api_key)

    grams = sum(i.portion_grams for i in result.items) or None
    return {
        "grams": grams,
        "kcal": result.totals.calories if result.items else None,
        "items": [i.name for i in result.items],
        "name": result.items[0].name if result.items else None,
        "volumetric": result.volumetric.model_dump() if result.volumetric else None,
    }


PREDICTORS = {"v1_llm": v1_llm, "volumetric": volumetric}
