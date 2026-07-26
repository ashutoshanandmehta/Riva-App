"""Unit: the checkin_questions and retrieve_medical_log handlers.

Store and backend reads are faked, so nothing here touches Supabase. The
fixtures mirror the rows seeded by 0002_logging.sql, because the scale direction
of those exact seeded values is what the normalisation has to get right.
"""

import pytest
from fastapi import HTTPException

from app.chat import handlers, symptoms
from app.config import Settings

CONFIG = Settings()
USER = "11111111-1111-1111-1111-111111111111"
TODAY = "2026-07-26"
TZ = "America/New_York"

# Mirrors the seeded checkin_questions / checkin_options rows.
QUESTIONS = [
    {
        "id": "mood",
        "category": "wellbeing",
        "title": "Mood",
        "subtitle": "How are you feeling today?",
        "sort_order": 1,
    },
    {
        "id": "energy",
        "category": "wellbeing",
        "title": "Energy",
        "subtitle": "How is your energy level?",
        "sort_order": 2,
    },
    {
        "id": "sleep",
        "category": "wellbeing",
        "title": "Sleep Quality",
        "subtitle": "How did you sleep?",
        "sort_order": 3,
    },
    {
        "id": "nausea",
        "category": "symptoms",
        "title": "Nausea",
        "subtitle": "Any nausea today?",
        "sort_order": 4,
    },
    {
        "id": "appetite",
        "category": "symptoms",
        "title": "Appetite",
        "subtitle": "How is your appetite?",
        "sort_order": 5,
    },
]
OPTIONS = {
    "mood": [
        {"code": c, "label": c.title(), "value": v}
        for c, v in [("awful", 1), ("low", 2), ("okay", 3), ("good", 4), ("great", 5)]
    ],
    "energy": [
        {"code": c, "label": c.title(), "value": v}
        for c, v in [("drained", 1), ("low", 2), ("okay", 3), ("good", 4), ("high", 5)]
    ],
    "sleep": [
        {"code": c, "label": c.title(), "value": v}
        for c, v in [("terrible", 1), ("poor", 2), ("okay", 3), ("good", 4), ("excellent", 5)]
    ],
    "nausea": [
        {"code": c, "label": c.title(), "value": v}
        for c, v in [("severe", 1), ("strong", 2), ("moderate", 3), ("mild", 4), ("none", 5)]
    ],
    "appetite": [
        {"code": c, "label": c.title(), "value": v}
        for c, v in [("none", 1), ("low", 2), ("okay", 3), ("good", 4), ("strong", 5)]
    ],
}


def _answer(day, question, code, value, category):
    return {
        "checkin_date": day,
        "question_id": question,
        "category": category,
        "title": question.title(),
        "option_code": code,
        "label": code.title(),
        "value": value,
    }


@pytest.fixture
def faked(monkeypatch):
    """Fakes every read the two handlers make, and records the calls."""
    calls: dict = {"checkin_answers": [], "side_effects": [], "shots": []}
    state: dict = {
        "answers": [],
        "shots": [],
        "side_effects": [],
        "plan": {"name": "Semaglutide", "current_dose_mg": 1.0, "cadence_days": 7},
    }

    def fake_checkin_answers(config, user_id, since=None, until=None):
        calls["checkin_answers"].append({"since": since, "until": until})
        return list(state["answers"])

    def fake_side_effects(config, user_id, days, since=None, until=None):
        calls["side_effects"].append({"days": days, "since": since, "until": until})
        return list(state["side_effects"])

    def fake_shots(config, user_id, limit, since=None, until=None):
        calls["shots"].append({"limit": limit, "since": since, "until": until})
        return list(state["shots"])

    monkeypatch.setattr(handlers.store, "local_day", lambda config, user_id: (TODAY, TZ))
    monkeypatch.setattr(
        handlers.store,
        "checkin_config",
        lambda config: {"questions": list(QUESTIONS), "options": OPTIONS},
    )
    monkeypatch.setattr(handlers.store, "checkin_answers", fake_checkin_answers)
    monkeypatch.setattr(handlers.store, "active_plan", lambda config, user_id: state["plan"])
    monkeypatch.setattr(handlers.backend, "list_side_effects", fake_side_effects)
    monkeypatch.setattr(handlers.backend, "list_shots", fake_shots)
    return {"calls": calls, "state": state}


# ---------------------------------------------------------------------------
# checkin_questions
# ---------------------------------------------------------------------------


def test_returns_the_seeded_set_in_order_on_the_native_scale(faked):
    result = handlers.checkin_questions(CONFIG, USER, {})
    assert [q["id"] for q in result["questions"]] == [
        "mood",
        "energy",
        "sleep",
        "nausea",
        "appetite",
    ]
    assert result["scale"] == symptoms.NATIVE_CHECKIN_SCALE
    assert result["day"] == TODAY and result["timezone"] == TZ

    nausea = next(q for q in result["questions"] if q["id"] == "nausea")
    # Native scale: "none" is the BEST answer and keeps value 5 here. Only
    # retrieve_medical_log converts it.
    assert {o["code"]: o["value"] for o in nausea["options"]}["none"] == 5


def test_todays_answers_are_resolved(faked):
    faked["state"]["answers"] = [_answer(TODAY, "sleep", "good", 4, "wellbeing")]
    result = handlers.checkin_questions(CONFIG, USER, {})

    sleep = next(q for q in result["questions"] if q["id"] == "sleep")
    assert sleep["answered_option_code"] == "good"
    assert sleep["answered_label"] == "Good"
    assert sleep["answered_value"] == 4

    mood = next(q for q in result["questions"] if q["id"] == "mood")
    assert mood["answered_option_code"] is None
    assert result["answered_count"] == 1
    assert result["unanswered"] == ["mood", "energy", "nausea", "appetite"]


def test_only_todays_answers_are_read(faked):
    """ "Today" is the user's local day, matching how log_checkin computes it."""
    handlers.checkin_questions(CONFIG, USER, {})
    assert faked["calls"]["checkin_answers"] == [{"since": TODAY, "until": TODAY}]


@pytest.mark.parametrize("category", ["wellbeing", "symptoms"])
def test_category_filter(faked, category):
    result = handlers.checkin_questions(CONFIG, USER, {"category": category})
    assert {q["category"] for q in result["questions"]} == {category}


def test_unknown_category_is_rejected(faked):
    with pytest.raises(HTTPException) as excinfo:
        handlers.checkin_questions(CONFIG, USER, {"category": "vitals"})
    assert excinfo.value.status_code == 400


def test_answered_count_respects_the_category_filter(faked):
    faked["state"]["answers"] = [_answer(TODAY, "sleep", "good", 4, "wellbeing")]
    result = handlers.checkin_questions(CONFIG, USER, {"category": "symptoms"})
    assert result["answered_count"] == 0
    assert result["unanswered"] == ["nausea", "appetite"]


# ---------------------------------------------------------------------------
# retrieve_medical_log — sections and window
# ---------------------------------------------------------------------------


def test_all_four_sections_by_default(faked):
    result = handlers.retrieve_medical_log(CONFIG, USER, {})
    assert result["sections"] == list(handlers.MEDICAL_SECTIONS)
    for section in handlers.MEDICAL_SECTIONS:
        assert section in result


def test_default_window_is_anchored_on_the_users_own_day(faked):
    result = handlers.retrieve_medical_log(CONFIG, USER, {})
    assert result["requested_range"] == {"start_date": "2026-06-26", "end_date": TODAY}
    assert faked["calls"]["side_effects"][0]["since"] == "2026-06-26"


def test_a_section_subset_returns_only_those_keys(faked):
    result = handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["plan"]})
    assert result["sections"] == ["plan"]
    assert "plan" in result
    for absent in ("shots", "symptoms", "wellbeing"):
        assert absent not in result
    # And no wasted reads.
    assert faked["calls"]["shots"] == [] and faked["calls"]["checkin_answers"] == []


def test_sections_are_returned_in_canonical_order(faked):
    result = handlers.retrieve_medical_log(
        CONFIG, USER, {"sections": ["wellbeing", "plan", "shots"]}
    )
    assert result["sections"] == ["shots", "plan", "wellbeing"]


def test_duplicate_sections_are_deduplicated(faked):
    result = handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["plan", "plan"]})
    assert result["sections"] == ["plan"]


def test_unknown_section_is_rejected(faked):
    with pytest.raises(HTTPException) as excinfo:
        handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["bloodwork"]})
    assert excinfo.value.status_code == 400
    assert "symptoms" in excinfo.value.detail


def test_reversed_range_is_rejected(faked):
    with pytest.raises(HTTPException) as excinfo:
        handlers.retrieve_medical_log(
            CONFIG, USER, {"start_date": "2026-07-26", "end_date": "2026-07-01"}
        )
    assert excinfo.value.status_code == 400


def test_checkin_answers_are_read_once_for_both_derived_sections(faked):
    """symptoms and wellbeing come from the same rows — reading them twice would
    double the round trips for no gain."""
    handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["symptoms", "wellbeing"]})
    assert len(faked["calls"]["checkin_answers"]) == 1


# ---------------------------------------------------------------------------
# retrieve_medical_log — content
# ---------------------------------------------------------------------------


def test_shots_are_oldest_first_with_a_comfort_scale(faked):
    faked["state"]["shots"] = [
        {
            "taken_at": "2026-07-24T09:00:00Z",
            "medication_name": "Semaglutide",
            "dose_mg": 1.0,
            "injection_site": "abdomen",
            "comfort_rating": 4,
        },
        {
            "taken_at": "2026-07-17T09:00:00Z",
            "medication_name": "Semaglutide",
            "dose_mg": 0.5,
            "injection_site": "thigh",
            "comfort_rating": 3,
        },
    ]
    shots = handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["shots"]})["shots"]
    assert [entry["dose_mg"] for entry in shots["entries"]] == [0.5, 1.0]
    assert "1 (worst) to 5 (best)" in shots["comfort_scale"]


def test_symptoms_section_reconciles_the_two_sources(faked):
    """The end-to-end scale check: a "mild" nausea check-in must arrive as
    severity 2, and a day present in both sources must appear once."""
    faked["state"]["side_effects"] = [
        {
            "log_date": "2026-07-24",
            "note": "rough",
            "effects": [{"effect": "nausea", "severity": 5}],
        }
    ]
    faked["state"]["answers"] = [
        _answer("2026-07-20", "nausea", "mild", 4, "symptoms"),
        _answer("2026-07-24", "nausea", "severe", 1, "symptoms"),
    ]
    section = handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["symptoms"]})["symptoms"]

    assert section["scale"] == symptoms.CANONICAL_SCALE
    by_day = {day["date"]: day for day in section["days"]}
    assert by_day["2026-07-20"]["effects"][0]["severity"] == 2  # mild -> 2, not 4
    assert len(by_day["2026-07-24"]["effects"]) == 1  # not double-reported
    assert by_day["2026-07-24"]["effects"][0]["severity"] == 5
    assert by_day["2026-07-24"]["effects"][0]["sources"] == ["side_effect_log", "checkin"]


def test_appetite_is_kept_out_of_the_symptom_timeline(faked):
    faked["state"]["answers"] = [_answer("2026-07-20", "appetite", "strong", 5, "symptoms")]
    section = handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["symptoms"]})["symptoms"]
    assert section["days"] == []
    assert section["non_directional"][0]["value"] == 5  # native, unconverted


def test_wellbeing_is_separate_and_not_inverted(faked):
    faked["state"]["answers"] = [
        _answer("2026-07-20", "sleep", "good", 4, "wellbeing"),
        _answer("2026-07-20", "nausea", "mild", 4, "symptoms"),
    ]
    result = handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["symptoms", "wellbeing"]})
    assert result["wellbeing"]["series"]["sleep"][0]["value"] == 4  # not 2
    assert "sleep" not in {
        effect["effect"] for day in result["symptoms"]["days"] for effect in day["effects"]
    }
    # The two sections advertise opposite directions, explicitly.
    assert result["symptoms"]["scale"] != result["wellbeing"]["scale"]


def test_provenance_states_there_are_no_clinician_notes(faked):
    """Guards the "what did my doctor say?" question: there is no such data, and
    the payload has to say so rather than let the model imply otherwise."""
    result = handlers.retrieve_medical_log(CONFIG, USER, {})
    assert "no" in result["note_provenance"].lower()
    assert "clinician" in result["note_provenance"]


def test_missing_plan_is_reported_as_none(faked):
    faked["state"]["plan"] = None
    assert handlers.retrieve_medical_log(CONFIG, USER, {"sections": ["plan"]})["plan"] is None


def test_empty_history_still_returns_well_formed_sections(faked):
    result = handlers.retrieve_medical_log(CONFIG, USER, {})
    assert result["shots"]["entries"] == []
    assert result["symptoms"]["days"] == []
    assert result["symptoms"]["summary"]["days_logged"] == 0
    assert result["wellbeing"]["series"] == {}
