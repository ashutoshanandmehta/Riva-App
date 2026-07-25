"""Fetch Nutrition5k ground-truth overhead depth (and rgb) for the golden dishes.

Depth is a 16-bit PNG where 10,000 units = 1 metre (N5k README), capped ~0.4 m.
The bucket is public; download over plain HTTPS (stdlib only, no requests). Cached.
"""
import sys
import urllib.request
from pathlib import Path

BASE = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset"
DEPTH_URL = BASE + "/imagery/realsense_overhead/{dish_id}/depth_raw.png"
RGB_URL = BASE + "/imagery/realsense_overhead/{dish_id}/rgb.png"

HERE = Path(__file__).resolve().parent
DEPTH_DIR = HERE / "depth"
RGB_DIR = HERE / "rgb"


def _fetch(url: str, dest: Path) -> bool:
    if dest.exists() and dest.stat().st_size > 0:
        return True
    try:
        with urllib.request.urlopen(url, timeout=90) as resp:
            data = resp.read()
    except Exception as error:  # missing dish / network
        print(f"  miss {dest.name}: {error}")
        return False
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return True


def fetch_dish(dish_id: str) -> bool:
    """Download depth_raw.png + rgb.png for one dish. True only if both land."""
    ok_depth = _fetch(DEPTH_URL.format(dish_id=dish_id), DEPTH_DIR / f"{dish_id}.png")
    ok_rgb = _fetch(RGB_URL.format(dish_id=dish_id), RGB_DIR / f"{dish_id}.png")
    return ok_depth and ok_rgb


def depth_path(dish_id: str) -> Path:
    return DEPTH_DIR / f"{dish_id}.png"


def rgb_path(dish_id: str) -> Path:
    return RGB_DIR / f"{dish_id}.png"


if __name__ == "__main__":
    import json

    golden = Path(__file__).resolve().parent.parent / "golden.n5k.jsonl"
    ids = [json.loads(x)["dish_id"] for x in golden.read_text().splitlines() if x.strip()]
    got = sum(fetch_dish(i) for i in ids)
    print(f"fetched depth+rgb for {got}/{len(ids)} dishes into {DEPTH_DIR}")
    sys.exit(0 if got else 1)
