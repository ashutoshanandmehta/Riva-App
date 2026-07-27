"""Unit: the tool registry, dispatch, and the retrieve_weight_log handler.

Backend reads are faked, so nothing here touches Supabase or the network
(mirrors the mocked style of test_suggestions.py).
"""

import pytest
from fastapi import HTTPException

from app import backend
from app.chat import handlers, tools
from app.config import Settings

CONFIG = Settings()
USER = "11111111-1111-1111-1111-111111111111"


@pytest.fixture
def weights(monkeypatch):
    """Captures the kwargs the handler passes down, and serves fixture rows."""
    calls: dict = {}

    def fake_list_weights(config, user_id, limit, since=None, until=None):
        calls.update(user_id=user_id, limit=limit, since=since, until=until)
        # Newest-first, the way PostgREST returns them.
        return [
            {"id": "c", "pounds": 208.4, "dose_mg": 1.0, "measured_at": "2026-07-24T07:00:00Z"},
            {"id": "b", "pounds": 212.0, "dose_mg": 0.5, "measured_at": "2026-07-10T07:00:00Z"},
            {"id": "a", "pounds": 220.6, "dose_mg": 0.5, "measured_at": "2026-07-01T07:00:00Z"},
        ]

    monkeypatch.setattr(handlers.backend, "list_weights", fake_list_weights)
    monkeypatch.setattr(
        handlers.store,
        "profile_targets",
        lambda config, user_id: {"start_weight": 225.0, "goal_weight": 190.0},
    )
    return calls


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------


def test_anthropic_tools_are_derived_from_the_registry():
    payload = tools.anthropic_tools()
    assert {entry["name"] for entry in payload} == set(tools.REGISTRY)
    for entry in payload:
        assert set(entry) == {"name", "description", "input_schema"}
        assert entry["description"].strip()
        assert entry["input_schema"]["type"] == "object"
        assert entry["input_schema"] is tools.REGISTRY[entry["name"]].input_schema


def test_command_catalogue_exposes_slashed_commands_and_arguments():
    entry = next(e for e in tools.command_catalogue() if e["tool"] == "retrieve_weight_log")
    assert "/retrieve_weight_log" in entry["commands"]
    assert entry["arguments"] == ["end_date", "limit", "start_date"]


def test_registry_keys_match_tool_names():
    for name, spec in tools.REGISTRY.items():
        assert name == spec.name


def test_schemas_forbid_undeclared_properties():
    """additionalProperties False keeps a model from inventing arguments."""
    for spec in tools.REGISTRY.values():
        assert spec.input_schema.get("additionalProperties") is False


# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------


def test_dispatch_drops_undeclared_arguments(weights):
    spec = tools.REGISTRY["retrieve_weight_log"]
    tools.dispatch(spec, CONFIG, USER, {"start_date": "2026-07-01", "nonsense": "x"})
    assert weights["since"] == "2026-07-01"


def test_dispatch_ignores_a_user_id_smuggled_into_the_arguments(weights):
    """The subject comes from the verified token. Even if a prompt-injected model
    emits one, it is not a declared property, so it never reaches the handler."""
    spec = tools.REGISTRY["retrieve_weight_log"]
    tools.dispatch(spec, CONFIG, USER, {"user_id": "22222222-2222-2222-2222-222222222222"})
    assert weights["user_id"] == USER


def test_dispatch_returns_the_handler_payload(weights):
    spec = tools.REGISTRY["retrieve_weight_log"]
    result = tools.dispatch(spec, CONFIG, USER, {})
    assert set(result) == {"requested_range", "entries", "summary"}


# ---------------------------------------------------------------------------
# retrieve_weight_log
# ---------------------------------------------------------------------------


def test_entries_are_returned_oldest_first(weights):
    result = handlers.retrieve_weight_log(CONFIG, USER, {})
    assert [entry["pounds"] for entry in result["entries"]] == [220.6, 212.0, 208.4]


def test_summary_arithmetic_is_computed_server_side(weights):
    summary = handlers.retrieve_weight_log(CONFIG, USER, {})["summary"]
    assert summary["count"] == 3
    assert summary["first_lbs"] == 220.6
    assert summary["latest_lbs"] == 208.4
    assert summary["change_lbs"] == -12.2  # lost weight reads negative
    assert summary["start_weight_lbs"] == 225.0
    assert summary["goal_weight_lbs"] == 190.0
    assert summary["to_goal_lbs"] == 18.4
    assert summary["period_start"] == "2026-07-01T07:00:00Z"
    assert summary["period_end"] == "2026-07-24T07:00:00Z"


def test_date_range_is_passed_through_to_the_query(weights):
    handlers.retrieve_weight_log(
        CONFIG, USER, {"start_date": "2026-07-01", "end_date": "2026-07-26"}
    )
    assert (weights["since"], weights["until"]) == ("2026-07-01", "2026-07-26")


def test_limit_is_clamped_to_the_maximum(weights):
    handlers.retrieve_weight_log(CONFIG, USER, {"limit": 5000})
    assert weights["limit"] == handlers.MAX_LIMIT


def test_limit_defaults_when_absent(weights):
    handlers.retrieve_weight_log(CONFIG, USER, {})
    assert weights["limit"] == handlers._DEFAULT_LIMIT


@pytest.mark.parametrize("value", ["last month", "2026-13-01", "07/01/2026", "2026-07-32"])
def test_unparseable_dates_are_a_clear_400(weights, value):
    """A model can emit prose where a date belongs. That must not silently
    become a whole-history read."""
    with pytest.raises(HTTPException) as excinfo:
        handlers.retrieve_weight_log(CONFIG, USER, {"start_date": value})
    assert excinfo.value.status_code == 400


def test_reversed_range_is_rejected(weights):
    with pytest.raises(HTTPException) as excinfo:
        handlers.retrieve_weight_log(
            CONFIG, USER, {"start_date": "2026-07-26", "end_date": "2026-07-01"}
        )
    assert excinfo.value.status_code == 400


def test_empty_history_summarises_without_crashing(monkeypatch):
    monkeypatch.setattr(handlers.backend, "list_weights", lambda *args, **kwargs: [])
    monkeypatch.setattr(handlers.store, "profile_targets", lambda config, user_id: {})
    summary = handlers.retrieve_weight_log(CONFIG, USER, {})["summary"]
    assert summary["count"] == 0
    assert summary["change_lbs"] is None
    assert summary["to_goal_lbs"] is None


def test_missing_goal_weight_leaves_to_goal_unset(weights, monkeypatch):
    monkeypatch.setattr(
        handlers.store, "profile_targets", lambda config, user_id: {"start_weight": 225.0}
    )
    summary = handlers.retrieve_weight_log(CONFIG, USER, {})["summary"]
    assert summary["goal_weight_lbs"] is None
    assert summary["to_goal_lbs"] is None
    assert summary["change_lbs"] == -12.2  # the rest of the trend still works


# ---------------------------------------------------------------------------
# The inclusive-date-range filters the handlers rely on. Chat is the only
# consumer of these kwargs, so they are covered here.
# ---------------------------------------------------------------------------


def test_timestamp_day_bounds_makes_the_end_day_inclusive():
    """`until` covers the whole end day, whatever time the row was stamped, so
    it becomes an exclusive `< next day`."""
    assert backend._timestamp_day_bounds("2026-07-01", "2026-07-26") == [
        "gte.2026-07-01",
        "lt.2026-07-27",
    ]


def test_timestamp_day_bounds_handles_one_sided_and_empty_ranges():
    assert backend._timestamp_day_bounds("2026-07-01", None) == ["gte.2026-07-01"]
    assert backend._timestamp_day_bounds(None, "2026-07-26") == ["lt.2026-07-27"]
    assert backend._timestamp_day_bounds(None, None) == []


def test_timestamp_day_bounds_crosses_a_month_end():
    assert backend._timestamp_day_bounds(None, "2026-07-31") == ["lt.2026-08-01"]
