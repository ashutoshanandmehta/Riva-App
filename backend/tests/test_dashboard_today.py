"""Unit: the dashboard's "today" is the user's local day.

Writes (`log_scan` and the other SQL `log_*` functions) stamp rows with the
profile-timezone day. A read that used the server's own day silently dropped
every log made while the two calendars disagree — the app showed zero calories
right after a scan reported them. Nothing here touches the network or a DB.
"""

from datetime import timedelta

import pytest

from app import backend

# Never on the same date as each other, so whichever one disagrees with the
# server clock at this moment catches a read that uses the server's day.
_AHEAD_TZ = "Pacific/Kiritimati"  # UTC+14
_BEHIND_TZ = "Pacific/Midway"  # UTC-11


def _run_dashboard(monkeypatch, tz: str) -> tuple[dict, dict]:
    """Runs `get_dashboard` against a stubbed REST layer whose only nutrition
    row sits on the profile-timezone day. Returns the dashboard and the query
    params the nutrition read used."""
    local_today = backend.profile_today({"timezone": tz})
    seen: dict = {}

    def fake_get_me(config, user_id):
        return {
            "profile": {"timezone": tz},
            "nutrition_goals": {"wellness_minutes_goal": 45},
            "plan": None,
        }

    def fake_select(config, table, params):
        if table != "nutrition_days":
            return []
        if "day" in params:
            seen["day_filter"] = params["day"]
        return [
            {
                "day": local_today.isoformat(),
                "calories": 640,
                "protein_grams": 31,
                "carb_grams": 52,
                "fiber_grams": 6,
                "water_ounces": 16,
            }
        ]

    monkeypatch.setattr(backend, "get_me", fake_get_me)
    monkeypatch.setattr(backend, "_select", fake_select)
    monkeypatch.setattr(backend, "list_weights", lambda *a, **k: [])
    monkeypatch.setattr(backend, "list_shots", lambda *a, **k: [])
    monkeypatch.setattr(backend, "list_side_effects", lambda *a, **k: [])
    monkeypatch.setattr(backend, "list_sleep_checkins", lambda *a, **k: [])
    monkeypatch.setattr(backend, "wellness_summary", lambda *a, **k: None)

    return backend.get_dashboard(None, "user-1"), seen


@pytest.mark.parametrize("tz", [_AHEAD_TZ, _BEHIND_TZ])
def test_today_is_the_profile_day_not_the_server_day(monkeypatch, tz):
    dashboard, _ = _run_dashboard(monkeypatch, tz)

    assert dashboard["today"] is not None, "today's log vanished from the dashboard"
    assert dashboard["today"]["calories"] == 640
    assert dashboard["today"]["protein_grams"] == 31
    assert dashboard["today"]["day"] == backend.profile_today({"timezone": tz}).isoformat()


@pytest.mark.parametrize("tz", [_AHEAD_TZ, _BEHIND_TZ])
def test_week_window_is_anchored_on_the_profile_day(monkeypatch, tz):
    """The seven-day window starts from the same local day, or the week strip
    loses a column at one end."""
    _, seen = _run_dashboard(monkeypatch, tz)

    week_ago = backend.profile_today({"timezone": tz}) - timedelta(days=7)
    assert seen["day_filter"] == f"gte.{week_ago.isoformat()}"


@pytest.mark.parametrize("tz", [_AHEAD_TZ, _BEHIND_TZ])
def test_streak_and_today_agree_on_the_day(monkeypatch, tz):
    """The streak already used the profile day; `today` uses the same one, so a
    fresh log cannot tick the streak while the calorie ring stays at zero."""
    dashboard, _ = _run_dashboard(monkeypatch, tz)

    assert dashboard["streak_days"] == 1
    assert dashboard["today"]["day"] == backend.profile_today({"timezone": tz}).isoformat()
