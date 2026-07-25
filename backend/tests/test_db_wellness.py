"""Integration: migration 0003 wellness objects on the sandbox DB. Skips
unless the container is running (docker compose up -d sandbox-db). Everything
runs inside the fixture connection's transaction, which rolls back on close.
"""

import uuid
from datetime import timedelta

import pytest


def _new_user(cur, tz="America/New_York"):
    """Provision a user + profile + goals directly. The signup trigger is
    skipped (replica mode) because the sandbox auth.users stub lacks the
    raw_user_meta_data column the trigger reads."""
    user_id = str(uuid.uuid4())
    cur.execute("SET LOCAL session_replication_role = replica")
    cur.execute("INSERT INTO auth.users (id) VALUES (%s)", (user_id,))
    cur.execute("SET LOCAL session_replication_role = DEFAULT")
    cur.execute(
        "INSERT INTO public.profiles (id, name, timezone) VALUES (%s, 'Test', %s)",
        (user_id, tz),
    )
    cur.execute("INSERT INTO public.nutrition_goals (user_id) VALUES (%s)", (user_id,))
    return user_id


def _local_day(cur, tz):
    cur.execute("SELECT (now() AT TIME ZONE %s)::date", (tz,))
    return cur.fetchone()[0]


def _add_session(cur, user_id, day, practice_id="yoga_beginners", kind="yoga", minutes=20):
    cur.execute(
        "INSERT INTO public.wellness_sessions (user_id, day, practice_id, kind, minutes)"
        " VALUES (%s, %s, %s, %s, %s)",
        (user_id, day, practice_id, kind, minutes),
    )


@pytest.mark.integration
def test_wellness_objects_exist(db):
    with db.cursor() as cur:
        cur.execute(
            "select to_regclass('public.wellness_sessions'),"
            "       to_regclass('public.wellness_suggestions')"
        )
        sessions, cache = cur.fetchone()
        assert sessions and cache
        cur.execute(
            "select count(*) from pg_proc where proname in"
            " ('wellness_streak', 'log_wellness_session', 'wellness_summary')"
        )
        assert cur.fetchone()[0] == 3
        cur.execute(
            "select count(*) from information_schema.columns"
            " where table_name = 'nutrition_goals' and column_name = 'wellness_minutes_goal'"
        )
        assert cur.fetchone()[0] == 1


@pytest.mark.integration
def test_streak_counts_consecutive_days(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        anchor = _local_day(cur, "America/New_York")
        for offset in range(3):
            _add_session(cur, user_id, anchor - timedelta(days=offset))
        cur.execute("SELECT public.wellness_streak(%s, %s)", (user_id, anchor))
        assert cur.fetchone()[0] == 3


@pytest.mark.integration
def test_streak_resets_at_gap(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        anchor = _local_day(cur, "America/New_York")
        _add_session(cur, user_id, anchor)
        _add_session(cur, user_id, anchor - timedelta(days=2))  # gap at anchor-1
        _add_session(cur, user_id, anchor - timedelta(days=3))
        cur.execute("SELECT public.wellness_streak(%s, %s)", (user_id, anchor))
        assert cur.fetchone()[0] == 1


@pytest.mark.integration
def test_streak_zero_without_sessions(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        anchor = _local_day(cur, "America/New_York")
        cur.execute("SELECT public.wellness_streak(%s, %s)", (user_id, anchor))
        assert cur.fetchone()[0] == 0


@pytest.mark.integration
def test_summary_anchors_at_yesterday_when_today_unpracticed(db):
    """An unbroken streak survives until end of day even before today's
    session is logged."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        _add_session(cur, user_id, today - timedelta(days=1))
        _add_session(cur, user_id, today - timedelta(days=2))
        cur.execute(
            "SELECT day, minutes_today, streak_days FROM public.wellness_summary(%s)", (user_id,)
        )
        day, minutes_today, streak_days = cur.fetchone()
        assert day == today
        assert minutes_today == 0
        assert streak_days == 2


@pytest.mark.integration
def test_same_day_sessions_dedupe_for_streak_but_sum_minutes(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        _add_session(cur, user_id, today - timedelta(days=1), minutes=10)
        _add_session(
            cur, user_id, today, practice_id="meditation_nsdr", kind="meditation", minutes=10
        )
        _add_session(cur, user_id, today, minutes=20)
        cur.execute("SELECT public.wellness_streak(%s, %s)", (user_id, today))
        assert cur.fetchone()[0] == 2  # today counts once
        cur.execute("SELECT minutes_today FROM public.wellness_summary(%s)", (user_id,))
        assert cur.fetchone()[0] == 30  # but minutes sum


@pytest.mark.integration
def test_log_wellness_session_return_shape(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        cur.execute(
            "SELECT day, minutes_today, streak_days"
            " FROM public.log_wellness_session(%s, 'yoga_beginners', 'yoga', 20)",
            (user_id,),
        )
        day, minutes_today, streak_days = cur.fetchone()
        assert day == today
        assert minutes_today == 20
        assert streak_days == 1
        cur.execute(
            "SELECT minutes_today FROM public.log_wellness_session(%s, 'mind_gratitude', 'mind', 7)",
            (user_id,),
        )
        assert cur.fetchone()[0] == 27


@pytest.mark.integration
def test_log_uses_profile_timezone_day(db):
    """The logged day is the user's local date, not the server's."""
    with db.cursor() as cur:
        user_id = _new_user(cur, tz="Pacific/Auckland")
        cur.execute(
            "SELECT day FROM public.log_wellness_session(%s, 'sleep_winddown', 'sleep', 12)",
            (user_id,),
        )
        assert cur.fetchone()[0] == _local_day(cur, "Pacific/Auckland")


@pytest.mark.integration
def test_suggestion_cache_unique_per_user_day(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        cur.execute(
            "INSERT INTO public.wellness_suggestions (user_id, day, payload)"
            " VALUES (%s, %s, '{\"suggestions\": []}'::jsonb)",
            (user_id, today),
        )
        with pytest.raises(Exception):
            cur.execute(
                "INSERT INTO public.wellness_suggestions (user_id, day, payload)"
                " VALUES (%s, %s, '{\"suggestions\": []}'::jsonb)",
                (user_id, today),
            )
