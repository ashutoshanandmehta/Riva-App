"""Identify the food item(s) in a view using the current V1 Claude scanner
(partner to SAM 2: Claude names/classifies, SAM 2 would provide per-item masks).
Returns [{name, grams}]; grams is the LLM portion estimate, used only to split a
total volume across items until per-item masks exist. Optional — the pipeline
runs without it (treats the capture as one _generic item)."""
import os
import sys
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[3]
if str(BACKEND) not in sys.path:
    sys.path.insert(0, str(BACKEND))


def _load_backend_env() -> None:
    env = BACKEND / ".env"
    if not env.exists():
        return
    for line in env.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip())


def identify(view_path) -> list[dict]:
    from app import preprocess, vision  # noqa: E402
    from app.config import settings  # noqa: E402
    from app.main import _assemble  # noqa: E402

    _load_backend_env()
    cfg = settings()
    client = vision.make_client(cfg)
    model = vision.resolve_model(cfg)
    prompt = vision.load_prompt(cfg.prompt_version)
    b64 = preprocess.prepare_image(Path(view_path).read_bytes())
    analysis = vision.analyze_image(client, model, b64, None, prompt)
    result = _assemble(analysis, cfg.fdc_api_key)
    return [{"name": i.name, "grams": float(i.portion_grams)} for i in result.items]
