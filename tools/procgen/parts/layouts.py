"""The hulls' surface layouts: per part, the seams, hatches, ribs and plating read off the show's references (the civilians,
M5-T40, docs/assets-civilian.md "Surface layouts"; the Starfury and the raider, M7-T15, their asset docs' "Surface"). Each function
returns the layouts by part name, in the frame the part is built in.

Levels (``core/seams.py``): 1 the major breaks (all the low texture set draws), 2 the references' seam density with hatches and
ribs, 3 the plating texture: plate to plate tone, sheen and grime, small proud hatches. The full set draws all three. Parts not
named stay plain: trusses, antennas, nozzles, turrets, and the civilians' arms and struts.
"""

from __future__ import annotations

import math
from collections.abc import Iterable

from ..core.seams import EMPTY, Cut, Feature, Hatch, Hoop, Path, Plates, SeamLayout, every, rings, spokes
from . import Part

INF = float("inf")
UP, DOWN, OUT, IN = (0.0, 1.0, 0.0), (0.0, -1.0, 0.0), (1.0, 0.0, 0.0), (-1.0, 0.0, 0.0)
X, Y, Z = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)


def dress(parts: Iterable[Part], layouts: dict[str, SeamLayout]) -> None:
    """Gives every named part its layout, before the generator places or mirrors it."""
    for part in parts:
        part.seams = layouts.get(part.name, EMPTY)


def _zbox(z0: float, z1: float) -> dict[str, tuple[float, float, float]]:
    return {"lo": (-INF, -INF, z0), "hi": (INF, INF, z1)}


def _plating(lines_level: int, tone: float, **kw: object) -> list[Feature]:
    """Mixed-size plating twice over: its seams at ``lines_level``, its tone, sheen and grime at level 3 on the same plates."""
    paint = {k: kw.pop(k) for k in ("sheen", "grime", "grime_m", "proud") if k in kw}
    return [
        Plates(**{**kw, "level": lines_level, "tone": 0.0, "sheen": 0.0}),
        Plates(**{**kw, **paint, "level": 3, "tone": tone, "depth": 0.0, "dark": 0.0}),
    ]


def _hatches(cell: tuple[float, float], share: float, seed: int, **kw: object) -> Plates:
    """Small plates standing proud here and there: the clusters of access hatches on the references."""
    return Plates(level=3, cell=cell, splits=1, min_m=0.5, scatter=share, inset_m=0.16 * min(cell), tone=0.05, dark=0.7, depth=0.7,
                  seed=seed, **kw)


# --- Earth Alliance: the Saturn family ---------------------------------------------------------------------------------
def saturn(cylinder_radius: float, dome_depth: float, cylinder_length: float, pod_length: float, pod_band: float,
           disc_centre_z: float) -> dict[str, SeamLayout]:
    """The shared Saturn parts, each in its own frame: the hull cylinder (also every tank), the cargo pod, the command disc."""
    r, d, length = cylinder_radius, dome_depth, cylinder_length
    b0, b1 = d, length - d
    course = (b1 - b0) / 12.0
    axis = (0.0, 0.0, 0.0)
    cylinder: list[Feature] = [
        # Low: the breaks at the paint bands' edges, where the barrel's sections join.
        *rings(2, [b0, b0 + 4 * course, b0 + 8 * course, b1], level=1, width=1.4),
        # Full: plate courses round each band, six strakes, petals on the domes, a hatch on each band's back.
        *rings(2, [b0 + k * course for k in range(1, 12) if k % 4], level=2),
        *spokes(2, axis, range(0, 360, 60), span=(b0, b1), level=2),
        *spokes(2, axis, range(30, 360, 60), span=(1.2, b0), level=2),
        *spokes(2, axis, range(30, 360, 60), span=(b1, length - 1.2), level=2),
        Cut(axis=2, at=0.45 * d, level=2), Cut(axis=2, at=length - 0.45 * d, level=2),
        *[Hatch(centre=(0.0, r, b0 + (4 * k + 1.5) * course), right=Z, up=X, size=(2.8, 1.9), corner_m=0.25, facing=UP, min_dot=0.9, level=2)
          for k in range(3)],
        *[Hatch(centre=(r, 0.0, b0 + (4 * k + 2.5) * course), right=Z, up=Y, size=(2.2, 2.6), corner_m=0.25, facing=OUT, min_dot=0.9, level=2)
          for k in range(3)],
        # Plating: each course cut into plates of mixed length, toned plate by plate, grime in the joints.
        Plates(level=3, wrap="barrel", axis=2, radius=r, around=12, cell=(course, 0.0), offset=(b0, 0.0), splits=2, min_m=1.3, keep=0.3,
               tone=0.07, sheen=0.08, grime=0.12, grime_m=0.45, depth=0.6, dark=0.55, seed=11, **_zbox(b0, b1)),
        _hatches((2.6, 1.7), 0.07, 13, wrap="barrel", axis=2, radius=r, around=32, **_zbox(b0, b1)),
    ]

    # The pod frame: u outboard from the inboard face, v up, w along its length.
    plen, band = pod_length, pod_band
    w0, w1 = band + 1.6, plen - band - 1.6
    slat = 2.46
    third = (w1 - w0) / 3.0
    pod: list[Feature] = [
        # Low: the frame round each face and the break at the pod's middle.
        Cut(axis=2, at=w0, level=1, width=1.4), Cut(axis=2, at=w1, level=1, width=1.4), Cut(axis=2, at=0.5 * plen, level=1, width=1.4),
        # Full: the faces' long slats inside the frame, the ribbed posts at each end, the belt along the flanks.
        *[Cut(axis=0, at=u, level=2, **_zbox(w0, w1)) for u in every(slat, 12 * slat, slat)],
        Cut(axis=1, at=0.0, level=2, **_zbox(w0, w1)),
        *rings(2, [band + 0.5, band + 1.05, plen - band - 0.5, plen - band - 1.05], level=2, depth=-0.8, flat_m=0.1),
        *rings(2, [w0 + third, w1 - third], level=2, width=0.8),
        # Plating: the slats as separate planks, each its own grey, dirt along their joints.
        Plates(level=3, wrap="sides", long_axis=2, cell=(third, slat), offset=(w0, 0.0), splits=1, min_m=2.0, keep=0.35, tone=0.09,
               sheen=0.08, grime=0.14, grime_m=0.5, depth=0.5, dark=0.5, seed=23, **_zbox(w0, w1)),
        _hatches((2.4, 1.2), 0.05, 29, wrap="sides", long_axis=2, **_zbox(w0, w1)),
    ]

    hub = (0.0, 0.0, disc_centre_z)
    disc: list[Feature] = [
        # Low: the rings where the lens's plating changes: round the fins and round the red ring.
        Hoop(axis=1, centre=hub, radius=7.3, level=1, width=1.4), Hoop(axis=1, centre=hub, radius=11.0, level=1, width=1.4),
        # Full: two more rings and the radial joints out from the fins.
        Hoop(axis=1, centre=hub, radius=9.15, level=2), Hoop(axis=1, centre=hub, radius=12.85, level=2),
        *spokes(1, hub, range(0, 360, 30), reach=(7.3, 13.7), level=2),
        # Plating: the ring sectors as plates of their own tone.
        Plates(level=3, wrap="polar", axis=1, centre=hub, radius=10.0, around=12, cell=(1.85, 0.0), offset=(7.3, 0.0), splits=1, min_m=0.8,
               keep=0.5, tone=0.06, sheen=0.08, grime=0.10, grime_m=0.35, depth=0.5, dark=0.5, seed=31),
    ]
    box = [*_plating(2, 0.07, wrap="sides", cell=(5.0, 3.2), splits=2, min_m=1.0, keep=0.35, grime=0.10, grime_m=0.4, seed=37)]
    drum = [*rings(2, [44.6, 47.4], level=2), Plates(level=3, wrap="sides", cell=(2.7, 2.5), offset=(41.9, 0.0), splits=1, tone=0.06,
                                                    depth=0.0, dark=0.0, seed=41)]
    return {
        "cylinder": SeamLayout.of(cylinder), "tank": SeamLayout.of(cylinder), "pod": SeamLayout.of(pod), "disc": SeamLayout.of(disc),
        "junction_module": SeamLayout.of(box), "junction_spine": SeamLayout.of(box), "junction_low": SeamLayout.of(box),
        "pod_block_low": SeamLayout.of(box), "pod_block_top": SeamLayout.of(box),
        "drum_top": SeamLayout.of(drum), "drum_low": SeamLayout.of(drum), "drum_truss": SeamLayout.of(drum),
    }


def saturn_engine(k: float) -> dict[str, SeamLayout]:
    """The engine section at scale ``k``, from its collar's front: the collar's ribs and the core tank's girth seams."""
    collar = [
        Cut(axis=2, at=3.25 * k, level=1, width=1.4),
        *rings(2, [z * k for z in (1.1, 2.15, 4.35, 5.4)], level=2, depth=-0.8, flat_m=0.12 * k),
        *spokes(2, (0.0, 0.0, 0.0), range(0, 360, 45), span=(0.5 * k, 6.0 * k), level=2),
        Plates(level=3, wrap="barrel", axis=2, radius=4.8 * k, around=8, cell=(3.25 * k, 0.0), splits=1, tone=0.07, depth=0.0, dark=0.0, seed=43),
    ]
    tank = [Cut(axis=2, at=8.2 * k, level=1), *rings(2, [5.0 * k, 11.4 * k], level=2)]
    return {"engine_collar": SeamLayout.of(collar), "engine_core_tank": SeamLayout.of(tank)}


# --- Earth Alliance: the Skylark ---------------------------------------------------------------------------------------
def skylark() -> dict[str, SeamLayout]:
    """The Skylark's parts in the ship's authored frame (the right-hand parts; their twins mirror)."""
    cap = (0.0, -0.45, 0.0)
    capsule: list[Feature] = [
        # Low: the rings either side of each paint band and the barrel's middle joint.
        *rings(2, [6.6, 7.8, 15.6, 16.8], level=1, width=1.3), Cut(axis=2, at=11.7, level=1),
        # Full: the barrel's panel courses and strakes, petals on both domes, the ribbed neck and spine, the cabin's sunk ports.
        *rings(2, [9.1, 10.4, 13.0, 14.3], level=2),
        *spokes(2, cap, range(0, 360, 30), span=(7.8, 15.6), level=2),
        *spokes(2, cap, [22.5 + 45.0 * k for k in range(8)], span=(3.4, 6.6), level=2),
        *spokes(2, cap, [22.5 + 45.0 * k for k in range(8)], span=(16.8, 20.2), level=2),
        Cut(axis=2, at=4.6, level=2), Cut(axis=2, at=19.0, level=2),
        *rings(2, every(21.6, 28.8, 1.2), level=2, depth=-0.7, flat_m=0.08),
        *[Hatch(centre=(3.7, 0.25, z), right=Z, up=Y, size=(0.95, 0.6), corner_m=0.12, sunk=1.6, tone=0.45, facing=OUT, min_dot=0.85, level=2)
          for z in (9.75, 11.05, 12.35, 13.65)],
        # Plating: the courses broken into panels of mixed size, each its own shade of the sand paint.
        Plates(level=3, wrap="barrel", axis=2, centre=cap, radius=3.73, around=12, cell=(1.3, 0.0), offset=(7.8, 0.0), splits=2, min_m=0.45,
               keep=0.3, tone=0.08, sheen=0.08, grime=0.10, grime_m=0.2, depth=0.6, dark=0.5, seed=3, **_zbox(7.8, 15.6)),
        Plates(level=3, wrap="barrel", axis=2, centre=cap, radius=3.73, around=8, cell=(1.6, 0.0), splits=1, tone=0.07, depth=0.0, dark=0.0,
               seed=5, **_zbox(1.7, 6.6)),
        Plates(level=3, wrap="barrel", axis=2, centre=cap, radius=3.73, around=8, cell=(1.6, 0.0), splits=1, tone=0.07, depth=0.0, dark=0.0,
               seed=6, **_zbox(16.8, 21.4)),
    ]
    capsule_layout = _centre(capsule, mirrored=lambda f: isinstance(f, Hatch))

    tank_axis = (5.44, -0.45, 0.0)
    tank: list[Feature] = [
        *rings(2, [21.4, 23.8, 25.0, 27.6], level=1, width=1.3),
        *rings(2, [22.6, 26.3], level=2),
        *spokes(2, tank_axis, range(0, 360, 45), span=(21.4, 27.6), level=2),
        *rings(2, every(29.9, 34.4, 0.9), level=2, depth=-0.7, flat_m=0.07),
        Plates(level=3, wrap="barrel", axis=2, centre=tank_axis, radius=2.16, around=8, cell=(1.2, 0.0), offset=(21.4, 0.0), splits=1, min_m=0.4,
               tone=0.08, sheen=0.08, grime=0.10, grime_m=0.2, depth=0.6, dark=0.5, seed=7, **_zbox(21.4, 27.6)),
    ]
    nac = (13.03, -0.26, 0.0)
    nacelle: list[Feature] = [
        *rings(2, [42.0, 46.0], level=1, width=1.3),
        *rings(2, [z for z in every(40.0, 49.0, 1.0) if z not in (42.0, 46.0)], level=2, width=0.8),
        *spokes(2, nac, range(0, 360, 30), span=(39.6, 49.4), level=2),
        Plates(level=3, wrap="barrel", axis=2, centre=nac, radius=2.5, around=12, cell=(2.0, 0.0), offset=(40.0, 0.0), splits=1, min_m=0.5,
               tone=0.08, sheen=0.08, grime=0.10, grime_m=0.2, depth=0.0, dark=0.0, seed=9, **_zbox(39.5, 49.5)),
    ]
    body_right: list[Feature] = [
        # Low: the slab's frames and the line the leading edge's plating follows.
        Cut(axis=2, at=38.5, level=1, width=1.3), Cut(axis=2, at=46.5, level=1, width=1.3),
        Path(points=((3.0, 0.0, 33.6), (5.9, 0.0, 34.6), (10.6, 0.0, 41.4), (10.6, 0.0, 46.5), (8.0, 0.0, 51.0)), facing=UP, level=1),
        # Full: a strake line, access hatches on the back, louvres along the flank and beside the ridge.
        Cut(axis=0, at=6.0, level=2, facing=UP, **_zbox(35.6, 51.0)),
        Cut(axis=2, at=42.5, level=2), Cut(axis=2, at=49.2, level=2),
        Hatch(centre=(4.5, 0.0, 40.4), right=X, up=Z, size=(1.9, 1.5), corner_m=0.2, facing=UP, level=2),
        Hatch(centre=(8.2, 0.0, 44.4), right=X, up=Z, size=(1.6, 2.4), corner_m=0.5, facing=UP, level=2),
        Hatch(centre=(4.6, 0.0, 48.0), right=X, up=Z, size=(1.6, 1.2), corner_m=0.2, facing=UP, level=2),
        Hatch(centre=(9.2, 0.0, 48.6), right=X, up=Z, size=(1.5, 3.4), slats=9, sunk=1.0, tone=0.8, facing=UP, level=2),
        Hatch(centre=(2.0, 0.0, 45.2), right=X, up=Z, size=(1.3, 2.8), slats=7, sunk=1.0, tone=0.8, facing=UP, level=2),
        Hatch(centre=(5.0, 0.0, 43.0), right=X, up=Z, size=(2.4, 1.6), corner_m=0.2, facing=DOWN, level=2),
        Hatch(centre=(8.0, 0.0, 47.0), right=X, up=Z, size=(1.8, 3.0), slats=8, sunk=1.0, tone=0.8, facing=DOWN, level=2),
    ]
    body = SeamLayout.of(body_right).mirrored_too(0) + SeamLayout.of([
        # Plating: angular plating in mixed sizes, toned plate by plate.
        Plates(level=3, wrap="sides", long_axis=2, cell=(4.0, 3.0), offset=(34.5, 0.0), splits=2, min_m=0.7, keep=0.3, tone=0.08, sheen=0.08,
               grime=0.10, grime_m=0.25, depth=0.6, dark=0.5, seed=15),
        _hatches((1.4, 0.9), 0.06, 17, wrap="sides", long_axis=2),
    ])
    fin = [Cut(axis=1, at=3.2, level=2), Cut(axis=2, at=48.0, level=2)]
    collar = [*rings(2, every(30.2, 34.2, 1.0), level=2, depth=-0.7, flat_m=0.08)]
    claw = [Plates(level=3, wrap="sides", long_axis=2, cell=(2.5, 1.5), splits=1, tone=0.07, depth=0.0, dark=0.0, seed=19)]
    return {
        "capsule": capsule_layout, "tank_r": SeamLayout.of(tank), "nacelle_r": SeamLayout.of(nacelle), "body": body,
        "dorsal_fin": SeamLayout.of(fin), "collar": SeamLayout.of(collar), "claw_out_r": SeamLayout.of(claw), "claw_in_r": SeamLayout.of(claw),
    }


def _centre(features: list[Feature], mirrored) -> SeamLayout:
    """A centre part's layout: the features ``mirrored`` picks are drawn on the right and copied to the left."""
    both = [f for f in features if mirrored(f)]
    return SeamLayout.of([f for f in features if not mirrored(f)]) + SeamLayout.of(both).mirrored_too(0)


# --- Narn ---------------------------------------------------------------------------------------------------------------
NARN_RIM = ((3.6, 15.3), (15.3, 22.0), (27.0, 23.0), (38.8, 19.1), (45.0, 15.5), (51.3, 6.7))  # the crescent's outline (z, half width)


def narn() -> dict[str, SeamLayout]:
    """The Narn transport's parts in the ship's authored frame, built as the Frazi fighter is (the maintainer, 2026-11-12): framed
    panels square to the ship's axes, a panel outlined inside a panel, and over all of it small rectangles in slightly varied
    shades of the part's own paint, with a few narrow bars standing proud."""

    def rim(inset: float, level: int, width: float = 1.0) -> list[Feature]:
        points = tuple((w - inset, 0.0, z) for z, w in NARN_RIM)
        return [Path(points=points, facing=side, level=level, width=width) for side in (UP, DOWN)]

    def outline(x: float, z: float, size: tuple[float, float], level: int = 1, sides: tuple = (UP, DOWN)) -> list[Feature]:
        """A panel's outline on the top and the belly, nothing sunk: the Frazi's panel inside a panel."""
        return [Hatch(centre=(x, 0.0, z), right=X, up=Z, size=size, corner_m=0.0, sunk=0.0, tone=1.0, facing=side, level=level)
                for side in sides]

    def rectangles(seed: int, tone: float = 0.10, cell: tuple[float, float] = (3.2, 2.4)) -> list[Feature]:
        """The Frazi's skin: small rectangles, each a slightly different shade, thin joints, narrow proud bars both ways."""
        return [
            *_plating(3, tone, wrap="sides", long_axis=2, cell=cell, splits=2, min_m=0.55, keep=0.25, sheen=0.08, grime=0.05, grime_m=0.2,
                      depth=0.3, dark=0.3, width=0.7, seed=seed),
            _hatches((2.6, 0.7), 0.07, seed + 1, wrap="sides", long_axis=2),
            _hatches((2.2, 0.6), 0.05, seed + 2, wrap="sides", long_axis=0),
        ]

    half: list[Feature] = [
        # Low: the trim line inside the rim, the frames across the plate, a framed panel on each half.
        *rim(2.2, 1, 1.4), Cut(axis=2, at=27.0, level=1, width=1.3), Cut(axis=2, at=38.8, level=1, width=1.3),
        *outline(17.2, 32.8, (4.4, 8.0)), *outline(16.4, 11.5, (2.6, 5.5)),
        # Full: a second line inside the first, a strake, more frames, the panels inside the framed ones.
        *rim(4.6, 2), Cut(axis=0, at=17.0, level=2, **_zbox(8.0, 27.0)),
        *rings(2, [8.0, 21.0, 33.0], level=2),
        *outline(17.2, 32.8, (2.4, 5.0), 2), *outline(16.4, 11.5, (1.3, 3.2), 2),
        *rectangles(51),
    ]
    centre: list[Feature] = [
        Cut(axis=2, at=27.0, level=1, width=1.3), Cut(axis=2, at=38.8, level=1, width=1.3),
        Cut(axis=0, at=6.8, level=1), Cut(axis=0, at=-6.8, level=1),
        *outline(0.0, 33.0, (7.0, 9.0)), *outline(9.9, 21.0, (3.4, 6.0)), *outline(-9.9, 21.0, (3.4, 6.0)),
        *rings(2, [21.0, 33.0, 45.0], level=2),
        *outline(0.0, 33.0, (4.0, 5.6), 2), *outline(9.9, 21.0, (1.8, 3.6), 2), *outline(-9.9, 21.0, (1.8, 3.6), 2),
        *rectangles(55),
    ]
    box: list[Feature] = [
        # Low: the box's frames at its paint panel's ends and middle, the belt along each side, a framed panel on the top and floor.
        *rings(2, [41.0, 51.0, 61.0], level=1, width=1.3), Cut(axis=1, at=0.0, level=1, **_zbox(36.0, 66.0)),
        *outline(0.0, 51.0, (13.0, 16.0)),
        # Full: the frames between, the lower belt, the strakes, the inner panels.
        *rings(2, [36.0, 46.0, 56.0, 66.0], level=2),
        Cut(axis=1, at=-4.25, level=2, **_zbox(36.0, 66.0)),
        *[Cut(axis=0, at=x, level=2, **_zbox(36.0, 69.0)) for x in (-8.5, 8.5)],
        *outline(0.0, 51.0, (8.0, 10.0), 2), *outline(0.0, 51.0, (3.4, 4.6), 2),
        *rectangles(59, 0.07),
    ]
    small = rectangles(63, 0.10, (2.4, 1.6))
    return {
        "crescent_r": SeamLayout.of(half), "crescent_centre": SeamLayout.of(centre), "box": SeamLayout.of(box),
        "cockpit": SeamLayout.of(small), "tower_r": SeamLayout.of(small), "fin_r": SeamLayout.of(small), "dorsal": SeamLayout.of(small),
    }


# --- Centauri -----------------------------------------------------------------------------------------------------------
def centauri() -> dict[str, SeamLayout]:
    """The Brezebel's parts in the ship's authored frame: long strakes of plates following the hull fore and aft."""
    strake = 3.25
    planks = dict(wrap="sides", long_axis=2, splits=2, min_m=1.4, keep=0.35, sheen=0.14, grime=0.05, grime_m=0.3)
    bow: list[Feature] = [
        # Low: two strake lines each side and the frame across the bow.
        *[Cut(axis=0, at=s * x, level=1, width=1.3) for s in (1.0, -1.0) for x in (2 * strake, 4 * strake)],
        Cut(axis=2, at=9.5, level=1, width=1.3),
        # Full: every strake, its plates butted at uneven stations; two hatches behind the dorsal fitting.
        *_plating(2, 0.08, cell=(9.5, strake), seed=71, **planks),
        Hatch(centre=(8.0, 0.0, 13.6), right=X, up=Z, size=(2.2, 2.8), corner_m=0.5, facing=UP, level=2),
        Hatch(centre=(-8.0, 0.0, 13.6), right=X, up=Z, size=(2.2, 2.8), corner_m=0.5, facing=UP, level=2),
    ]
    arm: list[Feature] = [
        *rings(2, [29.5, 40.0, 50.5], level=1, width=1.3),
        *_plating(2, 0.08, cell=(10.5, strake), offset=(19.0, 0.0), seed=73, **planks),
    ]
    fairing = [*_plating(2, 0.08, cell=(6.8, strake), offset=(22.1, 0.0), seed=75, **planks)]
    # The fins' plating runs across them in strips, as the Centauri fighters' wings are plated.
    fin_top = [Cut(axis=1, at=6.0, level=1), *rings(1, [3.5, 8.5, 11.0], level=2), Cut(axis=2, at=49.0, level=2),
               Plates(level=3, wrap="sides", long_axis=2, cell=(16.0, 2.5), offset=(41.0, 1.0), splits=1, min_m=2.0, tone=0.08, sheen=0.14,
                      depth=0.0, dark=0.0, seed=77)]
    fin_bot = [Cut(axis=1, at=-6.0, level=1), *rings(1, [-3.5, -8.5, -11.0], level=2), Cut(axis=2, at=49.0, level=2),
               Plates(level=3, wrap="sides", long_axis=2, cell=(16.0, 2.5), offset=(41.0, 1.5), splits=1, min_m=2.0, tone=0.08, sheen=0.14,
                      depth=0.0, dark=0.0, seed=79)]
    dorsal = [*_plating(2, 0.07, cell=(5.0, 2.4), seed=81, wrap="sides", long_axis=2, splits=1, min_m=1.0, sheen=0.14)]
    return {"bow": SeamLayout.of(bow), "arm_r": SeamLayout.of(arm), "fairing_r": SeamLayout.of(fairing), "fin_top_r": SeamLayout.of(fin_top),
            "fin_bot_r": SeamLayout.of(fin_bot), "dorsal": SeamLayout.of(dorsal)}


# --- Brakiri ------------------------------------------------------------------------------------------------------------
def brakiri() -> dict[str, SeamLayout]:
    """The Bokmai's parts in the ship's authored frame: a smooth skin in a few big plates, fine seams, clusters of small hatches."""
    skin = dict(wrap="sides", long_axis=2, splits=2, min_m=1.1, keep=0.4, sheen=0.09, grime=0.05, grime_m=0.25, width=0.8)
    bow: list[Feature] = [
        # Low: the blade's two long seams and its one frame.
        Cut(axis=1, at=4.4, level=1), Cut(axis=1, at=8.8, level=1), Cut(axis=2, at=8.0, level=1),
        # Full: the big plates between them, broken unevenly. Plating: their tone, and the small hatches.
        *_plating(2, 0.045, cell=(8.0, 4.4), seed=91, **skin),
        _hatches((1.5, 0.9), 0.13, 93, wrap="sides", long_axis=2),
    ]
    spine: list[Feature] = [
        Cut(axis=2, at=24.0, level=1), Cut(axis=2, at=36.0, level=1),
        *_plating(2, 0.045, cell=(12.0, 4.4), seed=95, **skin),
        _hatches((1.5, 0.9), 0.13, 97, wrap="sides", long_axis=2),
    ]
    limb = [*_plating(2, 0.045, cell=(10.0, 4.0), seed=99, **{**skin, "splits": 1}), _hatches((1.2, 0.8), 0.08, 101, wrap="sides", long_axis=2)]
    nacelle: list[Feature] = [
        Cut(axis=2, at=65.5, level=1), Cut(axis=2, at=72.0, level=1),
        *_plating(2, 0.045, cell=(6.5, 3.0), offset=(59.0, 0.0), seed=103, **skin),
        _hatches((1.2, 0.8), 0.10, 105, wrap="sides", long_axis=2),
    ]
    # The fins: chordwise seams up the blade and one seam along its span, as the reference drawing has them.
    fin_top = [*rings(1, [7.5, 11.5], level=1), *rings(1, [5.5, 9.5, 13.4], level=2), Cut(axis=2, at=74.5, level=2),
               _hatches((1.2, 0.7), 0.12, 107, wrap="sides", long_axis=2)]
    fin_bot = [*rings(1, [-3.5, -7.5, -11.5], level=1), *rings(1, [-1.5, -5.5, -9.5, -13.4], level=2), Cut(axis=2, at=74.5, level=2),
               _hatches((1.2, 0.7), 0.12, 109, wrap="sides", long_axis=2)]
    return {"bow": SeamLayout.of(bow), "spine": SeamLayout.of(spine), "arm_r": SeamLayout.of(limb), "strut_r": SeamLayout.of(limb),
            "web_r": SeamLayout.of(limb), "post_r": SeamLayout.of(limb), "nacelle_r": SeamLayout.of(nacelle),
            "fin_top_r": SeamLayout.of(fin_top), "fin_bot_r": SeamLayout.of(fin_bot)}


def brakiri_pod() -> SeamLayout:
    """The Bokmai's cargo pod in its own frame: a belt and two girth seams, then plating and hatches."""
    return SeamLayout.of([
        Cut(axis=1, at=0.0, level=1), Cut(axis=0, at=0.0, level=1),
        Cut(axis=0, at=6.4, level=2), Cut(axis=0, at=-6.4, level=2), Cut(axis=2, at=0.0, level=2), Cut(axis=1, at=3.2, level=2),
        Cut(axis=1, at=-3.2, level=2),
        Plates(level=3, wrap="sides", long_axis=0, cell=(3.2, 3.2), splits=2, min_m=0.7, keep=0.35, tone=0.05, sheen=0.09, grime=0.06,
               grime_m=0.25, depth=0.5, dark=0.45, width=0.8, seed=111),
        _hatches((1.3, 0.8), 0.10, 113, wrap="sides", long_axis=0),
    ])


# --- Earthforce: the Starfury (M7-T15) ----------------------------------------------------------------------------------
# The upper right deck's outline from above (x, leading edge z, trailing edge z), outboard of the cabin.
_FURY_LE = ((2.05, -2.82), (2.5, -2.53), (3.25, -2.03), (3.75, -1.71), (4.25, -1.45), (4.7, -1.32))
_FURY_TE = ((4.7, 1.36), (4.25, 1.2), (3.75, 0.98), (3.25, 0.74), (2.95, 0.6), (2.05, 0.6))
_FURY_SWEEP, _FURY_ACROSS = (0.847, 0.0, 0.531), (-0.531, 0.0, 0.847)  # along the leading edge, and square to it


def _fury_le(inset: float, x0: float = 2.05, x1: float = 4.7) -> tuple[tuple[float, float, float], ...]:
    """A line parallel to the deck's leading edge, ``inset`` metres behind it."""
    return tuple((x, 0.0, z + inset / 0.847) for x, z in _FURY_LE if x0 <= x <= x1)


def starfury() -> dict[str, SeamLayout]:
    """The Starfury's parts (docs/assets-starfury.md, "Surface"): struts and fuselage in the authored frame (the upper right arm;
    the others mirror), pod and claw in the pod's frame. The upper decks carry framed panels, the lower decks swept strakes, the
    pods ring courses over a ribbed rear housing."""
    deck = {"lo": (1.95, -INF, -INF), "hi": (4.8, INF, INF), "facing": UP}
    cabin = {"lo": (-INF, -INF, -4.3), "hi": (1.95, INF, 0.3), "facing": UP}
    frame = (*_fury_le(0.24), *((x, 0.0, z - 0.26) for x, z in _FURY_TE))

    major: list[Feature] = [
        # Low: the frame inside the deck's edges, the joints where the arm leaves the cabin and at mid span, the cabin's frames.
        Path(points=frame, closed=True, facing=UP, level=1, width=1.3),
        Cut(axis=0, at=1.97, level=1, width=1.3), Cut(axis=0, at=3.4, level=1, width=1.3),
        Cut(axis=2, at=-2.95, level=1, **cabin), Cut(axis=2, at=-1.45, level=1, **cabin),
    ]
    cabin_top: list[Feature] = [
        # The cabin's roof: a spine channel, dark panels either side of it, two round ports, wedges beside the canopy.
        Cut(axis=0, at=0.3, level=2, lo=(-INF, -INF, -3.9), hi=(INF, INF, 0.1), facing=UP),
        Hatch(centre=(0.62, 0.0, -2.2), right=X, up=Z, size=(0.3, 0.95), corner_m=0.03, sunk=0.8, tone=0.72, facing=UP, level=2),
        Hatch(centre=(0.62, 0.0, -0.75), right=X, up=Z, size=(0.3, 0.8), corner_m=0.03, sunk=0.8, tone=0.72, facing=UP, level=2),
        Hatch(centre=(0.14, 0.0, -1.45), right=X, up=Z, size=(0.16, 0.16), corner_m=0.08, sunk=1.4, tone=0.5, facing=UP, level=2),
        Hatch(centre=(1.3, 0.0, -3.3), right=X, up=Z, size=(0.42, 0.75), corner_m=0.05, sunk=0.6, tone=0.78, facing=UP, level=2),
        Hatch(centre=(1.35, 0.0, -1.9), right=X, up=Z, size=(0.5, 0.36), corner_m=0.05, facing=UP, level=2),
    ]
    framed: list[Feature] = [
        # The upper decks: two dark channels bent round lighter panels, an oblong port between them, small hatches.
        Path(points=((3.1, 0.0, -1.45), (2.45, 0.0, -1.85), (2.45, 0.0, -0.1), (3.1, 0.0, -0.1)), facing=UP, level=2, width=2.6, flat_m=0.025),
        Path(points=((3.75, 0.0, -1.05), (4.35, 0.0, -0.75), (4.35, 0.0, 0.6), (3.75, 0.0, 0.42)), facing=UP, level=2, width=2.6, flat_m=0.025),
        Hatch(centre=(3.38, 0.0, -0.75), right=X, up=Z, size=(0.2, 0.52), corner_m=0.1, sunk=1.4, tone=0.55, level=2, **deck),
        Hatch(centre=(2.8, 0.0, -0.95), right=X, up=Z, size=(0.3, 0.42), corner_m=0.04, level=2, **deck),
        Hatch(centre=(4.0, 0.0, -0.1), right=X, up=Z, size=(0.32, 0.24), corner_m=0.04, level=2, **deck),
        Hatch(centre=(2.5, 0.0, 0.42), right=X, up=Z, size=(0.5, 0.2), corner_m=0.04, tone=0.8, level=2, **deck),
        Cut(axis=0, at=2.75, level=2, **{**deck, "lo": (1.95, -INF, -0.1)}), Cut(axis=0, at=4.05, level=2, **{**deck, "hi": (4.8, INF, -0.75)}),
        Cut(axis=2, at=-0.1, level=2, **{**deck, "lo": (3.1, -INF, -INF), "hi": (3.75, INF, INF)}),
        Plates(level=3, wrap="planar", right=X, up=Z, cell=(0.9, 0.7), splits=2, min_m=0.2, keep=0.3, tone=0.06, sheen=0.07, grime=0.10,
               grime_m=0.035, depth=0.5, dark=0.45, width=0.8, seed=121),
        _hatches((0.45, 0.28), 0.06, 123, wrap="planar", right=X, up=Z, facing=UP),
    ]
    swept: list[Feature] = [
        # The lower decks: long strakes swept with the leading edge, slots just behind it, ribs, cabin rings.
        *[Path(points=_fury_le(d), facing=UP, level=2) for d in (0.85, 1.5, 2.15)],
        Cut(axis=0, at=2.75, level=2, **deck), Cut(axis=0, at=4.05, level=2, **deck),
        *[Hatch(centre=(x, 0.0, z + 0.62), right=_FURY_SWEEP, up=_FURY_ACROSS, size=(0.4, 0.07), corner_m=0.03, sunk=1.6, tone=0.4,
                level=2, **deck) for x, z in ((2.4, -2.6), (3.0, -2.2), (3.6, -1.81), (4.2, -1.48))],
        Hatch(centre=(3.0, 0.0, -0.3), right=_FURY_SWEEP, up=_FURY_ACROSS, size=(0.5, 0.3), corner_m=0.04, level=2, **deck),
        Hatch(centre=(4.25, 0.0, 0.35), right=_FURY_SWEEP, up=_FURY_ACROSS, size=(0.36, 0.24), corner_m=0.04, level=2, **deck),
        *rings(2, [-2.45, -1.95], level=2, depth=-0.8, flat_m=0.03, **cabin),
        Plates(level=3, wrap="planar", right=_FURY_SWEEP, up=_FURY_ACROSS, cell=(1.5, 0.65), offset=(0.0, 0.2), splits=1, min_m=0.35, keep=0.3,
               tone=0.045, sheen=0.09, grime=0.08, grime_m=0.035, depth=0.4, dark=0.4, width=0.8, seed=125, symmetric=False),
    ]

    # The pod: a body of revolution about its own z axis, grooved at -1.855 and 1.31; ring courses of plates of mixed length over
    # the drum, a ribbed rear housing over the nozzle.
    pod: list[Feature] = [
        *rings(2, [-0.95, 0.2], level=1, width=1.3),
        *rings(2, [z for z in every(-1.4, 1.1, 0.45) if abs(z + 0.95) > 0.1 and abs(z - 0.2) > 0.1], level=2),
        *spokes(2, (0.0, 0.0, 0.0), range(15, 360, 30), span=(1.5, 2.7), level=2, depth=-0.7, flat_m=0.012),
        Plates(level=3, wrap="barrel", axis=2, radius=0.8, around=10, cell=(0.45, 0.0), offset=(-1.4, 0.0), splits=1, min_m=0.16, keep=0.35,
               tone=0.07, sheen=0.08, grime=0.10, grime_m=0.03, depth=0.5, dark=0.5, width=0.8, seed=131, **_zbox(-1.65, 1.15)),
    ]

    # The fuselage under the decks: its flanks, the rear panel and the keel's ladder of sunk pockets.
    fuselage: list[Feature] = [
        Cut(axis=2, at=-2.95, level=1, width=1.3), Cut(axis=2, at=-1.45, level=1, width=1.3),
        Cut(axis=1, at=-0.55, level=2), *rings(2, [-2.2, -0.9], level=2),
        *[Hatch(centre=(sx * 0.16, 0.0, z), right=X, up=Z, size=(0.2, 0.3), corner_m=0.02, sunk=1.4, tone=0.6, facing=DOWN, level=2)
          for sx in (1.0, -1.0) for z in every(-3.1, -1.1, 0.5)],
        *[Hatch(centre=(0.0, -0.2, -2.2), right=Z, up=Y, size=(0.7, 0.36), corner_m=0.05, facing=side, min_dot=0.5, level=2) for side in (OUT, IN)],
        Plates(level=3, wrap="sides", long_axis=2, cell=(0.9, 0.6), splits=1, min_m=0.2, tone=0.06, sheen=0.08, grime=0.08, grime_m=0.035,
               depth=0.0, dark=0.0, seed=139),
    ]
    # The claws: toothed along their length, as the references' blades are.
    claw = [*rings(2, every(1.6, 4.4, 0.2), level=2, depth=-0.6, flat_m=0.012)]
    return {"strut_ur": SeamLayout.of([*major, *cabin_top, *framed]), "strut_lr": SeamLayout.of([*major, *cabin_top, *swept]),
            "pod": SeamLayout.of(pod), "fuselage": SeamLayout.of(fuselage), "claw": SeamLayout.of(claw)}


# --- Raiders: the Delta-V fighter (M7-T15) ------------------------------------------------------------------------------
RAIDER_EDGE_M = 0.55  # the edge band's width inside the leading edge
RAIDER_TE_M = 0.3  # and inside the trailing edge


def raider(le_ratio: float, half_span: float, trailing_z: float, notch: tuple[float, float], body_x: float,
           lobe_z: tuple[float, float], lobe_x: tuple[float, float], canopy_z: tuple[float, float]) -> dict[str, SeamLayout]:
    """The raider's parts in the authored frame (the right wing and housing; their twins mirror), sized from the wing's leading edge
    (``le_ratio`` metres out per metre aft), span, trailing edge and notch and from the housings' reach (docs/assets-raider.md,
    "Surface"): framed trapezoid panels in the wing's bays, a ridge in plates of mixed size, ribbed housings."""
    sweep = math.atan(le_ratio)
    notch_x, notch_z = notch
    notch_out = notch_z * le_ratio  # where the notch's back wall meets the leading edge

    def le(x: float, inset: float) -> tuple[float, float, float]:
        z = x / le_ratio + inset / math.sin(sweep)
        return (x, 0.0, max(z, notch_z + inset) if notch_x < x < notch_out else z)

    def te(x: float, inset: float) -> tuple[float, float, float]:
        return (x, 0.0, trailing_z - inset)

    def both(make) -> list[Feature]:
        return [make(side) for side in (UP, DOWN)]

    edge, back = RAIDER_EDGE_M, RAIDER_TE_M
    out_x = half_span - 0.4
    frames = (notch_out, 5.7)

    def bay(xa: float, xb: float, inset: float, level: int = 2, **kw: object) -> list[Feature]:
        """A panel outlined inside a bay of the wing, its sides parallel to the bay's."""
        points = (le(xa + inset, edge + inset), le(xb - inset, edge + inset), te(xb - inset, back + inset), te(xa + inset, back + inset))
        return both(lambda side: Path(points=points, closed=True, facing=side, level=level, **kw))

    facing_le = (math.cos(sweep), 0.0, -math.sin(sweep))
    wing: list[Feature] = [
        # Low: the line the edge band's plating follows, from the housing round the tip and along the trailing edge; the frames.
        *both(lambda side: Path(points=(le(body_x, edge), le(notch_x - 0.05, edge), (notch_x - 0.05, 0.0, notch_z + edge),
                                        le(notch_out, edge), le(out_x, edge), te(out_x, back), te(body_x, back)), facing=side, level=1, width=1.3)),
        *[Cut(axis=0, at=x, level=1, width=1.3, **_zbox(notch_z, INF)) for x in frames],
        # The leading edge's row of teeth, outboard of the notch.
        *[Cut(axis=0, at=x, level=2, width=1.6, facing=facing_le, min_dot=0.7) for x in every(notch_out + 0.3, half_span - 0.3, 0.42)],
        # Each bay carries a panel outlined inside it and a smaller one inside that; louvres behind the notch, a long hatch aft.
        *bay(frames[0], frames[1], 0.28), *bay(frames[1], out_x, 0.25),
        *bay(frames[0], frames[1], 0.75, width=0.8), *bay(frames[1], out_x, 0.6, width=0.8),
        Hatch(centre=(2.95, 0.0, 4.6), right=X, up=Z, size=(0.5, 0.9), slats=7, sunk=1.0, tone=0.7, facing=UP, level=2),
        Hatch(centre=(4.9, 0.0, 6.85), right=X, up=Z, size=(1.3, 0.34), corner_m=0.05, facing=UP, level=2),
        Hatch(centre=(4.4, 0.0, 5.7), right=X, up=Z, size=(1.5, 0.9), corner_m=0.08, facing=DOWN, level=2),
        Hatch(centre=(6.3, 0.0, 6.65), right=X, up=Z, size=(0.8, 0.5), slats=5, sunk=1.0, tone=0.7, facing=DOWN, level=2),
        # Large plates in 7 % tone.
        Plates(level=3, wrap="planar", right=Z, up=X, cell=(2.2, 1.35), offset=(0.0, 0.3), splits=1, min_m=0.5, keep=0.4, tone=0.07,
               sheen=0.12, grime=0.10, grime_m=0.05, depth=0.0, dark=0.0, seed=141, symmetric=False),
        _hatches((0.7, 0.4), 0.06, 143, wrap="planar", right=Z, up=X),
    ]

    # The ridge: frames behind the canopy and over the hump, a belt along each flank, hatches low on the sides, plates.
    behind = canopy_z[1] + 0.25
    ridge: list[Feature] = [
        Cut(axis=2, at=canopy_z[0] - 0.15, level=1, width=1.3), Cut(axis=2, at=behind, level=1, width=1.3),
        Cut(axis=2, at=4.5, level=2), Cut(axis=2, at=5.6, level=2), Cut(axis=1, at=0.2, level=2, **_zbox(behind, 6.1)),
        *_plating(3, 0.07, wrap="sides", long_axis=2, cell=(0.8, 0.55), splits=1, min_m=0.2, keep=0.3, sheen=0.12, grime=0.12, grime_m=0.04,
                  depth=0.5, dark=0.5, width=0.8, seed=151),
    ]
    ridge_right: list[Feature] = [
        Hatch(centre=(0.0, 0.05, 2.5), right=Z, up=Y, size=(0.5, 0.25), corner_m=0.04, facing=OUT, min_dot=0.5, level=2),
        Hatch(centre=(0.0, -0.05, 1.5), right=Z, up=Y, size=(0.4, 0.14), slats=4, sunk=1.0, tone=0.7, facing=OUT, min_dot=0.5, level=2),
    ]

    # The housing: ribbed across like the model's engine cages, strakes along its top and belly, a belt round the outer side.
    z0, z1 = lobe_z
    x_in, axis_x = lobe_x
    housing: list[Feature] = [
        *rings(2, [z0 + 0.3, z1 - 0.75], level=1, width=1.3),
        *rings(2, every(z0 + 0.9, z1 - 1.35, 0.45), level=2, depth=-0.8, flat_m=0.035),
        *[Cut(axis=0, at=x, level=2, **_zbox(z0 + 0.3, z1 - 0.75)) for x in (x_in + 0.35, axis_x, body_x - 0.6)],
        Cut(axis=1, at=0.0, level=2, **_zbox(z0, z1)),
        Plates(level=3, wrap="sides", long_axis=2, cell=(0.6, 0.5), offset=(z0 + 0.3, 0.0), splits=1, min_m=0.2, tone=0.07, sheen=0.12,
               grime=0.12, grime_m=0.04, depth=0.0, dark=0.0, seed=153, **_zbox(z0, z1)),
    ]
    return {"wing_r": SeamLayout.of(wing), "hump": SeamLayout.of(ridge) + SeamLayout.of(ridge_right).mirrored_too(0),
            "nacelle_r": SeamLayout.of(housing)}


__all__ = ["brakiri", "brakiri_pod", "centauri", "dress", "narn", "raider", "saturn", "saturn_engine", "skylark", "starfury"]
