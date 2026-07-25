"""Score predictions against ground truth — the same metrics as the volumetric
METRICS.md, so any predictor (the V1 LLM baseline today, the volumetric pipeline
later) is measured on the same real-world bar.
"""
import numpy as np


def _mape(pred: np.ndarray, truth: np.ndarray) -> float:
    return float(np.mean(np.abs(pred - truth) / truth) * 100)


def _r2(pred: np.ndarray, truth: np.ndarray) -> float:
    ss_res = float(np.sum((truth - pred) ** 2))
    ss_tot = float(np.sum((truth - truth.mean()) ** 2))
    return 1 - ss_res / ss_tot if ss_tot else 0.0


def _ingredient_recall(pred_items: list[str], truth_items: list[str]) -> float | None:
    if not truth_items:
        return None
    pj = " ".join(pred_items).lower()
    hit = sum(1 for t in truth_items if t.lower() in pj)
    return hit / len(truth_items)


def score(rows: list[dict]) -> dict:
    """rows: [{dish_id, truth(dict), pred(dict)}]. pred has grams, optional kcal,
    optional items. Returns aggregate metrics + per-dish detail."""
    usable = [r for r in rows if r.get("pred") and r["pred"].get("grams") is not None]
    if not usable:
        return {"n": 0, "detail": rows}

    g_pred = np.array([r["pred"]["grams"] for r in usable])
    g_true = np.array([float(r["truth"]["grams_total"]) for r in usable])

    kcal_rows = [r for r in usable
                 if r["truth"].get("kcal_total") and r["pred"].get("kcal")]
    cal_mape = (_mape(np.array([r["pred"]["kcal"] for r in kcal_rows]),
                      np.array([float(r["truth"]["kcal_total"]) for r in kcal_rows]))
                if kcal_rows else None)

    recalls = []
    for r in usable:
        truth_items = [c["name"] for c in r["truth"].get("components", [])] or \
            r["truth"].get("ingredients", [])
        rec = _ingredient_recall(r["pred"].get("items", []), truth_items)
        if rec is not None:
            recalls.append(rec)

    return {
        "n": len(usable),
        "grams_mape": _mape(g_pred, g_true),
        "grams_r2": _r2(g_pred, g_true),
        "calorie_mape": cal_mape,
        "calorie_n": len(kcal_rows),
        "ingredient_recall": (float(np.mean(recalls)) if recalls else None),
        "detail": rows,
    }
