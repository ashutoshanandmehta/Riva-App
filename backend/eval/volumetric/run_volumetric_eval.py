"""Phase 0 go/no-go: does depth-integrated volume predict food mass?

For each golden N5k dish: fetch GT depth, integrate volume, then relate volume to
GT grams. Reports R² (how much mass variance geometry explains) and a leave-one-out
grams MAPE after a 1-parameter global scale calibration. See METRICS.md for targets.

    ../../.venv/bin/python run_volumetric_eval.py
"""
import json
from datetime import datetime, timezone
from pathlib import Path

import n5k_depth
import numpy as np
import volume_engine

HERE = Path(__file__).resolve().parent
GOLDEN = HERE.parent / "golden.n5k.jsonl"
REPORTS = HERE / "reports"

GO_R2 = 0.60
GO_MAPE = 20.0
STRONG_MAPE = 15.0
V1_GRAMS_MAPE = 23.0  # current LLM-estimate baseline on N5k


def _fit(v: np.ndarray, g: np.ndarray) -> tuple[np.ndarray, float]:
    """Least-squares grams ~ a*volume + b; returns (coef, R²)."""
    A = np.vstack([v, np.ones_like(v)]).T
    coef, *_ = np.linalg.lstsq(A, g, rcond=None)
    pred = A @ coef
    ss_res = float(np.sum((g - pred) ** 2))
    ss_tot = float(np.sum((g - g.mean()) ** 2))
    r2 = 1 - ss_res / ss_tot if ss_tot else 0.0
    return coef, r2


def _loo_mape(v: np.ndarray, g: np.ndarray) -> float:
    """Leave-one-out grams MAPE — honest calibration with small N."""
    apes = []
    for i in range(len(v)):
        idx = [j for j in range(len(v)) if j != i]
        coef, _ = _fit(v[idx], g[idx])
        pred = coef[0] * v[i] + coef[1]
        apes.append(abs(pred - g[i]) / g[i])
    return float(np.mean(apes) * 100)


def main() -> None:
    golden = [json.loads(x) for x in GOLDEN.read_text().splitlines() if x.strip()]
    rows = []
    for dish in golden:
        did = dish["dish_id"]
        if not n5k_depth.fetch_dish(did):
            print(f"skip {did}: no depth")
            continue
        try:
            diag = volume_engine.compute(volume_engine.load_depth_m(n5k_depth.depth_path(did)))
        except Exception as error:
            print(f"skip {did}: {error}")
            continue
        rows.append({
            "dish_id": did, "dish": dish.get("dish", ""),
            "gt_grams": float(dish["grams"]), "gt_kcal": float(dish.get("kcal", 0)),
            "volume_ml": diag["volume_ml"], "food_px": diag["food_px"],
            "peak_cm": diag["peak_height_cm"], "plate_ref_m": diag["plate_ref_m"],
        })

    if len(rows) < 4:
        print(f"Only {len(rows)} dishes with depth — too few to judge.")
        return

    v = np.array([r["volume_ml"] for r in rows])
    g = np.array([r["gt_grams"] for r in rows])
    coef, r2 = _fit(v, g)
    loo = _loo_mape(v, g)
    density = float(np.median(g / np.where(v > 0, v, np.nan)))  # g/mL sanity (~0.4–1.2)

    verdict = ("STRONG" if r2 >= GO_R2 and loo <= STRONG_MAPE else
               "GO" if r2 >= GO_R2 and loo <= GO_MAPE else "RECONSIDER")

    lines = [
        f"# Volumetric Phase-0 eval — {datetime.now(timezone.utc):%Y%m%d-%H%M%S}",
        "",
        f"- Dishes with GT depth: **{len(rows)}** / {len(golden)}",
        f"- **R²(GT mass, depth-volume): {r2:.2f}**  (go ≥ {GO_R2})",
        f"- **Leave-one-out grams MAPE: {loo:.0f}%**  (go ≤ {GO_MAPE}%, strong ≤ {STRONG_MAPE}%; V1 LLM ≈ {V1_GRAMS_MAPE}%)",
        f"- Calibrated slope (≈ density): {coef[0]:.3f} g/mL; intercept {coef[1]:.0f} g; median g/mL {density:.2f}",
        f"- **Verdict: {verdict}**",
        "",
        "| dish | GT g | vol mL | peak cm | food px |",
        "|---|---|---|---|---|",
    ]
    for r in sorted(rows, key=lambda x: -x["gt_grams"]):
        lines.append(f"| {r['dish'][:20]} | {r['gt_grams']:.0f} | {r['volume_ml']:.0f} "
                     f"| {r['peak_cm']:.1f} | {r['food_px']} |")

    REPORTS.mkdir(parents=True, exist_ok=True)
    out = REPORTS / f"{datetime.now(timezone.utc):%Y%m%d-%H%M%S}.md"
    report = "\n".join(lines)
    out.write_text(report + "\n")
    print(report)
    print(f"\nReport -> {out}")


if __name__ == "__main__":
    main()
