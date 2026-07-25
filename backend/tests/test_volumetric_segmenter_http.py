"""Offline tests for `Sam2HTTPSegmenter` (the self-hosted Lightning SAM 2
client, backend/app/volumetric/segmenter.py) and `get_segmenter`'s selection
precedence between it, Replicate, and classical. The Lightning endpoint is
faked with `httpx.MockTransport` (no real network, no new dependency) —
`Sam2HTTPSegmenter` accepts an injected `httpx.Client` for exactly this.
"""

import base64
import json

import cv2
import httpx
import numpy as np
import pytest

import app.volumetric.segmenter as segmenter
from app.config import Settings


def _frame(color=(120, 60, 200), size=64) -> np.ndarray:
    return np.full((size, size, 3), color, dtype=np.uint8)


def _mask_png_b64(mask: np.ndarray) -> str:
    gray = mask.astype(np.uint8) * 255
    ok, buf = cv2.imencode(".png", gray)
    assert ok
    return base64.b64encode(buf).decode()


def _central_mask(size=64, frac_side=0.5) -> np.ndarray:
    """A square mask centred in the frame, sized to land inside the area
    filter (MIN_AREA_FRAC..MAX_AREA_FRAC)."""
    m = np.zeros((size, size), dtype=bool)
    half = int(size * frac_side / 2)
    c = size // 2
    m[c - half : c + half, c - half : c + half] = True
    return m


def _corner_mask(size=64, frac_side=0.5) -> np.ndarray:
    """Same area as `_central_mask` but pushed into a corner — lower
    centrality, should rank behind the central mask."""
    m = np.zeros((size, size), dtype=bool)
    side = int(size * frac_side)
    m[0:side, 0:side] = True
    return m


def _tiny_mask(size=64) -> np.ndarray:
    """Below MIN_AREA_FRAC — filtered out."""
    m = np.zeros((size, size), dtype=bool)
    m[0:2, 0:2] = True
    return m


def _make_segmenter(handler) -> segmenter.Sam2HTTPSegmenter:
    transport = httpx.MockTransport(handler)
    client = httpx.Client(transport=transport)
    settings_stub = Settings(
        anthropic_api_key="x", sam2_endpoint_url="http://fake-lightning", sam2_api_key="k"
    )
    seg = segmenter.Sam2HTTPSegmenter.__new__(segmenter.Sam2HTTPSegmenter)
    seg.endpoint = settings_stub.sam2_endpoint_url
    seg.api_key = settings_stub.sam2_api_key
    seg.timeout_s = settings_stub.sam2_timeout_s
    seg._client = client
    return seg


def test_happy_path_decodes_filters_and_ranks_by_centrality():
    central = _central_mask()
    corner = _corner_mask()

    def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["x-api-key"] == "k"
        body = json.loads(request.content)
        assert len(body["images"]) == 2
        assert body["mode"] == "auto"
        return httpx.Response(
            200,
            json={
                "results": [
                    # corner listed first in the payload — ranking must reorder it behind central
                    {
                        "masks": [_mask_png_b64(corner), _mask_png_b64(central)],
                        "width": 64,
                        "height": 64,
                    },
                    {"masks": [_mask_png_b64(central)], "width": 64, "height": 64},
                ]
            },
        )

    seg = _make_segmenter(handler)
    frames = [_frame(), _frame(color=(10, 200, 30))]
    batch = seg.segment_many(frames)

    assert len(batch) == 2
    # image 0: two masks survive the area filter, central ranked first
    assert len(batch[0]) == 2
    assert np.array_equal(batch[0][0], central)
    assert np.array_equal(batch[0][1], corner)
    # image 1: single surviving mask
    assert len(batch[1]) == 1
    assert np.array_equal(batch[1][0], central)


def test_connection_error_falls_back_to_classical_for_whole_batch(monkeypatch):
    calls = []

    def fake_classical_segment(self, bgr):
        calls.append(bgr)
        return ["classical-mask"]

    monkeypatch.setattr(segmenter.ClassicalSegmenter, "segment", fake_classical_segment)

    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("connection refused", request=request)

    seg = _make_segmenter(handler)
    frames = [_frame(), _frame(color=(1, 2, 3))]
    batch = seg.segment_many(frames)

    assert batch == [["classical-mask"], ["classical-mask"]]
    assert len(calls) == 2


@pytest.mark.parametrize("status", [401, 500])
def test_non_2xx_status_falls_back_to_classical_for_whole_batch(monkeypatch, status):
    monkeypatch.setattr(
        segmenter.ClassicalSegmenter, "segment", lambda self, bgr: ["classical-mask"]
    )

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(status, json={"error": "nope"})

    seg = _make_segmenter(handler)
    frames = [_frame()]
    batch = seg.segment_many(frames)

    assert batch == [["classical-mask"]]


def test_one_empty_result_falls_back_per_image_only(monkeypatch):
    central = _central_mask()
    fallback_calls = []
    monkeypatch.setattr(
        segmenter.ClassicalSegmenter,
        "segment",
        lambda self, bgr: fallback_calls.append(bgr) or ["classical-mask"],
    )

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "results": [
                    {"masks": [_mask_png_b64(central)], "width": 64, "height": 64},
                    # image 1: only a tiny mask, filtered out by area -> empty
                    {"masks": [_mask_png_b64(_tiny_mask())], "width": 64, "height": 64},
                ]
            },
        )

    seg = _make_segmenter(handler)
    frame_a, frame_b = _frame(), _frame(color=(9, 9, 9))
    batch = seg.segment_many([frame_a, frame_b])

    assert len(batch) == 2
    assert np.array_equal(batch[0][0], central)  # server's mask, no fallback
    assert batch[1] == ["classical-mask"]  # per-image fallback only
    assert len(fallback_calls) == 1
    assert np.array_equal(fallback_calls[0], frame_b)


class TestGetSegmenterPrecedence:
    def test_lightning_wins_when_only_it_is_set(self, monkeypatch):
        monkeypatch.setattr(
            segmenter,
            "settings",
            lambda: Settings(anthropic_api_key="x", sam2_endpoint_url="http://fake"),
        )
        assert isinstance(segmenter.get_segmenter(None), segmenter.Sam2HTTPSegmenter)

    def test_lightning_wins_over_replicate_when_both_set(self, monkeypatch):
        monkeypatch.setattr(
            segmenter,
            "settings",
            lambda: Settings(
                anthropic_api_key="x",
                sam2_endpoint_url="http://fake",
                replicate_api_token="tok",
            ),
        )
        assert isinstance(segmenter.get_segmenter(None), segmenter.Sam2HTTPSegmenter)

    def test_replicate_used_when_only_it_is_set(self, monkeypatch):
        monkeypatch.setattr(
            segmenter,
            "settings",
            lambda: Settings(anthropic_api_key="x", replicate_api_token="tok"),
        )

        class _FakeReplicateSegmenter:
            pass

        monkeypatch.setattr(
            segmenter, "Sam2ReplicateSegmenter", lambda *a, **k: _FakeReplicateSegmenter()
        )
        assert isinstance(segmenter.get_segmenter(None), _FakeReplicateSegmenter)

    def test_classical_when_neither_set(self, monkeypatch):
        monkeypatch.setattr(segmenter, "settings", lambda: Settings(anthropic_api_key="x"))
        assert isinstance(segmenter.get_segmenter(None), segmenter.ClassicalSegmenter)

    def test_force_classical_always_wins(self, monkeypatch):
        monkeypatch.setattr(
            segmenter,
            "settings",
            lambda: Settings(
                anthropic_api_key="x", sam2_endpoint_url="http://fake", replicate_api_token="tok"
            ),
        )
        assert isinstance(segmenter.get_segmenter("classical"), segmenter.ClassicalSegmenter)
