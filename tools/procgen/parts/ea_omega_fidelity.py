"""The Omega's fidelity check against its reference (M10-T68; CLAUDE.md, "STL fidelity"): the four-part print kit assembled by
``tools/refview/kit.py`` (``tools/refview/kits/ea_omega.json``: 16.876 m a millimetre, the stern at 1 714.3 m, the rotating
section's arms up and down as the kit's glue faces put them), its triangles at ``references/EA Omega kit assembled.npy``
(gitignored; ``python3 -m tools.refview.kit build ea_omega`` writes it).

Frame: the generator's (x to starboard, y up from the spine's axis, z aft from the probe's tip). A window is (u0, u1, v0, v1) in the
plane's (u, v). Most planes compare outlines (each row filled between its outermost edges): the kit's parts are printed hollow
and its faces carry greebles a print shows and a hull's plating paints. The spine's planes stand clear of its gun mounts (the
maintainer's turrets, which the kit does not carry).

The kit's launch bay is a print's shallow hall (its back wall at 244 m); the build's runs on to 322 m for its 32 Starfuries, so the
face's sweeps and depth map score the build's hall as closed at the kit's wall (:data:`BAY_PLUG`).
"""

from __future__ import annotations

from tools.refview.sections import SectionPlane

KIT = "EA Omega kit assembled.npy"  # under references/
METRES_PER_MM = 16.876
SPINE = (-80.0, 80.0, -75.0, 75.0)
ARM_TOP, ARM_LOW = (-115.0, 115.0, 75.0, 320.0), (-115.0, 115.0, -320.0, -75.0)
BOW = (-110.0, 110.0, -200.0, 105.0)


def _z(name: str, z: float, window: tuple[float, float, float, float], **kw: object) -> SectionPlane:
    return SectionPlane(f"{name}_z{z:.0f}", 2, z, window, **kw)


PLANES: dict[str, list[SectionPlane]] = {
    "bow_face": [_z("face", z, BOW, outline=True) for z in (190.0, 210.0)],
    "bow_block": [_z("bow_block", z, BOW, outline=True) for z in (255.0, 285.0)],
    # The bay: its frame's octagon at the face, and its mouth as the bow sees it ahead of the kit's back wall.
    "fore_bay": [_z("bay_frame", 196.0, (-50.0, 50.0, -30.0, 25.0), outline=True), _z("bay", 240.0, (-50.0, 50.0, -30.0, 30.0), relief=True)],
    "tankage": [_z("tank_r", z, (0.0, 45.0, -150.0, -58.0), outline=True) for z in (250.0, 280.0)],
    "retro_thrusters": [_z("retro_r", z, (5.0, 35.0, -130.0, -60.0), relief=True) for z in (200.0, 240.0)],
    "command_section": [_z("command", z, (-80.0, 80.0, -75.0, 100.0), outline=True) for z in (300.0, 340.0)],
    "forward_spine": [_z("spine_fore", z, SPINE, outline=True) for z in (440.0, 455.0, 500.0)],
    "collars": [_z("collar", z, (-100.0, 100.0, -100.0, 100.0)) for z in (545.0, 890.0)],
    "drum_arms": [*(_z("arm_top", z, ARM_TOP, outline=True) for z in (620.0, 717.0, 820.0)),
                  *(_z("arm_low", z, ARM_LOW, outline=True) for z in (620.0, 717.0, 820.0))],
    "drum_hub": [_z("hub", z, (-80.0, 80.0, -75.0, 75.0), outline=True) for z in (620.0, 717.0, 820.0)],
    "aft_spine": [_z("spine_aft", z, SPINE, outline=True) for z in (950.0, 1060.0, 1100.0, 1180.0, 1225.0)],
    "engine_housing": [_z("housing", z, (-120.0, 120.0, -120.0, 120.0), outline=True) for z in (1260.0, 1320.0, 1380.0)],
    "engines": [_z("engines", z, (-115.0, 115.0, -115.0, 115.0), outline=True) for z in (1440.0, 1480.0, 1540.0, 1600.0, 1640.0)],
}
# Planes a part may fail, each with the reason the maintainer accepted. None.
EXEMPT: dict[str, str] = {}

# The bow face (T66's sweeps, as the Nova's): cuts every ``step`` metres across ``span``, in ``window`` (None: both meshes), and the
# front depth map over FACE_BOX. The z sweep starts at the bay's frame (ahead of it stands only the probe, which the kit prints
# short); the x cuts are scored by face depth (each line filled from its first surface aft), the z and y cuts by outline.
FACE_SWEEPS: dict[str, tuple[tuple[float, float], float, tuple[float, float, float, float] | None]] = {
    "z": ((182.0, 450.0), 4.0, None),
    "x": ((-70.0, 70.0), 5.0, (150.0, 380.0, -200.0, 105.0)),
    "y": ((-190.0, 100.0), 5.0, (-75.0, 75.0, 150.0, 380.0)),
}
FACE_BY_DEPTH = {"z": False, "x": True, "y": False}
FACE_BOX = (-75.0, 75.0, -195.0, 100.0, 150.0, 450.0)
BAY_PLUG = ((-37.0, -21.5, 244.0), (37.0, 15.5, 250.0))  # the kit's back wall across the build's hall, for the face's scores
# The floors the face holds (the maintainer's bar is 0.90 a slice; the slices under it are the spine's turret mounts at 374 to
# 438 m, the shields' outer edges and the keel's tip, docs/assets-capital.md): each sweep's mean IoU, and the depth map's share
# within 2 m and its mean difference (m).
FACE_MEAN_IOU = {"z": 0.92, "x": 0.91, "y": 0.93}
FACE_DEPTH = {"within_tolerance": 0.55, "mean_abs_depth_diff_m": 6.0}

__all__ = ["BAY_PLUG", "EXEMPT", "FACE_BOX", "FACE_BY_DEPTH", "FACE_DEPTH", "FACE_MEAN_IOU", "FACE_SWEEPS", "KIT", "METRES_PER_MM", "PLANES"]
