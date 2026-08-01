"""Offline tests for the food-search pipeline — no Anthropic, no USDA.

`food_search.vision.make_client` is monkeypatched to a fake whose responses are
scripted per call, and `food_search.grounding.best_match` to a lookup table, so
this exercises the real orchestration: USDA first, Claude recipe only on a miss.
"""

import json
from dataclasses import dataclass, field

import pytest

from app import food_search
from app.config import Settings
from app.fdc import FdcCandidate
from app.schemas import FoodSearchRequest

# MARK: Fakes


@dataclass
class TextBlock:
    text: str
    type: str = "text"


@dataclass
class FakeResponse:
    content: list = field(default_factory=list)


class FakeMessages:
    def __init__(self, script):
        self.script = list(script)
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if not self.script:
            raise AssertionError("the pipeline made more model calls than the script allows")
        nxt = self.script.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        return FakeResponse(content=[TextBlock(json.dumps(nxt))])


class FakeClient:
    def __init__(self, script):
        self.messages = FakeMessages(script)


@pytest.fixture
def scripted(monkeypatch):
    """Installs a fake Claude client; returns the installer."""
    holder: dict = {}

    def install(*script):
        client = FakeClient(script)
        holder["client"] = client
        monkeypatch.setattr(food_search.vision, "make_client", lambda config: client)
        return client

    install()  # default: any model call is an error unless a test scripts one
    return lambda *script: install(*script), holder


@pytest.fixture
def usda(monkeypatch):
    """Installs a USDA lookup table keyed by lowercased query."""

    def install(table: dict[str, dict[str, float]]):
        def best_match(api_key, name):
            nutrients = table.get(name.strip().lower())
            if nutrients is None:
                return None, []
            candidate = FdcCandidate(
                fdc_id=1,
                description=name,
                data_type="SR Legacy",
                nutrients=nutrients,
            )
            return candidate, []

        monkeypatch.setattr(food_search.grounding, "best_match", best_match)

    return install


def _config() -> Settings:
    return Settings(_env_file=None, anthropic_api_key="x", fdc_api_key="y")


def _request(**kwargs) -> FoodSearchRequest:
    return FoodSearchRequest(**kwargs)


# Per 100 g, the shape fdc.search_foods produces.
CHICKEN = {
    "calories": 165.0,
    "protein_g": 31.0,
    "carb_g": 0.0,
    "fiber_g": 0.0,
    "fat_g": 3.6,
    "sugar_g": 0.0,
    "sodium_mg": 74.0,
}
FLOUR = {
    "calories": 364.0,
    "protein_g": 10.0,
    "carb_g": 76.0,
    "fiber_g": 2.7,
    "fat_g": 1.0,
    "sugar_g": 0.3,
    "sodium_mg": 2.0,
}


# MARK: The USDA path


def test_a_typed_food_usda_knows_costs_no_model_call(scripted, usda):
    install, holder = scripted
    install()
    usda({"chicken breast": CHICKEN})

    results = food_search.search(
        _config(),
        _request(original_item="pasta", search="chicken breast", original_grams=170),
    )

    assert len(results) == 1, "a typed search returns exactly one result to apply"
    assert holder["client"].messages.calls == [], "USDA knew it; Claude must not be called"
    result = results[0]
    assert result["matched"] is True
    assert result["name"] == "chicken breast"
    # 165 kcal/100g scaled to 170 g = 280.5, which `round` takes to even —
    # the same banker's rounding `main._assemble` applies to a scan item.
    assert result["calories"] == 280
    assert result["protein_grams"] == 53
    assert result["fat_g"] == 6.1


def test_the_searched_food_keeps_the_portion_already_on_the_plate(scripted, usda):
    install, _ = scripted
    install()
    usda({"chicken breast": CHICKEN})

    results = food_search.search(
        _config(),
        _request(
            original_item="pasta",
            search="chicken breast",
            original_grams=170,
            original_portion_desc="1 breast, about 6 oz",
        ),
    )

    assert results[0]["portion_grams"] == 170.0
    assert results[0]["portion_desc"] == "1 breast, about 6 oz"


def test_a_search_with_no_portion_falls_back_to_100g(scripted, usda):
    install, _ = scripted
    install()
    usda({"chicken breast": CHICKEN})

    results = food_search.search(
        _config(), _request(original_item="pasta", search="chicken breast")
    )

    assert results[0]["portion_grams"] == 100.0
    assert results[0]["calories"] == 165
    assert results[0]["portion_desc"] == "1 serving"


# MARK: The recipe path


MAGGI_RECIPE = {
    "dishes": [
        {
            "name": "maggi",
            "portion_desc": "1 cake",
            "portion_grams": 70,
            "ingredients": [
                # USDA knows this one, so its numbers must come from the table.
                {
                    "name": "wheat flour",
                    "grams": 50,
                    "calories": 999,  # deliberately wrong: USDA must win
                    "protein_g": 99,
                    "carb_g": 99,
                    "fiber_g": 99,
                    "fat_g": 99,
                    "sugar_g": 99,
                    "sodium_mg": 99,
                },
                # USDA does not, so the model's own numbers are the fallback.
                {
                    "name": "palm oil",
                    "grams": 12,
                    "calories": 106,
                    "protein_g": 0,
                    "carb_g": 0,
                    "fiber_g": 0,
                    "fat_g": 12,
                    "sugar_g": 0,
                    "sodium_mg": 0,
                },
            ],
        }
    ]
}


def test_a_food_usda_lacks_is_composed_from_a_claude_recipe(scripted, usda):
    install, holder = scripted
    install(MAGGI_RECIPE)
    usda({"wheat flour": FLOUR})  # "maggi" and "palm oil" are absent

    results = food_search.search(
        _config(), _request(original_item="pasta", search="maggi", original_grams=70)
    )

    assert len(results) == 1
    result = results[0]
    assert result["matched"] is False, "the proportions are the model's, so this is an estimate"
    assert result["name"] == "maggi"
    assert result["portion_grams"] == 70.0
    # 50 g of USDA flour (182 kcal) + the model's 106 kcal for palm oil = 288,
    # then rescaled from the 62 g the ingredients sum to onto the stated 70 g
    # portion (x1.129). The recipe states proportions; the portion sets scale.
    assert result["calories"] == 325
    assert result["protein_grams"] == 6
    assert result["fat_g"] == 14.1
    assert len(holder["client"].messages.calls) == 1, "one decomposition call, not one per attempt"


def test_a_recipe_ingredient_usda_also_lacks_uses_the_models_numbers(scripted, usda):
    install, _ = scripted
    install(MAGGI_RECIPE)
    usda({})  # USDA knows nothing at all

    results = food_search.search(_config(), _request(search="maggi", original_grams=70))

    # Entirely the model's numbers now: (999 + 106) rescaled 62 g -> 70 g.
    assert results[0]["calories"] == 1248
    assert results[0]["matched"] is False


def test_a_recipe_with_no_calories_is_dropped_rather_than_returned_at_zero(scripted, usda):
    install, _ = scripted
    install(
        {
            "dishes": [
                {
                    "name": "mystery",
                    "portion_desc": "1 serving",
                    "portion_grams": 70,
                    "ingredients": [
                        {
                            "name": "nothing",
                            "grams": 0,
                            "calories": 0,
                            "protein_g": 0,
                            "carb_g": 0,
                            "fiber_g": 0,
                            "fat_g": 0,
                            "sugar_g": 0,
                            "sodium_mg": 0,
                        }
                    ],
                }
            ]
        }
    )
    usda({})

    assert food_search.search(_config(), _request(search="mystery")) == []


# MARK: Suggestions


NAMES = {
    "candidates": [
        {"name": "Noodles", "portion_desc": "1 serving", "portion_grams": 70},
        {"name": "noodles", "portion_desc": "1 serving", "portion_grams": 70},  # dupe
        {"name": "Pasta", "portion_desc": "1 cup cooked", "portion_grams": 140},  # the original
        {"name": "Ramen", "portion_desc": "1 bowl", "portion_grams": 250},
    ]
}


def test_an_empty_search_asks_the_model_for_alternatives(scripted, usda):
    install, holder = scripted
    install(NAMES)
    usda({"noodles": FLOUR, "ramen": FLOUR})

    results = food_search.search(
        _config(), _request(original_item="pasta", plate_context="a bowl of noodles")
    )

    names = [r["name"] for r in results]
    assert names == ["Noodles", "Ramen"], "deduped, and the detected food is not offered back"
    assert results[0]["portion_grams"] == 70.0, "suggestions use the model's own portion"
    assert holder["client"].messages.calls[0]["system"].startswith("You are the food-search engine")


def test_suggestions_are_capped(scripted, usda):
    install, _ = scripted
    many = {
        "candidates": [
            {"name": f"food {n}", "portion_desc": "1 serving", "portion_grams": 100}
            for n in range(20)
        ]
    }
    install(many)
    usda({f"food {n}": FLOUR for n in range(20)})

    results = food_search.search(_config(), _request(original_item="pasta"))

    assert len(results) == food_search.MAX_SUGGESTIONS


# MARK: Degradation — a model failure must never fail the request


def test_a_failed_naming_call_falls_back_to_the_detected_item(scripted, usda):
    install, _ = scripted
    install(RuntimeError("anthropic is down"))
    usda({"pasta": FLOUR})

    results = food_search.search(_config(), _request(original_item="pasta"))

    assert [r["name"] for r in results] == ["pasta"]
    assert results[0]["matched"] is True


def test_a_failed_recipe_call_still_returns_the_usda_matches(scripted, usda):
    install, _ = scripted
    install(
        {
            "candidates": [
                {"name": "Noodles", "portion_desc": "1 serving", "portion_grams": 70},
                {"name": "Maggi", "portion_desc": "1 cake", "portion_grams": 70},
            ]
        },
        RuntimeError("anthropic is down"),
    )
    usda({"noodles": FLOUR})  # "maggi" misses and its recipe call fails

    results = food_search.search(_config(), _request(original_item="pasta"))

    assert [r["name"] for r in results] == ["Noodles"]


def test_a_typed_food_nobody_can_price_returns_an_empty_list(scripted, usda):
    install, _ = scripted
    install(RuntimeError("anthropic is down"))
    usda({})

    assert food_search.search(_config(), _request(search="qqqq")) == []


# MARK: Nothing implausible may reach the log
#
# An edited item is logged by exactly the same path as a scanned one, so it has
# to clear the same bar. Each of these produced a wrong number before the gate.


@pytest.mark.parametrize("grams", [-500, 0, 1_000_000, float("nan"), float("inf")])
def test_an_absurd_portion_never_scales_the_numbers(scripted, usda, grams):
    install, _ = scripted
    install()
    usda({"noodles": FLOUR})

    results = food_search.search(_config(), _request(search="noodles", original_grams=grams))

    portion = results[0]["portion_grams"]
    assert 0 < portion <= food_search.MAX_GRAMS, f"{grams} g leaked through as {portion}"
    # 364 kcal/100 g, so a sane portion cannot produce a five-figure total.
    assert 0 < results[0]["calories"] < 20_000


def test_a_recipe_overshooting_its_portion_is_rescaled_not_summed(scripted, usda):
    """The model listing 700 g of flour for a 70 g cake used to return tenfold
    calories against a row still labelled 70 g."""
    install, _ = scripted
    install(
        {
            "dishes": [
                {
                    "name": "maggi",
                    "portion_desc": "1 cake",
                    "portion_grams": 70,
                    "ingredients": [
                        {
                            "name": "wheat flour",
                            "grams": 700,
                            "calories": 0,
                            "protein_g": 0,
                            "carb_g": 0,
                            "fiber_g": 0,
                            "fat_g": 0,
                            "sugar_g": 0,
                            "sodium_mg": 0,
                        }
                    ],
                }
            ]
        }
    )
    usda({"wheat flour": FLOUR})

    results = food_search.search(_config(), _request(search="maggi", original_grams=70))

    # 70 g of flour at 364 kcal/100 g, not 700 g of it.
    assert results[0]["portion_grams"] == 70.0
    assert results[0]["calories"] == 255


def test_a_usda_lookup_raising_mid_recipe_does_not_fail_the_request(scripted, usda, monkeypatch):
    """`fdc.search_foods` swallows HTTP errors but not a malformed body."""
    install, _ = scripted
    install(MAGGI_RECIPE)

    def exploding(api_key, name):
        raise ValueError("malformed FDC body")

    monkeypatch.setattr(food_search.grounding, "best_match", exploding)

    assert food_search.search(_config(), _request(search="maggi", original_grams=70)) == []


def test_a_dish_the_model_does_not_echo_back_is_dropped(scripted, usda):
    """Recipes are matched to seeds by name; a mismatch must drop the
    candidate, never attach the wrong dish's nutrition to it."""
    install, _ = scripted
    install(
        {
            "dishes": [
                {
                    "name": "something else entirely",
                    "portion_desc": "1 cake",
                    "portion_grams": 70,
                    "ingredients": [
                        {
                            "name": "wheat flour",
                            "grams": 70,
                            "calories": 255,
                            "protein_g": 7,
                            "carb_g": 53,
                            "fiber_g": 2,
                            "fat_g": 0.7,
                            "sugar_g": 0.2,
                            "sodium_mg": 1,
                        }
                    ],
                }
            ]
        }
    )
    usda({"wheat flour": FLOUR})

    assert food_search.search(_config(), _request(search="maggi", original_grams=70)) == []


def test_a_usda_candidate_missing_a_nutrient_still_matches(scripted, usda):
    """FDC drops nutrients it never measured; that must not lose the match."""
    install, _ = scripted
    install()
    usda({"chicken breast": {"calories": 165.0, "protein_g": 31.0}})

    results = food_search.search(_config(), _request(search="chicken breast", original_grams=100))

    assert results[0]["matched"] is True
    assert results[0]["calories"] == 165
    assert results[0]["fiber_grams"] == 0
    assert results[0]["sodium_mg"] == 0.0
