"""The Nova's per-part section check (M10-T23; CLAUDE.md, "STL fidelity"): the planes each part seen up close is cut at,
against the reference model, with ``tools/refview/sections.py`` (the measure for open shells, M10-T62).

Frame: the generator's (x to starboard, y up from the spine's axis, z aft from the boom's tip); the reference is moved onto
it by :data:`REFERENCE_AXIS` (its box is centred, its axis is not). A window is (u0, u1, v0, v1) in the plane's (u, v).

The reference's command block is a shell of armour plates round loose inner parts, open at the front, so its planes are
compared by outline (each row filled between its outermost edges): the armour's hexagon and the strakes through it.
"""

from __future__ import annotations

from tools.refview.sections import SectionPlane

REFERENCE_AXIS = (0.0, 43.3, 0.0)  # the spine's axis from the middle of the reference's box (to starboard, up), m at 1 502.1 m
REFERENCE_MAPPING = {"right": "-x", "up": "+z", "aft": "+y"}
GIRDER = (-100.0, 100.0, -70.0, 70.0)


def _z(name: str, z: float, window: tuple[float, float, float, float], **kw: object) -> SectionPlane:
    return SectionPlane(f"{name}_z{z:.0f}", 2, z, window, **kw)


PLANES: dict[str, list[SectionPlane]] = {
    "command_block": [_z("command", z, (-75.0, 75.0, -180.0, 100.0), outline=True) for z in (240.0, 270.0, 300.0, 350.0)],
    "keel_wedge": [_z("wedge", 270.0, (-60.0, 60.0, -175.0, -50.0))],
    "tankage": [_z("tank", z, (-55.0, 55.0, -108.0, -38.0)) for z in (205.0, 210.0)],
    # The starboard retro thruster's oval nozzle as the bow sees it, in a window round its outline.
    "retro_thrusters": [_z("retro_r", z, (3.0, 26.0, -106.0, -54.0), relief=True) for z in (190.0, 225.0)],
    "flank_wing": [_z("wing", 380.0, (-95.0, 95.0, -30.0, 70.0))],
    "forward_spine": [_z("spine_fore", z, GIRDER) for z in (420.0, 500.0)],
    "ring_lugs": [_z("ring", z, GIRDER) for z in (465.0, 835.0, 944.0)],
    "collars": [_z("collar", z, GIRDER) for z in (540.0, 760.0)],
    # 575 m: the block's fore end, whole again since its bays moved to the bow (M10-T23 fix).
    "hangar_block": [_z("hangar", z, (-80.0, 80.0, -80.0, 80.0)) for z in (575.0, 600.0, 624.0, 650.0, 677.0, 725.0)],
    "aft_spine": [_z("spine_aft", z, GIRDER) for z in (800.0, 900.0, 1000.0, 1060.0)],
    "engine_housing": [_z("housing", z, (-115.0, 115.0, -110.0, 110.0)) for z in (1130.0, 1170.0, 1200.0, 1225.0)],
    "engines": [_z("engines", z, (-110.0, 110.0, -110.0, 110.0)) for z in (1260.0, 1300.0, 1350.0, 1400.0, 1440.0)],
}
# Planes a part may fail, each with the reason the maintainer accepted. None yet.
EXEMPT: dict[str, str] = {}


# The bow face (M10-T67, T66's sweeps): outline cuts every ``step`` metres across ``span``, in ``window`` (None: both meshes),
# and the front depth map over FACE_BOX. The x and y cuts see the face only, from the bow to the armour's end (z 150 to 380).
FACE_SWEEPS: dict[str, tuple[tuple[float, float], float, tuple[float, float, float, float] | None]] = {
    "z": ((150.0, 450.0), 4.0, None),
    "x": ((-70.0, 70.0), 5.0, (150.0, 380.0, -185.0, 100.0)),
    "y": ((-175.0, 95.0), 5.0, (-75.0, 75.0, 150.0, 380.0)),
}
FACE_BOX = (-75.0, 75.0, -180.0, 100.0, 150.0, 450.0)
# The floors the face holds today (the maintainer's target is every slice >= 0.90; see docs/assets-capital.md, "ea_nova"):
# each sweep's mean IoU, and the depth map's share within 2 m and its mean difference (m).
FACE_MEAN_IOU = {"z": 0.945, "x": 0.835, "y": 0.95}
FACE_DEPTH = {"within_tolerance": 0.61, "mean_abs_depth_diff_m": 7.8}

__all__ = ["EXEMPT", "FACE_BOX", "FACE_DEPTH", "FACE_MEAN_IOU", "FACE_SWEEPS", "PLANES", "REFERENCE_AXIS", "REFERENCE_MAPPING"]
