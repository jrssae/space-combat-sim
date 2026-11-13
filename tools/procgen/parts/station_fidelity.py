"""The station's per-part section check (M7-T21, CLAUDE.md "STL fidelity"): the planes each part seen up close is cut at, against the
reference STL, with ``tools/refview/sections.py``. Station frame (z aft from the bow tip, x starboard, y up); a window (u0, u1, v0,
v1) in the plane's (u, v) round the part, clear of other parts where it can be (a Cobra arm's window starts over the drum's skin).
Each Cobra arm is cut in its own frame: turned onto the top before the cut, so one set of windows serves all four.

Exemptions: planes a part may fail for a reason the maintainer accepted, with that reason.
"""

from __future__ import annotations

from tools.refview.sections import SectionPlane

from . import station as st

ARM_PLANES = (  # (name, z, window: x from, x to, y from, y to, outline) on an arm standing on top
    # The head's planes compare outlines: the STL's circular hatch is a recess in the peak.
    ("head_760", 760.0, (-90.0, 90.0, 265.0, 335.0), True),
    ("head_800", 800.0, (-90.0, 90.0, 280.0, 335.0), True),
    ("neck_900", 900.0, (-70.0, 70.0, 265.0, 300.0), False),
    ("neck_960", 960.0, (-70.0, 70.0, 229.0, 275.0), False),
    ("root_1030", 1030.0, (-55.0, 55.0, 194.0, 246.0), False),
    # Through the launch halls (T05, approved: the hall seen through an open door, the second row inside), which the STL leaves
    # solid round its door shafts: the outline is compared, so the section's shape still counts.
    ("root_1060", 1060.0, (-55.0, 55.0, 194.0, 246.0), True),
    ("root_1101", 1101.5, (-55.0, 55.0, 194.0, 246.0), True),
    ("root_1240", 1240.0, (-55.0, 55.0, 194.0, 246.0), False),
)
WINGS = ("alpha", "beta", "delta", "zeta")


def arm_planes() -> list[SectionPlane]:
    """Each arm's planes, the arm turned onto the top (alpha is already there)."""
    out = []
    for wing, angle in zip(WINGS, st.ARM_ANGLES_DEG, strict=True):
        for name, z, window, outline in ARM_PLANES:
            out.append(SectionPlane(f"arm_{wing}_{name}", 2, z, window, turn_deg=90.0 - angle, outline=outline))
    return out


PLANES: dict[str, list[SectionPlane]] = {
    "cobra_arms": arm_planes(),
    "main_docking_bay": [
        SectionPlane("main_docking_bay_z455", 2, 455.0, (-140.0, 140.0, -140.0, 140.0)),
        SectionPlane("main_docking_bay_z470", 2, 470.0, (-140.0, 140.0, -140.0, 140.0)),
        SectionPlane("main_docking_bay_z520", 2, 520.0, (-140.0, 140.0, -140.0, 140.0)),
        SectionPlane("main_docking_bay_side", 0, 0.0, (440.0, 660.0, -130.0, 130.0)),
    ],
    "cargo_bay": [
        SectionPlane("cargo_bay_z430", 2, 430.0, (-110.0, 110.0, 300.0, 380.0), outline=True),
        SectionPlane("cargo_bay_z465", 2, 465.0, (-110.0, 110.0, 300.0, 380.0), outline=True),
        SectionPlane("cargo_bay_side", 0, 0.0, (400.0, 500.0, 300.0, 380.0), outline=True),
        SectionPlane("cargo_bay_top", 1, 340.0, (-110.0, 110.0, 400.0, 500.0), outline=True),
    ],
    "dorsal_spine": [
        SectionPlane("spine_z1500", 2, 1500.0, (-200.0, 200.0, 340.0, 600.0)),
        SectionPlane("spine_z2000", 2, 2000.0, (-200.0, 200.0, 425.0, 600.0)),
        SectionPlane("spine_z2650", 2, 2650.0, (-200.0, 200.0, 340.0, 600.0)),
        SectionPlane("spine_z4500", 2, 4500.0, (-200.0, 200.0, 340.0, 600.0)),
        SectionPlane("spine_z5650", 2, 5650.0, (-200.0, 200.0, 350.0, 600.0)),
    ],
    "command_section": [
        SectionPlane("bow_z200", 2, 200.0, (-200.0, 200.0, 290.0, 400.0)),
        SectionPlane("bow_z400", 2, 400.0, (-200.0, 200.0, 290.0, 400.0)),
        SectionPlane("command_z600", 2, 600.0, (-200.0, 200.0, 300.0, 480.0)),
        SectionPlane("command_z1000", 2, 1000.0, (-200.0, 200.0, 300.0, 480.0)),
        SectionPlane("command_z1150", 2, 1150.0, (-200.0, 200.0, 300.0, 480.0)),
        SectionPlane("command_z1250", 2, 1250.0, (-200.0, 200.0, 300.0, 480.0)),
    ],
}

# Plane name -> the accepted reason it may score under 0.90.
EXEMPTIONS: dict[str, str] = {
    "main_docking_bay_z455": "the main docking bay is built from the maintainer's show references (T05, approved), not the STL's door",
    "main_docking_bay_z470": "the main docking bay is built from the maintainer's show references (T05, approved), not the STL's door",
    "main_docking_bay_z520": "the main docking bay is built from the maintainer's show references (T05, approved), not the STL's door",
    "main_docking_bay_side": "the main docking bay is built from the maintainer's show references (T05, approved), not the STL's door",
    "cargo_bay_side": "the throat and compartment are open for the pods (Q8 as refined; the maintainer: 'open only where the pods "
                      "enter'); the STL shuts the throat with a door plate",
}


def all_planes() -> list[SectionPlane]:
    return [p for planes in PLANES.values() for p in planes]


__all__ = ["ARM_PLANES", "EXEMPTIONS", "PLANES", "all_planes", "arm_planes"]
