"""Run the multi-item / multi-view volumetric pipeline on a capture directory.

    ../../../.venv/bin/python run_multiview.py "<dir of N views>"
    ../../../.venv/bin/python run_multiview.py "<dir>" --no-llm --class burger
    ../../../.venv/bin/python run_multiview.py "<dir>" --segmenter sam2   # needs REPLICATE_API_TOKEN

Segmenter: auto (SAM 2 if REPLICATE_API_TOKEN is set, else classical) unless forced
with --segmenter classical|sam2. --no-llm skips Claude identification.
"""
import argparse
import os
from pathlib import Path

import capture_set
import identify as identify_mod
import pipeline

# Load backend/.env so REPLICATE_API_TOKEN / ANTHROPIC_API_KEY reach the SDKs
# regardless of cwd. backend/ is three levels up from this file.
_ENV = Path(__file__).resolve().parents[3] / ".env"
if _ENV.exists():
    for _line in _ENV.read_text().splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _k, _, _v = _line.partition("=")
            os.environ.setdefault(_k.strip(), _v.strip())


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("capture_dir")
    ap.add_argument("--no-llm", action="store_true", help="skip Claude identification")
    ap.add_argument("--class", dest="klass", default="_generic", help="class when --no-llm")
    ap.add_argument("--segmenter", choices=["classical", "sam2"], default=None,
                    help="force segmenter (default: auto by REPLICATE_API_TOKEN)")
    args = ap.parse_args()

    views = capture_set.discover_views(args.capture_dir)
    if not views:
        print(f"No views in {args.capture_dir}")
        return
    print(f"Discovered {len(views)} view(s): {[v.name for v in views]}")

    if args.no_llm:
        items = [{"name": args.klass, "grams": 100.0}]
    else:
        items = identify_mod.identify(views[-1])
        print(f"Identified item(s): {[i['name'] for i in items]}")

    res = pipeline.run(args.capture_dir, items, segmenter_force=args.segmenter)
    print(f"Segmenter: {res['segmenter']}  |  items detected: {res['meal']['n_items']}")

    for name, fused, g in res["items"]:
        print(f"\nItem: {name}")
        for e in fused["estimates"]:
            print(f"  {e.view:<14} role={e.role:<7} vol={e.volume_ml:6.0f} mL conf={e.confidence:.2f}")
        mass = f"{g.mass_g:.0f}g" if g.mass_g is not None else "—"
        kcal = f"{g.kcal:.0f}kcal" if g.kcal is not None else "—"
        print(f"  -> fused {fused['volume_ml']:.0f} mL over {fused['n_views']} view(s) | "
              f"class={g.food_class} action={g.action} mass={mass} {kcal} "
              f"conf={g.confidence:.2f} [{g.reason}]")

    m = res["meal"]
    print(f"\nMeal: {m['mass_g']} g, {m['kcal']} kcal "
          f"(items {m['n_items']}, logged {m['n_logged']}, retake {m['n_retake']})")


if __name__ == "__main__":
    main()
