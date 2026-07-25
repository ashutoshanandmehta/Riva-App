"""Load the food-class + scale-prior tables and resolve a free-text food name
to a class. Unknown names fall back to `_generic` (never a hard failure)."""
import json
from functools import lru_cache
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Canonical class table lives with the app (single source, shared with the
# production plausibility gate). HERE.parents[2] == backend/.
APP_TABLE = HERE.parents[2] / "app" / "food_classes.json"


@lru_cache
def food_classes() -> dict:
    return json.loads(APP_TABLE.read_text())


@lru_cache
def scale_priors() -> dict:
    return json.loads((HERE / "scale_priors.json").read_text())


def resolve_class(name: str | None) -> tuple[str, dict]:
    """Map a detected food name -> (class_key, class_record). Alias substring
    match, else `_generic`. Deterministic (longest-alias-wins) so 'cheeseburger'
    beats a stray 'cheese' alias."""
    classes = food_classes()
    if not name:
        return "_generic", classes["_generic"]
    n = name.lower()
    best_key, best_len = None, 0
    for key, rec in classes.items():
        if key.startswith("_"):
            continue
        for alias in rec.get("aliases", []):
            if alias in n and len(alias) > best_len:
                best_key, best_len = key, len(alias)
    if best_key:
        return best_key, classes[best_key]
    return "_generic", classes["_generic"]
