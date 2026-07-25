"""Plausibility gate for volumetric estimates — REQUIRED before any value is logged.

Converts a fused volume to mass and calories using the per-class density and
kcal/100g, then validates volume against the class's plausible [min,max]:

    in range            -> action "log"      (unchanged)
    mildly out of range -> action "clamp"    (clamp to bound, low confidence)
    grossly out (>= RETAKE_FACTOR beyond)    -> action "retake" (do NOT log)

Class ranges live in app/food_classes.json (per class: volume_ml, density_g_ml,
kcal_100g), resolved through app.plausibility — the same table the V1 grams gate
uses; unknown classes use `_generic`. Nothing is ever silently logged at the raw
value.
"""

from dataclasses import dataclass

from app.plausibility import resolve_class

RETAKE_FACTOR = 3.0  # >3x beyond a bound => too unreliable to log, ask for a retake


@dataclass
class GateResult:
    food_class: str
    action: str  # "log" | "clamp" | "retake"
    volume_ml: float  # possibly clamped
    raw_volume_ml: float
    mass_g: float | None
    kcal: float | None
    confidence: float  # 0..1, penalised on clamp
    reason: str


def gate(
    raw_volume_ml: float,
    food_name: str | None,
    base_confidence: float,
    llm_class: str | None = None,
) -> GateResult:
    key, rec = resolve_class(food_name, llm_class=llm_class)
    lo, hi = rec["volume_ml"]
    density = rec["density_g_ml"][1]  # typical
    kcal100 = rec["kcal_100g"]

    if raw_volume_ml < lo / RETAKE_FACTOR or raw_volume_ml > hi * RETAKE_FACTOR:
        return GateResult(
            key,
            "retake",
            raw_volume_ml,
            raw_volume_ml,
            None,
            None,
            0.0,
            f"volume {raw_volume_ml:.0f} mL is >{RETAKE_FACTOR:g}x "
            f"outside plausible [{lo}, {hi}] for '{key}' — retake",
        )

    action, vol, conf, reason = "log", raw_volume_ml, base_confidence, "in plausible range"
    if raw_volume_ml < lo:
        action, vol, conf = "clamp", lo, min(base_confidence, 0.4)
        reason = f"below min {lo} mL — clamped up, low confidence"
    elif raw_volume_ml > hi:
        action, vol, conf = "clamp", hi, min(base_confidence, 0.4)
        reason = f"above max {hi} mL — clamped down, low confidence"

    mass = vol * density
    kcal = mass / 100.0 * kcal100
    return GateResult(key, action, vol, raw_volume_ml, mass, kcal, conf, reason)
