"""Validate the dataset and extract frames from every capture.mp4. Run this after
capturing dishes, before scoring. Idempotent: skips dishes that already have frames.
"""
import dataset
import frames as frames_mod


def main() -> None:
    dishes = dataset.discover()
    if not dishes:
        print(f"No dishes under {dataset.DATASET}. See README.md for the protocol.")
        return
    ok = 0
    for d in dishes:
        if d["problems"]:
            print(f"! {d['dish_id']}: {'; '.join(d['problems'])}")
            continue
        existing = sorted(d["frames_dir"].glob("*.jp*g")) if d["frames_dir"].exists() else []
        if existing:
            n = len(existing)
        elif d.get("video"):
            try:
                n = len(frames_mod.extract(d["video"], d["frames_dir"]))
            except Exception as error:
                print(f"! {d['dish_id']}: frame extraction failed: {error}")
                continue
        else:
            n = 0
        ok += 1
        print(f"  {d['dish_id']}: OK — {n} frame(s), truth {d['truth']['grams_total']}g")
    print(f"\n{ok}/{len(dishes)} dishes ready.")


if __name__ == "__main__":
    main()
