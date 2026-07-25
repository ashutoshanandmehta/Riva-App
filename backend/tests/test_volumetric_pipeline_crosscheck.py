"""Offline tests for the LLM-grams cross-check in `pipeline.run_volumetric`
(item D): a carved mass that grossly diverges from the LLM's own summed
gram estimate, under a weak class prior (_generic) or weak geometry
(boundary hit / low confidence), defers to the LLM grams instead of logging
the (likely bad) carve. Mocking follows `test_volumetric_endpoint.py`'s
pattern — `_llm`/`vision.analyze_image`/`grounding.best_match`/the segmenter
are all monkeypatched so `_assemble` never touches the network — plus
`pipeline.carve.visual_hull_volume` and `pipeline.gate` are monkeypatched
directly to pin the carve/gate outputs each scenario needs, independent of
real carve geometry or class tables.
"""

import numpy as np
import pytest

import app.grounding as grounding
import app.main as main
import app.vision as vision
import app.volumetric.pipeline as pipeline
from app.volumetric.carve import HullEstimate
from app.volumetric.gate import GateResult
from app.volumetric.payload import CaptureSet, Frame

VALID_POSE = list(np.eye(4).flatten())
VALID_INTRINSICS = {"fx": 600.0, "fy": 600.0, "cx": 240.0, "cy": 240.0}


class _FakeSegmenter:
    name = "test-fake"

    def segment(self, bgr):
        h, w = bgr.shape[:2]
        mask = np.zeros((h, w), dtype=bool)
        mask[h // 4 : 3 * h // 4, w // 4 : 3 * w // 4] = True
        return [mask]


def _fake_llm():
    return object(), "test-model"


def _solid_jpeg_bytes() -> bytes:
    import io

    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGB", (480, 480), color=(200, 120, 80)).save(buffer, format="JPEG")
    return buffer.getvalue()


def _frame(name: str) -> Frame:
    return Frame(
        file=name,
        image_bytes=_solid_jpeg_bytes(),
        width=480,
        height=480,
        pose=VALID_POSE,
        intrinsics=VALID_INTRINSICS,
        depth_bytes=None,
        sharpness=10.0,
    )


def _capture() -> CaptureSet:
    return CaptureSet(tier="B", mode="food", hint=None, frames=[_frame("f0.jpg"), _frame("f1.jpg")])


def _analysis(name: str, food_class: str, portion_grams: float) -> dict:
    return {
        "scan_type": "food",
        "reason": None,
        "plate": "white plate",
        "items": [
            {
                "name": name,
                "food_class": food_class,
                "portion_desc": "1 portion",
                "portion_grams": portion_grams,
                "is_liquid": False,
                "confidence": "medium",
                "calories": 300,
                "protein_g": 10,
                "carb_g": 30,
                "fiber_g": 2,
                "fat_g": 10,
                "sugar_g": 2,
                "sodium_mg": 300,
                "alternatives": [],
            }
        ],
        "water": None,
    }


@pytest.fixture
def _stub_common(monkeypatch):
    monkeypatch.setattr(main, "_llm", _fake_llm)
    monkeypatch.setattr(grounding, "best_match", lambda api_key, name: (None, []))
    monkeypatch.setattr(pipeline.segmenter, "get_segmenter", lambda force=None: _FakeSegmenter())


def _stub_carve_and_gate(monkeypatch, *, boundary_hit: bool, gate_result: GateResult):
    fake_hull = HullEstimate(
        volume_ml=gate_result.raw_volume_ml,
        n_views=2,
        voxel_count=100,
        confidence=gate_result.confidence,
        center=(0.0, 0.0, 0.0),
        boundary_hit=boundary_hit,
    )
    monkeypatch.setattr(pipeline.carve, "visual_hull_volume", lambda *a, **k: fake_hull)
    monkeypatch.setattr(pipeline, "gate", lambda *a, **k: gate_result)


def test_incident_generic_class_carve_diverges_llm_wins(monkeypatch, _stub_common):
    """Pins the real-capture incident at the pipeline level: a small fried
    snack the LLM sized at ~70g carved to 385g under `_generic` — LLM grams
    must win and `mass_source` must record it."""
    monkeypatch.setattr(
        vision, "analyze_image", lambda *a, **k: _analysis("Mystery Snack Item", "other", 70.0)
    )
    gate_result = GateResult(
        food_class="_generic",
        action="clamp",
        volume_ml=400.0,
        raw_volume_ml=641.6,
        mass_g=385.0,
        kcal=700.0,
        confidence=0.8,
        reason="above max — clamped down, low confidence",
    )
    _stub_carve_and_gate(monkeypatch, boundary_hit=False, gate_result=gate_result)

    result = pipeline.run_volumetric(_capture(), fdc_api_key="")

    assert result.volumetric.mass_source == "llm"
    assert result.items[0].portion_grams == pytest.approx(70.0)


def test_known_class_healthy_geometry_carve_wins_despite_divergence(monkeypatch, _stub_common):
    """A known class with healthy geometry (no boundary hit, confidence above
    the weak threshold) trusts the carve unconditionally, even against a
    >3x-divergent LLM estimate — guards against degrading correct carves."""
    monkeypatch.setattr(
        vision, "analyze_image", lambda *a, **k: _analysis("steamed rice", "rice", 90.0)
    )
    gate_result = GateResult(
        food_class="rice",
        action="log",
        volume_ml=300.0,
        raw_volume_ml=300.0,
        mass_g=300.0,
        kcal=390.0,
        confidence=0.8,
        reason="in plausible range",
    )
    _stub_carve_and_gate(monkeypatch, boundary_hit=False, gate_result=gate_result)

    result = pipeline.run_volumetric(_capture(), fdc_api_key="")

    assert result.volumetric.mass_source == "carve"
    assert result.items[0].portion_grams == pytest.approx(300.0)


def test_known_class_weak_geometry_and_divergence_llm_wins(monkeypatch, _stub_common):
    """A known class does not save a carve whose geometry is weak (grid
    boundary hit) when it also grossly diverges from the LLM's grams — the
    weak-geometry escape hatch still applies regardless of class prior."""
    monkeypatch.setattr(
        vision, "analyze_image", lambda *a, **k: _analysis("steamed rice", "rice", 90.0)
    )
    gate_result = GateResult(
        food_class="rice",
        action="log",
        volume_ml=300.0,
        raw_volume_ml=300.0,
        mass_g=300.0,
        kcal=390.0,
        confidence=0.8,
        reason="in plausible range",
    )
    _stub_carve_and_gate(monkeypatch, boundary_hit=True, gate_result=gate_result)

    result = pipeline.run_volumetric(_capture(), fdc_api_key="")

    assert result.volumetric.mass_source == "llm"
    assert result.items[0].portion_grams == pytest.approx(90.0)


def test_generic_class_mild_divergence_carve_wins(monkeypatch, _stub_common):
    """Divergence within the 3x band under a weak (_generic) prior does not
    trigger the override — the rule should not fire on mild disagreement."""
    monkeypatch.setattr(
        vision, "analyze_image", lambda *a, **k: _analysis("Mystery Snack Item", "other", 100.0)
    )
    gate_result = GateResult(
        food_class="_generic",
        action="log",
        volume_ml=200.0,
        raw_volume_ml=200.0,
        mass_g=200.0,
        kcal=360.0,
        confidence=0.8,
        reason="in plausible range",
    )
    _stub_carve_and_gate(monkeypatch, boundary_hit=False, gate_result=gate_result)

    result = pipeline.run_volumetric(_capture(), fdc_api_key="")

    assert result.volumetric.mass_source == "carve"
    assert result.items[0].portion_grams == pytest.approx(200.0)
