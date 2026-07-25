"""Offline tests for the dev-only capture persistence path
(`app.volumetric.capture_store.save`). No network, no DB — every assertion is
against the filesystem tree it writes under a pytest tmp_path.

Reuses `dataset.validate_truth` from the real-world eval harness so the
written `truth.json` is checked against the *actual* dataset schema, not a
hand-rolled copy of it (mirrors how `eval/predictors.py` reaches into
`backend/` — here the target, `eval/realworld/dataset.py`, is a bare script
module, so its own directory is added to `sys.path` rather than `backend/`)."""

import json
import logging
import sys
from pathlib import Path

import pytest

REALWORLD_DIR = Path(__file__).resolve().parents[1] / "eval" / "realworld"
if str(REALWORLD_DIR) not in sys.path:
    sys.path.insert(0, str(REALWORLD_DIR))

import dataset  # noqa: E402

from app.volumetric import capture_store  # noqa: E402
from app.volumetric.payload import CaptureSet, Frame  # noqa: E402

MANIFEST_RAW = json.dumps({"tier": "B", "capture_ms": 3200, "hint": None, "mode": "food"})


def _frame(index: int, *, depth_bytes: bytes | None = None) -> Frame:
    return Frame(
        file=f"frame_{index:04d}.jpg",
        image_bytes=f"jpeg-bytes-{index}".encode(),
        width=1280,
        height=960,
        pose=[float(index * 16 + i) for i in range(16)],
        intrinsics={"fx": 1000.0 + index, "fy": 1000.0 + index, "cx": 640.0, "cy": 480.0},
        depth_bytes=depth_bytes,
        sharpness=100.0 + index,
    )


def _capture(n_frames: int = 2, tier: str = "B", hint: str | None = None, **kwargs) -> CaptureSet:
    frames = [_frame(i, **kwargs) for i in range(n_frames)]
    return CaptureSet(tier=tier, mode="food", hint=hint, frames=frames)


def test_save_writes_expected_tree_matching_dataset_schema(tmp_path):
    capture = _capture(hint="grilled chicken with veggies")

    dish_dir = capture_store.save(
        capture, MANIFEST_RAW, str(tmp_path), "Grilled Chicken", 150.0, None
    )

    assert dish_dir is not None
    assert dish_dir.parent == tmp_path
    assert dish_dir.name == "grilled_chicken_00"

    frame_files = sorted((dish_dir / "frames").glob("frame_*.jpg"))
    assert [f.name for f in frame_files] == ["frame_00.jpg", "frame_01.jpg"]
    assert (dish_dir / "frames" / "frame_00.jpg").read_bytes() == b"jpeg-bytes-0"
    assert (dish_dir / "frames" / "frame_01.jpg").read_bytes() == b"jpeg-bytes-1"

    poses = json.loads((dish_dir / "arkit_poses.json").read_text())
    assert poses["tier"] == "B"
    assert len(poses["frames"]) == 2
    for index, entry in enumerate(poses["frames"]):
        assert entry["file"] == f"frame_{index:02d}.jpg"
        assert entry["pose"] == capture.frames[index].pose
        assert entry["intrinsics"] == capture.frames[index].intrinsics
        assert entry["width"] == 1280 and entry["height"] == 960
        assert "depth_file" not in entry

    assert (dish_dir / "manifest.json").read_text() == MANIFEST_RAW

    truth = json.loads((dish_dir / "truth.json").read_text())
    assert truth == {
        "dish_id": "grilled_chicken_00",
        "name": "Grilled Chicken",
        "grams_total": 150.0,
        "hint": "grilled chicken with veggies",
        "device": "iphone",
        "arkit": True,
        "tier": "B",
        "n_frames": 2,
    }
    assert dataset.validate_truth(truth, dish_dir.name) == []


def test_save_without_grams_truth_omits_field_and_dataset_flags_it_incomplete(tmp_path):
    capture = _capture()

    dish_dir = capture_store.save(
        capture, MANIFEST_RAW, str(tmp_path), "Grilled Chicken", None, None
    )

    truth = json.loads((dish_dir / "truth.json").read_text())
    assert "grams_total" not in truth  # never fabricate a weight

    problems = dataset.validate_truth(truth, dish_dir.name)
    assert any("grams_total" in p for p in problems)


def test_save_same_label_twice_creates_distinct_dirs_without_overwrite(tmp_path):
    capture = _capture()

    first = capture_store.save(capture, MANIFEST_RAW, str(tmp_path), "Chicken Bowl", 100.0, None)
    second = capture_store.save(capture, MANIFEST_RAW, str(tmp_path), "Chicken Bowl", 200.0, None)

    assert first.name == "chicken_bowl_00"
    assert second.name == "chicken_bowl_01"
    assert first != second

    # The first dish's files are untouched by the second save.
    first_truth = json.loads((first / "truth.json").read_text())
    assert first_truth["grams_total"] == 100.0
    assert sorted(p.name for p in (first / "frames").glob("*.jpg")) == [
        "frame_00.jpg",
        "frame_01.jpg",
    ]


def test_save_defaults_dish_id_to_capture_when_no_label(tmp_path):
    capture = _capture()

    dish_dir = capture_store.save(capture, MANIFEST_RAW, str(tmp_path), None, None, None)

    assert dish_dir.name == "capture_00"
    truth = json.loads((dish_dir / "truth.json").read_text())
    assert truth["name"] == "unlabeled"


def test_save_includes_depth_file_only_for_frames_that_have_one(tmp_path):
    capture = CaptureSet(
        tier="A",
        mode="food",
        hint=None,
        frames=[_frame(0, depth_bytes=b"depth-bytes-0"), _frame(1)],
    )

    dish_dir = capture_store.save(capture, MANIFEST_RAW, str(tmp_path), "Soup", 300.0, None)

    assert (dish_dir / "frames" / "depth_00.bin").read_bytes() == b"depth-bytes-0"
    assert not (dish_dir / "frames" / "depth_01.bin").exists()

    poses = json.loads((dish_dir / "arkit_poses.json").read_text())
    assert poses["frames"][0]["depth_file"] == "depth_00.bin"
    assert "depth_file" not in poses["frames"][1]


def test_save_falls_back_to_capture_hint_when_no_form_hint_given(tmp_path):
    capture = _capture(hint="capture-level hint")

    dish_dir = capture_store.save(capture, MANIFEST_RAW, str(tmp_path), "Soup", 300.0, None)

    truth = json.loads((dish_dir / "truth.json").read_text())
    assert truth["hint"] == "capture-level hint"


def test_save_returns_none_and_writes_nothing_when_base_dir_empty(tmp_path):
    capture = _capture()

    result = capture_store.save(capture, MANIFEST_RAW, "", "Soup", 300.0, None)

    assert result is None
    assert list(tmp_path.iterdir()) == []


def test_save_fails_soft_when_base_dir_is_unwritable(tmp_path, caplog):
    not_a_dir = tmp_path / "not_a_directory"
    not_a_dir.write_text("i am a file, not a dataset dir")
    capture = _capture()

    with caplog.at_level(logging.WARNING):
        result = capture_store.save(capture, MANIFEST_RAW, str(not_a_dir), "Soup", 300.0, None)

    assert result is None
    assert any("persistence failed" in message for message in caplog.messages)


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
