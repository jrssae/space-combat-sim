"""The Asimov liner's per-part section check (M10-T53; CLAUDE.md, "STL fidelity"): the planes each part seen up close is cut at,
against the reference model, with ``tools/refview/sections.py``.

Frame: the generator's (x to starboard, y up from the sphere's axis, z aft from the saucer's nose), which is the reference's own at
600 m with the mapping below (its box is centred on the sphere). A window is (u0, u1, v0, v1) in the plane's (u, v).
"""

from __future__ import annotations

from tools.refview.sections import SectionPlane

REFERENCE_MAPPING = {"right": "-x", "up": "+z", "aft": "+y"}
SPHERE = (-180.0, 180.0, -180.0, 180.0)
FACE = (-100.0, 100.0, -100.0, 100.0)


def _z(name: str, z: float, window: tuple[float, float, float, float], **kw: object) -> SectionPlane:
    return SectionPlane(f"{name}_z{z:.0f}", 2, z, window, **kw)


PLANES: dict[str, list[SectionPlane]] = {
    "saucer": [_z("saucer", z, (-55.0, 55.0, 14.0, 70.0)) for z in (20.0, 45.0, 70.0)],
    "spine": [_z("spine", z, (-60.0, 60.0, 14.0, 86.0)) for z in (105.0, 130.0, 150.0, 170.0)],
    "spine_side": [SectionPlane("spine_x0", 0, 0.0, (20.0, 180.0, 14.0, 90.0))],
    # The face: the collar and its teeth as the bow sees them (the reference leaks stripes across the recessed disc in a plain cut
    # there), the rim round the recessed disc, and the disc with the hexagonal mouth. The build has the show's deep bowl there
    # (EXEMPT); the mouth is held where the build has it, in the bowl's floor (215 m).
    "forward_face": [_z("face_collar", 178.0, FACE, relief=True), _z("face_rim", 181.5, FACE), _z("face_mouth", 200.0, SPHERE)],
    "hex_mouth": [_z("mouth", z, (-40.0, 40.0, -50.0, 5.0)) for z in (190.0, 215.0)],
    "sphere": [_z("sphere", z, SPHERE) for z in (250.0, 300.0, 330.0, 380.0, 420.0, 460.0)],
    "bands": [_z("groove", z, SPHERE) for z in (236.0, 428.0)],
    # The reference's nacelles are inside-out where they run into the sphere, so its sections there leave them as holes: the frame's
    # planes compare outlines.
    "engine_frame": [_z("frame", z, (-110.0, 110.0, -110.0, 110.0), outline=True) for z in (490.0, 505.0)],
    # The bells' thin open walls are judged along their length (a cut through the upper row's axes), where a plane across them
    # would only weigh their rims.
    "engines": [*(_z("engines", z, (-80.0, 80.0, -75.0, 75.0)) for z in (520.0, 540.0, 560.0, 575.0)),
                SectionPlane("engines_y38", 1, 37.5, (-80.0, 80.0, 470.0, 600.0))],
}
# Planes a part may fail, each with the reason the maintainer accepted.
_BOWL = "Q95: the forward face has the show's deep bowl, not the reference's shallow recessed disc (screen-plausible, the face only)"
EXEMPT: dict[str, str] = {"face_collar_z178": _BOWL, "face_rim_z182": _BOWL, "face_mouth_z200": _BOWL, "mouth_z190": _BOWL}

__all__ = ["EXEMPT", "PLANES", "REFERENCE_MAPPING"]
