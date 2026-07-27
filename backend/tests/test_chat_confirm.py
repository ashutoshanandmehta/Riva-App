"""Unit: the write gate. Nothing here touches Supabase or the network.

The property under test is one sentence: a write tool cannot save anything the
user was not shown and did not approve in an *earlier* turn. Everything else in
this file is a way of trying to break that.
"""

import pytest
from fastapi import HTTPException

from app.chat import confirm, handlers_writes, tools
from app.chat.spec import ToolSpec
from app.config import Settings

CONFIG = Settings()
USER = "11111111-1111-1111-1111-111111111111"

WRITE_TOOLS = [name for name, spec in tools.REGISTRY.items() if spec.writes]


@pytest.fixture
def logged(monkeypatch):
    """Captures what actually reached the backend write helpers."""
    calls: list[tuple] = []

    monkeypatch.setattr(
        handlers_writes.backend,
        "log_weight",
        lambda config, user_id, pounds, measured_at: (
            calls.append(("log_weight", user_id, pounds, measured_at)),
            {"pounds": pounds, "measured_at": measured_at or "2026-07-26"},
        )[1],
    )
    monkeypatch.setattr(
        handlers_writes.backend,
        "log_side_effects",
        lambda config, user_id, effects, note: (
            calls.append(("log_side_effects", user_id, effects, note)),
            [{"log_date": "2026-07-26", **effect} for effect in effects],
        )[1],
    )
    monkeypatch.setattr(
        handlers_writes.backend,
        "delete_todo",
        lambda config, user_id, todo_id: calls.append(("delete_todo", user_id, todo_id)),
    )
    return calls


def _previewed(spec, arguments) -> list[dict]:
    """A thread in which an earlier turn previewed this exact write."""
    return [
        {
            "role": "assistant",
            "tool_calls": [
                {
                    "tool": spec.name,
                    "arguments": arguments,
                    "data": confirm.preview(spec, arguments),
                }
            ],
        }
    ]


def _spent(spec, arguments) -> list[dict]:
    """A thread in which that previewed write has since been completed."""
    return _previewed(spec, arguments) + [
        {
            "role": "assistant",
            "tool_calls": [
                {
                    "tool": spec.name,
                    "arguments": arguments,
                    "data": confirm.stamp(
                        {"status": "saved"}, confirm.fingerprint(spec.name, arguments)
                    ),
                }
            ],
        }
    ]


def _approve(spec, arguments) -> set[str]:
    """What the route resolves when the user taps Confirm on that preview."""
    return confirm.resolve(_previewed(spec, arguments), confirm.fingerprint(spec.name, arguments))


# ---------------------------------------------------------------------------
# The gate
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("name", WRITE_TOOLS)
def test_every_write_tool_declares_a_confirm_argument(name):
    assert confirm.CONFIRM_KEY in tools.REGISTRY[name].properties
    assert tools.REGISTRY[name].confirm_summary is not None


def test_no_read_tool_is_marked_as_writing():
    for name in ("retrieve_weight_log", "retrieve_nutrition_log", "retrieve_todos"):
        assert tools.REGISTRY[name].writes is False


def test_an_unconfirmed_write_previews_and_saves_nothing(logged):
    spec = tools.REGISTRY["record_weight"]
    result = tools.dispatch(spec, CONFIG, USER, {"pounds": 201.4})

    assert result["status"] == confirm.NEEDS_CONFIRMATION
    assert "201.4" in result["will_write"]
    assert logged == []


def test_confirm_true_without_a_prior_preview_still_saves_nothing(logged):
    """The one that matters: a model cannot approve itself inside a turn."""
    spec = tools.REGISTRY["record_weight"]
    result = tools.dispatch(spec, CONFIG, USER, {"pounds": 201.4, "confirm": True}, set())

    assert result["status"] == confirm.NEEDS_CONFIRMATION
    assert logged == []


def test_a_previewed_and_confirmed_write_goes_through(logged):
    spec = tools.REGISTRY["record_weight"]
    arguments = {"pounds": 201.4}
    approved = _approve(spec, arguments)

    result = tools.dispatch(spec, CONFIG, USER, {**arguments, "confirm": True}, approved)

    assert result["status"] == "saved"
    assert logged == [("log_weight", USER, 201.4, None)]


def test_approval_does_not_carry_to_different_values(logged):
    """Saying yes to 201.4 lbs is not saying yes to 210.4 lbs."""
    spec = tools.REGISTRY["record_weight"]
    approved = _approve(spec, {"pounds": 201.4})

    result = tools.dispatch(spec, CONFIG, USER, {"pounds": 210.4, "confirm": True}, approved)

    assert result["status"] == confirm.NEEDS_CONFIRMATION
    assert logged == []


def test_approval_does_not_carry_to_a_different_tool(logged):
    approved = _approve(tools.REGISTRY["record_weight"], {"pounds": 201.4})
    spec = tools.REGISTRY["remove_todo"]

    result = tools.dispatch(spec, CONFIG, USER, {"todo_id": "abc", "confirm": True}, approved)

    assert result["status"] == confirm.NEEDS_CONFIRMATION
    assert logged == []


def test_the_confirm_flag_never_reaches_the_handler():
    """The gate is not data. A handler that saw `confirm` could store it."""
    seen: dict = {}
    spec = ToolSpec(
        name="record_probe",
        description="test double",
        input_schema={
            "type": "object",
            "additionalProperties": False,
            "properties": {"pounds": {"type": "number"}, confirm.CONFIRM_KEY: {"type": "boolean"}},
            "required": ["pounds"],
        },
        handler=lambda config, user_id, arguments: seen.update(arguments) or {},
        writes=True,
        confirm_summary=lambda arguments: "probe",
    )
    approved = _approve(spec, {"pounds": 201.4})

    tools.dispatch(spec, CONFIG, USER, {"pounds": 201.4, "confirm": True}, approved)

    assert seen == {"pounds": 201.4}


def test_previewed_fingerprints_ignores_ordinary_read_results():
    history = [
        {
            "role": "assistant",
            "tool_calls": [{"tool": "retrieve_weight_log", "data": {"entries": []}}],
        },
        {"role": "user", "content": "yes"},
    ]
    assert confirm.previewed_fingerprints(history) == set()


# ---------------------------------------------------------------------------
# Assent: being shown a preview is not the same as agreeing to it
# ---------------------------------------------------------------------------


def test_a_preview_alone_does_not_approve_anything():
    """The regression this whole mechanism exists for.

    A stored preview proves the user was *shown* a write, never that they said
    yes. Without a token, a thread containing a preview must approve nothing —
    otherwise a user who replied "no" leaves the same trace as one who agreed.
    """
    spec = tools.REGISTRY["record_weight"]
    assert confirm.resolve(_previewed(spec, {"pounds": 201.4}), None) == set()


def test_a_refusal_after_a_preview_blocks_the_write(logged):
    """User is shown the write and replies "no". The client sends no token."""
    spec = tools.REGISTRY["record_weight"]
    arguments = {"pounds": 201.4}
    history = _previewed(spec, arguments) + [{"role": "user", "content": "no, that's wrong"}]

    approved = confirm.resolve(history, None)
    result = tools.dispatch(spec, CONFIG, USER, {**arguments, "confirm": True}, approved)

    assert result["status"] == confirm.NEEDS_CONFIRMATION
    assert logged == []


def test_a_spent_fingerprint_cannot_be_replayed(logged):
    """One approval authorises one write, not every repeat of it."""
    spec = tools.REGISTRY["record_side_effects"]
    arguments = {"effects": [{"effect": "nausea", "severity": 3}], "note": None}
    token = confirm.fingerprint(spec.name, arguments)

    approved = confirm.resolve(_spent(spec, arguments), token)
    result = tools.dispatch(spec, CONFIG, USER, {**arguments, "confirm": True}, approved)

    assert approved == set()
    assert result["status"] == confirm.NEEDS_CONFIRMATION
    assert logged == []


def test_one_token_cannot_buy_two_writes_in_the_same_turn(logged):
    """Within a turn the stored stamp is not yet readable, so the live set has
    to be consumed too. The model can emit the same confirmed tool_use block
    twice in one response; only the first may write."""
    spec = tools.REGISTRY["record_weight"]
    arguments = {"pounds": 201.4}
    approved = _approve(spec, arguments)

    first = tools.dispatch(spec, CONFIG, USER, {**arguments, "confirm": True}, approved)
    second = tools.dispatch(spec, CONFIG, USER, {**arguments, "confirm": True}, approved)

    assert first["status"] == "saved"
    assert second["status"] == confirm.NEEDS_CONFIRMATION
    assert logged == [("log_weight", USER, 201.4, None)]


def test_a_rejected_write_leaves_the_approval_usable(logged):
    """A 400 is not a spend: the user should be able to correct and retry."""
    spec = tools.REGISTRY["record_weight"]
    arguments = {"pounds": 201.4}
    approved = _approve(spec, arguments)

    monkey = handlers_writes.backend.log_weight

    def boom(config, user_id, pounds, measured_at):
        raise HTTPException(status_code=400, detail="nope")

    handlers_writes.backend.log_weight = boom
    try:
        with pytest.raises(HTTPException):
            tools.dispatch(spec, CONFIG, USER, {**arguments, "confirm": True}, approved)
    finally:
        handlers_writes.backend.log_weight = monkey

    assert approved == {confirm.fingerprint(spec.name, arguments)}
    assert logged == []


def test_a_forged_token_approves_nothing():
    spec = tools.REGISTRY["record_weight"]
    history = _previewed(spec, {"pounds": 201.4})
    assert confirm.resolve(history, "deadbeefdeadbeef") == set()


def test_a_token_for_a_preview_in_this_turn_only_approves_nothing():
    """History excludes the current turn, so a self-issued preview is unusable."""
    spec = tools.REGISTRY["record_weight"]
    token = confirm.fingerprint(spec.name, {"pounds": 201.4})
    assert confirm.resolve([], token) == set()


def test_a_completed_write_is_stamped_so_it_can_be_spent(logged):
    """`consumed()` reads this back; without the stamp, replay protection is off."""
    spec = tools.REGISTRY["record_weight"]
    arguments = {"pounds": 201.4}

    result = tools.dispatch(
        spec, CONFIG, USER, {**arguments, "confirm": True}, _approve(spec, arguments)
    )

    assert result[confirm.CONFIRMED_KEY] == confirm.fingerprint(spec.name, arguments)
    assert confirm.consumed([{"tool_calls": [{"data": result}]}]) == {
        confirm.fingerprint(spec.name, arguments)
    }


def test_a_read_result_is_never_stamped():
    """Only writes are spendable; a read must not accrue replay bookkeeping."""
    spec = ToolSpec(
        name="retrieve_probe",
        description="test double",
        input_schema={"type": "object", "additionalProperties": False, "properties": {}},
        handler=lambda config, user_id, arguments: {"entries": []},
    )
    result = tools.dispatch(spec, CONFIG, USER, {}, set())
    assert confirm.CONFIRMED_KEY not in result


# ---------------------------------------------------------------------------
# Handler validation, past the gate
# ---------------------------------------------------------------------------


def _confirmed(name: str, arguments: dict):
    spec = tools.REGISTRY[name]
    return tools.dispatch(
        spec, CONFIG, USER, {**arguments, "confirm": True}, _approve(spec, arguments)
    )


@pytest.mark.parametrize("pounds", [12, 2000, "heavy"])
def test_an_implausible_weight_is_a_400(pounds, logged):
    with pytest.raises(HTTPException) as error:
        _confirmed("record_weight", {"pounds": pounds})
    assert error.value.status_code == 400
    assert logged == []


def test_side_effects_replace_the_day_and_report_it(logged):
    result = _confirmed(
        "record_side_effects",
        {"effects": [{"effect": "nausea", "severity": 3}], "note": "rough morning"},
    )
    assert result["replaced_todays_set"] is True
    assert result["saved"] == [{"effect": "nausea", "severity": 3}]
    assert logged[0][2] == [{"effect": "nausea", "severity": 3}]
    assert logged[0][3] == "rough morning"


@pytest.mark.parametrize(
    "effects",
    [
        [],
        [{"effect": "sneezing", "severity": 2}],
        [{"effect": "nausea", "severity": 9}],
        [{"effect": "nausea", "severity": 2}, {"effect": "nausea", "severity": 4}],
        ["nausea"],
    ],
)
def test_a_bad_side_effect_list_is_a_400(effects, logged):
    with pytest.raises(HTTPException) as error:
        _confirmed("record_side_effects", {"effects": effects})
    assert error.value.status_code == 400
    assert logged == []


def test_a_one_off_todo_without_a_due_date_is_a_400():
    with pytest.raises(HTTPException) as error:
        _confirmed(
            "set_todo",
            {
                "title": "Weigh in",
                "category": "weight",
                "repeat_rule": "once",
                "remind_hour": 8,
                "remind_minute": 0,
            },
        )
    assert error.value.status_code == 400


def test_a_daily_todo_with_a_due_date_is_a_400():
    with pytest.raises(HTTPException) as error:
        _confirmed(
            "set_todo",
            {
                "title": "Drink water",
                "category": "water",
                "repeat_rule": "daily",
                "remind_hour": 8,
                "remind_minute": 0,
                "due_date": "2026-08-01",
            },
        )
    assert error.value.status_code == 400


def test_a_missing_todo_id_is_a_400_that_names_where_to_get_one():
    with pytest.raises(HTTPException) as error:
        _confirmed("remove_todo", {})
    assert error.value.status_code == 400
    assert "retrieve_todos" in error.value.detail


def test_removing_a_todo_passes_the_verified_user(logged):
    result = _confirmed("remove_todo", {"todo_id": "todo-1"})
    # Plus the spent-approval stamp, which every completed write now carries.
    assert result["status"] == "deleted"
    assert result["todo_id"] == "todo-1"
    assert logged == [("delete_todo", USER, "todo-1")]
