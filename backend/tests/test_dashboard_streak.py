"""Unit: Home's logging-streak rules and the profile-timezone day behind them.
Pure functions plus a monkeypatched REST layer — nothing here touches the
network or a database."""

from datetime import date

from app import backend

_TODAY = date(2026, 7, 27)


def _days(*offsets: int) -> set[str]:
    """Logged-day set built from day offsets before `_TODAY`."""
    return {date.fromordinal(_TODAY.toordinal() - offset).isoformat() for offset in offsets}


def test_counts_consecutive_days_ending_today():
    assert backend.nutrition_streak(_days(0, 1, 2), _TODAY) == 3


def test_unlogged_today_keeps_yesterdays_streak_alive():
    # The wellness rule: a streak survives until the end of the current day, so
    # opening the app before logging must not zero it.
    assert backend.nutrition_streak(_days(1, 2, 3), _TODAY) == 3


def test_gap_ends_the_streak():
    # Logged today and yesterday, then a missing day, then more history.
    assert backend.nutrition_streak(_days(0, 1, 3, 4), _TODAY) == 2


def test_no_history_is_zero():
    assert backend.nutrition_streak(set(), _TODAY) == 0


def test_only_stale_history_is_zero():
    # Nothing today or yesterday: the streak is already broken.
    assert backend.nutrition_streak(_days(2, 3, 4), _TODAY) == 0


def test_single_day_today():
    assert backend.nutrition_streak(_days(0), _TODAY) == 1


def test_profile_today_uses_the_profile_timezone():
    # Kiritimati (UTC+14) and Midway (UTC-11) are never on the same date.
    ahead = backend.profile_today({"timezone": "Pacific/Kiritimati"})
    behind = backend.profile_today({"timezone": "Pacific/Midway"})
    assert ahead != behind
    assert (ahead - behind).days == 1


def test_profile_today_falls_back_on_an_unknown_timezone():
    assert backend.profile_today({"timezone": "Mars/Olympus_Mons"}) == date.today()
    assert backend.profile_today({"timezone": None}) == backend.profile_today(
        {"timezone": "America/New_York"}
    )


def test_logged_days_query_excludes_empty_days(monkeypatch):
    """A day row exists as soon as anything touches it, so the streak query has
    to filter on real activity rather than on the row's existence."""
    seen = {}

    def fake_select(config, table, params):
        seen["table"] = table
        seen["params"] = params
        return [
            {"day": "2026-07-27", "calories": 1400, "water_ounces": 0},
            {"day": "2026-07-26", "calories": 0, "water_ounces": 32},
            # Touched but empty — a row exists, the day was not logged.
            {"day": "2026-07-25", "calories": 0, "water_ounces": 0},
        ]

    monkeypatch.setattr(backend, "_select", fake_select)
    days = backend._logged_nutrition_days(None, "user-1")

    assert days == {"2026-07-27", "2026-07-26"}
    assert seen["table"] == "nutrition_days"
    assert seen["params"]["deleted_at"] == "is.null"
    assert seen["params"]["user_id"] == "eq.user-1"
