"""Offline tests for the `volumetric` real-world eval predictor
(`eval/realworld/predictors.py`): it must reconstruct a `CaptureSet` from a
banked capture (written by `app.volumetric.capture_store.save`) exactly the
way the live `/v1/scan/volumetric` route would build one from an upload, then
hand it to `app.volumetric.pipeline.run_volumetric`.

Fixtures are built by actually calling `capture_store.save` against a
synthetic `CaptureSet` (rather than hand-authoring `arkit_poses.json`), so the
test can't drift from the real on-disk layout. `pipeline.run_volumetric` is
monkeypatched to avoid any Claude/USDA network call — this test's job is the
predictor's reconstruction logic, not the pipeline itself (covered elsewhere)."""

import json
import sys
from pathlib import Path

import pytest

REALWORLD_DIR = Path(__file__).resolve().parents[1] / "eval" / "realworld"
if str(REALWORLD_DIR) not in sys.path:
    sys.path.insert(0, str(REALWORLD_DIR))

import predictors  # noqa: E402

from app.schemas import (  # noqa: E402
    ExtendedNutrients,
    LatencyBreakdown,
    NutritionDayDelta,
    ScanItem,
    ScanResponse,
    Totals,
)
from app.volumetric import capture_store  # noqa: E402
from app.volumetric.payload import CaptureSet, Frame  # noqa: E402

MANIFEST_RAW = json.dumps({"tier": "B", "capture_ms": 3200, "hint": None, "mode": "food"})


def _frame(index: int) -> Frame:
    return Frame(
        file=f"frame_{index:04d}.jpg",
        image_bytes=f"jpeg-bytes-{index}".encode(),
        width=1280,
        height=960,
        pose=[float(index * 16 + i) for i in range(16)],
        intrinsics={"fx": 1000.0 + index, "fy": 1000.0 + index, "cx": 640.0, "cy": 480.0},
        depth_bytes=None,
        sharpness=100.0 + index,
    )


def _fake_result(grams: float) -> ScanResponse:
    item = ScanItem(
        name="grilled chicken",
        portion_desc="1 serving",
        portion_grams=grams,
        confidence="high",
        calories=400,
        protein_grams=30,
        carb_grams=10,
        fiber_grams=2,
        extended=ExtendedNutrients(fat_g=10, sugar_g=1, sodium_mg=300),
        matched=True,
        fdc_id=1,
        fdc_description="chicken",
        source="usda",
        alternatives=[],
    )
    return ScanResponse(
        scan_type="food",
        requested_mode="food",
        mode_mismatch=False,
        reason=None,
        plate=None,
        items=[item],
        water=None,
        totals=Totals(calories=400, protein_grams=30, carb_grams=10, fiber_grams=2),
        nutrition_day_delta=NutritionDayDelta(
            calories=400, protein_grams=30, carb_grams=10, fiber_grams=2, water_ounces=0
        ),
        prompt_version="test",
        model="test-model",
        latency=LatencyBreakdown(total_ms=1, preprocess_ms=1, vision_ms=1, grounding_ms=1),
    )


def test_volumetric_predictor_reconstructs_capture_from_arkit_poses(tmp_path, monkeypatch):
    capture = CaptureSet(
        tier="B",
        mode="food",
        hint="grilled chicken with veggies",
        frames=[_frame(0), _frame(1)],
    )
    dish_dir = capture_store.save(capture, MANIFEST_RAW, str(tmp_path), "Chicken Bowl", 150.0, None)

    captured = {}

    def _fake_run_volumetric(cap, fdc_api_key):
        captured["capture"] = cap
        captured["fdc_api_key"] = fdc_api_key
        return _fake_result(150.0)

    monkeypatch.setattr("app.volumetric.pipeline.run_volumetric", _fake_run_volumetric)

    frame_paths = sorted((dish_dir / "frames").glob("frame_*.jpg"))
    truth = {"hint": "grilled chicken with veggies", "grams_total": 150.0}
    result = predictors.volumetric(frame_paths, truth)

    reconstructed = captured["capture"]
    assert reconstructed.tier == "B"
    assert reconstructed.mode == "food"
    assert reconstructed.hint == "grilled chicken with veggies"
    assert len(reconstructed.frames) == 2
    assert reconstructed.frames[0].pose == capture.frames[0].pose
    assert reconstructed.frames[0].intrinsics == capture.frames[0].intrinsics
    assert reconstructed.frames[0].width == 1280
    assert reconstructed.frames[0].height == 960
    assert reconstructed.frames[0].image_bytes == b"jpeg-bytes-0"
    assert reconstructed.poses_present is True

    assert result["grams"] == 150.0
    assert result["kcal"] == 400
    assert result["items"] == ["grilled chicken"]
    assert result["volumetric"] is None


def test_volumetric_predictor_falls_back_to_tier_c_without_arkit_poses(tmp_path, monkeypatch):
    frames_dir = tmp_path / "stills_dish" / "frames"
    frames_dir.mkdir(parents=True)
    frame_paths = []
    for index in range(2):
        path = frames_dir / f"frame_{index:02d}.jpg"
        path.write_bytes(f"still-bytes-{index}".encode())
        frame_paths.append(path)

    captured = {}

    def _fake_run_volumetric(cap, fdc_api_key):
        captured["capture"] = cap
        return _fake_result(200.0)

    monkeypatch.setattr("app.volumetric.pipeline.run_volumetric", _fake_run_volumetric)

    result = predictors.volumetric(frame_paths, {"hint": None, "grams_total": 200.0})

    reconstructed = captured["capture"]
    assert reconstructed.tier == "C"
    assert all(f.pose is None for f in reconstructed.frames)
    assert all(f.intrinsics is None for f in reconstructed.frames)
    assert reconstructed.poses_present is False
    assert result["grams"] == 200.0


if __name__ == "__main__":
    sys.exit(pytest.main([__file__, "-v"]))
