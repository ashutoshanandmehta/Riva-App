"""Unit: slash-command parsing and the security boundary on tool arguments.

No network, no database — `parse_command` is pure.
"""

import pytest
from fastapi import HTTPException

from app.chat import router, tools
from app.chat import spec as spec_module


def _detail(excinfo):
    return excinfo.value.detail


# ---------------------------------------------------------------------------
# Command vs free text
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "query",
    [
        "how is my weight trending this month?",
        "what did my doctor say about my dosage?",
        # A slash inside a sentence is not a command; only a leading one is.
        "is 1/2 a pound a week normal?",
        "  what about my goal weight  ",
    ],
)
def test_free_text_is_not_a_command(query):
    assert router.parse_command(query) is None
    assert router.looks_like_command(query) is False


def test_bare_slash_is_an_unknown_command_not_free_text():
    """A lone `/` names no tool. Answering it as conversation would spend a
    model call on a question the user never finished asking, so it 400s with the
    catalogue instead."""
    with pytest.raises(HTTPException) as excinfo:
        router.parse_command("/")
    assert excinfo.value.status_code == 400
    assert "/retrieve_weight_log" in _detail(excinfo)


@pytest.mark.parametrize(
    "query",
    [
        "/retrieve_weight_log",
        "/retrieve-weight-log",
        "/Retrieve_Weight_Log",
        "  /retrieve_weight_log  ",
    ],
)
def test_slug_matching_is_normalised(query):
    """Hyphens, underscores, case, and surrounding space all resolve the same."""
    parsed = router.parse_command(query)
    assert parsed is not None
    assert parsed.spec.name == "retrieve_weight_log"
    assert parsed.arguments == {}


def test_unknown_command_lists_the_available_ones():
    """An unrecognised command must 400, never fall through to a paid LLM call
    that answers something the user did not ask."""
    with pytest.raises(HTTPException) as excinfo:
        router.parse_command("/retrieve_bloodwork")
    assert excinfo.value.status_code == 400
    assert "/retrieve_weight_log" in _detail(excinfo)


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------


def test_key_value_arguments_are_parsed_and_coerced():
    parsed = router.parse_command(
        "/retrieve_weight_log start_date=2026-07-01 end_date=2026-07-26 limit=30"
    )
    assert parsed.arguments == {
        "start_date": "2026-07-01",
        "end_date": "2026-07-26",
        "limit": 30,  # coerced to int per the schema, not left a string
    }


def test_hyphenated_argument_keys_are_normalised():
    parsed = router.parse_command("/retrieve_weight_log start-date=2026-07-01")
    assert parsed.arguments == {"start_date": "2026-07-01"}


def test_quoted_values_survive_parsing():
    parsed = router.parse_command('/retrieve_weight_log start_date="2026-07-01"')
    assert parsed.arguments == {"start_date": "2026-07-01"}


def test_unbalanced_quotes_do_not_raise_an_unhandled_error():
    """shlex raises on a stray quote, so parsing falls back to plain splitting.

    The slug still resolves; the mangled date value is then rejected as a date,
    which is the point — a clean 400, never a ValueError escaping as a 500.
    """
    for query in ('/retrieve_weight_log"', '/retrieve_weight_log start_date=2026-07-01"'):
        with pytest.raises(HTTPException) as excinfo:
            router.parse_command(query)
        assert excinfo.value.status_code == 400


def test_argument_without_equals_is_rejected():
    with pytest.raises(HTTPException) as excinfo:
        router.parse_command("/retrieve_weight_log lastmonth")
    assert excinfo.value.status_code == 400
    assert "key=value" in _detail(excinfo)


def test_undeclared_argument_is_rejected_with_the_accepted_list():
    with pytest.raises(HTTPException) as excinfo:
        router.parse_command("/retrieve_weight_log month=july")
    assert excinfo.value.status_code == 400
    assert "start_date" in _detail(excinfo)


@pytest.mark.parametrize("value", ["last-month", "2026-13-01", "07/01/2026"])
def test_malformed_dates_are_rejected_during_parsing(value):
    """`format: date` is validated here, not just in the handler, so a mistyped
    date is caught before the route persists anything."""
    with pytest.raises(HTTPException) as excinfo:
        router.parse_command(f"/retrieve_weight_log start_date={value}")
    assert excinfo.value.status_code == 400
    assert "2026-07-01" in _detail(excinfo)


def test_non_integer_limit_is_rejected():
    with pytest.raises(HTTPException) as excinfo:
        router.parse_command("/retrieve_weight_log limit=lots")
    assert excinfo.value.status_code == 400
    assert "whole number" in _detail(excinfo)


# ---------------------------------------------------------------------------
# Coercion by declared type, exercised through synthetic specs so the tests
# still cover array/boolean/enum handling before the tools that use them land.
# ---------------------------------------------------------------------------


def _spec(properties: dict) -> tools.ToolSpec:
    return tools.ToolSpec(
        name="probe",
        description="test only",
        input_schema={"type": "object", "properties": properties, "required": []},
        handler=lambda config, user_id, arguments: {},
    )


def test_array_values_split_on_commas():
    spec = _spec({"sections": {"type": "array", "items": {"type": "string"}}})
    assert router._coerce(spec, "sections", "shots, plan ,symptoms") == [
        "shots",
        "plan",
        "symptoms",
    ]


def test_array_enum_membership_is_checked_per_item():
    spec = _spec(
        {"sections": {"type": "array", "items": {"type": "string", "enum": ["shots", "plan"]}}}
    )
    assert router._coerce(spec, "sections", "shots,plan") == ["shots", "plan"]
    with pytest.raises(HTTPException) as excinfo:
        router._coerce(spec, "sections", "shots,bloodwork")
    assert excinfo.value.status_code == 400


def test_scalar_enum_membership_is_checked():
    spec = _spec({"category": {"type": "string", "enum": ["wellbeing", "symptoms"]}})
    assert router._coerce(spec, "category", "symptoms") == "symptoms"
    with pytest.raises(HTTPException):
        router._coerce(spec, "category", "vitals")


@pytest.mark.parametrize(
    ("raw", "expected"),
    [("true", True), ("TRUE", True), ("1", True), ("yes", True), ("false", False), ("no", False)],
)
def test_boolean_values(raw, expected):
    spec = _spec({"debug": {"type": "boolean"}})
    assert router._coerce(spec, "debug", raw) is expected


def test_non_boolean_value_is_rejected():
    spec = _spec({"debug": {"type": "boolean"}})
    with pytest.raises(HTTPException):
        router._coerce(spec, "debug", "maybe")


# ---------------------------------------------------------------------------
# The security boundary. These two are regression guards, not behaviour tests:
# the verified user id is bound by dispatch(), so a tool that accepted a subject
# argument would let a prompt-injected model read another account.
# ---------------------------------------------------------------------------


def test_no_tool_declares_a_subject_argument():
    for spec in tools.REGISTRY.values():
        offending = spec_module.FORBIDDEN_ARG_KEYS.intersection(k.lower() for k in spec.properties)
        assert not offending, f"{spec.name} declares {sorted(offending)}"


def test_every_registered_command_resolves_to_its_tool():
    for name, spec in tools.REGISTRY.items():
        assert spec.slugs, f"{name} exposes no command"
        for slug in spec.slugs:
            assert tools.COMMAND_INDEX[slug] is spec
            assert router.parse_command(f"/{slug}").spec is spec
