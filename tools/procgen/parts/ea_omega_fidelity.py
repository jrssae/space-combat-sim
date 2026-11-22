"""The Omega's per-part section check (M10-T21; CLAUDE.md, "STL fidelity"): the planes each part seen up close is cut at,
against the reference model, with ``tools/refview/sections.py`` (the measure for open shells, M10-T62).

Frame: the generator's (x to starboard, y up from the spine's axis, z aft from the boom's tip); the reference is moved onto
it by :data:`REFERENCE_AXIS_Y` (its box is centred, its axis is not). A window is (u0, u1, v0, v1) in the plane's (u, v).

The rotating section is compared with the build turned as the reference has it (``drum_deg`` -45) and both turned back by
:data:`DRUM_TURN_DEG`, so its arms lie along x in the window. The reference's shells there are open and the measure fills
the space between the two arms' inner faces, so each arm and the hub are cut in windows of their own.
"""

from __future__ import annotations

from tools.refview.sections import SectionPlane

REFERENCE_AXIS_Y = 35.58  # the spine's axis above the middle of the reference's box, m at 1 714.3 m
REFERENCE_MAPPING = {"right": "+y", "up": "+z", "aft": "+x"}
DRUM_TURN_DEG = 45.0
SPINE = (-80.0, 80.0, -70.0, 70.0)
ARM = (80.0, 320.0, -110.0, 110.0)
TANK = (0.0, 40.0, -150.0, -58.0)  # the starboard reactant tank and the beam under it
BAY = (-50.0, 50.0, -30.0, 30.0)  # the launch bay's mouth and the tube round it


def _z(name: str, z: float, window: tuple[float, float, float, float], **kw: object) -> SectionPlane:
    return SectionPlane(f"{name}_z{z:.0f}", 2, z, window, **kw)


PLANES: dict[str, list[SectionPlane]] = {
    # The launch bay's hall runs through the bow block and the command section (182 to 318 m). The reference's hall is open
    # shells that its winding fills, so these planes compare the block's outline and the hall is judged by relief, as the
    # bow sees its mouth.
    "bow_block": [_z("bow_block", z, (-75.0, 75.0, -60.0, 100.0), outline=True) for z in (255.0, 285.0)],
    "fore_bay": [_z("bay", z, BAY, relief=True) for z in (250.0, 300.0)],
    # The reference's tanks are open shells ahead of z 270, so the forward plane is compared by its outline.
    "tankage": [_z("tank_r", 250.0, TANK, outline=True), _z("tank_r", 280.0, TANK)],
    # The starboard retro thruster's oval nozzle as the bow sees it, in a window round its outline.
    "retro_thrusters": [_z("retro_r", z, (5.0, 32.0, -126.0, -64.0), relief=True) for z in (200.0, 240.0)],
    "command_section": [_z("command", 300.0, (-80.0, 80.0, -70.0, 100.0), outline=True), _z("command", 340.0, (-80.0, 80.0, -70.0, 100.0))],
    "forward_spine": [_z("spine_fore", z, SPINE) for z in (448.0, 498.0)],
    "collars": [_z("collar", z, (-100.0, 100.0, -100.0, 100.0)) for z in (530.0, 900.0)],
    "drum_arms": [*(_z("arm_r", z, ARM, turn_deg=DRUM_TURN_DEG) for z in (620.0, 717.0, 800.0)),
                  *(_z("arm_l", z, (-ARM[1], -ARM[0], ARM[2], ARM[3]), turn_deg=DRUM_TURN_DEG) for z in (620.0, 717.0, 800.0))],
    "drum_hub": [_z("hub", z, (-78.0, 78.0, -64.0, 64.0), turn_deg=DRUM_TURN_DEG) for z in (620.0, 717.0, 800.0)],
    "aft_spine": [_z("spine_aft", z, SPINE) for z in (945.0, 1055.0, 1100.0, 1175.0, 1210.0)],
    "engine_housing": [_z("housing", z, (-115.0, 115.0, -110.0, 110.0)) for z in (1260.0, 1300.0, 1345.0)],
    "engines": [_z("engines", z, (-105.0, 105.0, -90.0, 90.0)) for z in (1420.0, 1540.0, 1590.0, 1630.0)],
}
# Planes a part may fail, each with the reason the maintainer accepted. None yet.
EXEMPT: dict[str, str] = {}

__all__ = ["DRUM_TURN_DEG", "EXEMPT", "PLANES", "REFERENCE_AXIS_Y", "REFERENCE_MAPPING"]
