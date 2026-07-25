import pytest

from app.volumetric.gate import RETAKE_FACTOR, gate


def test_retake_factor_matches_gate_boundary():
    assert RETAKE_FACTOR == 3.0


def test_in_range_logs_with_computed_mass_and_kcal():
    # burger: volume_ml [150, 1300], density typical 0.55, kcal_100g 250
    g = gate(500.0, "burger", base_confidence=0.7)
    assert g.action == "log"
    assert g.food_class == "burger"
    assert g.volume_ml == 500.0
    assert g.raw_volume_ml == 500.0
    assert g.mass_g == pytest.approx(500.0 * 0.55)
    assert g.kcal == pytest.approx(g.mass_g / 100.0 * 250)
    assert g.confidence == 0.7


def test_mildly_below_min_clamps_up_with_lowered_confidence():
    # below min (150) but not past the retake floor (150 / 3 = 50)
    g = gate(100.0, "burger", base_confidence=0.7)
    assert g.action == "clamp"
    assert g.volume_ml == 150.0
    assert g.raw_volume_ml == 100.0
    assert g.confidence <= 0.4
    assert g.mass_g == pytest.approx(150.0 * 0.55)
    assert g.kcal == pytest.approx(g.mass_g / 100.0 * 250)


def test_mildly_above_max_clamps_down_with_lowered_confidence():
    # above max (1300) but not past the retake ceiling (1300 * 3 = 3900)
    g = gate(1400.0, "burger", base_confidence=0.7)
    assert g.action == "clamp"
    assert g.volume_ml == 1300.0
    assert g.raw_volume_ml == 1400.0
    assert g.confidence <= 0.4
    assert g.mass_g == pytest.approx(1300.0 * 0.55)
    assert g.kcal == pytest.approx(g.mass_g / 100.0 * 250)


def test_grossly_below_min_is_retake_with_no_logged_mass():
    g = gate(40.0, "burger", base_confidence=0.7)  # < 150 / 3 = 50
    assert g.action == "retake"
    assert g.mass_g is None
    assert g.kcal is None
    assert g.confidence == 0.0


def test_grossly_above_max_is_retake_with_no_logged_mass():
    g = gate(4000.0, "burger", base_confidence=0.7)  # > 1300 * 3 = 3900
    assert g.action == "retake"
    assert g.mass_g is None
    assert g.kcal is None
    assert g.confidence == 0.0


def test_nimki_incident_clamps_to_fried_snack_bound_via_llm_class():
    # Regression for the real-capture incident: "Nimki" (a fried snack, true
    # weight 50-100g) measured 641.6 mL and used to pass through `_generic`
    # (volume band [30,1500], density 0.6) unclamped -> 385g, action=log. With
    # `llm_class="fried_snack"` (volume [20,400], density [0.3,0.5,0.8]) it
    # must clamp to the 400 mL upper bound at the typical density (0.5).
    g = gate(641.6, "Nimki (fried savory Bihari snack)", 0.7, llm_class="fried_snack")
    assert g.food_class == "fried_snack"
    assert g.action == "clamp"
    assert g.volume_ml == 400
    assert g.mass_g == pytest.approx(400 * 0.5)


def test_unknown_food_falls_back_to_generic_class():
    # _generic: volume_ml [30, 1500], density typical 0.6, kcal_100g 180
    g = gate(500.0, "quantum gizmo", base_confidence=0.7)
    assert g.food_class == "_generic"
    assert g.action == "log"
    assert g.mass_g == pytest.approx(500.0 * 0.6)
    assert g.kcal == pytest.approx(g.mass_g / 100.0 * 180)
