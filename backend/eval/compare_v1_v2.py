"""V1 (gpt-5.2 + USDA) vs V2 (CalorieMama + USDA) on Nutrition5k.

Both grounded in USDA. Because CalorieMama estimates no portion, we compare
PORTION-NEUTRAL density: calories per 100 g, against the dish's real density
(N5k total kcal / total mass). This isolates the identifier feeding USDA.

  V1 density = gpt-5.2 grounded totals.calories / detected grams * 100
  V2 density = USDA per-100g calories for CalorieMama's top food name
  truth      = golden kcal / grams * 100

Usage (from backend/):  .venv/bin/python eval/compare_v1_v2.py
"""

import io
import json
import statistics
import sys
from pathlib import Path

import httpx
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app import grounding, preprocess, vision  # noqa: E402
from app.config import settings  # noqa: E402
from app.main import _assemble  # noqa: E402

GOLDEN = ROOT / "eval" / "golden.n5k.jsonl"
IMAGES = ROOT / "eval" / "images"
CM_URL = "https://caloriemama.ai/api/food_recognition_proxy"
CM_HEADERS = {"Referer": "https://caloriemama.ai/", "Origin": "https://caloriemama.ai"}


def caloriemama_top(path: Path) -> str | None:
    img = Image.open(path).convert("RGB").resize((544, 544))
    buf = io.BytesIO(); img.save(buf, "JPEG")
    r = httpx.post(CM_URL, headers=CM_HEADERS,
                   files={"media": ("image.jpeg", buf.getvalue(), "image/jpeg")}, timeout=40)
    for g in r.json().get("results", []):
        for it in g.get("items", []):
            return it.get("name")
    return None


def main() -> None:
    config = settings()
    golden = [json.loads(x) for x in GOLDEN.read_text().splitlines() if x.strip()]

    client = vision.make_client(config)
    model = vision.resolve_model(config)
    prompt_text = vision.load_prompt(config.prompt_version)

    rows = []
    for case in golden:
        path = IMAGES / case["file"]
        if not path.exists():
            continue
        truth = case["kcal"] / case["grams"] * 100 if case.get("grams") else None
        if not truth:
            continue

        # --- V1: Claude (RIVA_SCAN_MODEL, default Sonnet) + USDA ---
        v1 = v1_name = None
        try:
            b64 = preprocess.prepare_image(path.read_bytes())
            analysis = vision.analyze_image(client, model, b64, None, prompt_text)
            result = _assemble(analysis, config.fdc_api_key)
            grams = sum(i.portion_grams for i in result.items)
            if grams:
                v1 = result.totals.calories / grams * 100
            if result.items:
                v1_name = max(result.items, key=lambda i: i.portion_grams).name
        except Exception as error:
            v1_name = f"ERR {error}"

        # --- V2: CalorieMama name -> USDA ---
        v2 = v2_name = None
        try:
            v2_name = caloriemama_top(path)
            if v2_name:
                cand, _ = grounding.best_match(config.fdc_api_key, v2_name)
                if cand:
                    v2 = cand["nutrients"].get("calories")
        except Exception as error:
            v2_name = f"ERR {error}"

        rows.append({
            "dish": case.get("dish", ""), "truth": truth,
            "v1": v1, "v1_name": v1_name, "v2": v2, "v2_name": v2_name,
            "v1_err": abs(v1 - truth) / truth if v1 else None,
            "v2_err": abs(v2 - truth) / truth if v2 else None,
        })

    def mape(key):
        errs = [r[key] for r in rows if r[key] is not None]
        return f"{100 * statistics.mean(errs):.0f}%" if errs else "n/a"

    def cov(key):
        got = sum(1 for r in rows if r[key.replace('_err', '')] is not None)
        return f"{got}/{len(rows)}"

    print(f"\n# V1 vs V2 on Nutrition5k — density (kcal/100g), {len(rows)} dishes\n")
    print(f"{'':22}{'V1 gpt-5.2':>14}{'V2 CalorieMama':>18}")
    print(f"{'per-100g cal MAPE':22}{mape('v1_err'):>14}{mape('v2_err'):>18}")
    print(f"{'produced a number':22}{cov('v1_err'):>14}{cov('v2_err'):>18}")
    wins = sum(1 for r in rows if r['v1_err'] is not None and r['v2_err'] is not None and r['v1_err'] < r['v2_err'])
    both = sum(1 for r in rows if r['v1_err'] is not None and r['v2_err'] is not None)
    print(f"{'V1 closer (of both)':22}{f'{wins}/{both}':>14}")

    print("\n## per dish  (truth kcal/100g  |  V1  |  V2)\n")
    for r in rows:
        f = lambda v: f"{v:5.0f}" if v is not None else "  -- "
        print(f"{r['dish']:<16} {r['truth']:5.0f} | V1 {f(r['v1'])} ({(r['v1_name'] or '')[:26]}) "
              f"| V2 {f(r['v2'])} ({(r['v2_name'] or '')[:20]})")


if __name__ == "__main__":
    main()
