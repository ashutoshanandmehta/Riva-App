"""Unit: the wellness suggestion module — schema shape, deterministic
fallback rules, payload validation, and the cache helpers (mocked, no
network)."""

import pytest

from app import backend, suggestions
from app.config import Settings

# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------


def test_schema_enum_matches_catalog():
    enum = suggestions.SUGGEST_SCHEMA["properties"]["suggestions"]["items"]["properties"][
        "practice_id"
    ]["enum"]
    assert set(enum) == set(suggestions.CATALOG)


def test_schema_is_strict():
    schema = suggestions.SUGGEST_SCHEMA
    assert schema["additionalProperties"] is False
    array = schema["properties"]["suggestions"]
    item = array["items"]
    assert item["additionalProperties"] is False
    assert set(item["required"]) == {"practice_id", "reason"}
    assert set(item["properties"]["practice_id"]["enum"]) == set(suggestions.CATALOG)


def test_catalog_has_all_planned_practices():
    assert set(suggestions.CATALOG) == {
        "yoga_beginners",
        "yoga_weightloss",
        "yoga_digestion",
        "meditation_isha",
        "meditation_nsdr",
        "exercise_walk",
        "mind_gratitude",
        "sleep_winddown",
    }
    for kind, minutes, title in suggestions.CATALOG.values():
        assert kind in ("yoga", "meditation", "exercise", "mind", "sleep")
        assert 0 < minutes <= 300
        assert title


# ---------------------------------------------------------------------------
# Fallback rules
# ---------------------------------------------------------------------------


def _ctx(**overrides):
    context = {
        "day": "2026-07-24",
        "local_hour": 14,
        "minutes_today": 0,
        "goal_minutes": 45,
        "streak_days": 0,
        "recent_kinds": {},
        "sleep_quality_avg": None,
    }
    context.update(overrides)
    return context


def test_fallback_is_deterministic():
    context = _ctx()
    assert suggestions.fallback(context) == suggestions.fallback(context)


def test_fallback_morning_suggests_yoga():
    result = suggestions.fallback(_ctx(local_hour=8))
    assert result["suggestions"][0]["practice_id"] == "yoga_beginners"


def test_fallback_evening_suggests_winddown():
    result = suggestions.fallback(_ctx(local_hour=21))
    assert result["suggestions"][0]["practice_id"] == "sleep_winddown"


def test_fallback_low_sleep_suggests_nsdr_over_time_of_day():
    result = suggestions.fallback(_ctx(local_hour=8, sleep_quality_avg=2.0))
    assert result["suggestions"][0]["practice_id"] == "meditation_nsdr"


def test_fallback_midday_suggests_gratitude():
    result = suggestions.fallback(_ctx(local_hour=14))
    assert result["suggestions"][0]["practice_id"] == "mind_gratitude"


def test_fallback_survives_missing_context():
    result = suggestions.fallback(None)
    assert 1 <= len(result["suggestions"]) <= 3
    for entry in result["suggestions"]:
        assert entry["practice_id"] in suggestions.CATALOG
        assert len(entry["reason"]) <= 120


# ---------------------------------------------------------------------------
# Payload validation
# ---------------------------------------------------------------------------


def test_validated_dedupes_and_caps():
    payload = {
        "suggestions": [
            {"practice_id": "yoga_beginners", "reason": "a"},
            {"practice_id": "yoga_beginners", "reason": "dupe"},
            {"practice_id": "not_in_catalog", "reason": "bad"},
            {"practice_id": "mind_gratitude", "reason": "x" * 200},
            {"practice_id": "exercise_walk", "reason": "b"},
            {"practice_id": "meditation_isha", "reason": "over the cap"},
        ]
    }
    result = suggestions._validated(payload)
    ids = [s["practice_id"] for s in result["suggestions"]]
    assert ids == ["yoga_beginners", "mind_gratitude", "exercise_walk"]
    assert len(result["suggestions"][1]["reason"]) == 120


def test_validated_rejects_junk():
    with pytest.raises(ValueError):
        suggestions._validated({"suggestions": [{"practice_id": "nope", "reason": ""}]})
    with pytest.raises(ValueError):
        suggestions._validated({"nothing": True})


# ---------------------------------------------------------------------------
# Cache helpers (backend REST layer mocked)
# ---------------------------------------------------------------------------

_CONFIG = Settings(_env_file=None)
_PAYLOAD = {"suggestions": [{"practice_id": "yoga_beginners", "reason": "hi"}]}


def test_get_cached_suggestions_hit_and_miss(monkeypatch):
    calls = []

    def fake_select(config, table, params):
        calls.append((table, params))
        if params["day"] == "eq.2026-07-24":
            return [{"payload": _PAYLOAD}]
        return []

    monkeypatch.setattr(backend, "_select", fake_select)
    assert backend.get_cached_suggestions(_CONFIG, "user-1", "2026-07-24") == _PAYLOAD
    assert backend.get_cached_suggestions(_CONFIG, "user-1", "2026-07-25") is None
    assert all(table == "wellness_suggestions" for table, _ in calls)
    assert calls[0][1]["user_id"] == "eq.user-1"


def test_cache_suggestions_inserts_row(monkeypatch):
    inserted = {}

    def fake_insert(config, table, payload, params=None):
        inserted["table"] = table
        inserted["payload"] = payload
        return [payload]

    monkeypatch.setattr(backend, "_insert", fake_insert)
    backend.cache_suggestions(_CONFIG, "user-1", "2026-07-24", _PAYLOAD)
    assert inserted["table"] == "wellness_suggestions"
    assert inserted["payload"] == {
        "user_id": "user-1",
        "day": "2026-07-24",
        "payload": _PAYLOAD,
    }


def test_resolve_model_override():
    assert suggestions.resolve_model(_CONFIG) == suggestions.DEFAULT_MODEL
    custom = Settings(_env_file=None, riva_suggest_model="claude-haiku-4-5")
    assert suggestions.resolve_model(custom) == "claude-haiku-4-5"
