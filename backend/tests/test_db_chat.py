"""Integration: migration 0005 chat objects on the sandbox DB. Skips unless the
container is running (docker compose up -d sandbox-db). Everything runs inside
the fixture connection's transaction, which rolls back on close.

The point of most of these is isolation: chat transcripts are health-related free
text, so "another user's thread is unreachable" is the property under test.
"""

import json
import uuid

import pytest

from app.chat import symptoms

_MESSAGE_COLUMNS = "id, role, content, tool_calls, model, prompt_version, created_at"
_ROLE, _CONTENT, _TOOL_CALLS = 1, 2, 3


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


def _start_thread(cur, user_id, title=None):
    cur.execute("SELECT id, title FROM public.start_chat_thread(%s, %s)", (user_id, title))
    return cur.fetchone()


def _log(cur, user_id, thread_id, role="user", content="hi", tool_calls=None, model=None):
    cur.execute(
        f"SELECT {_MESSAGE_COLUMNS} FROM public.log_chat_message(%s, %s, %s, %s, %s, %s, NULL)",
        (
            user_id,
            thread_id,
            role,
            content,
            json.dumps(tool_calls if tool_calls is not None else []),
            model,
        ),
    )
    return cur.fetchone()


def _messages(cur, user_id, thread_id, limit=50):
    cur.execute(
        f"SELECT {_MESSAGE_COLUMNS} FROM public.list_chat_messages(%s, %s, %s)",
        (user_id, thread_id, limit),
    )
    return cur.fetchall()


@pytest.mark.integration
def test_chat_objects_exist(db):
    with db.cursor() as cur:
        cur.execute("select to_regclass('public.chat_threads')")
        assert cur.fetchone()[0]
        cur.execute("select to_regclass('public.chat_messages')")
        assert cur.fetchone()[0]
        cur.execute(
            "select count(*) from pg_proc where proname in"
            " ('start_chat_thread', 'log_chat_message', 'list_chat_messages',"
            " 'list_chat_threads', 'delete_chat_thread')"
        )
        assert cur.fetchone()[0] == 5


@pytest.mark.integration
@pytest.mark.parametrize("table", ["chat_threads", "chat_messages"])
def test_chat_rls_is_select_only(db, table):
    """Clients read their own rows; every write goes through an RPC."""
    with db.cursor() as cur:
        cur.execute(
            "select cmd from pg_policies where schemaname = 'public' and tablename = %s",
            (table,),
        )
        assert [row[0] for row in cur.fetchall()] == ["SELECT"]


@pytest.mark.integration
@pytest.mark.parametrize(
    "call",
    [
        "public.start_chat_thread(%s, NULL)",
        "public.log_chat_message(%s, gen_random_uuid(), 'user', 'hi', '[]'::jsonb, NULL, NULL)",
        "public.list_chat_messages(%s, gen_random_uuid(), 50)",
        "public.list_chat_threads(%s, 50)",
        "public.delete_chat_thread(%s, gen_random_uuid())",
    ],
)
def test_client_roles_cannot_execute_the_rpcs(db, call):
    """The REVOKE is the entire barrier between a signed-in client and another
    account's transcripts, since p_user_id is trusted. Prove it holds."""
    psycopg = pytest.importorskip("psycopg")
    with db.cursor() as cur:
        user_id = _new_user(cur)
        cur.execute("SET LOCAL ROLE authenticated")
        with pytest.raises(psycopg.errors.InsufficientPrivilege):
            cur.execute(f"SELECT * FROM {call}", (user_id,))


@pytest.mark.integration
def test_thread_and_messages_round_trip(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]

        _log(cur, user_id, thread_id, "user", "how is my weight trending?")
        _log(
            cur,
            user_id,
            thread_id,
            "assistant",
            "Down 12 lbs since July 1.",
            tool_calls=[{"tool": "retrieve_weight_log", "arguments": {}, "data": {}}],
            model="claude-sonnet-5",
        )

        rows = _messages(cur, user_id, thread_id)
        assert [row[_ROLE] for row in rows] == ["user", "assistant"]  # oldest first
        assert rows[1][_TOOL_CALLS][0]["tool"] == "retrieve_weight_log"


@pytest.mark.integration
def test_first_user_turn_names_the_thread(db):
    """Saves a round trip: the client never has to send a title."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id, title = _start_thread(cur, user_id)
        assert title is None

        _log(cur, user_id, thread_id, "user", "how is my weight trending?")
        cur.execute("SELECT title FROM public.chat_threads WHERE id = %s", (thread_id,))
        assert cur.fetchone()[0] == "how is my weight trending?"

        # A later turn must not rename it.
        _log(cur, user_id, thread_id, "user", "and last month?")
        cur.execute("SELECT title FROM public.chat_threads WHERE id = %s", (thread_id,))
        assert cur.fetchone()[0] == "how is my weight trending?"


@pytest.mark.integration
def test_an_explicit_title_is_kept(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id, title = _start_thread(cur, user_id, title="  Weight check  ")
        assert title == "Weight check"  # trimmed
        _log(cur, user_id, thread_id, "user", "how is my weight trending?")
        cur.execute("SELECT title FROM public.chat_threads WHERE id = %s", (thread_id,))
        assert cur.fetchone()[0] == "Weight check"


@pytest.mark.integration
def test_a_long_first_turn_is_truncated_to_fit_the_title_constraint(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        _log(cur, user_id, thread_id, "user", "w" * 400)
        cur.execute("SELECT title FROM public.chat_threads WHERE id = %s", (thread_id,))
        assert len(cur.fetchone()[0]) == 120


@pytest.mark.integration
def test_cannot_append_to_another_users_thread(db):
    """The isolation guarantee: a forged thread id writes nothing at all."""
    with db.cursor() as cur:
        owner = _new_user(cur)
        intruder = _new_user(cur)
        thread_id = _start_thread(cur, owner)[0]
        _log(cur, owner, thread_id, "user", "private question")

        assert _log(cur, intruder, thread_id, "user", "hijacked") is None
        assert [row[_CONTENT] for row in _messages(cur, owner, thread_id)] == ["private question"]


@pytest.mark.integration
def test_cannot_read_another_users_thread(db):
    with db.cursor() as cur:
        owner = _new_user(cur)
        intruder = _new_user(cur)
        thread_id = _start_thread(cur, owner)[0]
        _log(cur, owner, thread_id, "user", "private question")

        assert _messages(cur, intruder, thread_id) == []


@pytest.mark.integration
def test_appending_to_an_unknown_thread_writes_nothing(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        assert _log(cur, user_id, str(uuid.uuid4()), "user", "hi") is None


@pytest.mark.integration
def test_list_messages_keeps_the_newest_turns_but_orders_them_forward(db):
    """A long thread has to drop its oldest turns, not its most recent ones."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        for index in range(6):
            _log(cur, user_id, thread_id, "user", f"turn {index}")

        rows = _messages(cur, user_id, thread_id, limit=3)
        assert [row[_CONTENT] for row in rows] == ["turn 3", "turn 4", "turn 5"]


@pytest.mark.integration
def test_threads_list_most_recently_active_first_with_counts(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        first = _start_thread(cur, user_id, title="Older")[0]
        second = _start_thread(cur, user_id, title="Newer")[0]
        _log(cur, user_id, first, "user", "a")
        _log(cur, user_id, second, "user", "b")
        # Touching the older thread again must float it back to the top.
        _log(cur, user_id, first, "assistant", "c")

        cur.execute(
            "SELECT id, title, message_count FROM public.list_chat_threads(%s, 50)", (user_id,)
        )
        rows = cur.fetchall()
        assert [row[0] for row in rows] == [first, second]
        assert [row[2] for row in rows] == [2, 1]


@pytest.mark.integration
def test_threads_list_excludes_other_users(db):
    with db.cursor() as cur:
        owner = _new_user(cur)
        intruder = _new_user(cur)
        _start_thread(cur, owner, title="Mine")
        cur.execute("SELECT id FROM public.list_chat_threads(%s, 50)", (intruder,))
        assert cur.fetchall() == []


@pytest.mark.integration
def test_delete_soft_deletes_the_thread_and_its_messages(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        _log(cur, user_id, thread_id, "user", "private question")

        cur.execute("SELECT id FROM public.delete_chat_thread(%s, %s)", (user_id, thread_id))
        assert cur.fetchone()[0] == thread_id
        assert _messages(cur, user_id, thread_id) == []
        cur.execute("SELECT deleted_at FROM public.chat_threads WHERE id = %s", (thread_id,))
        assert cur.fetchone()[0] is not None
        cur.execute(
            "SELECT count(*) FROM public.chat_messages WHERE thread_id = %s AND deleted_at IS NULL",
            (thread_id,),
        )
        assert cur.fetchone()[0] == 0

        # Deleting twice is a no-op, which the route turns into a 404.
        cur.execute("SELECT id FROM public.delete_chat_thread(%s, %s)", (user_id, thread_id))
        assert cur.fetchall() == []


@pytest.mark.integration
def test_delete_ignores_another_users_thread(db):
    with db.cursor() as cur:
        owner = _new_user(cur)
        intruder = _new_user(cur)
        thread_id = _start_thread(cur, owner)[0]

        cur.execute("SELECT id FROM public.delete_chat_thread(%s, %s)", (intruder, thread_id))
        assert cur.fetchall() == []
        cur.execute("SELECT deleted_at FROM public.chat_threads WHERE id = %s", (thread_id,))
        assert cur.fetchone()[0] is None


@pytest.mark.integration
def test_cannot_append_to_a_deleted_thread(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        cur.execute("SELECT id FROM public.delete_chat_thread(%s, %s)", (user_id, thread_id))
        assert _log(cur, user_id, thread_id, "user", "after delete") is None


@pytest.mark.integration
def test_deleting_the_account_removes_the_transcripts(db):
    """HIPAA deletion: transcripts must not outlive the account."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        _log(cur, user_id, thread_id, "user", "private question")

        cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
        cur.execute("SELECT count(*) FROM public.chat_threads WHERE id = %s", (thread_id,))
        assert cur.fetchone()[0] == 0
        cur.execute("SELECT count(*) FROM public.chat_messages WHERE thread_id = %s", (thread_id,))
        assert cur.fetchone()[0] == 0


# Constraint tests each end on their failing statement, since a raised error
# aborts the fixture's transaction for anything that follows.


@pytest.mark.integration
def test_unknown_role_is_rejected(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        with pytest.raises(Exception):
            _log(cur, user_id, thread_id, role="system")


@pytest.mark.integration
def test_a_user_turn_cannot_carry_tool_output(db):
    """Guards against a role mix-up replaying tool results back as if the user
    had said them."""
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        with pytest.raises(Exception):
            _log(cur, user_id, thread_id, role="user", tool_calls=[{"tool": "x"}])


@pytest.mark.integration
def test_a_user_turn_cannot_carry_a_model_name(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        with pytest.raises(Exception):
            _log(cur, user_id, thread_id, role="user", model="claude-sonnet-5")


# ---------------------------------------------------------------------------
# Scale-conversion coverage, checked against the REAL seeded check-in config
# rather than a fixture. The unit tests in test_chat_symptoms.py hard-code the
# seeded values; these prove the seed still matches them, so re-seeding a
# question or option cannot silently produce an unconverted or misdirected value.
# ---------------------------------------------------------------------------


@pytest.mark.integration
def test_every_seeded_symptom_option_has_a_defined_conversion(db):
    with db.cursor() as cur:
        cur.execute(
            "SELECT o.question_id, o.code, o.value"
            "  FROM public.checkin_options o"
            "  JOIN public.checkin_questions q ON q.id = o.question_id"
            " WHERE q.category = %s",
            (symptoms.SYMPTOM_CATEGORY,),
        )
        rows = cur.fetchall()
        assert rows, "no symptom-category options are seeded"
        for question_id, code, value in rows:
            assert symptoms.to_severity(value) is not None, (
                f"{question_id}.{code} (value {value}) has no severity conversion"
            )


@pytest.mark.integration
def test_every_seeded_symptom_question_is_classified(db):
    """A new symptom question must be explicitly declared a burden measure or not.
    Falling through unclassified would put it on the wrong scale silently."""
    with db.cursor() as cur:
        cur.execute(
            "SELECT id FROM public.checkin_questions WHERE category = %s",
            (symptoms.SYMPTOM_CATEGORY,),
        )
        seeded = {row[0] for row in cur.fetchall()}
    classified = symptoms.BURDEN_QUESTIONS | symptoms.APPETITE_QUESTIONS
    assert seeded <= classified, f"unclassified symptom question(s): {seeded - classified}"


@pytest.mark.integration
def test_seeded_nausea_scale_actually_inverts(db):
    """The specific failure this whole module exists to prevent: "none" is the
    best nausea day and must convert to the LOWEST severity."""
    with db.cursor() as cur:
        cur.execute("SELECT code, value FROM public.checkin_options WHERE question_id = 'nausea'")
        by_code = {code: value for code, value in cur.fetchall()}

    assert symptoms.to_severity(by_code["none"]) == 1
    assert symptoms.to_severity(by_code["mild"]) == 2
    assert symptoms.to_severity(by_code["severe"]) == 5


@pytest.mark.integration
def test_seeded_wellbeing_questions_are_not_treated_as_symptoms(db):
    with db.cursor() as cur:
        cur.execute(
            "SELECT id FROM public.checkin_questions WHERE category = %s",
            (symptoms.WELLBEING_CATEGORY,),
        )
        seeded = {row[0] for row in cur.fetchall()}
    assert seeded and not seeded & (symptoms.BURDEN_QUESTIONS | symptoms.APPETITE_QUESTIONS)


@pytest.mark.integration
def test_tool_calls_must_be_an_array(db):
    with db.cursor() as cur:
        user_id = _new_user(cur)
        thread_id = _start_thread(cur, user_id)[0]
        with pytest.raises(Exception):
            cur.execute(
                "SELECT id FROM public.log_chat_message("
                "%s, %s, 'assistant', 'x', '{\"tool\": \"x\"}'::jsonb, NULL, NULL)",
                (user_id, thread_id),
            )
