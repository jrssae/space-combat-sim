class_name EmitterCurves
extends RefCounted
## The numbers behind the ship lights (M3-T22, architecture §7.3): how bright a nozzle, a muzzle flash and the explosion's own
## light are, and where they sit. Kept apart from the nodes that own the emitters so the values are unit-tested. All of them are
## tuned by eye (AC35).

## A main-pod nozzle: its light sits this far out along the exhaust, so it falls on the pod and its strut and not inside the
## hull.
const NOZZLE_OFFSET_M: float = 1.5
const NOZZLE_RANGE_M: float = 15.0
const NOZZLE_PEAK_ENERGY: float = 2.5
## Plume levels under this give no light (the smoothed level never reaches exactly 0).
const NOZZLE_MIN_LEVEL: float = 0.01

## A shot's flash at the muzzle.
const FLASH_S: float = 0.06
const FLASH_PEAK_ENERGY: float = 6.0
const FLASH_RANGE_M: float = 10.0
## How far in front of the muzzle the flash light sits, so it falls on the nose.
const FLASH_OFFSET_M: float = 1.0


## Energy of a nozzle light for a plume at `level` (0..1): dark at idle, full at full thrust.
static func nozzle_energy(level: float) -> float:
	if level < NOZZLE_MIN_LEVEL:
		return 0.0
	return NOZZLE_PEAK_ENERGY * minf(level, 1.0)


## The light colour for a plume of HDR colour `glow`: the same hue at display brightness (a light colour above 1 only
## double-counts the energy).
static func light_color(glow: Color) -> Color:
	var peak: float = maxf(glow.r, maxf(glow.g, glow.b))
	if peak <= 0.0:
		return Color.WHITE
	return Color(glow.r / peak, glow.g / peak, glow.b / peak)


## Energy of a muzzle flash `age_s` after the shot: full at the shot, fading to nothing at `FLASH_S`.
static func flash_energy(age_s: float) -> float:
	if age_s >= FLASH_S:
		return 0.0
	return FLASH_PEAK_ENERGY * (1.0 - maxf(age_s, 0.0) / FLASH_S)
