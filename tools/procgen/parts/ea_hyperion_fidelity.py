"""The Hyperion's per-part section check (M10-T22; CLAUDE.md, "STL fidelity"): the planes each part seen up close is cut at,
against the reference model, with ``tools/refview/sections.py`` (the measure for open shells, M10-T62).

Frame: the generator's (x to starboard from the hull's axis, y up from the middle of the reference's box, z aft from the bow
guns' muzzles). A window is (u0, u1, v0, v1) in the plane's (u, v).

The build is symmetric (the maintainer saw no lopsidedness), the reference is not quite: its box is centred on the engine block,
the bow, deck, tower and fin are mirror-symmetric about x = -3.4 m in that box, the truss and module about -2.8, the sponsons
about -6.75 (3.35 m to port) and the bells about +1.0, and its starboard flank toes in from 280 m to 5.5 m narrower than the
port one by 436 m (measured by mirror-matching each part and cutting the flanks; no yaw or roll explains it: the tower's top and
the fin's foot share one axis). So each part is compared on its own axis (:data:`PART_AXIS_X`): the sections score its shape,
the silhouettes the whole; the forward hull is built at the two flanks' mean.

The bells are open shells in the reference and hollow in the build only near the mouth, so they are compared by outline, as is
the engine block's aft plane (the reference sinks the bells' throats into the block); the sponsons are cut ahead of and behind
the bays (the reference's sponsons are solid).
"""

from __future__ import annotations

import numpy as np

from tools.refview.sections import SectionPlane

REFERENCE_AXIS_X = -3.4  # the hull's axis in the reference's box, m at 1 025.39 m
REFERENCE_MAPPING = {"right": "+x", "up": "+z", "aft": "-y"}
FORE = (-80.0, 80.0, -60.0, 60.0)
SPONSON_R, SPONSON_L = (50.0, 92.0, -45.0, 0.0), (-92.0, -50.0, -45.0, 0.0)
TOWER = (-35.0, 35.0, -140.0, 140.0)
GIRDER = (-20.0, 20.0, 29.5, 60.0)  # the girder and its keel, above the plane of the struts
SPINE_AFT = (-20.0, 20.0, 22.0, 50.0)
MODULE = (-70.0, 70.0, -15.0, 80.0)
TANK_R, TANK_L = (45.0, 90.0, -35.0, 55.0), (-90.0, -45.0, -35.0, 55.0)
BLOCK = (-132.0, 132.0, -40.0, 65.0)
BELLS = (-102.0, 102.0, -20.0, 45.0)


def _z(name: str, z: float, window: tuple[float, float, float, float], **kw: object) -> SectionPlane:
    return SectionPlane(f"{name}_z{z:.0f}", 2, z, window, **kw)


PLANES: dict[str, list[SectionPlane]] = {
    "forward_hull": [_z("fore", z, FORE) for z in (120.0, 200.0, 280.0, 330.0, 365.0)],
    "sponsons": [*(_z("sponson_r", z, SPONSON_R) for z in (395.0, 404.0, 436.0)), *(_z("sponson_l", z, SPONSON_L) for z in (395.0, 404.0, 436.0))],
    "command_tower": [_z("tower", z, TOWER) for z in (420.0, 445.0, 465.0)],
    "truss": [_z("girder", z, GIRDER) for z in (545.0, 600.0, 640.0)],
    "reactor_module": [_z("module", z, MODULE) for z in (690.0, 725.0)],
    "aft_spine": [_z("spine_aft", z, SPINE_AFT) for z in (780.0, 830.0, 858.0)],
    "fuel_tanks": [*(_z("tank_r", z, TANK_R) for z in (865.0, 880.0)), *(_z("tank_l", z, TANK_L) for z in (865.0, 880.0))],
    "engine_block": [_z("block", 905.0, BLOCK), _z("block", 935.0, BLOCK, outline=True)],
    "bells": [_z("bells", z, BELLS, outline=True) for z in (985.0, 1015.0)],
}
# Where each part's own axis stands in the reference's box, m (see above).
PART_AXIS_X: dict[str, float] = {
    "forward_hull": REFERENCE_AXIS_X, "sponsons": -6.75, "command_tower": REFERENCE_AXIS_X, "truss": -2.85, "reactor_module": -2.7,
    "aft_spine": -3.5, "fuel_tanks": -2.75, "engine_block": 0.0, "bells": 1.0,
}


def reference_for(part: str, reference: np.ndarray) -> np.ndarray:
    """The reference's triangles (in its box frame) moved so ``part`` stands on the build's axis."""
    return np.asarray(reference) - np.array([PART_AXIS_X[part], 0.0, 0.0])


# Planes a part may fail, each with the reason the maintainer accepted. None yet.
EXEMPT: dict[str, str] = {}

__all__ = ["EXEMPT", "PART_AXIS_X", "PLANES", "REFERENCE_AXIS_X", "REFERENCE_MAPPING", "reference_for"]
