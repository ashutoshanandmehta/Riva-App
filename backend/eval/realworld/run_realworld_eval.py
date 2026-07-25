"""Real-world eval: ingest captures, run a predictor, score against kitchen-scale
truth. This is the fair test of the volumetric redesign (N5k is top-down-only and
can't test multi-view). Today it scores the V1 LLM baseline; swap --predictor to
the volumetric pipeline once it exists.

    ../../.venv/bin/python run_realworld_eval.py                 # V1 baseline
    ../../.venv/bin/python run_realworld_eval.py --predictor v1_llm --limit 5
"""

import argparse
from datetime import datetime, timezone
from pathlib import Path

import dataset
import frames as frames_mod
import predictors
import score as score_mod

HERE = Path(__file__).resolve().parent
REPORTS = HERE / "reports"


def ingest_one(dish: dict) -> list[Path]:
    """Ensure a frames/ set exists: reuse stills, else extract from capture.mp4."""
    fdir = dish["frames_dir"]
    existing = sorted(fdir.glob("*.jp*g")) if fdir.exists() else []
    if existing:
        return existing
    if dish.get("video"):
        return frames_mod.extract(dish["video"], fdir)
    return []


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--predictor", default="v1_llm", choices=list(predictors.PREDICTORS))
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args()

    dishes = dataset.discover()
    blocked = [d for d in dishes if d["problems"]]
    ready = [d for d in dishes if not d["problems"]]
    for d in blocked:
        print(f"! {d['dish_id']}: {'; '.join(d['problems'])}")
    if not ready:
        print(
            f"\nNo valid dishes in {dataset.DATASET}. See README.md for the capture "
            f"protocol, then drop dishes under dataset/<id>/ (truth.json + capture.mp4)."
        )
        return
    if args.limit:
        ready = ready[: args.limit]

    predict = predictors.PREDICTORS[args.predictor]
    rows = []
    for d in ready:
        try:
            frame_paths = ingest_one(d)
            pred = predict(frame_paths, d["truth"])
        except Exception as error:
            print(f"! {d['dish_id']}: predictor failed: {error}")
            pred = None
        rows.append({"dish_id": d["dish_id"], "truth": d["truth"], "pred": pred})
        if pred:
            print(
                f"  {d['dish_id']}: pred {pred.get('grams')}g / truth {d['truth']['grams_total']}g"
            )

    res = score_mod.score(rows)
    stamp = f"{datetime.now(timezone.utc):%Y%m%d-%H%M%S}"
    lines = [
        f"# Real-world eval ({args.predictor}) — {stamp}",
        "",
        f"- Dishes scored: **{res['n']}** (blocked: {len(blocked)})",
    ]
    if res["n"]:
        lines += [
            f"- **Grams MAPE: {res['grams_mape']:.0f}%**   R²(grams): {res['grams_r2']:.2f}",
            f"- Calorie MAPE: {res['calorie_mape']:.0f}% (n={res['calorie_n']})"
            if res["calorie_mape"] is not None
            else "- Calorie MAPE: n/a (no kcal truth)",
            f"- Ingredient recall: {res['ingredient_recall'] * 100:.0f}%"
            if res["ingredient_recall"] is not None
            else "- Ingredient recall: n/a",
            "",
        ]
        volumetric = args.predictor == "volumetric"
        header = "| dish | truth g | pred g |" + (" gate | mass source |" if volumetric else "")
        lines += [header, "|---|---|---|" + ("---|---|" if volumetric else "")]
        for r in rows:
            pg = r["pred"].get("grams") if r["pred"] else None
            row = f"| {r['dish_id']} | {r['truth']['grams_total']} | {pg if pg is not None else 'ERR'} |"
            if volumetric:
                vol = (r["pred"] or {}).get("volumetric") or {}
                row += f" {vol.get('gate_action', '-')} | {vol.get('mass_source', '-')} |"
            lines.append(row)

    REPORTS.mkdir(parents=True, exist_ok=True)
    report = "\n".join(lines)
    (REPORTS / f"{stamp}.md").write_text(report + "\n")
    print("\n" + report)


if __name__ == "__main__":
    main()
