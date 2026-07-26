"""Unit: the nutrition, wellness, goals and to-do read handlers.

Store reads are faked, so nothing here touches Supabase. The assertions are
about the two things a model cannot be trusted to do itself: the summary
arithmetic, and the window defaulting to the *user's* calendar day.
"""

import pytest

from app.chat import handlers_reads, store, tools
from app.config import Settings

CONFIG = Settings()
USER = "11111111-1111-1111-1111-111111111111"
TODAY = "2026-07-26"

_DAYS = [
    {
        "day": "2026-07-24",
        "calories": 1400,
        "protein_grams": 120,
        "carb_grams": 130,
        "fiber_grams": 20,
        "water_ounces": 64,
    },
    {
        "day": "2026-07-25",
        "calories": 1800,
        "protein_grams": 140,
        "carb_grams": 150,
        "fiber_grams": 30,
        "water_ounces": 96,
    },
]

_GOALS = {"protein_goal": 130, "carb_goal": 284, "fiber_goal": 30, "water_goal": 80}


@pytest.fixture
def nutrition(monkeypatch):
    """Serves fixture rows and captures the range the handler asked for."""
    asked: dict = {}

    def fake_days(config, user_id, since, until):
        asked.update(since=since, until=until)
        return list(_DAYS)

    monkeypatch.setattr(store, "nutrition_days", fake_days)
    monkeypatch.setattr(store, "nutrition_goals", lambda config, user_id: dict(_GOALS))
    monkeypatch.setattr(store, "local_day", lambda config, user_id: (TODAY, "America/New_York"))
    monkeypatch.setattr(
        store,
        "food_entries",
        lambda config, user_id, since, until: [
            {
                "day": "2026-07-25",
                "scan_type": "food",
                "created_at": "2026-07-25T18:00:00Z",
                "calories": 620,
                "protein_grams": 48,
                "water_ounces": 0,
                "items": [{"name": "grilled chicken"}, {"name": "rice"}, 7],
            }
        ],
    )
    return asked


# ---------------------------------------------------------------------------
# Nutrition
# ---------------------------------------------------------------------------


def test_nutrition_defaults_to_the_users_own_last_thirty_days(nutrition):
    handlers_reads.retrieve_nutrition_log(CONFIG, USER, {})
    assert nutrition["until"] == TODAY
    assert nutrition["since"] == "2026-06-26"


def test_nutrition_summary_does_the_arithmetic(nutrition):
    summary = handlers_reads.retrieve_nutrition_log(CONFIG, USER, {})["summary"]

    assert summary["days_logged"] == 2
    assert summary["avg_calories"] == 1600.0
    assert summary["total_protein_grams"] == 260
    assert summary["highest_calorie_day"]["day"] == "2026-07-25"
    assert summary["lowest_calorie_day"]["day"] == "2026-07-24"
    assert summary["latest_day"]["day"] == "2026-07-25"


def test_nutrition_counts_days_that_met_each_goal(nutrition):
    summary = handlers_reads.retrieve_nutrition_log(CONFIG, USER, {})["summary"]

    # protein: 120 misses 130, 140 clears it. water: 64 misses 80, 96 clears it.
    assert summary["days_meeting_protein_grams_goal"] == 1
    assert summary["days_meeting_water_ounces_goal"] == 1
    # Calories have no goal row, so there is nothing to compare against.
    assert summary["days_meeting_calories_goal"] is None


def test_nutrition_omits_meals_unless_asked(nutrition):
    assert "meals" not in handlers_reads.retrieve_nutrition_log(CONFIG, USER, {})


def test_nutrition_meals_survive_a_malformed_items_blob(nutrition):
    result = handlers_reads.retrieve_nutrition_log(CONFIG, USER, {"include_meals": True})
    assert result["meals"][0]["items"] == ["grilled chicken", "rice"]
    assert result["meals_truncated"] is False


def test_an_empty_nutrition_window_summarises_to_nothing_not_zero(nutrition, monkeypatch):
    monkeypatch.setattr(store, "nutrition_days", lambda config, user_id, since, until: [])
    summary = handlers_reads.retrieve_nutrition_log(CONFIG, USER, {})["summary"]

    assert summary["days_logged"] == 0
    assert summary["avg_calories"] is None
    assert summary["latest_day"] is None


# ---------------------------------------------------------------------------
# Wellness
# ---------------------------------------------------------------------------


@pytest.fixture
def wellness(monkeypatch):
    monkeypatch.setattr(store, "local_day", lambda config, user_id: (TODAY, "America/New_York"))
    monkeypatch.setattr(store, "wellness_minutes_goal", lambda config, user_id: 20)
    monkeypatch.setattr(
        store,
        "wellness_sessions",
        lambda config, user_id, since, until: [
            {"day": "2026-07-25", "kind": "meditation", "practice_id": "calm", "minutes": 12},
            {"day": "2026-07-25", "kind": "yoga", "practice_id": "flow", "minutes": 10},
            {"day": "2026-07-26", "kind": "meditation", "practice_id": "calm", "minutes": 5},
        ],
    )
    monkeypatch.setattr(
        handlers_reads.backend,
        "wellness_summary",
        lambda config, user_id: {"day": TODAY, "minutes_today": 5, "streak_days": 4},
    )


def test_wellness_groups_minutes_by_day_and_kind(wellness):
    summary = handlers_reads.retrieve_wellness_log(CONFIG, USER, {})["summary"]

    assert summary["session_count"] == 3
    assert summary["active_days"] == 2
    assert summary["total_minutes"] == 27
    assert summary["minutes_by_kind"] == {"meditation": 17, "yoga": 10}
    # 22 minutes on the 25th clears the 20-minute goal; 5 on the 26th does not.
    assert summary["days_meeting_goal"] == 1


def test_wellness_takes_the_streak_from_the_server_not_the_rows(wellness):
    today = handlers_reads.retrieve_wellness_log(CONFIG, USER, {})["today"]
    assert today == {"day": TODAY, "minutes": 5, "streak_days": 4}


def test_a_missing_wellness_summary_is_not_a_failure(wellness, monkeypatch):
    monkeypatch.setattr(handlers_reads.backend, "wellness_summary", lambda config, user_id: None)
    today = handlers_reads.retrieve_wellness_log(CONFIG, USER, {})["today"]
    assert today == {"day": None, "minutes": None, "streak_days": None}


# ---------------------------------------------------------------------------
# Goals and to-dos
# ---------------------------------------------------------------------------


def test_profile_goals_returns_targets_and_no_identity(monkeypatch):
    monkeypatch.setattr(
        store,
        "profile_targets",
        lambda config, user_id: {
            "start_weight": 225.0,
            "goal_weight": 190.0,
            "height_inches": 70.0,
            "timezone": "America/Chicago",
        },
    )
    monkeypatch.setattr(store, "nutrition_goals", lambda config, user_id: dict(_GOALS))
    monkeypatch.setattr(store, "wellness_minutes_goal", lambda config, user_id: 45)
    monkeypatch.setattr(
        store,
        "health_goals",
        lambda config, user_id: {
            "glp1_support": True,
            "weight_mgmt": True,
            "sleep_recovery": False,
        },
    )
    monkeypatch.setattr(store, "active_plan", lambda config, user_id: {"name": "tirzepatide"})

    result = handlers_reads.retrieve_profile_goals(CONFIG, USER, {})

    assert result["weight"]["goal_weight_lbs"] == 190.0
    assert result["wellness_minutes_goal"] == 45
    assert result["health_goals"]["selected"] == ["GLP-1 support", "weight management"]
    assert result["timezone"] == "America/Chicago"
    # The identity columns are never selected, so they cannot appear here even
    # if a future profiles read grows wider.
    assert set(store._TARGET_COLUMNS.split(",")).isdisjoint(
        {"full_name", "date_of_birth", "clinician_name"}
    )


def test_todos_expose_the_id_the_write_tools_need(monkeypatch):
    monkeypatch.setattr(store, "local_day", lambda config, user_id: (TODAY, "America/New_York"))
    monkeypatch.setattr(
        handlers_reads.backend,
        "list_todos",
        lambda config, user_id: [
            {
                "id": "todo-1",
                "title": "Drink water",
                "category": "water",
                "repeat_rule": "daily",
                "remind_hour": 9,
                "remind_minute": 5,
                "due_date": None,
                "is_done": False,
            }
        ],
    )

    result = handlers_reads.retrieve_todos(CONFIG, USER, {})

    assert result["todos"][0]["todo_id"] == "todo-1"
    assert result["todos"][0]["remind_at"] == "09:05"
    assert (result["open_count"], result["done_count"]) == (1, 0)


# ---------------------------------------------------------------------------
# Registry wiring
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "name",
    [
        "retrieve_nutrition_log",
        "retrieve_wellness_log",
        "retrieve_profile_goals",
        "retrieve_todos",
    ],
)
def test_each_new_read_tool_is_registered_and_addressable(name):
    spec = tools.REGISTRY[name]
    assert spec.writes is False
    assert spec.input_schema["additionalProperties"] is False
    for slug in spec.slugs:
        assert tools.COMMAND_INDEX[slug] is spec
