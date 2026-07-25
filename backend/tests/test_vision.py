import json

from app import plausibility, vision
from app.config import Settings


def _walk(node):
    if isinstance(node, dict):
        yield node
        for v in node.values():
            yield from _walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v)


def test_anthropic_schema_has_no_bare_type_unions():
    # Anthropic structured outputs reject `"type": [...]`; the transform must
    # have rewritten every union into anyOf.
    for node in _walk(vision._ANTHROPIC_SCHEMA):
        assert not isinstance(node.get("type"), list), node


def test_nullable_field_becomes_anyof():
    reason = vision._ANTHROPIC_SCHEMA["properties"]["reason"]
    assert "anyOf" in reason
    assert {"type": "null"} in reason["anyOf"]


def test_water_object_union_preserves_object_shape():
    water = vision._ANTHROPIC_SCHEMA["properties"]["water"]
    obj = next(v for v in water["anyOf"] if v.get("type") == "object")
    assert obj["additionalProperties"] is False
    assert "container_type" in obj["properties"]


def test_resolve_model_default_and_override():
    assert vision.resolve_model(Settings(riva_scan_model="")) == "claude-sonnet-5"
    assert vision.resolve_model(Settings(riva_scan_model="claude-opus-4-8")) == "claude-opus-4-8"


def test_scan_schema_wellformed():
    s = vision.SCAN_SCHEMA
    assert s["type"] == "object"
    assert s["additionalProperties"] is False
    assert {"scan_type", "items", "water"} <= set(s["properties"])


def test_food_class_enum_values_are_valid_classes_or_other():
    item_schema = vision.SCAN_SCHEMA["properties"]["items"]["items"]
    enum_values = item_schema["properties"]["food_class"]["enum"]
    known_classes = set(plausibility.food_classes())
    for value in enum_values:
        if value == "other":
            continue
        assert value in known_classes, value


def test_food_class_schema_survives_anthropic_and_fallback_processing():
    # _ANTHROPIC_SCHEMA (via _nullable_to_anyof) must still carry the enum.
    item_schema = vision._ANTHROPIC_SCHEMA["properties"]["items"]["items"]
    assert "food_class" in item_schema["properties"]
    assert "food_class" in item_schema["required"]
    # The prompt-fallback path serializes SCAN_SCHEMA directly (see
    # analyze_image's except branch) — confirm that round-trips cleanly.
    fallback_item_schema = json.loads(json.dumps(vision.SCAN_SCHEMA))["properties"]["items"][
        "items"
    ]
    expected_enum = vision.SCAN_SCHEMA["properties"]["items"]["items"]["properties"]["food_class"][
        "enum"
    ]
    assert fallback_item_schema["properties"]["food_class"]["enum"] == expected_enum
