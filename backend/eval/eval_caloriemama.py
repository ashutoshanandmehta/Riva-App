"""Evaluate CalorieMama food recognition against the Nutrition5k golden set.

CalorieMama is a classifier: it names the dish (with alternatives) but does NOT
estimate portion size, so we score IDENTIFICATION, not calories. For each N5k
dish we ask: does CalorieMama's top-5 match the dominant ingredient, and how
many of the ground-truth ingredients does it surface?

Usage (from backend/):
    .venv/bin/python eval/eval_caloriemama.py
"""

import difflib
import io
import json
import sys
from pathlib import Path

import httpx
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "eval" / "golden.n5k.jsonl"
IMAGES = ROOT / "eval" / "images"
URL = "https://caloriemama.ai/api/food_recognition_proxy"
HEADERS = {"Referer": "https://caloriemama.ai/", "Origin": "https://caloriemama.ai"}
STOP = {"cooked", "raw", "grilled", "roasted", "with", "and", "the", "salad", "mixed"}


def caloriemama(path: Path):
    img = Image.open(path).convert("RGB").resize((544, 544))
    buf = io.BytesIO()
    img.save(buf, "JPEG")
    r = httpx.post(URL, headers=HEADERS,
                   files={"media": ("image.jpeg", buf.getvalue(), "image/jpeg")}, timeout=40)
    data = r.json()
    names = [it["name"] for g in data.get("results", []) for it in g.get("items", [])]
    return data.get("is_food"), names


def matches(term: str, name: str) -> bool:
    t, n = term.lower().strip(), name.lower()
    if not t:
        return False
    if t in n:
        return True
    if any(w in n for w in t.split() if len(w) > 2 and w not in STOP):
        return True
    return difflib.SequenceMatcher(None, t, n).ratio() >= 0.72


def any_match(term: str, names: list[str]) -> bool:
    return any(matches(term, nm) for nm in names)


def main() -> None:
    if not GOLDEN.exists():
        sys.exit(f"No golden set at {GOLDEN} — run eval/n5k_to_golden.py first.")
    golden = [json.loads(x) for x in GOLDEN.read_text().splitlines() if x.strip()]

    rows = []
    for case in golden:
        path = IMAGES / case["file"]
        if not path.exists():
            continue
        try:
            is_food, names = caloriemama(path)
        except Exception as error:  # keep going
            rows.append({**case, "error": str(error)})
            continue
        top5 = names[:5]
        dom = case.get("dish", "")
        ingrs = case.get("ingredients", []) or []
        ingr_hits = [ing for ing in ingrs if any_match(ing, top5)]
        rows.append({
            "file": case["file"], "dom": dom, "ingrs": ingrs, "top5": top5,
            "is_food": is_food,
            "dom_hit": any_match(dom, top5) if dom else None,
            "any_ingr_hit": len(ingr_hits) > 0,
            "recall": (len(ingr_hits) / len(ingrs)) if ingrs else None,
        })

    scored = [r for r in rows if "error" not in r]
    n = len(scored)
    if not n:
        sys.exit("No scored dishes.")
    dom_rows = [r for r in scored if r["dom_hit"] is not None]

    def pct(part, whole):
        return f"{100 * part / whole:.0f}%" if whole else "n/a"

    print(f"\n# CalorieMama vs Nutrition5k — {n} dishes\n")
    print(f"is_food = True                : {pct(sum(bool(r['is_food']) for r in scored), n)}")
    print(f"Dominant ingredient in top-5  : {pct(sum(bool(r['dom_hit']) for r in dom_rows), len(dom_rows))}")
    print(f"Any real ingredient in top-5  : {pct(sum(r['any_ingr_hit'] for r in scored), n)}")
    rec = [r['recall'] for r in scored if r['recall'] is not None]
    print(f"Ingredient recall (mean)      : {100 * sum(rec) / len(rec):.0f}%" if rec else "n/a")

    print("\n## Per dish (CalorieMama top-3  vs  N5k dominant)\n")
    for r in scored:
        mark = "OK " if r["dom_hit"] else ".. "
        print(f"{mark} {r['dom']:<16} <- {', '.join(r['top5'][:3])}")


if __name__ == "__main__":
    main()
