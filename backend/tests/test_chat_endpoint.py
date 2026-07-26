"""Offline tests for `POST /v1/chat` — no Supabase, no Anthropic, no DB.

`app.main._require_user` is monkeypatched to a fixed verified user, and
`app.chat.store` is replaced with an in-memory double, so this exercises the
route's own orchestration (parse -> open thread -> log the turn -> dispatch ->
log the answer) without needing the production Supabase credentials, which are
deliberately absent from this environment.
"""

import pytest
from fastapi.testclient import TestClient

import app.main as main
from app.chat import confirm, handlers, handlers_writes, routes, store

USER = "11111111-1111-1111-1111-111111111111"
THREAD = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

WEIGHT_ROWS = [
    {"id": "b", "pounds": 208.4, "dose_mg": 1.0, "measured_at": "2026-07-24T07:00:00Z"},
    {"id": "a", "pounds": 220.6, "dose_mg": 0.5, "measured_at": "2026-07-01T07:00:00Z"},
]


class FakeStore:
    """Records what the route persisted, in order."""

    def __init__(self):
        self.logged: list[dict] = []
        self.opened: list[str | None] = []
        self.listed: list[dict] = []
        # What list_messages should return; tests set this to fake prior turns.
        self.history: list[dict] = []
        self.threads: list[dict] = []
        self.deleted: list[str] = []

    def ensure_thread(self, config, user_id, thread_id):
        self.opened.append(thread_id)
        return thread_id or THREAD

    def log_message(
        self,
        config,
        user_id,
        thread_id,
        role,
        content,
        tool_calls=None,
        model=None,
        prompt_version=None,
    ):
        entry = {
            "user_id": user_id,
            "thread_id": thread_id,
            "role": role,
            "content": content,
            "tool_calls": tool_calls or [],
            "model": model,
            "prompt_version": prompt_version,
        }
        self.logged.append(entry)
        return entry

    def list_messages(self, config, user_id, thread_id, limit):
        self.listed.append({"thread_id": thread_id, "limit": limit})
        return list(self.history)

    def list_threads(self, config, user_id, limit):
        return list(self.threads)

    def delete_thread(self, config, user_id, thread_id):
        self.deleted.append(thread_id)


@pytest.fixture
def fake_store(monkeypatch):
    double = FakeStore()
    for name in ("ensure_thread", "log_message", "list_messages", "list_threads", "delete_thread"):
        monkeypatch.setattr(routes.store, name, getattr(double, name))
    monkeypatch.setattr(store, "profile_targets", lambda config, user_id: {"goal_weight": 190.0})
    monkeypatch.setattr(handlers.store, "profile_targets", lambda config, user_id: {})
    monkeypatch.setattr(handlers.backend, "list_weights", lambda *a, **k: list(WEIGHT_ROWS))
    return double


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(main, "_require_user", lambda authorization: USER)
    return TestClient(main.app)


def _post(client, **body):
    return client.post("/v1/chat", json=body, headers={"Authorization": "Bearer test"})


# ---------------------------------------------------------------------------
# Command path
# ---------------------------------------------------------------------------


def test_command_returns_structured_data_and_no_prose(client, fake_store):
    response = _post(client, query="/retrieve_weight_log start_date=2026-07-01")
    assert response.status_code == 200
    body = response.json()

    assert body["kind"] == "command"
    assert body["message"] is None
    # No LLM ran, so these stay unset — a zero-cost reply is distinguishable.
    assert body["model"] is None and body["prompt_version"] is None
    assert body["thread_id"] == THREAD
    assert len(body["tool_calls"]) == 1

    call = body["tool_calls"][0]
    assert call["tool"] == "retrieve_weight_log"
    assert call["arguments"] == {"start_date": "2026-07-01"}
    assert [entry["pounds"] for entry in call["data"]["entries"]] == [220.6, 208.4]
    assert call["data"]["summary"]["change_lbs"] == -12.2


def test_both_turns_are_persisted_in_order(client, fake_store):
    _post(client, query="/retrieve_weight_log")
    assert [entry["role"] for entry in fake_store.logged] == ["user", "assistant"]

    user_turn, assistant_turn = fake_store.logged
    assert user_turn["content"] == "/retrieve_weight_log"
    assert user_turn["tool_calls"] == []
    # The command path has no prose; the structured result is the whole answer.
    assert assistant_turn["content"] == ""
    assert assistant_turn["tool_calls"][0]["tool"] == "retrieve_weight_log"
    # Both turns are stamped with the verified user, never anything client-sent.
    assert {entry["user_id"] for entry in fake_store.logged} == {USER}


def test_an_existing_thread_id_is_reused(client, fake_store):
    body = _post(client, query="/retrieve_weight_log", thread_id=THREAD).json()
    assert body["thread_id"] == THREAD
    assert fake_store.opened == [THREAD]


def test_a_user_id_in_the_body_is_ignored(client, fake_store):
    """The subject is the bearer token's user. A body user_id is not a field on
    the request model, so it cannot redirect the read."""
    response = _post(
        client,
        query="/retrieve_weight_log",
        user_id="22222222-2222-2222-2222-222222222222",
    )
    assert response.status_code == 200
    assert {entry["user_id"] for entry in fake_store.logged} == {USER}


# ---------------------------------------------------------------------------
# Rejections
# ---------------------------------------------------------------------------


def test_unknown_command_400s_without_persisting_anything(client, fake_store):
    """Parsing happens before any write, so a typo leaves no thread and no
    dangling user turn behind."""
    response = _post(client, query="/retrieve_bloodwork")
    assert response.status_code == 400
    assert "/retrieve_weight_log" in response.json()["detail"]
    assert fake_store.logged == []
    assert fake_store.opened == []


def test_bad_argument_400s_without_persisting_anything(client, fake_store):
    response = _post(client, query="/retrieve_weight_log start_date=last-month")
    assert response.status_code == 400
    assert fake_store.logged == []


@pytest.mark.parametrize("query", ["", "   ", "\n"])
def test_empty_query_is_rejected(client, fake_store, query):
    response = _post(client, query=query)
    assert response.status_code == 400
    assert fake_store.logged == []


def test_oversized_query_is_rejected(client, fake_store):
    response = _post(client, query="w" * 5000)
    assert response.status_code == 400
    assert fake_store.logged == []


# ---------------------------------------------------------------------------
# Conversational path
# ---------------------------------------------------------------------------


@pytest.fixture
def fake_agent(monkeypatch):
    """Stands in for the tool-calling loop (covered in test_chat_agent.py)."""
    seen: dict = {}

    def run(config, user_id, history, query, approved=None):
        seen.update(
            user_id=user_id, history=list(history), query=query, approved=set(approved or set())
        )
        return routes.agent.AgentResult(
            message="You're down 12.2 lbs since July 1.",
            tool_calls=[
                {
                    "tool": "retrieve_weight_log",
                    "arguments": {"start_date": "2026-07-01"},
                    "data": {"summary": {"change_lbs": -12.2}},
                }
            ],
            model="claude-sonnet-5",
            prompt_version="v1",
            iterations=2,
        )

    monkeypatch.setattr(routes.agent, "run", run)
    return seen


def test_free_text_returns_a_grounded_answer(client, fake_store, fake_agent):
    body = _post(client, query="how is my weight trending this month?").json()

    assert body["kind"] == "conversation"
    assert body["message"] == "You're down 12.2 lbs since July 1."
    # An LLM ran, so these are set — the marker that distinguishes a paid reply.
    assert body["model"] == "claude-sonnet-5"
    assert body["prompt_version"] == "v1"
    # The structured data the answer was grounded in rides along, so the app can
    # render the same card it shows for the equivalent command.
    assert body["tool_calls"][0]["tool"] == "retrieve_weight_log"
    assert body["tool_calls"][0]["data"]["summary"]["change_lbs"] == -12.2


def test_the_answer_is_persisted_with_its_model_and_tool_calls(client, fake_store, fake_agent):
    _post(client, query="how is my weight trending?")

    assert [entry["role"] for entry in fake_store.logged] == ["user", "assistant"]
    answer = fake_store.logged[1]
    assert answer["content"] == "You're down 12.2 lbs since July 1."
    assert answer["model"] == "claude-sonnet-5"
    assert answer["prompt_version"] == "v1"
    assert answer["tool_calls"][0]["tool"] == "retrieve_weight_log"


def test_prior_turns_are_replayed_but_the_current_question_is_not_duplicated(
    client, fake_store, fake_agent
):
    """The route logs the user turn before running the loop, so it has to drop
    that row from the history it replays — otherwise the question arrives twice."""
    fake_store.history = [
        {"id": "1", "role": "user", "content": "how is my weight trending?"},
        {"id": "2", "role": "assistant", "content": "Down 12 lbs."},
        {"id": "3", "role": "user", "content": "and last month?"},
    ]
    _post(client, query="and last month?", thread_id=THREAD)

    assert [row["content"] for row in fake_agent["history"]] == [
        "how is my weight trending?",
        "Down 12 lbs.",
    ]
    assert fake_agent["query"] == "and last month?"


def test_history_is_read_from_the_same_thread(client, fake_store, fake_agent):
    _post(client, query="follow-up", thread_id=THREAD)
    assert fake_store.listed[0]["thread_id"] == THREAD


def test_the_verified_user_reaches_the_loop(client, fake_store, fake_agent):
    _post(client, query="whose data?", user_id="22222222-2222-2222-2222-222222222222")
    assert fake_agent["user_id"] == USER


def test_a_model_outage_records_the_question_and_the_failure(client, fake_store, monkeypatch):
    """The question stays, and so does what the user was actually told.

    An earlier version stored the user turn alone, on the reasoning that no
    assistant turn should be invented. But the 502 detail *is* the sentence the
    client puts on screen, so storing it records what happened rather than
    fabricating it — and it stops the unanswered question from being replayed
    into the next prompt as though the companion had ignored it.
    """
    from fastapi import HTTPException

    def unavailable(config, user_id, history, query, approved=None):
        raise HTTPException(status_code=502, detail=routes.agent.UNAVAILABLE)

    monkeypatch.setattr(routes.agent, "run", unavailable)
    response = _post(client, query="how is my weight trending?")
    assert response.status_code == 502
    assert [entry["role"] for entry in fake_store.logged] == ["user", "assistant"]
    assert fake_store.logged[-1]["content"] == routes.agent.UNAVAILABLE


# ---------------------------------------------------------------------------
# Assent plumbing: the `confirm` field is the only route to a write
# ---------------------------------------------------------------------------


def _weight_preview_turn(pounds: float) -> dict:
    """A stored earlier turn in which this write was previewed to the user."""
    spec = routes.tools.REGISTRY["record_weight"]
    arguments = {"pounds": pounds}
    return {
        "role": "assistant",
        "content": "",
        "tool_calls": [
            {
                "tool": spec.name,
                "arguments": arguments,
                "data": confirm.preview(spec, arguments),
            }
        ],
    }


def test_a_write_command_without_an_assent_token_only_previews(client, fake_store, monkeypatch):
    """Even with the model's confirm flag set, no token means no write."""
    saved: list = []
    monkeypatch.setattr(
        handlers_writes.backend, "log_weight", lambda *a, **k: saved.append(a) or {}
    )
    fake_store.history = [_weight_preview_turn(201.4)]

    response = _post(client, query="/record_weight pounds=201.4 confirm=true")

    assert response.status_code == 200
    assert response.json()["tool_calls"][0]["data"]["status"] == confirm.NEEDS_CONFIRMATION
    assert saved == []


def test_a_write_command_with_the_assent_token_goes_through(client, fake_store, monkeypatch):
    saved: list = []
    monkeypatch.setattr(
        handlers_writes.backend,
        "log_weight",
        lambda config, user_id, pounds, measured_at: (
            saved.append(pounds),
            {"pounds": pounds, "measured_at": "2026-07-26"},
        )[1],
    )
    fake_store.history = [_weight_preview_turn(201.4)]
    token = confirm.fingerprint("record_weight", {"pounds": 201.4})

    response = _post(client, query="/record_weight pounds=201.4 confirm=true", confirm=token)

    assert response.status_code == 200
    assert response.json()["tool_calls"][0]["data"]["status"] == "saved"
    assert saved == [201.4]


def test_the_assent_token_reaches_the_conversational_loop(client, fake_store, fake_agent):
    """The model path resolves the same token the command path does."""
    fake_store.history = [_weight_preview_turn(201.4)]
    token = confirm.fingerprint("record_weight", {"pounds": 201.4})

    _post(client, query="yes please", confirm=token)

    assert fake_agent["approved"] == {token}


def test_no_token_means_the_loop_can_approve_nothing(client, fake_store, fake_agent):
    fake_store.history = [_weight_preview_turn(201.4)]

    _post(client, query="yes please")

    assert fake_agent["approved"] == set()


# ---------------------------------------------------------------------------
# Thread history
# ---------------------------------------------------------------------------


def _auth(client, method, path):
    return getattr(client, method)(path, headers={"Authorization": "Bearer test"})


def test_threads_are_listed(client, fake_store):
    fake_store.threads = [
        {
            "id": THREAD,
            "title": "how is my weight trending?",
            "message_count": 4,
            "created_at": "2026-07-26T10:00:00Z",
            "updated_at": "2026-07-26T10:05:00Z",
        }
    ]
    body = _auth(client, "get", "/v1/chat/threads").json()
    assert body["threads"][0]["title"] == "how is my weight trending?"
    assert body["threads"][0]["message_count"] == 4


def test_an_untitled_thread_lists_without_a_title(client, fake_store):
    fake_store.threads = [{"id": THREAD, "title": None, "message_count": 0}]
    assert _auth(client, "get", "/v1/chat/threads").json()["threads"][0]["title"] is None


def test_a_thread_transcript_is_returned_oldest_first(client, fake_store):
    fake_store.history = [
        {"id": "1", "role": "user", "content": "how is my weight trending?", "tool_calls": []},
        {
            "id": "2",
            "role": "assistant",
            "content": "Down 12.2 lbs.",
            "tool_calls": [{"tool": "retrieve_weight_log", "arguments": {}, "data": {}}],
            "model": "claude-sonnet-5",
            "prompt_version": "v1",
        },
    ]
    body = _auth(client, "get", f"/v1/chat/threads/{THREAD}").json()
    assert body["thread_id"] == THREAD
    assert [m["role"] for m in body["messages"]] == ["user", "assistant"]
    assert body["messages"][1]["tool_calls"][0]["tool"] == "retrieve_weight_log"
    assert body["messages"][1]["model"] == "claude-sonnet-5"


def test_an_unreadable_thread_is_404_not_an_empty_transcript(client, fake_store):
    """The SQL filters on ownership, so "no rows" and "not yours" are the same
    answer — never confirm that someone else's thread exists."""
    fake_store.history = []
    response = _auth(client, "get", f"/v1/chat/threads/{THREAD}")
    assert response.status_code == 404


def test_a_non_uuid_thread_id_is_404_not_500(client, fake_store):
    assert _auth(client, "get", "/v1/chat/threads/not-a-uuid").status_code == 404
    assert _auth(client, "delete", "/v1/chat/threads/not-a-uuid").status_code == 404


def test_a_thread_can_be_deleted(client, fake_store):
    response = _auth(client, "delete", f"/v1/chat/threads/{THREAD}")
    assert response.status_code == 204
    assert fake_store.deleted == [THREAD]


def test_thread_routes_require_authentication(monkeypatch, fake_store):
    from fastapi import HTTPException

    def deny(authorization):
        raise HTTPException(status_code=401, detail="Sign in to continue.")

    monkeypatch.setattr(main, "_require_user", deny)
    unauthenticated = TestClient(main.app)
    assert unauthenticated.get("/v1/chat/threads").status_code == 401
    assert unauthenticated.get(f"/v1/chat/threads/{THREAD}").status_code == 401
    assert unauthenticated.delete(f"/v1/chat/threads/{THREAD}").status_code == 401


# ---------------------------------------------------------------------------
# The other two commands, end to end through the route
# ---------------------------------------------------------------------------


@pytest.fixture
def medical(monkeypatch):
    """Minimal fakes for the checkin/medical reads (see test_chat_medical.py for
    the thorough coverage of what these handlers build)."""
    monkeypatch.setattr(
        handlers.store, "local_day", lambda config, user_id: ("2026-07-26", "America/New_York")
    )
    monkeypatch.setattr(
        handlers.store,
        "checkin_config",
        lambda config: {
            "questions": [
                {"id": "nausea", "category": "symptoms", "title": "Nausea", "subtitle": None}
            ],
            "options": {"nausea": [{"code": "none", "label": "None", "value": 5}]},
        },
    )
    monkeypatch.setattr(
        handlers.store,
        "checkin_answers",
        lambda config, user_id, since=None, until=None: [
            {
                "checkin_date": "2026-07-20",
                "question_id": "nausea",
                "category": "symptoms",
                "title": "Nausea",
                "option_code": "mild",
                "label": "Mild",
                "value": 4,
            }
        ],
    )
    monkeypatch.setattr(handlers.store, "active_plan", lambda config, user_id: None)
    monkeypatch.setattr(handlers.backend, "list_shots", lambda *a, **k: [])
    monkeypatch.setattr(handlers.backend, "list_side_effects", lambda *a, **k: [])


def test_checkin_questions_command(client, fake_store, medical):
    body = _post(client, query="/checkin-questions").json()
    call = body["tool_calls"][0]
    assert call["tool"] == "checkin_questions"
    assert call["data"]["day"] == "2026-07-26"
    assert [q["id"] for q in call["data"]["questions"]] == ["nausea"]


def test_checkin_questions_short_alias(client, fake_store, medical):
    body = _post(client, query="/checkin").json()
    assert body["tool_calls"][0]["tool"] == "checkin_questions"


def test_medical_log_command_with_a_section_argument(client, fake_store, medical):
    body = _post(client, query="/retrieve_medical_log sections=symptoms").json()
    call = body["tool_calls"][0]
    assert call["tool"] == "retrieve_medical_log"
    assert call["arguments"] == {"sections": ["symptoms"]}
    # The scale conversion survives the whole route: "mild" (native 4) -> 2.
    assert call["data"]["symptoms"]["days"][0]["effects"][0]["severity"] == 2


def test_medical_log_rejects_an_unknown_section_before_persisting(client, fake_store, medical):
    """The enum is on the schema, so the router rejects it during parsing."""
    response = _post(client, query="/retrieve_medical_log sections=bloodwork")
    assert response.status_code == 400
    assert fake_store.logged == []


# ---------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------


def test_command_catalogue_is_served_for_the_client(client):
    response = client.get("/v1/chat/commands", headers={"Authorization": "Bearer test"})
    assert response.status_code == 200
    entry = next(e for e in response.json()["commands"] if e["tool"] == "retrieve_weight_log")
    assert "/retrieve_weight_log" in entry["commands"]
    assert entry["arguments"] == ["end_date", "limit", "start_date"]


def test_chat_requires_authentication(monkeypatch, fake_store):
    """Unauthenticated callers never reach the registry."""
    from fastapi import HTTPException

    def deny(authorization):
        raise HTTPException(status_code=401, detail="Sign in to continue.")

    monkeypatch.setattr(main, "_require_user", deny)
    response = TestClient(main.app).post("/v1/chat", json={"query": "/retrieve_weight_log"})
    assert response.status_code == 401
    assert fake_store.logged == []
