"""The Hyperion's per-part section check (M10-T22; CLAUDE.md, "STL fidelity"): the planes each part seen up close is cut at,
against the reference model (``references/EA-Hyperion-V5c.stl``, Q58), with ``tools/refview/sections.py``.

Frame: the generator's (x to starboard from the hull's axis, y up from the middle of the reference's box, z aft from the bow's
prongs). A window is (u0, u1, v0, v1) in the plane's (u, v). The reference is symmetric and its box is centred on the hull's
axis, so no part needs moving (:data:`PART_AXIS_X` stays for parts that would).

Planes stay clear of the reference's groove round the hull (the paint lines: 56-59, 92-95, 137-141, 333-336 and 367-370 m along
the forward hull, 48-50, 78-80, -75 and -98 to -100 m up the tower), which the ship does not have, and of the Starfury bays in
the hangar bump, which the reference does not have (Q58). The bells are open shells in the reference and hollow in the build
only near the mouth, so they are compared by outline.
"""

from __future__ import annotations

import numpy as np

from tools.refview.sections import SectionPlane

REFERENCE = "EA-Hyperion-V5c.stl"
REFERENCE_MAPPING = {"right": "-x", "up": "+z", "aft": "+y"}
FORE = (-95.0, 95.0, -75.0, 55.0)
SPONSON_R, SPONSON_L = (55.0, 95.0, -75.0, -15.0), (-95.0, -55.0, -75.0, -15.0)
TOWER = (-45.0, 45.0, -165.0, 165.0)
GIRDER = (-25.0, 25.0, 0.0, 55.0)  # the girder, its bump and the lower box, above the plane of the struts' feet
MODULE = (-75.0, 75.0, -25.0, 60.0)
TANK_R, TANK_L = (20.0, 105.0, -80.0, 60.0), (-105.0, -20.0, -80.0, 60.0)
BLOCK = (-132.0, 132.0, -90.0, 65.0)
BELLS = (-120.0, 120.0, -55.0, 30.0)


def _z(name: str, z: float, window: tuple[float, float, float, float], **kw: object) -> SectionPlane:
    return SectionPlane(f"{name}_z{z:.0f}", 2, z, window, **kw)


PLANES: dict[str, list[SectionPlane]] = {
    "forward_hull": [_z("fore", z, FORE) for z in (75.0, 120.0, 170.0, 220.0, 250.0, 315.0)],
    "sponsons": [*(_z("sponson_r", z, SPONSON_R) for z in (355.0, 380.0, 405.0)), *(_z("sponson_l", z, SPONSON_L) for z in (355.0, 380.0, 405.0))],
    "command_tower": [_z("tower", z, TOWER) for z in (385.0, 425.0, 455.0)],
    "truss": [_z("girder", z, GIRDER) for z in (500.0, 570.0, 605.0, 655.0)],
    "reactor_module": [_z("module", z, MODULE) for z in (690.0, 715.0)],
    "aft_spine": [_z("spine_aft", z, GIRDER) for z in (760.0, 800.0)],
    "fuel_tanks": [*(_z("tank_r", z, TANK_R) for z in (870.0, 895.0)), *(_z("tank_l", z, TANK_L) for z in (870.0, 895.0))],
    "engine_block": [_z("block", z, BLOCK) for z in (920.0, 950.0)],
    "bells": [_z("bells", z, BELLS, outline=True) for z in (990.0, 1015.0)],
}
# Where each part's own axis stands in the reference's box, m: on it, for every part of this reference.
PART_AXIS_X: dict[str, float] = dict.fromkeys(PLANES, 0.0)


def reference_for(part: str, reference: np.ndarray) -> np.ndarray:
    """The reference's triangles (in its box frame) moved so ``part`` stands on the build's axis."""
    return np.asarray(reference) - np.array([PART_AXIS_X[part], 0.0, 0.0])


# Planes a part may fail, each with the reason the maintainer accepted. None yet.
EXEMPT: dict[str, str] = {}

__all__ = ["EXEMPT", "PART_AXIS_X", "PLANES", "REFERENCE", "REFERENCE_MAPPING", "reference_for"]
