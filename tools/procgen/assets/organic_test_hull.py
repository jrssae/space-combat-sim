"""``organic_test_hull``: the organic part library's test hull (M10-T06, D12.2), a cruiser-class body grown from every
organic part, so the organic hull tasks (T35, T36, T41, T42, T60 and the semi-organic ones) have a worked example and the
break-up tasks (T08 to T11) an organic hull to cut.

Not a ship of the show. One seamless body (``parts/organic.py``: a head, three lobes round a core, a ribbed tail and a pod
on a stalk each side, melted together and cut into the head, core and tail sections by ``core/organic.sectioned``), and
limbs rooted in it: a claw each side of the bow, three ribbed legs a side, three tendrils aft, and three half-open petals
round the head (``parts/organic_petal.py``). Written by ``core/capital.py`` as any capital hull.

Layout (authored frame, metres; -z forward, the hull's axis on y = 0): the claws' tips near z = 0, the head z 30 to 130,
the petals' hinges at z = 118, the core's lobes z 95 to 245, the tail to z = 268, the tendrils' tips at z = 300.

Options: ``look`` (``vorlon``, the default, ``shadow`` or ``hex``: ``styles/organic.py``) and ``sheen`` (``a``, ``b``,
``c``: the look sheet's options); ``cell_m`` (the body's grid, 1 m) and ``body_triangles``; and ``core/capital.build``'s
(``spacing``, ``atlas_px``, ``detail_px``).
"""

from __future__ import annotations

import math

import numpy as np

from ..core import capital as cap
from ..core import organic, sdf
from ..core.context import AssetOutputs, BuildContext
from ..parts import capital as cp
from ..parts import organic as po
from ..parts import organic_petal as petals
from ..styles import Style
from ..styles import organic as looks

ASSET_ID = "organic_test_hull"
GENERATOR_VERSION = 1
SHIP_CLASS = "cruiser"
DEFAULT_LOOK = "vorlon"
CELL_M = 1.0
BODY_TRIANGLES = 36_000
BLEND_M = 8.0
ATLAS_PX = 4096
HINGE_Z, HINGE_RADIUS = 118.0, 22.0
PETAL_CLOSED = petals.PetalPose(length_m=62.0, width_m=40.0, curl_radius_m=27.0, bow_radius_m=70.0)
PETAL_OPEN = petals.PetalPose(length_m=54.0, width_m=46.0, curl_radius_m=160.0, hinge_deg=50.0)
PETAL_OPENING = 0.45
# The explosive section's blast, J: a placeholder of the right order until a hull task sets its own (M10-T03).
BLAST_J = 4.0e14
NOTES = ("sections[].blast_energy_j: a placeholder (the test hull is not a ship of the show)",)

SECTIONS = (
    cap.Section("head", "bridge", 0.16),
    cap.Section("core", "reactor", 0.30, BLAST_J),
    cap.Section("tail", "engine", 0.14),
    cap.Section("petals", "structure", 0.14),
    cap.Section("claw_r", "structure", 0.05),  # and its port twin, claw_l
    cap.Section("legs_r", "structure", 0.08),  # and legs_l
)
# Where the body's skin is cut into its sections: each a box of the hull's length the section owns.
REGIONS = {"head": (-50.0, 108.0), "core": (108.0, 212.0), "tail": (212.0, 320.0)}
LEG_STATIONS = (138.0, 166.0, 194.0)


def _limbs(style: Style) -> list[tuple[str, cp.Module, sdf.Field]]:
    """The starboard and centre limbs: each with its section and the root that melts it into the body."""
    skin = style.material("hull_dark")
    out: list[tuple[str, cp.Module, sdf.Field]] = []

    def add(section: str, name: str, path: po.Path, width: np.ndarray, flat: float, side: str, pieces: int = 4) -> None:
        height = flat * width
        out.append((section, po.limb(name, path, width, height, skin, sides=12, pieces=pieces, skin=cp.SKIN_FITTING).on_side(side),
                    po.limb_root(path, width, height)))

    claw = po.claw_path((24.0, 0.0, 92.0), 104.0, (1.0, 0.0, -0.75), (-1.0, 0.0, -1.0), 62.0)
    add("claw_r", "claw_r", claw, po.ribs(claw, po.taper(claw, 7.5, 0.0, 0.8), 7.0, 0.12), 0.55, cp.RIGHT, 5)
    for k, z in enumerate(LEG_STATIONS):
        reach = 1.0 - 0.12 * k
        leg = po.leg_path((24.0, -8.0, z), (24.0 + 46.0 * reach, 12.0, z - 12.0), (24.0 + 66.0 * reach, -64.0 * reach, z - 38.0))
        add("legs_r", f"leg_{k}_r", leg, po.ribs(leg, po.taper(leg, 5.5 * reach, 0.0, 0.7), 5.0, 0.18), 0.8, cp.RIGHT, 6)
    top = po.tendril_path((0.0, 8.0, 246.0), (0.0, 16.0, 300.0), 3.0, 1.25)
    add("tail", "tendril_top", top, po.taper(top, 3.6, 0.0, 0.6), 1.0, cp.CENTRE)
    low = po.tendril_path((11.0, -5.0, 244.0), (26.0, -12.0, 296.0), 2.5, 1.5, (1.0, 0.3, 0.0))
    add("tail", "tendril_r", low, po.taper(low, 3.0, 0.0, 0.6), 1.0, cp.RIGHT)
    return out


def _body_parts(roots: list[sdf.Field]) -> list[sdf.Field]:
    """What the body is melted from: the head, the core's lobes, the ribbed tail and the pods, and every limb's root. The
    starboard parts are mirrored here: the body is whole, both sides."""
    both = lambda f: [f, f.mirrored(0)]  # noqa: E731
    head = po.lobe(100.0, 58.0, 50.0, centre=(0.0, 0.0, 80.0))
    lobes = [*both(po.lobe(150.0, 36.0, 32.0, 0.35, (22.0, -10.0, 170.0))), po.lobe(150.0, 36.0, 32.0, 0.35, (0.0, 20.0, 170.0))]
    core = sdf.ellipsoid((14.0, 14.0, 80.0), (0.0, 0.0, 170.0))
    tail = sdf.ribbed(po.lobe(96.0, 40.0, 34.0, 0.6, (0.0, 0.0, 220.0)), 1.4, 9.0)
    pods = both(po.pod(9.0, 30.0, 8.0, 3.5, at=(30.0, -6.0, 152.0), out=(1.0, -0.25, 0.0)))
    return [head, *lobes, core, tail, *pods, *roots]


def modules(style: Style, seed: int = 0, cell_m: float = CELL_M, body_triangles: int = BODY_TRIANGLES) -> list[cp.Module]:
    """Every module in its place and section (centre modules and the starboard one of each pair)."""
    limbs = _limbs(style)
    roots = [f for _, m, root in limbs for f in ([root, root.mirrored(0)] if m.side == cp.RIGHT else [root])]
    regions = {name: sdf.box((400.0, 400.0, z1 - z0), (0.0, 0.0, 0.5 * (z0 + z1))) for name, (z0, z1) in REGIONS.items()}
    points = {
        "head": [cp.Hardpoint("beam", cp.BEAM, (0.0, -24.0, 62.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"arc_deg": 40.0, "aperture_m": 6.0})],
        "tail": [cp.Hardpoint("engine", cp.ENGINE, (0.0, 0.0, 266.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0), {"share": 1.0, "radius_m": 9.0})],
    }
    parts = _body_parts(roots)
    body = po.body(parts, BLEND_M, relief_m=0.5, relief_scale_m=7.0, seed=seed)
    out = organic.sectioned(body, regions, cell_m, body_triangles, style.material("hull"), tolerance_m=3.0, skin=cp.SKIN_HULL,
                            hardpoints=points, parts=parts)
    out += [m.in_section(section) for section, m, _ in limbs]
    shell = petals.petal("petal", PETAL_CLOSED, PETAL_OPEN, PETAL_OPENING, 1.2, style.material("hull_panel"), pieces=6, skin=cp.SKIN_HULL)
    for name, angle, side in (("petal_top", 0.0, cp.CENTRE), ("petal_r", 120.0, cp.RIGHT)):
        up = (math.sin(math.radians(angle)), math.cos(math.radians(angle)), 0.0)
        placed = shell.mounted((HINGE_RADIUS * up[0], HINGE_RADIUS * up[1], HINGE_Z), up)
        out.append(cp.module(name, placed.part.mesh, [s.renamed(s.name.replace("petal", name, 1)) for s in placed.shapes],
                             skin=cp.SKIN_HULL).in_section("petals").on_side(side))
    return out


def spec(ctx: BuildContext) -> cap.CapitalSpec:
    style = looks.organic(str(ctx.option("look", DEFAULT_LOOK)), str(ctx.option("sheen", "a")))
    return cap.CapitalSpec(
        asset_id=ASSET_ID,
        generator_version=GENERATOR_VERSION,
        ship_class=SHIP_CLASS,
        modules=tuple(modules(style.style, ctx.seed, float(ctx.option("cell_m", CELL_M)), int(ctx.option("body_triangles", BODY_TRIANGLES)))),
        sections=SECTIONS,
        style=style,
        bridge=cap.Pose((0.0, 12.0, 44.0)),
        pieces=(cap.PieceSpec(cap.HULL_PIECE, ATLAS_PX),),
        jump_point=cap.JumpPoint(ahead_m=500.0, mouth_radius_m=200.0),
        cover_tolerance_m=4.0,
        cover_reach_m=8.0,
        notes=NOTES,
    )


def build(ctx: BuildContext) -> AssetOutputs:
    """Generate the test hull into ``ctx.out_dir``."""
    return cap.build(spec(ctx), ctx)


__all__ = ["ASSET_ID", "DEFAULT_LOOK", "GENERATOR_VERSION", "SECTIONS", "SHIP_CLASS", "build", "modules", "spec"]
