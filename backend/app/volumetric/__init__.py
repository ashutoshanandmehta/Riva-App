"""Volumetric portion-estimation building blocks: per-view geometry, pluggable
segmentation, cross-view association, and the volume plausibility gate.

Promoted from the eval prototype (backend/eval/volumetric/multiview/). The
food-class table stays canonical in app.plausibility / app.food_classes.json —
this package resolves classes through app.plausibility, it does not duplicate
the table.
"""
