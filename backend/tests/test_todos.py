"""Unit: the todo RPC wrappers and the route validation in front of them.
The REST layer is monkeypatched, so nothing here touches the network."""

import pytest
from fastapi import HTTPException

from app import backend, main
from app.config import Settings
from app.schemas import TodoUpsertRequest

_CONFIG = Settings(_env_file=None)

_ROW = {
    "id": "todo-1",
    "title": "Log breakfast",
    "category": "food",
    "repeat_rule": "daily",
    "remind_hour": 8,
    "remind_minute": 0,
    "due_date": None,
    "is_done": False,
}


def _capture(monkeypatch, rows):
    """Replaces backend._rpc and records the call it received."""
    seen = {}

    def fake_rpc(config, function, params):
        seen["function"] = function
        seen["params"] = params
        return rows

    monkeypatch.setattr(backend, "_rpc", fake_rpc)
    return seen


def _request(**overrides):
    fields = {
        "title": "Log breakfast",
        "category": "food",
        "repeat_rule": "daily",
        "remind_hour": 8,
        "remind_minute": 0,
    }
    fields.update(overrides)
    return TodoUpsertRequest(**fields)


# ---------------------------------------------------------------------------
# backend wrappers
# ---------------------------------------------------------------------------


def test_list_todos_passes_the_user(monkeypatch):
    seen = _capture(monkeypatch, [_ROW])
    assert backend.list_todos(_CONFIG, "user-1") == [_ROW]
    assert seen["function"] == "list_todos"
    assert seen["params"] == {"p_user_id": "user-1"}


def test_upsert_todo_sends_a_null_id_when_creating(monkeypatch):
    seen = _capture(monkeypatch, [_ROW])
    entry = {
        "id": None,
        "title": "Log breakfast",
        "category": "food",
        "repeat_rule": "daily",
        "remind_hour": 8,
        "remind_minute": 0,
        "due_date": None,
    }
    assert backend.upsert_todo(_CONFIG, "user-1", entry) == _ROW
    assert seen["function"] == "upsert_todo"
    assert seen["params"] == {
        "p_user_id": "user-1",
        "p_todo_id": None,
        "p_title": "Log breakfast",
        "p_category": "food",
        "p_repeat_rule": "daily",
        "p_remind_hour": 8,
        "p_remind_minute": 0,
        "p_due_date": None,
    }


def test_upsert_todo_is_404_when_nothing_matched(monkeypatch):
    """An edit against an unknown or foreign id returns no rows."""
    _capture(monkeypatch, [])
    with pytest.raises(HTTPException) as error:
        backend.upsert_todo(_CONFIG, "user-1", {**_ROW, "id": "someone-elses"})
    assert error.value.status_code == 404


def test_set_todo_done_passes_the_flag(monkeypatch):
    seen = _capture(monkeypatch, [{**_ROW, "is_done": True}])
    assert backend.set_todo_done(_CONFIG, "user-1", "todo-1", True)["is_done"] is True
    assert seen["function"] == "set_todo_done"
    assert seen["params"] == {"p_user_id": "user-1", "p_todo_id": "todo-1", "p_done": True}


def test_set_todo_done_is_404_when_nothing_matched(monkeypatch):
    _capture(monkeypatch, [])
    with pytest.raises(HTTPException) as error:
        backend.set_todo_done(_CONFIG, "user-1", "gone", True)
    assert error.value.status_code == 404


def test_delete_todo_is_404_when_already_gone(monkeypatch):
    _capture(monkeypatch, [])
    with pytest.raises(HTTPException) as error:
        backend.delete_todo(_CONFIG, "user-1", "gone")
    assert error.value.status_code == 404


def test_delete_todo_succeeds_quietly(monkeypatch):
    seen = _capture(monkeypatch, [{"id": "todo-1"}])
    assert backend.delete_todo(_CONFIG, "user-1", "todo-1") is None
    assert seen["params"] == {"p_user_id": "user-1", "p_todo_id": "todo-1"}


# ---------------------------------------------------------------------------
# route validation
# ---------------------------------------------------------------------------


def test_validated_todo_trims_the_title():
    assert main._validated_todo(_request(title="  Weigh in  "))["title"] == "Weigh in"


def test_validated_todo_keeps_a_once_due_date():
    entry = main._validated_todo(_request(repeat_rule="once", due_date="2026-07-26"))
    assert entry["due_date"] == "2026-07-26"


def test_validated_todo_drops_a_due_date_from_a_daily_todo():
    """The client may leave a stale date behind when switching to daily; the
    todos_due_date_matches_repeat constraint would reject it."""
    entry = main._validated_todo(_request(repeat_rule="daily", due_date="2026-07-26"))
    assert entry["due_date"] is None


@pytest.mark.parametrize(
    "overrides",
    [
        {"title": "   "},
        {"title": "x" * 81},
        {"category": "sleep"},
        {"repeat_rule": "weekly"},
        {"remind_hour": 24},
        {"remind_hour": -1},
        {"remind_minute": 60},
        {"repeat_rule": "once", "due_date": None},
        # Unparseable dates would otherwise reach Postgres and surface as a
        # 502 that reads like the backend is down.
        {"repeat_rule": "once", "due_date": "tomorrow"},
        {"repeat_rule": "once", "due_date": "2026-13-45"},
        {"repeat_rule": "once", "due_date": ""},
    ],
)
def test_validated_todo_rejects_bad_payloads(overrides):
    with pytest.raises(HTTPException) as error:
        main._validated_todo(_request(**overrides))
    assert error.value.status_code == 400


def test_non_uuid_id_in_the_body_is_404_not_502():
    """A malformed id is an unknown to-do, not a database failure."""
    with pytest.raises(HTTPException) as error:
        main._validated_todo(_request(id="abc"))
    assert error.value.status_code == 404


@pytest.mark.parametrize("todo_id", ["abc", "", "1234", "not-a-uuid"])
def test_non_uuid_path_id_is_404(todo_id):
    with pytest.raises(HTTPException) as error:
        main._validated_todo_id(todo_id)
    assert error.value.status_code == 404


def test_valid_uuid_path_id_passes_through():
    valid = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
    assert main._validated_todo_id(valid) == valid
