"""Integration: migration 0004 todo objects on the sandbox DB. Skips unless
the container is running (docker compose up -d sandbox-db). Everything runs
inside the fixture connection's transaction, which rolls back on close.
"""

import uuid
from datetime import timedelta

import pytest

_COLUMNS = "id, title, category, repeat_rule, remind_hour, remind_minute, due_date, is_done"
# Column positions in the tuples _create / _list return.
_ID, _TITLE, _CATEGORY, _REPEAT, _HOUR, _MINUTE, _DUE, _DONE = range(8)


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


def _upsert(
    cur,
    user_id,
    todo_id=None,
    title="Log breakfast",
    category="food",
    repeat_rule="daily",
    remind_hour=8,
    remind_minute=0,
    due_date=None,
):
    """Create (todo_id None) or edit one to-do; returns the row, or None."""
    cur.execute(
        f"SELECT {_COLUMNS} FROM public.upsert_todo(%s, %s, %s, %s, %s, %s, %s, %s)",
        (
            user_id,
            todo_id,
            title,
            category,
            repeat_rule,
            remind_hour,
            remind_minute,
            due_date,
        ),
    )
    return cur.fetchone()


def _list(cur, user_id):
    cur.execute(f"SELECT {_COLUMNS} FROM public.list_todos(%s)", (user_id,))
    return cur.fetchall()


@pytest.mark.integration
def test_todo_objects_exist(db):
    with db.cursor() as cur:
        cur.execute("select to_regclass('public.todos')")
        assert cur.fetchone()[0]
        cur.execute(
            "select count(*) from pg_proc where proname in"
            " ('list_todos', 'upsert_todo', 'set_todo_done', 'delete_todo')"
        )
        assert cur.fetchone()[0] == 4


@pytest.mark.integration
def test_todos_rls_is_select_only(db):
    """Clients read their own rows; every write goes through an RPC."""
    with db.cursor() as cur:
        cur.execute(
            "select cmd from pg_policies where schemaname = 'public' and tablename = 'todos'"
        )
        assert [row[0] for row in cur.fetchall()] == ["SELECT"]


@pytest.mark.integration
def test_upsert_creates_then_edits_in_place(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        created = _upsert(cur, user_id)
        assert created[_TITLE:] == ("Log breakfast", "food", "daily", 8, 0, None, False)

        edited = _upsert(
            cur,
            user_id,
            todo_id=created[_ID],
            title="  Drink water  ",
            category="water",
            remind_hour=19,
            remind_minute=30,
        )
        assert edited[_ID] == created[_ID]  # same row, not a second one
        assert edited[_TITLE] == "Drink water"  # trimmed
        assert (edited[_CATEGORY], edited[_HOUR], edited[_MINUTE]) == ("water", 19, 30)
        assert len(_list(cur, user_id)) == 1


@pytest.mark.integration
def test_upsert_ignores_another_users_todo(db):
    with db.cursor() as cur:
        owner = _new_user(cur)
        intruder = _new_user(cur)
        todo_id = _upsert(cur, owner)[_ID]

        # No row matched, so nothing comes back; the route turns that into 404.
        assert _upsert(cur, intruder, todo_id=todo_id, title="Hijacked") is None
        assert _list(cur, owner)[0][_TITLE] == "Log breakfast"


@pytest.mark.integration
def test_set_done_uses_profile_timezone_day(db):
    with db.cursor() as cur:
        user_id = _new_user(cur, tz="Pacific/Auckland")
        todo_id = _upsert(cur, user_id)[_ID]

        cur.execute(
            f"SELECT {_COLUMNS} FROM public.set_todo_done(%s, %s, true)", (user_id, todo_id)
        )
        assert cur.fetchone()[_DONE] is True
        cur.execute("SELECT completed_on FROM public.todos WHERE id = %s", (todo_id,))
        assert cur.fetchone()[0] == _local_day(cur, "Pacific/Auckland")

        cur.execute(
            f"SELECT {_COLUMNS} FROM public.set_todo_done(%s, %s, false)", (user_id, todo_id)
        )
        assert cur.fetchone()[_DONE] is False


@pytest.mark.integration
def test_set_done_ignores_another_users_todo(db):
    with db.cursor() as cur:
        owner = _new_user(cur)
        intruder = _new_user(cur)
        todo_id = _upsert(cur, owner)[_ID]

        cur.execute(
            f"SELECT {_COLUMNS} FROM public.set_todo_done(%s, %s, true)", (intruder, todo_id)
        )
        assert cur.fetchall() == []
        assert _list(cur, owner)[0][_DONE] is False


@pytest.mark.integration
def test_daily_todo_reopens_the_next_day(db):
    """A daily to-do ticked yesterday reads back open today — no cron needed."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        todo_id = _upsert(cur, user_id)[_ID]
        yesterday = _local_day(cur, "America/New_York") - timedelta(days=1)
        cur.execute("UPDATE public.todos SET completed_on = %s WHERE id = %s", (yesterday, todo_id))

        rows = _list(cur, user_id)
        assert len(rows) == 1
        assert rows[0][_DONE] is False


@pytest.mark.integration
def test_once_todo_completed_earlier_drops_off_the_list(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        todo_id = _upsert(
            cur, user_id, title="Weigh in", category="weight", repeat_rule="once", due_date=today
        )[_ID]

        # Ticked today: still on the card, shown as done.
        cur.execute("SELECT id FROM public.set_todo_done(%s, %s, true)", (user_id, todo_id))
        rows = _list(cur, user_id)
        assert len(rows) == 1 and rows[0][_DONE] is True

        # Ticked on an earlier day: finished business, off the card.
        cur.execute(
            "UPDATE public.todos SET completed_on = %s WHERE id = %s",
            (today - timedelta(days=1), todo_id),
        )
        assert _list(cur, user_id) == []


@pytest.mark.integration
def test_changing_the_repeat_rule_clears_completion(db):
    """completed_on means "done today" for daily and "done for good" for once.
    Carrying it across a rule change made the to-do vanish off the card."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        todo_id = _upsert(cur, user_id, title="Weigh in", category="weight")[_ID]
        # Ticked yesterday, so it is open again today.
        cur.execute(
            "UPDATE public.todos SET completed_on = %s WHERE id = %s",
            (today - timedelta(days=1), todo_id),
        )

        edited = _upsert(
            cur,
            user_id,
            todo_id=todo_id,
            title="Weigh in",
            category="weight",
            repeat_rule="once",
            due_date=today,
        )
        assert edited[_DONE] is False
        # Still on the card, rather than read as a finished one-off.
        assert [row[_ID] for row in _list(cur, user_id)] == [todo_id]


@pytest.mark.integration
def test_moving_a_once_todo_to_a_new_date_clears_completion(db):
    """The same trap without a rule change: a ticked one-off rescheduled to a
    new day would keep completed_on and drop straight off the card."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        todo_id = _upsert(
            cur,
            user_id,
            title="Order refill",
            category="custom",
            repeat_rule="once",
            due_date=today,
        )[_ID]
        cur.execute("SELECT id FROM public.set_todo_done(%s, %s, true)", (user_id, todo_id))

        edited = _upsert(
            cur,
            user_id,
            todo_id=todo_id,
            title="Order refill",
            category="custom",
            repeat_rule="once",
            due_date=today + timedelta(days=3),
        )
        assert edited[_DONE] is False
        assert [row[_ID] for row in _list(cur, user_id)] == [todo_id]


@pytest.mark.integration
def test_editing_without_a_reschedule_keeps_completion(db):
    """Fixing a typo must not silently un-tick the to-do."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        todo_id = _upsert(cur, user_id)[_ID]
        cur.execute("SELECT id FROM public.set_todo_done(%s, %s, true)", (user_id, todo_id))

        edited = _upsert(cur, user_id, todo_id=todo_id, title="Log first breakfast")
        assert edited[_TITLE] == "Log first breakfast"
        assert edited[_DONE] is True


@pytest.mark.integration
@pytest.mark.parametrize(
    "call",
    [
        "public.list_todos(%s)",
        "public.upsert_todo(%s, NULL, 'x', 'food', 'daily', 8, 0, NULL)",
        "public.set_todo_done(%s, gen_random_uuid(), true)",
        "public.delete_todo(%s, gen_random_uuid())",
    ],
)
def test_client_roles_cannot_execute_the_rpcs(db, call):
    """The REVOKE is the entire barrier between a signed-in client and another
    account's rows, since p_user_id is trusted. Prove it actually holds."""
    psycopg = pytest.importorskip("psycopg")
    with db.cursor() as cur:
        user_id = _new_user(cur)
        cur.execute("SET LOCAL ROLE authenticated")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            cur.execute(f"SELECT * FROM {call}", (user_id,))


@pytest.mark.integration
def test_delete_soft_deletes_and_hides(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        todo_id = _upsert(cur, user_id)[_ID]

        cur.execute("SELECT id FROM public.delete_todo(%s, %s)", (user_id, todo_id))
        assert cur.fetchone()[0] == todo_id
        assert _list(cur, user_id) == []
        cur.execute("SELECT deleted_at FROM public.todos WHERE id = %s", (todo_id,))
        assert cur.fetchone()[0] is not None

        # Deleting twice is a no-op, which the route turns into a 404.
        cur.execute("SELECT id FROM public.delete_todo(%s, %s)", (user_id, todo_id))
        assert cur.fetchall() == []


@pytest.mark.integration
def test_delete_ignores_another_users_todo(db):
    with db.cursor() as cur:
        owner = _new_user(cur)
        intruder = _new_user(cur)
        todo_id = _upsert(cur, owner)[_ID]

        cur.execute("SELECT id FROM public.delete_todo(%s, %s)", (intruder, todo_id))
        assert cur.fetchall() == []
        assert len(_list(cur, owner)) == 1


@pytest.mark.integration
def test_list_orders_by_reminder_time(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        _upsert(cur, user_id, title="Evening", remind_hour=19)
        _upsert(cur, user_id, title="Morning", remind_hour=7, remind_minute=30)
        _upsert(cur, user_id, title="Midday", remind_hour=12)
        assert [row[_TITLE] for row in _list(cur, user_id)] == ["Morning", "Midday", "Evening"]


# Constraint tests each end on their failing statement, since a raised error
# aborts the fixture's transaction for anything that follows.


@pytest.mark.integration
def test_once_todo_requires_a_due_date(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        with pytest.raises(Exception):
            _upsert(cur, user_id, repeat_rule="once", due_date=None)


@pytest.mark.integration
def test_daily_todo_rejects_a_due_date(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        today = _local_day(cur, "America/New_York")
        with pytest.raises(Exception):
            _upsert(cur, user_id, repeat_rule="daily", due_date=today)


@pytest.mark.integration
def test_blank_title_is_rejected(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        with pytest.raises(Exception):
            _upsert(cur, user_id, title="   ")


@pytest.mark.integration
def test_unknown_category_is_rejected(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        with pytest.raises(Exception):
            _upsert(cur, user_id, category="sleep")
