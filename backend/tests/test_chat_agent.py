"""Unit: the tool-calling loop. No Anthropic, no Supabase, no network.

`vision.make_client` is monkeypatched to a fake whose responses are scripted per
call, so each test drives the loop through an exact stop_reason sequence.
"""

import json
from dataclasses import dataclass, field

import pytest
from fastapi import HTTPException

from app.chat import agent, tools
from app.config import Settings

USER = "11111111-1111-1111-1111-111111111111"
OTHER = "22222222-2222-2222-2222-222222222222"


# ---------------------------------------------------------------------------
# A minimal stand-in for the Anthropic response shape the loop reads
# ---------------------------------------------------------------------------


@dataclass
class TextBlock:
    text: str
    type: str = "text"


@dataclass
class ThinkingBlock:
    thinking: str = "..."
    signature: str = "sig"
    type: str = "thinking"


@dataclass
class ToolUseBlock:
    name: str
    input: dict
    id: str = "toolu_1"
    type: str = "tool_use"


@dataclass
class Usage:
    input_tokens: int = 10
    output_tokens: int = 20


@dataclass
class FakeResponse:
    stop_reason: str
    content: list = field(default_factory=list)
    usage: Usage = field(default_factory=Usage)


class FakeMessages:
    def __init__(self, script):
        self.script = list(script)
        self.calls: list[dict] = []

    def create(self, **kwargs):
        self.calls.append(kwargs)
        if not self.script:
            raise AssertionError("the loop made more model calls than the script allows")
        nxt = self.script.pop(0)
        if isinstance(nxt, Exception):
            raise nxt
        return nxt


class FakeClient:
    def __init__(self, script):
        self.messages = FakeMessages(script)


@pytest.fixture
def scripted(monkeypatch):
    """Installs a fake client and a fake weight tool; returns the harness."""
    holder: dict = {}

    def install(*script):
        client = FakeClient(script)
        holder["client"] = client
        monkeypatch.setattr(agent.vision, "make_client", lambda config: client)
        return client

    tool_calls: list[dict] = []

    def fake_dispatch(spec, config, user_id, arguments, approved=None):
        tool_calls.append({"tool": spec.name, "user_id": user_id, "arguments": dict(arguments)})
        return {"summary": {"change_lbs": -12.2}}

    monkeypatch.setattr(agent.tools, "dispatch", fake_dispatch)
    holder["install"] = install
    holder["dispatched"] = tool_calls
    return holder


CONFIG = Settings()


def _weight_call(**arguments):
    return FakeResponse(
        stop_reason="tool_use",
        content=[
            ThinkingBlock(),
            TextBlock("Let me check your weight log."),
            ToolUseBlock(name="retrieve_weight_log", input=arguments),
        ],
    )


def _answer(text):
    return FakeResponse(stop_reason="end_turn", content=[TextBlock(text)])


# ---------------------------------------------------------------------------
# The happy path
# ---------------------------------------------------------------------------


def test_single_tool_then_answer(scripted):
    client = scripted["install"](_weight_call(start_date="2026-07-01"), _answer("Down 12.2 lbs."))
    result = agent.run(CONFIG, USER, [], "how is my weight trending?")

    assert result.message == "Down 12.2 lbs."
    assert result.iterations == 2
    assert result.model == agent.DEFAULT_MODEL
    assert result.prompt_version == CONFIG.riva_chat_prompt_version
    assert [call["tool"] for call in result.tool_calls] == ["retrieve_weight_log"]
    assert result.tool_calls[0]["arguments"] == {"start_date": "2026-07-01"}
    assert result.tool_calls[0]["data"] == {"summary": {"change_lbs": -12.2}}
    assert len(client.messages.calls) == 2


def test_the_verified_user_is_what_reaches_dispatch(scripted):
    """The whole security boundary in one assertion: the subject comes from the
    caller, never from anything the model emitted."""
    scripted["install"](_weight_call(user_id=OTHER), _answer("ok"))
    agent.run(CONFIG, USER, [], "whose data?")
    assert [call["user_id"] for call in scripted["dispatched"]] == [USER]


def test_tools_and_system_prompt_are_sent(scripted):
    scripted["install"](_answer("hello"))
    agent.run(CONFIG, USER, [], "hi")
    sent = scripted["client"].messages.calls[0]
    assert {t["name"] for t in sent["tools"]} == set(tools.REGISTRY)
    assert "GLP-1" in sent["system"]
    assert sent["max_tokens"] == agent.MAX_TOKENS


def test_adaptive_thinking_and_effort_are_requested(scripted):
    """Thinking stays on for a tool-calling turn; budget_tokens is never sent
    (it 400s on the current models)."""
    scripted["install"](_answer("hi"))
    agent.run(CONFIG, USER, [], "hi")
    sent = scripted["client"].messages.calls[0]
    assert sent["thinking"] == {"type": "adaptive"}
    assert "budget_tokens" not in json.dumps(sent["thinking"])
    assert sent["output_config"]["effort"] == CONFIG.riva_chat_effort


def test_haiku_runs_without_thinking_or_effort(scripted, monkeypatch):
    """Haiku predates both parameters and errors on effort."""
    config = Settings(riva_chat_model="claude-haiku-4-5")
    scripted["install"](_answer("hi"))
    agent.run(config, USER, [], "hi")
    sent = scripted["client"].messages.calls[0]
    assert "thinking" not in sent and "output_config" not in sent


# ---------------------------------------------------------------------------
# Message construction
# ---------------------------------------------------------------------------


def test_the_assistant_turn_is_echoed_back_verbatim(scripted):
    """Thinking and tool_use blocks must survive unchanged or the next call 400s."""
    first = _weight_call()
    scripted["install"](first, _answer("done"))
    agent.run(CONFIG, USER, [], "q")

    second = scripted["client"].messages.calls[1]
    assistant = second["messages"][-2]
    assert assistant["role"] == "assistant"
    assert assistant["content"] is first.content  # same objects, not rebuilt


def test_all_tool_results_go_back_in_one_user_message(scripted):
    """Splitting them teaches the model to stop calling tools in parallel."""
    parallel = FakeResponse(
        stop_reason="tool_use",
        content=[
            ToolUseBlock(name="retrieve_weight_log", input={}, id="toolu_a"),
            ToolUseBlock(name="checkin_questions", input={}, id="toolu_b"),
        ],
    )
    scripted["install"](parallel, _answer("both"))
    agent.run(CONFIG, USER, [], "q")

    results = scripted["client"].messages.calls[1]["messages"][-1]
    assert results["role"] == "user"
    assert [block["tool_use_id"] for block in results["content"]] == ["toolu_a", "toolu_b"]
    assert len(scripted["dispatched"]) == 2


def test_history_is_replayed_as_text_turns(scripted):
    scripted["install"](_answer("ok"))
    history = [
        {"id": "1", "role": "user", "content": "first question", "tool_calls": []},
        {"id": "2", "role": "assistant", "content": "first answer", "tool_calls": []},
    ]
    agent.run(CONFIG, USER, history, "follow-up")
    sent = scripted["client"].messages.calls[0]["messages"]
    assert [(m["role"], m["content"]) for m in sent] == [
        ("user", "first question"),
        ("assistant", "first answer"),
        ("user", "follow-up"),
    ]


def test_a_command_turn_replays_as_a_named_placeholder():
    """Command-path turns store no prose. An empty assistant message would be
    rejected, so the tool names stand in for it."""
    replayed = agent.history_messages(
        [
            {"role": "user", "content": "/retrieve_weight_log"},
            {"role": "assistant", "content": "", "tool_calls": [{"tool": "retrieve_weight_log"}]},
        ]
    )
    assert replayed[1]["role"] == "assistant"
    assert "retrieve_weight_log" in replayed[1]["content"]


def test_history_always_starts_with_a_user_turn():
    """The API rejects a transcript that opens on an assistant message, which is
    what a window that clipped mid-exchange would produce."""
    replayed = agent.history_messages(
        [
            {"role": "assistant", "content": "trailing answer from an earlier window"},
            {"role": "user", "content": "next question"},
        ]
    )
    assert [m["role"] for m in replayed] == ["user"]


def test_empty_and_unknown_role_rows_are_skipped():
    replayed = agent.history_messages(
        [
            {"role": "user", "content": "   "},
            {"role": "system", "content": "not a transcript role"},
            {"role": "user", "content": "real"},
            {"role": "assistant", "content": "", "tool_calls": []},
        ]
    )
    assert [(m["role"], m["content"]) for m in replayed] == [("user", "real")]


# ---------------------------------------------------------------------------
# Tool failures recover instead of ending the turn
# ---------------------------------------------------------------------------


def test_a_rejected_argument_returns_an_is_error_result(scripted, monkeypatch):
    """A mistyped date should become a retry, not a dead turn or a 400."""

    def rejecting_dispatch(spec, config, user_id, arguments, approved=None):
        raise HTTPException(status_code=400, detail="start_date must be a date like 2026-07-01.")

    monkeypatch.setattr(agent.tools, "dispatch", rejecting_dispatch)
    scripted["install"](_weight_call(start_date="last month"), _answer("Which month?"))
    result = agent.run(CONFIG, USER, [], "q")

    assert result.message == "Which month?"
    assert result.tool_calls == []  # nothing ran, so nothing is reported as data
    sent = scripted["client"].messages.calls[1]["messages"][-1]["content"][0]
    assert sent["is_error"] is True
    assert "2026-07-01" in sent["content"]


def test_an_unexpected_tool_exception_is_reported_to_the_model(scripted, monkeypatch):
    def exploding_dispatch(spec, config, user_id, arguments, approved=None):
        raise RuntimeError("postgrest exploded")

    monkeypatch.setattr(agent.tools, "dispatch", exploding_dispatch)
    scripted["install"](_weight_call(), _answer("I could not read that."))
    result = agent.run(CONFIG, USER, [], "q")

    assert result.message == "I could not read that."
    block = scripted["client"].messages.calls[1]["messages"][-1]["content"][0]
    assert block["is_error"] is True and "exploded" in block["content"]


def test_a_hallucinated_tool_name_is_reported_not_dispatched(scripted):
    scripted["install"](
        FakeResponse(
            stop_reason="tool_use",
            content=[ToolUseBlock(name="retrieve_bloodwork", input={})],
        ),
        _answer("I don't have bloodwork."),
    )
    result = agent.run(CONFIG, USER, [], "q")

    assert scripted["dispatched"] == []
    assert result.tool_calls == []
    block = scripted["client"].messages.calls[1]["messages"][-1]["content"][0]
    assert block["is_error"] is True
    assert "retrieve_weight_log" in block["content"]  # lists what does exist


# ---------------------------------------------------------------------------
# Stop reasons and the iteration cap
# ---------------------------------------------------------------------------


def test_iteration_cap_ends_with_tools_withdrawn(scripted):
    """The last pass sets tool_choice none so the turn must produce prose rather
    than another tool request the loop has no room to serve."""
    config = Settings(riva_chat_max_tool_iterations=3)
    scripted["install"](_weight_call(), _weight_call(), _answer("Best I have."))
    result = agent.run(config, USER, [], "q")

    calls = scripted["client"].messages.calls
    assert len(calls) == 3
    assert "tool_choice" not in calls[0] and "tool_choice" not in calls[1]
    assert calls[2]["tool_choice"] == {"type": "none"}
    assert result.message == "Best I have."
    assert result.iterations == 3


def test_a_refusal_is_answered_safely_without_reading_content(scripted):
    """stop_reason is checked before content — a refusal carries no answer."""
    scripted["install"](FakeResponse(stop_reason="refusal", content=[]))
    result = agent.run(CONFIG, USER, [], "something disallowed")
    assert result.message == agent.REFUSED
    assert "clinician" in result.message


def test_truncation_is_disclosed_rather_than_passed_off_as_complete(scripted):
    scripted["install"](FakeResponse(stop_reason="max_tokens", content=[TextBlock("Partial")]))
    result = agent.run(CONFIG, USER, [], "q")
    assert result.message.startswith("Partial")
    assert "cut short" in result.message


def test_an_empty_answer_falls_back_to_a_message(scripted):
    """Never return an empty string as the assistant's reply."""
    scripted["install"](FakeResponse(stop_reason="end_turn", content=[]))
    assert agent.run(CONFIG, USER, [], "q").message == agent.NO_ANSWER


def test_multiple_text_blocks_are_joined(scripted):
    scripted["install"](
        FakeResponse(stop_reason="end_turn", content=[TextBlock("One."), TextBlock("Two.")])
    )
    assert agent.run(CONFIG, USER, [], "q").message == "One.\n\nTwo."


def test_tool_use_stop_reason_with_no_tool_block_does_not_loop(scripted):
    """Defensive: the loop must not append an empty tool_result turn and spin."""
    scripted["install"](
        FakeResponse(stop_reason="tool_use", content=[TextBlock("I'll look that up.")])
    )
    result = agent.run(CONFIG, USER, [], "q")
    assert result.message == "I'll look that up."
    assert len(scripted["client"].messages.calls) == 1


# ---------------------------------------------------------------------------
# Outage handling
# ---------------------------------------------------------------------------


def test_a_model_outage_is_a_502_not_a_fabricated_answer(scripted):
    scripted["install"](RuntimeError("connection reset"))
    with pytest.raises(HTTPException) as excinfo:
        agent.run(CONFIG, USER, [], "q")
    assert excinfo.value.status_code == 502
    assert excinfo.value.detail == agent.UNAVAILABLE


def test_an_outage_midway_through_the_loop_still_raises(scripted):
    scripted["install"](_weight_call(), RuntimeError("connection reset"))
    with pytest.raises(HTTPException) as excinfo:
        agent.run(CONFIG, USER, [], "q")
    assert excinfo.value.status_code == 502


def test_a_missing_api_key_is_a_503(monkeypatch):
    def no_client(config):
        raise RuntimeError("ANTHROPIC_API_KEY is not set in backend/.env.")

    monkeypatch.setattr(agent.vision, "make_client", no_client)
    with pytest.raises(HTTPException) as excinfo:
        agent.run(CONFIG, USER, [], "q")
    assert excinfo.value.status_code == 503


def test_a_missing_prompt_version_is_a_503(scripted):
    config = Settings(riva_chat_prompt_version="v99")
    scripted["install"](_answer("hi"))
    with pytest.raises(HTTPException) as excinfo:
        agent.run(config, USER, [], "q")
    assert excinfo.value.status_code == 503


# ---------------------------------------------------------------------------
# The shipped prompt has to carry the safety and scale rules
# ---------------------------------------------------------------------------


def test_the_prompt_states_the_scale_directions_and_safety_limits():
    prompt = agent.load_prompt("v1")
    assert "severity_1_5_higher_worse" in prompt
    assert "value_1_5_higher_better" in prompt
    # Never let the model treat the two scales as comparable.
    assert "opposite direction" in prompt or "Never compare" in prompt
    # No dosing advice, no invented clinician notes, no recomputed arithmetic.
    assert "clinician" in prompt
    assert "no" in prompt.lower() and "provider" in prompt
    assert "Never recompute" in prompt


# ---------------------------------------------------------------------------
# A pre-write prompt must not be paired with the write tools
# ---------------------------------------------------------------------------


def test_a_pre_write_prompt_version_is_refused_while_write_tools_exist():
    """`config.py` documents this constraint; here it is actually enforced.

    v1 predates the write tools and carries none of the confirmation rules, so
    running it with them registered puts a model with no instructions about
    confirming in front of the user's medical log.
    """
    assert any(spec.writes for spec in tools.REGISTRY.values())

    with pytest.raises(HTTPException) as excinfo:
        agent._assert_prompt_supports_tools("v1")

    assert excinfo.value.status_code == 503
    assert "predates the write tools" in excinfo.value.detail


def test_the_shipped_prompt_version_is_allowed():
    agent._assert_prompt_supports_tools(Settings().riva_chat_prompt_version)
