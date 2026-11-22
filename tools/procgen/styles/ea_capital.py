"""Earth Alliance warships (M10-T21, the Omega first; the Nova and Warlock follow; the Hyperion, a different style, has its own
looks in ``ea_hyperion.py`` on :func:`capital_style`): the fleet's grey plating in a panel mosaic (``styles/capital.PanelMosaic``),
dark recessed bands, a painted face on the command section, black window rows, red-orange running lights, blue-white engines
and the fleet's red-lit launch bays.

Colours are sRGB read off the stills in ``references/show/m10/ea_omega/`` (gitignored): the plating a mottled blue-grey
that wanders from plate to plate, the command section's fore face a rust ochre, the rotating section's slats a darker
grey, the engines' wake blue-white.

Three looks for the maintainer's A/B/C sheet (:data:`LOOKS`); the chosen one becomes :data:`DEFAULT_LOOK`.

A renegade hull (M10-T02, not built yet) repaints through the livery hook: :func:`ea_capital` takes ``livery``, role to
sRGB, laid over the look's own paint (the ``stripe`` role is the command section's face, where a marking band would go).
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass

from ..core.color import capture_albedo
from ..core.geometry import Material
from . import Style
from .capital import CapitalStyle, PanelMosaic
from .ea_civilian import lin
from .earth_alliance_station import BAY_RED, LAMP_GLOW, LAMP_STRENGTH

PREFIX = "eaw"
ENGINE_GLOW = 0xBFD8FF  # the blue-white of the wake in the stills
ENGINE_STRENGTH = 4.0
DECK_GLOW = 0xFFC890  # the warm light in a launch bay's hall
WINDOW_GLOW = 0xFFE7C2
# A launch bay's red light (the maintainer, 2026-11-21: every EA hull's bays, as Babylon 5's docking bay): the station's red, bright
# round the mouth and dimmer inside, and its red lamps at the mouth's corners. ``parts/capital_bays.launch_bay(lit=True)`` uses them.
BAY_MOUTH_STRENGTH = 1.6  # the station's mouth frames
BAY_DEEP_STRENGTH = 0.9
BAY_HALL_STRENGTH = 0.12  # the hall's walls, faintly red as if lit by the strips


@dataclass(frozen=True)
class Look:
    """One surface option: the paint by role (sRGB), how strongly the plates wander in tone, and the wear."""

    key: str
    title: str
    paint: Mapping[str, int]
    plate_tone: float
    plate_grime: float
    metallic: float
    edge_wear: float
    streaks: float
    grime: float


# role: (paneled, metallic or None for the look's, roughness)
ROLES: dict[str, tuple[bool, float | None, float | None]] = {
    "hull": (True, None, 0.55),
    "hull_panel": (True, None, 0.58),
    "hull_dark": (True, None, 0.6),
    "stripe": (True, None, 0.62),
    "hazard_dark": (False, 0.5, None),
    "canopy_glass": (False, 0.0, 0.15),
    "canopy_frame": (False, 0.5, None),
    "nozzle": (False, 0.85, 0.32),
    "barrel": (False, 0.8, 0.3),
    "bore": (False, 0.0, None),
    "interior": (False, 0.0, None),
    "rcs": (False, 0.7, 0.35),
}
FIXED = {"hazard_dark": 0x1C1C1E, "canopy_glass": 0x0B0E12, "canopy_frame": 0x3A3C40, "nozzle": 0x4A4946, "barrel": 0x55565A, "bore": 0x0C0C0C,
         "interior": 0x24231F, "rcs": 0x5E5F63}

LOOKS: dict[str, Look] = {
    "a": Look("a", "A: show grey, rust face", {"hull": 0x8C9199, "hull_panel": 0x747A84, "hull_dark": 0x3F434B, "stripe": 0x8A5A32},
              plate_tone=0.16, plate_grime=0.12, metallic=0.35, edge_wear=0.35, streaks=0.2, grime=0.1),
    "b": Look("b", "B: station grey, clean", {"hull": 0xA2A5AE, "hull_panel": 0x8C8F97, "hull_dark": 0x4A4C52, "stripe": 0x915555},
              plate_tone=0.08, plate_grime=0.05, metallic=0.45, edge_wear=0.25, streaks=0.1, grime=0.05),
    "c": Look("c", "C: dark gunmetal, ochre face", {"hull": 0x666A70, "hull_panel": 0x54585E, "hull_dark": 0x2C2E33, "stripe": 0xA07830},
              plate_tone=0.2, plate_grime=0.18, metallic=0.5, edge_wear=0.45, streaks=0.28, grime=0.14),
}
DEFAULT_LOOK = "a"


def ea_capital(look: str = DEFAULT_LOOK, livery: Mapping[str, int] | None = None) -> CapitalStyle:
    """The fleet's capital style in one of the looks, any role repainted by ``livery`` (the renegades' marking, M10-T02)."""
    if look not in LOOKS:
        raise ValueError(f"ea_capital has no look {look!r}; it has {sorted(LOOKS)}")
    chosen = LOOKS[look]
    return capital_style(chosen, f"ea_capital_{look}", PREFIX, fleet_mosaic(chosen), livery)


def fleet_mosaic(chosen: Look) -> PanelMosaic:
    """The Earth Alliance fleet's standard plate mosaic (the Omega's; the Hyperion wears it too), in a look's tone and grime."""
    return PanelMosaic(plate_m=(18.0, 9.0), splits=2, tone=chosen.plate_tone, grime=chosen.plate_grime, frames_m=30.0, major_every=4)


def capital_style(chosen: Look, name: str, prefix: str, skin: PanelMosaic, livery: Mapping[str, int] | None = None) -> CapitalStyle:
    """An EA warship style from a look: the fleet's roles and fixed paints, its lit bays and engines, under ``name`` with its
    materials named from ``prefix``. Each class's style module (this one, ``ea_hyperion``) brings its own looks and skin."""
    paint = {**FIXED, **chosen.paint, **dict(livery or {})}
    unknown = set(paint) - set(ROLES)
    if unknown:
        raise ValueError(f"{name} has no roles {sorted(unknown)}")
    look = chosen.key
    tag = f"{prefix}_{look}" if not livery else f"{prefix}_{look}_" + "_".join(f"{k}{v:06x}" for k, v in sorted(livery.items()))
    materials = {role: Material(f"{tag}_{role}", capture_albedo(paint[role]), paneled=paneled,
                                metallic=chosen.metallic if metallic is None else metallic, roughness=roughness)
                 for role, (paneled, metallic, roughness) in ROLES.items()}
    materials["hazard"] = Material(f"{tag}_deck_lit", capture_albedo(0x8A8474), emissive=lin(DECK_GLOW), emissive_strength=0.6)
    materials["window"] = Material(f"{tag}_window", capture_albedo(0x2A2824), emissive=lin(WINDOW_GLOW), emissive_strength=1.5)
    materials.update(bay_light_materials(tag))
    materials["nozzle_throat"] = Material(f"{tag}_nozzle_throat", capture_albedo(0x1C1B1A), metallic=0.8, roughness=0.45, emissive=lin(ENGINE_GLOW),
                                          emissive_strength=ENGINE_STRENGTH)
    style = Style(
        name=name,
        materials=materials,
        panel_size_m=0.5,
        panel_line_width_m=0.035,
        panel_line_darkness=0.6,
        panel_tint_jitter=0.06,
        edge_wear=chosen.edge_wear,
        streaks=chosen.streaks,
        grime=chosen.grime,
        extra={"bare_metal": 0.2, "smudge": 0.15, "smudge_scale_m": 0.6, "speckle": 0.04, "streak_length_m": 0.35},
    )
    return CapitalStyle(name, style, skin)


def bay_light_materials(tag: str) -> dict[str, Material]:
    """The roles a lit launch bay draws its glow in (``parts/capital_bays.BAY_LIGHT_ROLES``), named under ``tag``: any style whose
    hulls have red-lit bays adds these."""
    red = lin(BAY_RED)
    return {
        "bay_light": Material(f"{tag}_bay_light", capture_albedo(0xD8D0C0), emissive=red, emissive_strength=BAY_MOUTH_STRENGTH),
        "bay_light_deep": Material(f"{tag}_bay_light_deep", capture_albedo(0xD8D0C0), emissive=red, emissive_strength=BAY_DEEP_STRENGTH),
        "bay_lamp": Material(f"{tag}_bay_lamp", capture_albedo(0x7A2A24), emissive=lin(LAMP_GLOW), emissive_strength=LAMP_STRENGTH),
        "bay_hall": Material(f"{tag}_bay_hall", capture_albedo(0x3C3838), metallic=0.5, roughness=0.6, emissive=red, emissive_strength=BAY_HALL_STRENGTH),
    }


__all__ = ["DEFAULT_LOOK", "FIXED", "LOOKS", "ROLES", "Look", "bay_light_materials", "capital_style", "ea_capital", "fleet_mosaic"]
