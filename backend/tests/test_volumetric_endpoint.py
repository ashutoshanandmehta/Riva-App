"""Offline tests for `POST /v1/scan/volumetric` — no Anthropic, no USDA, no
Supabase, no DB. `app.main._llm` and `app.vision.analyze_image` are
monkeypatched so no network call is made; `app.grounding.best_match` is
monkeypatched so USDA grounding is skipped regardless of the configured FDC
key; the segmenter is monkeypatched to a deterministic in-memory mask so the
test does not depend on GrabCut converging (or on whether a real
REPLICATE_API_TOKEN happens to be set locally)."""

import io
import json

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

import app.grounding as grounding
import app.main as main
import app.vision as vision
import app.volumetric.pipeline as pipeline

FOOD_ANALYSIS = {
    "scan_type": "food",
    "reason": None,
    "plate": "white plate",
    "items": [
        {
            "name": "cheeseburger",
            "portion_desc": "1 burger",
            "portion_grams": 250,
            "is_liquid": False,
            "confidence": "high",
            "calories": 600,
            "protein_g": 30,
            "carb_g": 40,
            "fiber_g": 3,
            "fat_g": 30,
            "sugar_g": 5,
            "sodium_mg": 900,
            "alternatives": [],
        }
    ],
    "water": None,
}

NOT_FOOD_ANALYSIS = {
    "scan_type": "not_food",
    "reason": "no food visible",
    "plate": None,
    "items": [],
    "water": None,
}


class _FakeSegmenter:
    """Returns one deterministic rectangular mask per frame, sized well above
    geometry.view_volume's minimum pixel count, regardless of GrabCut's
    behaviour on a synthetic image."""

    name = "test-fake"

    def segment(self, bgr):
        h, w = bgr.shape[:2]
        mask = np.zeros((h, w), dtype=bool)
        mask[h // 4 : 3 * h // 4, w // 4 : 3 * w // 4] = True
        return [mask]


def _fake_llm():
    return object(), "test-model"


def _jpeg_bytes(size=(120, 120), color=(200, 120, 80)) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", size, color=color).save(buffer, format="JPEG")
    return buffer.getvalue()


def _manifest(**overrides) -> dict:
    base = {
        "tier": "B",
        "capture_ms": 1000,
        "hint": None,
        "mode": "food",
        "frames": [
            {
                "file": "frame_0000.jpg",
                "pose": None,
                "intrinsics": None,
                "width": 120,
                "height": 120,
                "depth_file": None,
                "sharpness": 10.0,
            },
            {
                "file": "frame_0001.jpg",
                "pose": None,
                "intrinsics": None,
                "width": 120,
                "height": 120,
                "depth_file": None,
                "sharpness": 20.0,
            },
        ],
    }
    base.update(overrides)
    return base


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(main, "_llm", _fake_llm)
    monkeypatch.setattr(vision, "analyze_image", lambda *a, **k: dict(FOOD_ANALYSIS))
    monkeypatch.setattr(grounding, "best_match", lambda api_key, name: (None, []))
    monkeypatch.setattr(pipeline.segmenter, "get_segmenter", lambda force=None: _FakeSegmenter())
    return TestClient(main.app)


def _post_volumetric(client, manifest, files_map):
    files = [("frames", (name, data, "image/jpeg")) for name, data in files_map.items()]
    return client.post("/v1/scan/volumetric", data={"manifest": json.dumps(manifest)}, files=files)


def test_happy_path_returns_gated_volumetric_debug_block(client):
    manifest = _manifest()
    files_map = {"frame_0000.jpg": _jpeg_bytes(), "frame_0001.jpg": _jpeg_bytes()}
    response = _post_volumetric(client, manifest, files_map)

    assert response.status_code == 200
    body = response.json()
    # A 200 already proves FastAPI's own response_model=ScanResponse validation
    # passed server-side; response_model_exclude_none strips None fields (e.g.
    # water, fdc_id), so re-validating the trimmed JSON against the full model
    # client-side would fail on those — check shape directly instead.
    assert body["scan_type"] == "food"
    assert body["items"][0]["name"] == "cheeseburger"

    delta = body["nutrition_day_delta"]
    for field in ("calories", "protein_grams", "carb_grams", "fiber_grams", "water_ounces"):
        assert isinstance(delta[field], int)

    assert "volumetric" in body
    vol = body["volumetric"]
    assert vol["tier"] == "B"
    assert vol["n_views"] == 2
    assert vol["parametric_fallback"] is True
    assert vol["poses_present"] is False
    assert vol["gate_action"] in ("log", "clamp", "retake")


def test_not_food_short_circuits_without_volume_math(client, monkeypatch):
    monkeypatch.setattr(vision, "analyze_image", lambda *a, **k: dict(NOT_FOOD_ANALYSIS))
    manifest = _manifest()
    files_map = {"frame_0000.jpg": _jpeg_bytes(), "frame_0001.jpg": _jpeg_bytes()}
    response = _post_volumetric(client, manifest, files_map)

    assert response.status_code == 200
    body = response.json()
    assert body["scan_type"] == "not_food"
    assert body["volumetric"]["segmenter"] == "none"
    assert body["volumetric"]["parametric_fallback"] is True
    assert "gate_action" not in body["volumetric"]  # None -> excluded


def test_missing_manifest_field_returns_400(client):
    response = client.post(
        "/v1/scan/volumetric",
        files=[("frames", ("frame_0000.jpg", _jpeg_bytes(), "image/jpeg"))],
    )
    assert response.status_code == 400


def test_invalid_manifest_json_returns_400(client):
    response = client.post(
        "/v1/scan/volumetric",
        data={"manifest": "not json"},
        files=[("frames", ("frame_0000.jpg", _jpeg_bytes(), "image/jpeg"))],
    )
    assert response.status_code == 400


def test_missing_frame_upload_returns_400(client):
    manifest = _manifest()
    response = client.post("/v1/scan/volumetric", data={"manifest": json.dumps(manifest)})
    assert response.status_code == 400


def test_v1_scan_response_omits_volumetric_key_when_absent(client):
    response = client.post("/v1/scan", files={"image": ("frame.jpg", _jpeg_bytes(), "image/jpeg")})
    assert response.status_code == 200
    assert "volumetric" not in response.json()
