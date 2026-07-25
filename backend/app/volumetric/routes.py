"""`POST /v1/scan/volumetric` — the multi-frame capture endpoint behind the
iOS "3D scan (beta)" flow (B1 milestone: the parametric pipeline; the
calibrated carver is a later step). Real and reachable in the shipping app
today, but explicitly opt-in and labeled experimental client-side — this is
not a debug-only tool.

Anonymous and stateless like `/v1/scan` — no auth dependency, no DB writes.
The iOS client persists an accepted result separately, through the existing
authenticated `/v1/log` path (see `ScanRepository.accept`), not through this
route.

Multipart contract: a `manifest` form field (the JSON payload described in
`app.volumetric.payload`) plus one file part per frame/depth referenced in it.
Files are matched to the manifest by **upload filename** (`UploadFile.filename`,
i.e. the `file`/`depth_file` values), not by form field name — this lets every
frame share a generic field name (e.g. repeated `frames`) while still being
addressable by the name the manifest gave it.
"""

import json
import logging

from fastapi import APIRouter, HTTPException, Request
from starlette.datastructures import UploadFile

from app.config import settings
from app.schemas import ScanResponse
from app.volumetric import capture_store, payload, pipeline

logger = logging.getLogger(__name__)

router = APIRouter()


def _parse_grams_truth(raw: str | None) -> float | None:
    """`grams_truth` arrives as a form-field string (iOS ground-truth capture
    tool); ignore it silently if it isn't a number rather than 400ing a scan
    over a debug-only field."""
    if not raw:
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def _merge_form_fallbacks(manifest_raw: str, hint: str | None, mode: str | None) -> str:
    """`hint`/`mode` form fields are used only when the manifest itself omits
    them — the manifest is the source of truth when it states a value."""
    try:
        manifest = json.loads(manifest_raw)
    except (TypeError, ValueError):
        return manifest_raw  # let payload.parse raise the clear "not valid JSON" error
    if not isinstance(manifest, dict):
        return manifest_raw  # let payload.parse raise the clear "must be an object" error
    if manifest.get("hint") is None and hint:
        manifest["hint"] = hint
    if not manifest.get("mode") and mode:
        manifest["mode"] = mode
    return json.dumps(manifest)


@router.post("/v1/scan/volumetric", response_model=ScanResponse, response_model_exclude_none=True)
async def scan_volumetric(request: Request) -> ScanResponse:
    form = await request.form()

    manifest_raw = form.get("manifest")
    if not isinstance(manifest_raw, str) or not manifest_raw:
        raise HTTPException(status_code=400, detail="Missing 'manifest' form field.")

    files: dict[str, bytes] = {}
    for _, value in form.multi_items():
        if isinstance(value, UploadFile) and value.filename:
            files[value.filename] = await value.read()

    hint = form.get("hint")
    mode = form.get("mode")
    hint_str = hint if isinstance(hint, str) else None
    manifest_raw = _merge_form_fallbacks(
        manifest_raw,
        hint_str,
        mode if isinstance(mode, str) else None,
    )

    try:
        capture = payload.parse(manifest_raw, files)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    # Dev-only ground-truth capture tool: banks the raw capture to disk (for
    # offline re-scoring once the calibrated carver exists) before the
    # pipeline runs, so it's kept even if the pipeline later errors. OFF
    # unless VOLUMETRIC_CAPTURE_DIR is set; never allowed to affect the
    # response below.
    if settings().volumetric_capture_dir:
        label = form.get("label")
        grams_truth = form.get("grams_truth")
        try:
            capture_store.save(
                capture,
                manifest_raw,
                settings().volumetric_capture_dir,
                label if isinstance(label, str) else None,
                _parse_grams_truth(grams_truth if isinstance(grams_truth, str) else None),
                hint_str,
            )
        except Exception as error:
            logger.warning("volumetric capture persistence failed: %s", error)

    try:
        return pipeline.run_volumetric(capture, settings().fdc_api_key)
    except HTTPException:
        raise
    except Exception as error:
        logger.exception("Volumetric scan failed")
        raise HTTPException(status_code=502, detail=f"Volumetric scan error: {error}") from error
