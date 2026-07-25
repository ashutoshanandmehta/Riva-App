"""Contract-parity guard for the D2 assumption behind the volumetric flow:
a `ScanResponse` returned by `app.volumetric.pipeline.run_volumetric` (food
item + `VolumetricDebug` block included) must still map cleanly onto
`LogRequest`, the shape the client posts to `/v1/log` to persist an accepted
scan. Nothing here calls the network or a real pipeline — it builds a
`ScanResponse` the same way `_assemble` + `run_volumetric` do, then performs
the exact field mapping the iOS client is expected to do, and asserts the
resulting `LogRequest(**mapped)` construction raises no validation error.

This is a regression guard, not new behaviour: if either schema drifts (a
field renamed, retyped, or a new required field appears on either side)
without a compatible mapping, this test fails first."""

from app.schemas import (
    ExtendedNutrients,
    LatencyBreakdown,
    LogRequest,
    NutritionDayDelta,
    ScanItem,
    ScanResponse,
    Totals,
    VolumetricDebug,
)


def _volumetric_scan_response() -> ScanResponse:
    """A realistic `ScanResponse` for a tier-B volumetric scan, shaped the way
    `run_volumetric` -> `_assemble` produces it: one grounded food item, a
    populated `volumetric` block, no `debug` (client requests omit it)."""
    item = ScanItem(
        name="cheeseburger",
        portion_desc="1 burger",
        portion_grams=245.0,
        confidence="high",
        calories=600,
        protein_grams=30,
        carb_grams=40,
        fiber_grams=3,
        extended=ExtendedNutrients(fat_g=30.0, sugar_g=5.0, sodium_mg=900.0),
        matched=True,
        fdc_id=12345,
        fdc_description="Cheeseburger, regular, single patty",
        source="usda",
        alternatives=[],
        plausibility="ok",
    )
    return ScanResponse(
        scan_type="food",
        requested_mode="auto",
        mode_mismatch=False,
        reason=None,
        plate="white plate",
        items=[item],
        water=None,
        totals=Totals(calories=600, protein_grams=30, carb_grams=40, fiber_grams=3),
        nutrition_day_delta=NutritionDayDelta(
            calories=600, protein_grams=30, carb_grams=40, fiber_grams=3, water_ounces=0
        ),
        prompt_version="v3",
        model="test-model",
        latency=LatencyBreakdown(total_ms=100, preprocess_ms=10, vision_ms=70, grounding_ms=20),
        debug=None,
        volumetric=VolumetricDebug(
            tier="B",
            n_views=2,
            segmenter="test-fake",
            parametric_fallback=True,
            poses_present=False,
            food_class="burger",
            volume_ml=210.5,
            raw_volume_ml=205.0,
            mass_g=245.0,
            gate_action="log",
            reason=None,
        ),
    )


def _map_to_log_request_fields(response: ScanResponse) -> dict:
    """Mirrors the mapping the client performs when it accepts a scan for
    persistence: the DB-facing counters come from `nutrition_day_delta`
    (already the increment set for `nutrition_days`), not from `totals`."""
    return {
        "scan_type": response.scan_type,
        "items": [item.model_dump() for item in response.items],
        "calories": response.nutrition_day_delta.calories,
        "protein_grams": response.nutrition_day_delta.protein_grams,
        "carb_grams": response.nutrition_day_delta.carb_grams,
        "fiber_grams": response.nutrition_day_delta.fiber_grams,
        "water_ounces": response.nutrition_day_delta.water_ounces,
        "model": response.model,
        "prompt_version": response.prompt_version,
    }


def test_volumetric_scan_response_maps_onto_log_request_with_no_validation_error():
    response = _volumetric_scan_response()
    assert response.volumetric is not None  # sanity: this is the volumetric-shaped response

    mapped = _map_to_log_request_fields(response)
    log_request = LogRequest(**mapped)

    assert log_request.scan_type == "food"
    assert log_request.items[0]["name"] == "cheeseburger"
    assert log_request.calories == 600
    assert log_request.protein_grams == 30
    assert log_request.carb_grams == 40
    assert log_request.fiber_grams == 3
    assert log_request.water_ounces == 0
    assert log_request.model == "test-model"
    assert log_request.prompt_version == "v3"


def test_volumetric_scan_response_water_variant_maps_onto_log_request():
    """A water-only volumetric scan (no items) must also satisfy LogRequest —
    `scan_type` is one of the three /v1/log accepts and `items` is legally
    empty."""
    response = _volumetric_scan_response()
    response.scan_type = "water"
    response.items = []
    response.nutrition_day_delta = NutritionDayDelta(
        calories=0, protein_grams=0, carb_grams=0, fiber_grams=0, water_ounces=16
    )
    response.volumetric = VolumetricDebug(
        tier="B",
        n_views=2,
        segmenter="none",
        parametric_fallback=True,
        poses_present=False,
        reason="not food / no items",
    )

    mapped = _map_to_log_request_fields(response)
    log_request = LogRequest(**mapped)

    assert log_request.scan_type == "water"
    assert log_request.items == []
    assert log_request.water_ounces == 16


def test_scan_response_field_names_needed_by_log_request_all_exist():
    """Cheap structural guard: every field the mapping reads off `ScanResponse`
    (directly or via `nutrition_day_delta`) is a real field on those models,
    typed as expected. Catches a rename on the ScanResponse/NutritionDayDelta
    side even before a value-level test would."""
    response_fields = ScanResponse.model_fields
    delta_fields = NutritionDayDelta.model_fields
    log_fields = LogRequest.model_fields

    assert "scan_type" in response_fields
    assert "items" in response_fields
    assert "model" in response_fields
    assert "prompt_version" in response_fields
    assert "nutrition_day_delta" in response_fields

    for name in ("calories", "protein_grams", "carb_grams", "fiber_grams", "water_ounces"):
        assert name in delta_fields
        assert name in log_fields
