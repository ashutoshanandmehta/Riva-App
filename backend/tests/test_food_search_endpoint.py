"""Offline tests for `POST /v1/food-search` — no Supabase, no Anthropic, no USDA.

`app.main._require_user` is monkeypatched to a fixed verified user and the
pipeline itself is stubbed, so this covers the route's own contract: auth,
validation, and the wire shape the shipped iOS client decodes.
"""

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

import app.main as main

USER = "11111111-1111-1111-1111-111111111111"

PRICED = {
    "name": "noodles",
    "portion_desc": "1 serving",
    "portion_grams": 70.0,
    "calories": 340,
    "protein_grams": 8,
    "carb_grams": 62,
    "fiber_grams": 3,
    "fat_g": 5.4,
    "sugar_g": 1.2,
    "sodium_mg": 620.0,
    "matched": True,
}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(main, "_require_user", lambda authorization: USER)
    return TestClient(main.app)


@pytest.fixture
def searched(monkeypatch):
    """Captures the request the route handed the pipeline."""
    seen: list = []

    def fake_search(config, request):
        seen.append(request)
        return [dict(PRICED)]

    monkeypatch.setattr(main.food_search, "search", fake_search)
    return seen


def _post(client, **body):
    return client.post("/v1/food-search", json=body, headers={"Authorization": "Bearer test"})


def test_the_response_is_a_top_level_array_of_snake_case_objects(client, searched):
    """This assertion IS the iOS contract: FoodReplacementService decodes
    `[FoodSuggestion].self` with `.convertFromSnakeCase`."""
    response = _post(client, original_item="pasta", search="noodles")

    assert response.status_code == 200
    body = response.json()
    assert isinstance(body, list)
    assert body[0] == PRICED
    assert set(body[0]) == {
        "name",
        "portion_desc",
        "portion_grams",
        "calories",
        "protein_grams",
        "carb_grams",
        "fiber_grams",
        "fat_g",
        "sugar_g",
        "sodium_mg",
        "matched",
    }


def test_the_plate_context_reaches_the_pipeline(client, searched):
    _post(
        client,
        original_item="pasta",
        search="",
        plate_context="a bowl of noodles",
        other_items=["broccoli"],
        original_grams=70,
        original_portion_desc="1 serving",
    )

    request = searched[0]
    assert request.original_item == "pasta"
    assert request.plate_context == "a bowl of noodles"
    assert request.other_items == ["broccoli"]
    assert request.original_grams == 70
    assert request.original_portion_desc == "1 serving"


def test_a_client_that_omits_the_portion_fields_still_works(client, searched):
    """Both are newer than the shipped build, so they must stay optional."""
    response = _post(client, original_item="pasta", search="noodles")

    assert response.status_code == 200
    assert searched[0].original_grams == 0
    assert searched[0].original_portion_desc == ""


def test_an_empty_body_is_a_400(client, searched):
    response = _post(client)

    assert response.status_code == 400
    assert response.json()["detail"] == "Say which food to replace, or search for one."
    assert searched == [], "the pipeline must not be called for a request that cannot work"


def test_an_oversized_query_is_a_400(client, searched):
    response = _post(client, original_item="pasta", search="x" * 121)

    assert response.status_code == 400
    assert "120 characters" in response.json()["detail"]
    assert searched == []


def test_a_suggest_request_needs_only_the_detected_item(client, searched):
    response = _post(client, original_item="pasta")

    assert response.status_code == 200
    assert searched[0].search == ""


def test_the_route_requires_a_verified_user(monkeypatch, searched):
    """The gate runs before any work, so whatever `_require_user` raises is
    what the caller gets and the pipeline is never reached. Patched rather
    than left to the ambient env, which decides on its own between 401 (a
    configured Supabase) and 503 (open stateless mode)."""

    def deny(authorization):
        raise HTTPException(status_code=401, detail="Sign in to continue.")

    monkeypatch.setattr(main, "_require_user", deny)
    response = TestClient(main.app).post("/v1/food-search", json={"original_item": "pasta"})

    assert response.status_code == 401
    assert searched == []


def test_no_result_is_an_empty_array_not_an_error(client, monkeypatch):
    monkeypatch.setattr(main.food_search, "search", lambda config, request: [])

    response = _post(client, original_item="pasta", search="qqqq")

    assert response.status_code == 200
    assert response.json() == []
