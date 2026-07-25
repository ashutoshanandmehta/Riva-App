import json

import pytest

from app.volumetric.payload import parse

VALID_POSE = list(range(16))


def _manifest(**overrides) -> dict:
    base = {
        "tier": "B",
        "capture_ms": 3200,
        "hint": None,
        "mode": "food",
        "frames": [
            {
                "file": "frame_0000.jpg",
                "pose": VALID_POSE,
                "intrinsics": {"fx": 1.0, "fy": 1.0, "cx": 0.5, "cy": 0.5},
                "width": 1280,
                "height": 960,
                "depth_file": None,
                "sharpness": 123.4,
            }
        ],
    }
    base.update(overrides)
    return base


def test_parse_round_trips_a_valid_manifest_and_files():
    manifest = _manifest()
    files = {"frame_0000.jpg": b"jpeg-bytes"}
    capture = parse(json.dumps(manifest), files)

    assert capture.tier == "B"
    assert capture.mode == "food"
    assert capture.hint is None
    assert len(capture.frames) == 1
    frame = capture.frames[0]
    assert frame.file == "frame_0000.jpg"
    assert frame.image_bytes == b"jpeg-bytes"
    assert frame.width == 1280 and frame.height == 960
    assert frame.pose == [float(v) for v in VALID_POSE]
    assert frame.intrinsics == {"fx": 1.0, "fy": 1.0, "cx": 0.5, "cy": 0.5}
    assert frame.depth_bytes is None
    assert frame.sharpness == 123.4
    assert capture.poses_present is True


def test_parse_defaults_tier_and_mode_when_absent():
    manifest = _manifest(tier=None, mode=None)
    del manifest["tier"]
    del manifest["mode"]
    manifest["frames"][0]["pose"] = None
    capture = parse(json.dumps(manifest), {"frame_0000.jpg": b"x"})
    assert capture.tier == "C"
    assert capture.mode == "food"
    assert capture.poses_present is False


def test_parse_round_trips_depth_file():
    manifest = _manifest()
    manifest["frames"][0]["depth_file"] = "depth_0000.bin"
    files = {"frame_0000.jpg": b"jpeg-bytes", "depth_0000.bin": b"depth-bytes"}
    capture = parse(json.dumps(manifest), files)
    assert capture.frames[0].depth_bytes == b"depth-bytes"


def test_parse_raises_on_non_json_manifest():
    with pytest.raises(ValueError):
        parse("not json at all", {})


def test_parse_raises_on_empty_frames():
    manifest = _manifest(frames=[])
    with pytest.raises(ValueError):
        parse(json.dumps(manifest), {})


def test_parse_raises_on_missing_frame_file():
    manifest = _manifest()
    with pytest.raises(ValueError):
        parse(json.dumps(manifest), {})  # frame_0000.jpg never uploaded


def test_parse_raises_on_missing_depth_file():
    manifest = _manifest()
    manifest["frames"][0]["depth_file"] = "depth_0000.bin"
    files = {"frame_0000.jpg": b"jpeg-bytes"}  # depth file missing
    with pytest.raises(ValueError):
        parse(json.dumps(manifest), files)


def test_parse_raises_on_bad_pose_length():
    manifest = _manifest()
    manifest["frames"][0]["pose"] = [1.0, 2.0, 3.0]  # not 16
    files = {"frame_0000.jpg": b"jpeg-bytes"}
    with pytest.raises(ValueError):
        parse(json.dumps(manifest), files)
