from app import plausibility as p
from app.schemas import ExtendedNutrients, ScanItem


def test_in_range_is_ok():
    g = p.gate_grams(300, "cheeseburger")
    assert g.food_class == "burger"
    assert g.label == "ok" and g.factor == 1.0


def test_over_max_clamps_down():
    # burger mass max = 1300 mL * 0.8 g/mL = 1040 g
    g = p.gate_grams(1500, "burger")
    assert g.label == "clamped"
    assert g.grams == 1040.0 and g.factor < 1.0


def test_gross_over_is_implausible():
    g = p.gate_grams(5000, "burger")  # > 1040 * 3
    assert g.label == "implausible" and g.grams == 1040.0


def test_unknown_food_falls_back_to_generic():
    g = p.gate_grams(300, "quantum gizmo")
    assert g.food_class == "_generic" and g.label == "ok"


def test_llm_class_wins_over_alias_scan():
    # "steak" would alias-scan to "meat"; a valid llm_class overrides it.
    key, rec = p.resolve_class("steak", llm_class="fried_snack")
    assert key == "fried_snack"
    assert rec is p.food_classes()["fried_snack"]


def test_llm_class_other_falls_through_to_alias_scan():
    key, _ = p.resolve_class("steak", llm_class="other")
    assert key == "meat"


def test_llm_class_junk_falls_through_to_alias_scan():
    key, _ = p.resolve_class("steak", llm_class="not_a_real_class")
    assert key == "meat"


def test_nimki_resolves_to_fried_snack_via_llm_class():
    key, rec = p.resolve_class("Nimki (fried savory Bihari snack)", llm_class="fried_snack")
    assert key == "fried_snack"
    assert rec["volume_ml"] == [20, 400]


def test_curry_and_gravy_now_resolve_to_curry_gravy_not_soup():
    assert p.resolve_class("curry")[0] == "curry_gravy"
    assert p.resolve_class("gravy")[0] == "curry_gravy"


def test_adjust_item_clamps_and_scales_macros():
    item = ScanItem(
        name="cheeseburger",
        portion_desc="",
        portion_grams=2080,
        confidence="high",
        calories=4000,
        protein_grams=200,
        carb_grams=300,
        fiber_grams=20,
        extended=ExtendedNutrients(fat_g=200, sugar_g=40, sodium_mg=2000),
        matched=True,
        fdc_id=1,
        fdc_description="x",
        source="usda",
        alternatives=[],
    )
    p.adjust_item(item)  # 2080 -> clamp to 1040 (factor 0.5)
    assert item.portion_grams == 1040.0
    assert item.plausibility == "clamped"
    assert item.calories == 2000 and item.protein_grams == 100
    assert item.confidence == "low"
