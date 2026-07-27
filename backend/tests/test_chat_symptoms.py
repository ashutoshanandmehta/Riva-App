"""Unit: the symptom normaliser. Pure — no config, no DB, no network.

These are the highest-value tests in the chat feature. Riva stores the same
symptom in two tables on opposite 1-to-5 scales, so an off-by-direction bug here
would have the companion confidently tell a user the exact opposite of the truth.
"""

import pytest

from app.chat import symptoms

# Mirrors the seeded checkin_options rows in 0002_logging.sql. value 5 is always
# the best state, which is what makes conversion necessary.
NAUSEA_OPTIONS = [
    ("severe", 1),
    ("strong", 2),
    ("moderate", 3),
    ("mild", 4),
    ("none", 5),
]
APPETITE_OPTIONS = [("none", 1), ("low", 2), ("okay", 3), ("good", 4), ("strong", 5)]
SLEEP_OPTIONS = [("terrible", 1), ("poor", 2), ("okay", 3), ("good", 4), ("excellent", 5)]


def _answer(day, question, code, value, label=None, category=symptoms.SYMPTOM_CATEGORY):
    return {
        "checkin_date": day,
        "question_id": question,
        "category": category,
        "option_code": code,
        "label": label or code.title(),
        "value": value,
    }


def _log(day, effects, note=None):
    return {
        "log_date": day,
        "note": note,
        "effects": [{"effect": effect, "severity": severity} for effect, severity in effects],
    }


# ---------------------------------------------------------------------------
# Conversion
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(("code", "value"), NAUSEA_OPTIONS)
def test_every_seeded_nausea_option_converts(code, value):
    """6 - value, for the whole seeded set."""
    assert symptoms.to_severity(value) == 6 - value


def test_the_direction_actually_flips():
    """The one that matters: "none" is the best day and must become the *lowest*
    severity, "severe" the worst and must become the highest."""
    assert symptoms.to_severity(5) == 1  # none      -> mildest
    assert symptoms.to_severity(4) == 2  # mild      -> 2, not 4
    assert symptoms.to_severity(1) == 5  # severe    -> worst


@pytest.mark.parametrize("value", [0, 6, -1, None, "", "mild", 2.7])
def test_out_of_range_values_are_dropped_not_guessed(value):
    if value == 2.7:
        # int(2.7) is 2, which is in range — floats are tolerated, not dropped.
        assert symptoms.to_severity(value) == 4
    else:
        assert symptoms.to_severity(value) is None


# ---------------------------------------------------------------------------
# Merging the two sources
# ---------------------------------------------------------------------------


def test_side_effect_only_day():
    result = symptoms.build_symptom_timeline([_log("2026-07-20", [("headache", 3)])], [])
    effect = result["days"][0]["effects"][0]
    assert effect["severity"] == 3
    assert effect["sources"] == [symptoms.SOURCE_SIDE_EFFECT_LOG]
    assert effect["corroborating_severity"] is None


def test_checkin_only_day_is_converted():
    result = symptoms.build_symptom_timeline(
        [], [_answer("2026-07-20", "nausea", "mild", 4, "Mild")]
    )
    effect = result["days"][0]["effects"][0]
    assert effect["effect"] == "nausea"
    assert effect["severity"] == 2  # converted from value 4, NOT left as 4
    assert effect["sources"] == [symptoms.SOURCE_CHECKIN]


def test_a_day_in_both_sources_collapses_to_one_entry():
    """The reconciliation rule: the side-effect log wins, the check-in rides along."""
    result = symptoms.build_symptom_timeline(
        [_log("2026-07-20", [("nausea", 5)], note="rough morning")],
        [_answer("2026-07-20", "nausea", "severe", 1, "Severe")],
    )
    day = result["days"][0]
    assert len(day["effects"]) == 1  # not double-reported
    effect = day["effects"][0]
    assert effect["severity"] == 5
    assert effect["source"] == symptoms.SOURCE_SIDE_EFFECT_LOG
    assert effect["sources"] == [symptoms.SOURCE_SIDE_EFFECT_LOG, symptoms.SOURCE_CHECKIN]
    assert effect["corroborating_severity"] == 5  # severe -> 5, agrees
    assert effect["corroborating_label"] == "Severe"
    assert effect["agrees"] is True
    assert day["note"] == "rough morning"


def test_disagreeing_sources_keep_both_numbers_visible():
    """A conflict must not be averaged away or silently resolved."""
    result = symptoms.build_symptom_timeline(
        [_log("2026-07-20", [("nausea", 5)])],
        [_answer("2026-07-20", "nausea", "mild", 4, "Mild")],
    )
    effect = result["days"][0]["effects"][0]
    assert effect["severity"] == 5
    assert effect["corroborating_severity"] == 2
    assert effect["agrees"] is False


def test_days_are_ordered_oldest_first():
    result = symptoms.build_symptom_timeline(
        [
            _log("2026-07-24", [("nausea", 2)]),
            _log("2026-07-20", [("nausea", 4)]),
            _log("2026-07-22", [("nausea", 3)]),
        ],
        [],
    )
    assert [day["date"] for day in result["days"]] == [
        "2026-07-20",
        "2026-07-22",
        "2026-07-24",
    ]


def test_effects_within_a_day_are_ordered_stably():
    result = symptoms.build_symptom_timeline(
        [_log("2026-07-20", [("nausea", 2), ("bloating", 3), ("headache", 1)])], []
    )
    assert [e["effect"] for e in result["days"][0]["effects"]] == [
        "bloating",
        "headache",
        "nausea",
    ]


# ---------------------------------------------------------------------------
# Trend summary
# ---------------------------------------------------------------------------


def test_per_effect_trend_is_computed_server_side():
    """ "Is my nausea getting better or worse?" is arithmetic, not model judgement."""
    result = symptoms.build_symptom_timeline(
        [
            _log("2026-07-20", [("nausea", 5)]),
            _log("2026-07-22", [("nausea", 3)]),
            _log("2026-07-24", [("nausea", 2)]),
        ],
        [],
    )
    nausea = result["summary"]["effects"]["nausea"]
    assert nausea["days"] == 3
    assert nausea["first"] == 5
    assert nausea["latest"] == 2
    assert nausea["change"] == -3  # improving reads negative
    assert nausea["max"] == 5
    assert nausea["mean"] == 3.3
    assert result["summary"]["days_logged"] == 3


def test_trend_mixes_the_two_sources_on_one_scale():
    """A check-in day and a side-effect day belong to the same series once both
    are canonical — this is the whole point of the module."""
    result = symptoms.build_symptom_timeline(
        [_log("2026-07-24", [("nausea", 4)])],
        [_answer("2026-07-20", "nausea", "none", 5, "None")],
    )
    nausea = result["summary"]["effects"]["nausea"]
    assert nausea["first"] == 1  # 2026-07-20, converted from "none"
    assert nausea["latest"] == 4  # 2026-07-24, from the side-effect log
    assert nausea["change"] == 3  # got worse


# ---------------------------------------------------------------------------
# Appetite: symptom category, but not a burden
# ---------------------------------------------------------------------------


def test_appetite_is_reported_separately_and_not_converted():
    result = symptoms.build_symptom_timeline(
        [], [_answer("2026-07-20", "appetite", "strong", 5, "Strong")]
    )
    assert result["days"] == []  # never in the symptom timeline
    assert result["summary"]["effects"] == {}  # never in a symptom total
    point = result["non_directional"][0]
    assert point["question_id"] == "appetite"
    assert point["value"] == 5  # native value, NOT 6-5=1
    assert point["label"] == "Strong"
    assert point["directional"] is False
    assert point["scale"] == symptoms.APPETITE_SCALE


@pytest.mark.parametrize(("code", "value"), APPETITE_OPTIONS)
def test_every_seeded_appetite_option_survives_unconverted(code, value):
    result = symptoms.build_symptom_timeline([], [_answer("2026-07-20", "appetite", code, value)])
    assert result["non_directional"][0]["value"] == value


def test_appetite_does_not_suppress_a_real_symptom_on_the_same_day():
    result = symptoms.build_symptom_timeline(
        [_log("2026-07-20", [("nausea", 4)])],
        [
            _answer("2026-07-20", "appetite", "low", 2, "Low"),
            _answer("2026-07-20", "nausea", "mild", 4, "Mild"),
        ],
    )
    assert [e["effect"] for e in result["days"][0]["effects"]] == ["nausea"]
    assert len(result["non_directional"]) == 1


# ---------------------------------------------------------------------------
# Wellbeing stays on its own scale
# ---------------------------------------------------------------------------


def test_wellbeing_answers_are_not_inverted():
    answers = [
        _answer("2026-07-20", "sleep", "good", 4, "Good", symptoms.WELLBEING_CATEGORY),
        _answer("2026-07-20", "mood", "great", 5, "Great", symptoms.WELLBEING_CATEGORY),
    ]
    result = symptoms.build_wellbeing_timeline(answers)
    assert result["scale"] == symptoms.WELLBEING_SCALE
    assert result["series"]["sleep"][0]["value"] == 4  # not 2
    assert result["series"]["mood"][0]["value"] == 5  # not 1
    assert result["series"]["sleep"][0]["label"] == "Good"


@pytest.mark.parametrize(("code", "value"), SLEEP_OPTIONS)
def test_every_seeded_sleep_option_passes_through(code, value):
    result = symptoms.build_wellbeing_timeline(
        [_answer("2026-07-20", "sleep", code, value, None, symptoms.WELLBEING_CATEGORY)]
    )
    assert result["series"]["sleep"][0]["value"] == value


def test_wellbeing_never_enters_the_symptom_timeline():
    answers = [_answer("2026-07-20", "sleep", "poor", 2, "Poor", symptoms.WELLBEING_CATEGORY)]
    assert symptoms.build_symptom_timeline([], answers)["days"] == []


def test_symptoms_never_enter_the_wellbeing_timeline():
    answers = [_answer("2026-07-20", "nausea", "mild", 4, "Mild")]
    assert symptoms.build_wellbeing_timeline(answers)["series"] == {}


def test_wellbeing_series_is_date_ordered_with_a_trend():
    answers = [
        _answer("2026-07-24", "sleep", "good", 4, "Good", symptoms.WELLBEING_CATEGORY),
        _answer("2026-07-20", "sleep", "poor", 2, "Poor", symptoms.WELLBEING_CATEGORY),
    ]
    result = symptoms.build_wellbeing_timeline(answers)
    assert [point["date"] for point in result["series"]["sleep"]] == [
        "2026-07-20",
        "2026-07-24",
    ]
    summary = result["summary"]["sleep"]
    assert (summary["first"], summary["latest"], summary["change"]) == (2, 4, 2)


# ---------------------------------------------------------------------------
# Degenerate input
# ---------------------------------------------------------------------------


def test_empty_inputs_produce_an_empty_but_well_formed_payload():
    result = symptoms.build_symptom_timeline([], [])
    assert result["days"] == []
    assert result["summary"] == {"days_logged": 0, "effects": {}}
    assert result["scale"] == symptoms.CANONICAL_SCALE  # the label is always present
    wellbeing = symptoms.build_wellbeing_timeline([])
    assert wellbeing["series"] == {} and wellbeing["summary"] == {}


def test_rows_missing_a_date_or_question_are_skipped():
    result = symptoms.build_symptom_timeline(
        [{"log_date": None, "note": None, "effects": [{"effect": "nausea", "severity": 3}]}],
        [_answer(None, "nausea", "mild", 4), _answer("2026-07-20", None, "mild", 4)],
    )
    assert result["days"] == []


def test_a_corrupt_severity_is_dropped_without_losing_the_day():
    result = symptoms.build_symptom_timeline(
        [_log("2026-07-20", [("nausea", 99), ("headache", 2)])], []
    )
    assert [e["effect"] for e in result["days"][0]["effects"]] == ["headache"]


def test_a_log_with_no_effects_still_carries_its_note():
    result = symptoms.build_symptom_timeline([_log("2026-07-20", [], note="felt fine")], [])
    assert result["days"][0]["note"] == "felt fine"
    assert result["days"][0]["effects"] == []
