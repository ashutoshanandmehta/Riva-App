import numpy as np

from app.volumetric.associate import associate


def _rect(h, w, y0, y1, x0, x1):
    m = np.zeros((h, w), bool)
    m[y0:y1, x0:x1] = True
    return m


def test_associate_two_items_across_two_views():
    v1 = [_rect(100, 100, 40, 80, 10, 40), _rect(100, 100, 40, 80, 60, 90)]
    v2 = [_rect(100, 100, 42, 82, 12, 42), _rect(100, 100, 42, 82, 62, 92)]
    tracks = associate([v1, v2])
    assert len(tracks) == 2  # two distinct items
    assert all(len(t) == 2 for t in tracks)  # each seen in both views


def test_associate_single_item_multi_view_is_one_track():
    v = [[_rect(100, 100, 40, 80, 30, 70)]] * 3  # same blob, 3 views
    tracks = associate(v)
    assert len(tracks) == 1 and len(tracks[0]) == 3


def test_associate_empty_views_returns_no_tracks():
    assert associate([[], []]) == []
