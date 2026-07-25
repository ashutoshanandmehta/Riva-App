from app.config import Settings


def test_strip_whitespace_removes_wraps_and_trailing_slash():
    s = Settings(anthropic_api_key="  sk-ant-\n abc  ", fdc_api_key="key/")
    assert s.anthropic_api_key == "sk-ant-abc"
    assert s.fdc_api_key == "key"


def test_defaults():
    s = Settings(anthropic_api_key="x")
    assert s.riva_scan_model == ""      # empty => Sonnet default in vision.resolve_model
    assert s.prompt_version == "v1"
