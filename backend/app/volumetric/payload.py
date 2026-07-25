"""Parses the `/v1/scan/volumetric` multipart request into an in-memory
capture set: the manifest (tiering + per-frame pose/intrinsics metadata) plus
the raw frame/depth bytes uploaded alongside it.

Contract (produced by the iOS capture flow, step 4):

    {
      "tier": "B", "capture_ms": 3200, "hint": null, "mode": "food",
      "frames": [
        {"file": "frame_0000.jpg", "pose": [..16 floats..] | null,
         "intrinsics": {"fx": .., "fy": .., "cx": .., "cy": ..} | null,
         "width": 1280, "height": 960,
         "depth_file": "depth_0000.bin" | null, "sharpness": 123.4},
        ...
      ]
    }

Every failure here is a client-payload defect, so it raises `ValueError` with a
clear, user-facing message — `routes.py` turns that into an HTTP 400.
"""

import json
from dataclasses import dataclass

DEFAULT_TIER = "C"
DEFAULT_MODE = "food"
POSE_LENGTH = 16  # row-major 4x4 ARKit world transform


@dataclass
class Frame:
    file: str
    image_bytes: bytes
    width: int
    height: int
    pose: list[float] | None  # 16 floats, row-major 4x4 ARKit world transform
    intrinsics: dict | None  # {"fx", "fy", "cx", "cy"}
    depth_bytes: bytes | None  # Tier A only
    sharpness: float | None


@dataclass
class CaptureSet:
    tier: str  # "A" | "B" | "C"
    mode: str
    hint: str | None
    frames: list[Frame]

    @property
    def poses_present(self) -> bool:
        return bool(self.frames) and all(f.pose is not None for f in self.frames)


def parse(manifest_json: str, files: dict[str, bytes]) -> CaptureSet:
    """`manifest_json` is the raw `manifest` form field; `files` maps every
    uploaded part's filename to its bytes. Raises `ValueError` on any
    malformed or incomplete payload."""
    try:
        manifest = json.loads(manifest_json)
    except (TypeError, ValueError) as error:
        raise ValueError(f"manifest is not valid JSON: {error}") from error
    if not isinstance(manifest, dict):
        raise ValueError("manifest must be a JSON object")

    raw_frames = manifest.get("frames")
    if not isinstance(raw_frames, list) or not raw_frames:
        raise ValueError("manifest.frames must be a non-empty list")

    frames: list[Frame] = []
    for index, raw_frame in enumerate(raw_frames):
        if not isinstance(raw_frame, dict):
            raise ValueError(f"frames[{index}] must be an object")

        file_name = raw_frame.get("file")
        if not file_name or not isinstance(file_name, str):
            raise ValueError(f"frames[{index}].file is required")
        image_bytes = files.get(file_name)
        if image_bytes is None:
            raise ValueError(f"frames[{index}].file '{file_name}' was not uploaded")

        depth_file = raw_frame.get("depth_file")
        depth_bytes: bytes | None = None
        if depth_file is not None:
            depth_bytes = files.get(depth_file)
            if depth_bytes is None:
                raise ValueError(f"frames[{index}].depth_file '{depth_file}' was not uploaded")

        pose = raw_frame.get("pose")
        if pose is not None:
            if not isinstance(pose, list) or len(pose) != POSE_LENGTH:
                raise ValueError(f"frames[{index}].pose must have exactly {POSE_LENGTH} floats")
            try:
                pose = [float(v) for v in pose]
            except (TypeError, ValueError) as error:
                raise ValueError(f"frames[{index}].pose must be all numbers: {error}") from error

        frames.append(
            Frame(
                file=file_name,
                image_bytes=image_bytes,
                width=int(raw_frame.get("width", 0)),
                height=int(raw_frame.get("height", 0)),
                pose=pose,
                intrinsics=raw_frame.get("intrinsics"),
                depth_bytes=depth_bytes,
                sharpness=raw_frame.get("sharpness"),
            )
        )

    return CaptureSet(
        tier=manifest.get("tier") or DEFAULT_TIER,
        mode=manifest.get("mode") or DEFAULT_MODE,
        hint=manifest.get("hint"),
        frames=frames,
    )
