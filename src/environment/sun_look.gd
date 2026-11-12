class_name SunLook
extends RefCounted
## How the star looks on the scaled-space layer and in the lens flare (M6-T12, AC7): the colours from its temperature, the
## disc and corona settings the shader takes, and how strongly the flare shows when planets cover part of the disc. Pure.

## The glow sphere's radius over the disc's: room for the corona to fade out inside it.
const GLOW_SCALE: float = 10.0
## The disc's brightness in linear light against a lit surface's 1.5 (the planet's full sun); the tonemap folds the rest.
const DISC_BRIGHTNESS: float = 2.4
## The corona's brightness at the disc's edge, relative to the disc's own.
const CORONA_STRENGTH: float = 0.25
## Limb darkening: the edge of a K dwarf's disc is about 30 percent dimmer than its centre.
const LIMB_DARKENING: float = 0.7
## Below this part of the disc showing, the flare is off; the flare follows the part showing between.
const FLARE_OFF_BELOW: float = 0.02


## The disc's colour, linear, largest channel 1.
static func disc_colour(temperature_k: float) -> Color:
	return StarColor.linear_from_kelvin(temperature_k)


## The corona is warmer than the disc: the hot gas scatters less blue.
static func corona_colour(temperature_k: float) -> Color:
	var disc: Color = disc_colour(temperature_k)
	return Color(disc.r, disc.g * 0.9, disc.b * 0.7)


## The flare's share of its full strength when `lit_part` of the star's disc is showing (`ScaledSpace.key_light`): 1 in the
## open, falling to 0 as a planet hides the disc.
static func flare_factor(lit_part: float) -> float:
	return smoothstep(FLARE_OFF_BELOW, 1.0, clampf(lit_part, 0.0, 1.0))


## The star shader's parameters, in sRGB for the colour uniforms (`source_color`).
static func uniforms(temperature_k: float) -> Dictionary:
	return {
		&"colour": disc_colour(temperature_k).linear_to_srgb(),
		&"corona_colour": corona_colour(temperature_k).linear_to_srgb(),
		&"glow_scale": GLOW_SCALE,
		&"disc_brightness": DISC_BRIGHTNESS,
		&"corona_strength": CORONA_STRENGTH,
		&"limb_darkening": LIMB_DARKENING,
	}


## The brightness of a disc of unit radius at `x` radii from its centre (limb darkening inside, the corona outside), in units
## of the disc's centre. The shader does the same sum; this keeps its law testable.
static func profile(x: float) -> float:
	if x < 1.0:
		return 1.0 - LIMB_DARKENING * (1.0 - sqrt(1.0 - x * x))
	if x >= GLOW_SCALE:
		return 0.0
	var fade: float = 1.0 - smoothstep(GLOW_SCALE * 0.5, GLOW_SCALE * 0.95, x)
	return CORONA_STRENGTH * pow(1.0 / x, 1.6) * fade
