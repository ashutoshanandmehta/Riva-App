"""Offline tests for the multi-item / multi-view plumbing (no token, no network).
Run from this directory:  ../../../.venv/bin/python -m pytest test_multiview.py -q
"""
from pathlib import Path

import associate
import numpy as np
import pipeline

SAMPLE_DIR = "/Users/ashutoshanand/Downloads/Riva/sample multi view pictures"


def _rect(h, w, y0, y1, x0, x1):
    m = np.zeros((h, w), bool)
    m[y0:y1, x0:x1] = True
    return m


def test_associate_two_items_across_two_views():
    v1 = [_rect(100, 100, 40, 80, 10, 40), _rect(100, 100, 40, 80, 60, 90)]
    v2 = [_rect(100, 100, 42, 82, 12, 42), _rect(100, 100, 42, 82, 62, 92)]
    tracks = associate.associate([v1, v2])
    assert len(tracks) == 2                      # two distinct items
    assert all(len(t) == 2 for t in tracks)      # each seen in both views


def test_associate_single_item_multi_view_is_one_track():
    v = [[_rect(100, 100, 40, 80, 30, 70)]] * 3  # same blob, 3 views
    tracks = associate.associate(v)
    assert len(tracks) == 1 and len(tracks[0]) == 3


def test_classical_single_item_pipeline_on_sample():
    if not Path(SAMPLE_DIR).exists():
        import pytest
        pytest.skip("sample dir not present")
    res = pipeline.run(SAMPLE_DIR, items=[{"name": "burger", "grams": 100}],
                       segmenter_force="classical")
    assert res["segmenter"] == "classical"
    assert res["meal"]["n_items"] == 1           # one burger, not three views-as-items
    name, fused, g = res["items"][0]
    assert fused["n_views"] == 3
    assert g.action in ("log", "clamp")
    assert 100 < fused["volume_ml"] < 2000
