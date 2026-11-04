"""Wing liveries (M4-T30b, Q35): what a wing paints over the shared hull maps, as data the hull shader reads.

Every Starfury draws the same mesh and maps; a livery is a colour pair, a pattern and where the ship's number goes. A pattern is a
short list of stripes: a band of one of the two colours where a linear coordinate of the object-space position (``|x|`` for a mirror
symmetric one) falls in a range, on the parts of some zones, optionally only on faces turned one way. Numbers are drawn from a digit
atlas inside number fields (a plane on one zone, read along ``right`` with the digits' tops along ``up``). The glb carries each
vertex's zone; the albedo map's alpha says where paint may go (hull paint that is not chipped). ``livery_section`` packs all of it
for ``MeshAssets`` and the shader, so a wing's livery is two colours and two small integers per instance and every wing instances.

Names are matched case-insensitively. A wing that is not named here gets a stable livery from its name (FNV-1a, which Godot's
``Livery`` computes the same way); the empty name is the plain field-grey livery with no number (enemies, unnamed ships).
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any

import numpy as np

from .color import srgb_to_linear
from .textures import GLYPH_H, GLYPH_W, glyph_strokes, _stroke_distance

Vec3 = tuple[float, float, float]

# The zones a vertex can be in (glb COLOR_0's red channel, zone / 255); 0 is never painted.
ZONES: dict[str, int] = {"fuselage": 1, "fittings": 2, "strut_upper": 3, "strut_lower": 4, "pod": 5, "claw": 6, "gun_mount": 7}
UP: Vec3 = (0.0, 1.0, 0.0)
DOWN: Vec3 = (0.0, -1.0, 0.0)
ANY_FACING = -2.0  # a stripe's min_facing that every face passes

DIGIT_CELL_PX = (96, 128)  # one digit's cell in the atlas: 6 by 8 glyph units at 16 px a unit (the 4 by 6 glyph centred)
DIGIT_PX_PER_UNIT = 16.0
DIGIT_RANGE_UNITS = 1.5  # the atlas stores 1 - distance / range: 255 on a stroke's centre line, 0 this far from it
PLAIN_PATTERN = "plain"


def zone_of(part_name: str) -> int:
    """The livery zone of a Starfury part (0: never painted)."""
    kind = part_name.split("_")[0]
    if kind == "strut":
        return ZONES["strut_lower"] if part_name.endswith(("_lr", "_ll")) else ZONES["strut_upper"]
    if part_name == "gun_mount":
        return ZONES["gun_mount"]
    return ZONES.get(kind, 0) if part_name not in ("cockpit", "cockpit_interior") else 0


@dataclass(frozen=True)
class Stripe:
    """Paint ``slot`` (1 primary, 2 secondary) where ``lo <= axis . (|x| or x, y, z) < hi`` on ``zones``' faces turned towards
    ``facing`` by at least ``min_facing`` (cosine). Later stripes paint over earlier ones."""

    zones: tuple[int, ...]
    axis: Vec3
    lo: float
    hi: float
    slot: int
    mirror: bool = True
    facing: Vec3 = UP
    min_facing: float = ANY_FACING


@dataclass(frozen=True)
class NumberField:
    """Where a number is painted: on ``zones``' faces turned to ``facing``, centred on ``centre``, read along ``right``, the digits'
    tops along ``up``, ``height_m`` tall, strokes ``weight`` glyph units wide. The centre's y is taken on the point's side of y = 0,
    so one field serves an upper and a lower part (the pods)."""

    zones: tuple[int, ...]
    centre: Vec3
    right: Vec3
    up: Vec3
    facing: Vec3
    height_m: float
    weight: float = 1.0


@dataclass(frozen=True)
class Livery:
    """A wing's paint: two colours (sRGB 0..255), a pattern from ``PATTERNS``, the number's colour and which ``NUMBER_FIELDS`` it uses."""

    name: str
    primary: Vec3
    secondary: Vec3
    pattern: str
    number_colour: Vec3 = (236.0, 238.0, 236.0)
    numbers: tuple[str, ...] = ("dorsal", "wing")  # Q37: large on the deck, small on the upper left wing

    @property
    def numbered(self) -> bool:
        return bool(self.numbers)

    def linear(self, which: str) -> Vec3:
        return tuple(float(c) for c in srgb_to_linear(np.asarray(getattr(self, which), dtype=float) / 255.0))


def _zones(*names: str) -> tuple[int, ...]:
    return tuple(ZONES[n] for n in names)


STRUTS = _zones("strut_upper", "strut_lower")
BODY = _zones("fuselage", "fittings")

# The patterns. Coordinates are the Starfury's object frame (centred, -z forward, metres); the struts run from the centre line to
# |x| 4.7, the dorsal deck is |x| < 0.55 from z -2.5 to -0.74, the pods sit at |x| 4.5 to 7 from z -2 to 3.5.
PATTERNS: dict[str, tuple[Stripe, ...]] = {
    PLAIN_PATTERN: (),
    # Broad bands across all four struts, alternating, as on the reference's "fancy" sheet.
    "bands": tuple(
        Stripe(STRUTS, (1.0, 0.0, 0.0), 1.5 + 0.48 * k, 1.98 + 0.48 * k, 1 if k % 2 == 0 else 2) for k in range(6)
    ),
    # A broad band round the front of each pod with thin edges, and the nose of the body.
    "nose_band": (
        Stripe(_zones("pod"), (0.0, 0.0, 1.0), -1.15, -0.25, 2),
        Stripe(_zones("pod"), (0.0, 0.0, 1.0), -1.07, -0.33, 1),
        Stripe(BODY, (0.0, 0.0, 1.0), -9.0, -2.7, 1),
        Stripe(BODY, (0.0, 0.0, 1.0), -2.7, -2.6, 2),
    ),
    # An arrowhead pointing at the nose across the body and the upper struts' roots, edged in the second colour.
    "chevron": (
        Stripe(BODY + _zones("strut_upper"), (-0.75, 0.0, 1.0), -3.08, -1.92, 2, facing=UP, min_facing=0.3),
        Stripe(BODY + _zones("strut_upper"), (-0.75, 0.0, 1.0), -3.0, -2.0, 1, facing=UP, min_facing=0.3),
        Stripe(STRUTS, (1.0, 0.0, 0.0), 3.55, 3.95, 1),
    ),
    # Thin double lines along the body and across every strut, and a narrow chevron on the deck.
    "pinstripe": (
        Stripe(BODY, (1.0, 0.0, 0.0), 0.42, 0.48, 1),
        Stripe(STRUTS, (1.0, 0.0, 0.0), 1.32, 1.4, 1),
        Stripe(STRUTS, (1.0, 0.0, 0.0), 1.5, 1.58, 1),
        Stripe(STRUTS, (1.0, 0.0, 0.0), 4.1, 4.18, 1),
        Stripe(BODY + _zones("strut_upper"), (-0.9, 0.0, 1.0), -2.35, -2.05, 2, facing=UP, min_facing=0.3),
    ),
}

NUMBER_FIELDS: dict[str, NumberField] = {
    # Large on the back behind the canopy (the upper struts' roots meet over the fuselage there), read from above with the nose up.
    "dorsal": NumberField(_zones("fuselage", "fittings", "strut_upper"), (0.0, 1.5, -1.0), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0), UP,
                          0.8, 1.15),
    # Small on the upper left strut, behind its hazard stripes, as the show's ID numbers.
    "wing": NumberField(_zones("strut_upper"), (-2.6, 1.7, 0.3), (1.0, 0.0, 0.0), (0.0, 0.0, -1.0), UP, 0.42, 0.9),
}

LIVERIES: dict[str, Livery] = {
    "alpha": Livery("alpha", (182.0, 194.0, 82.0), (54.0, 62.0, 74.0), "bands"),
    "beta": Livery("beta", (36.0, 82.0, 156.0), (226.0, 228.0, 230.0), "nose_band", (30.0, 44.0, 84.0)),
    # Delta's number in its dark green, so it reads inside the V on the grey (Q37 left the contrast to us).
    "delta": Livery("delta", (42.0, 96.0, 54.0), (216.0, 206.0, 168.0), "chevron", (28.0, 64.0, 36.0)),
    "zeta": Livery("zeta", (176.0, 30.0, 34.0), (134.0, 46.0, 146.0), "pinstripe", (176.0, 30.0, 34.0)),
}
PLAIN = Livery("plain", (150.0, 152.0, 156.0), (150.0, 152.0, 156.0), PLAIN_PATTERN, numbers=())

# What a wing without its own livery is given: a palette pair and a pattern picked by its name's hash.
FALLBACK_PALETTES: tuple[tuple[Vec3, Vec3, Vec3], ...] = (
    ((214.0, 112.0, 32.0), (40.0, 40.0, 44.0), (40.0, 40.0, 44.0)),  # orange and black
    ((40.0, 150.0, 150.0), (230.0, 232.0, 228.0), (230.0, 232.0, 228.0)),  # teal and white
    ((120.0, 34.0, 40.0), (208.0, 190.0, 140.0), (208.0, 190.0, 140.0)),  # maroon and sand
    ((226.0, 196.0, 40.0), (36.0, 52.0, 110.0), (36.0, 52.0, 110.0)),  # yellow and navy
    ((96.0, 104.0, 60.0), (30.0, 32.0, 28.0), (230.0, 230.0, 220.0)),  # olive and black
    ((70.0, 120.0, 190.0), (196.0, 60.0, 40.0), (236.0, 238.0, 236.0)),  # sky blue and red
)
FALLBACK_PATTERNS: tuple[str, ...] = ("bands", "nose_band", "chevron", "pinstripe")
FALLBACK_NUMBERS: tuple[str, ...] = ("dorsal", "wing")


def fnv1a32(text: str) -> int:
    """FNV-1a, 32 bits, over the UTF-8 bytes: the stable hash Godot's ``Livery`` repeats."""
    h = 0x811C9DC5
    for byte in text.encode("utf-8"):
        h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
    return h


def livery_for(wing: str) -> Livery:
    """The livery of a wing by name: its own, a stable fallback for any other name, the plain one for no name."""
    key = wing.strip().lower()
    if not key:
        return PLAIN
    if key in LIVERIES:
        return LIVERIES[key]
    h = fnv1a32(key)
    primary, secondary, number = FALLBACK_PALETTES[h % len(FALLBACK_PALETTES)]
    pattern = FALLBACK_PATTERNS[(h >> 16) % len(FALLBACK_PATTERNS)]
    return Livery(key, primary, secondary, pattern, number, FALLBACK_NUMBERS)


def number_text(number: int) -> str:
    """A ship's number as painted: two digits from 1 (the leader is 01); none for 0 or less."""
    return f"{number % 100:02d}" if number > 0 else ""


# --- the reference evaluator (what the shader computes, for tests and previews) -----------------
def paint_slots(stripes: Sequence[Stripe], points: np.ndarray, normals: np.ndarray, zones: np.ndarray) -> np.ndarray:
    """Per point: 0 (the hull's own paint), 1 (primary) or 2 (secondary) under ``stripes``."""
    p = np.asarray(points, dtype=float)
    n = np.asarray(normals, dtype=float)
    z = np.asarray(zones)
    out = np.zeros(len(p), dtype=np.int64)
    for s in stripes:
        q = np.column_stack([np.abs(p[:, 0]) if s.mirror else p[:, 0], p[:, 1], p[:, 2]])
        c = q @ np.asarray(s.axis)
        hit = np.isin(z, s.zones) & (c >= s.lo) & (c < s.hi) & (n @ np.asarray(s.facing) >= s.min_facing)
        out[hit] = s.slot
    return out


# --- the digit atlas ------------------------------------------------------------------------------
def digit_atlas() -> np.ndarray:
    """Ten cells, 0 to 9, of the stroke font's digits as distance fields: 255 on a stroke's centre line, falling to 0 at
    ``DIGIT_RANGE_UNITS`` glyph units from it. A cell is 6 by 8 units with the 4 by 6 glyph in its middle."""
    cw, ch = DIGIT_CELL_PX
    ys, xs = np.mgrid[0:ch, 0:cw]
    # Glyph units with y up, the glyph's origin one unit in from the cell's left and bottom.
    gx = (xs + 0.5) / DIGIT_PX_PER_UNIT - 0.5 * (cw / DIGIT_PX_PER_UNIT - GLYPH_W)
    gy = (ch - ys - 0.5) / DIGIT_PX_PER_UNIT - 0.5 * (ch / DIGIT_PX_PER_UNIT - GLYPH_H)
    points = np.column_stack([gx.ravel(), gy.ravel()])
    cells = []
    for digit in "0123456789":
        strokes = glyph_strokes(digit)
        if digit == "0":
            strokes = strokes[:1]  # an open zero: the stencil's slash would make the leader's "01" read as a letter
        d = _stroke_distance(points, strokes).reshape(ch, cw)
        cells.append(np.clip(np.rint((1.0 - d / DIGIT_RANGE_UNITS) * 255.0), 0, 255).astype(np.uint8))
    return np.concatenate(cells, axis=1)


def digit_import_sidecar() -> str:
    """Godot's ``.import`` for the digit atlas: lossless (a distance field must not be block compressed), mipmaps, linear."""
    return (
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\n"
        "compress/mode=0\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\n"
        "compress/hdr_compression=1\ncompress/normal_map=2\ncompress/channel_pack=1\n"
        "mipmaps/generate=true\nmipmaps/limit=-1\nroughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
        "process/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n"
    )


# --- what the manifest carries ------------------------------------------------------------------
def _r(values: Sequence[float], digits: int = 5) -> list[float]:
    return [round(float(v), digits) for v in values]


def _livery_json(livery: Livery) -> dict[str, Any]:
    return {
        "primary": _r(livery.linear("primary")),
        "secondary": _r(livery.linear("secondary")),
        "number_colour": _r(livery.linear("number_colour")),
        "pattern": livery.pattern,
        "numbers": list(livery.numbers),
    }


def livery_section(digit_file: str, hull_paint: Sequence[float]) -> dict[str, Any]:
    """The manifest's ``livery`` section: the hull paint the base map was painted with (linear), the zones, every pattern's
    stripes, the number fields, the named liveries (linear RGB), the plain one and the fallback's palettes, patterns and number
    fields, and the digit atlas's file and cell."""
    return {
        "hull_paint": _r(hull_paint),
        "zones": dict(ZONES),
        "patterns": {
            name: [
                {"zones": list(s.zones), "axis": _r(s.axis), "lo": s.lo, "hi": s.hi, "slot": s.slot, "mirror": s.mirror,
                 "facing": _r(s.facing), "min_facing": s.min_facing}
                for s in stripes
            ]
            for name, stripes in PATTERNS.items()
        },
        "number_fields": {
            name: {"zones": list(f.zones), "centre": _r(f.centre), "right": _r(f.right), "up": _r(f.up), "facing": _r(f.facing),
                   "height_m": f.height_m, "weight": f.weight}
            for name, f in NUMBER_FIELDS.items()
        },
        "liveries": {name: _livery_json(livery) for name, livery in LIVERIES.items()},
        "plain": _livery_json(PLAIN),
        "fallback": {
            "palettes": [
                {"primary": _r(srgb_to_linear(np.asarray(p, dtype=float) / 255.0)),
                 "secondary": _r(srgb_to_linear(np.asarray(s, dtype=float) / 255.0)),
                 "number_colour": _r(srgb_to_linear(np.asarray(c, dtype=float) / 255.0))}
                for p, s, c in FALLBACK_PALETTES
            ],
            "patterns": list(FALLBACK_PATTERNS),
            "numbers": list(FALLBACK_NUMBERS),
        },
        "digits": {"file": digit_file, "cell_px": list(DIGIT_CELL_PX), "px_per_unit": DIGIT_PX_PER_UNIT,
                   "range_units": DIGIT_RANGE_UNITS, "glyph": [GLYPH_W, GLYPH_H], "advance": 5.4},
    }


__all__ = ["DIGIT_CELL_PX", "LIVERIES", "Livery", "NUMBER_FIELDS", "NumberField", "PATTERNS", "PLAIN", "PLAIN_PATTERN", "Stripe",
           "ZONES", "digit_atlas", "digit_import_sidecar", "fnv1a32", "livery_for", "livery_section", "number_text", "paint_slots",
           "zone_of"]
