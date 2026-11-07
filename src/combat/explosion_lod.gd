class_name ExplosionLod
extends RefCounted
## The explosion level of detail (M4-T23, architecture §17.14): how a death is drawn from how far the camera is, the distances
## set by the blast's size. Near it is the full `Explosion` (light, flash, fireball, sparks, fragments, gas, debris); between it
## is a reduced one (no light, the gas shell only, no debris); far it is a point flash in one shared multimesh (`FarFlashes`),
## which costs no node and no particle. A far flash is drawn as T28's running lights and T11's far dots are: never under a
## pixel, and below its real size its brightness falls with the inverse square of distance, so the light it delivers is
## physical. Its size, peak and length grow with the blast's energy, so a capital's death reads across tens of km and a
## fighter's across a few. Pure maths; `far_flash.gdshader` draws the same.

enum Level { FULL, REDUCED, FAR }

## The full effect within this many bounding radii of the camera, the reduced one within this many.
const FULL_RADII: float = 250.0
const REDUCED_RADII: float = 800.0
## The flash's radius per cube root of the blast's energy, m/J^(1/3): about 3 m for a raider's death.
const FLASH_M_PER_CBRT_J: float = 0.0024
## The peak brightness (linear, HDR) of a blast of `PEAK_REF_J`; it grows with the cube root of the energy, so the light it
## delivers grows with the energy itself, between these bounds.
const PEAK_REF: float = 2.0
const PEAK_REF_J: float = 2.0e9
const PEAK_MIN: float = 0.5
const PEAK_MAX: float = 16.0
## A flash reads while the light it delivers at its one pixel is above this (a quarter of a full pixel).
const VISIBLE_DELIVERED: float = 0.25
## Its rise, and its length: a base plus a part that grows with its size.
const RISE_S: float = 0.04
const FLASH_BASE_S: float = 0.4
const FLASH_S_PER_SQRT_M: float = 0.1
## The flash's colour (linear), times its brightness.
const COLOR: Color = Color(1.0, 0.8, 0.55)


## How a death of a hull of `radius_m` at `distance_m` from the camera is drawn.
static func level(radius_m: float, distance_m: float) -> Level:
	var r: float = maxf(radius_m, 0.5)
	if distance_m <= r * FULL_RADII:
		return Level.FULL
	if distance_m <= r * REDUCED_RADII:
		return Level.REDUCED
	return Level.FAR


## The flash's radius for a blast of `energy_j`, m.
static func flash_radius_m(energy_j: float) -> float:
	return FLASH_M_PER_CBRT_J * pow(maxf(energy_j, 1.0), 1.0 / 3.0)


## The flash's peak brightness for a blast of `energy_j`.
static func peak(energy_j: float) -> float:
	return clampf(PEAK_REF * pow(maxf(energy_j, 1.0) / PEAK_REF_J, 1.0 / 3.0), PEAK_MIN, PEAK_MAX)


## How long the flash lasts, s.
static func flash_s(energy_j: float) -> float:
	return FLASH_BASE_S + FLASH_S_PER_SQRT_M * sqrt(flash_radius_m(energy_j))


## The flash's brightness `age_s` into a life of `life_s`, 0..1: a fast rise, then a fade to nothing.
static func envelope(age_s: float, life_s: float) -> float:
	if age_s <= 0.0 or age_s >= life_s:
		return 0.0
	if age_s < RISE_S:
		return age_s / RISE_S
	var t: float = (age_s - RISE_S) / maxf(life_s - RISE_S, 1e-6)
	return (1.0 - t) * (1.0 - t)


## Pixels per radian at the screen's centre for `lines` and a vertical field of view of `fov_deg`.
static func pixels_per_radian(lines: float, fov_deg: float) -> float:
	return 0.5 * lines / tan(deg_to_rad(fov_deg) * 0.5)


## The flash of a blast of `energy_j` at `distance_m` on a screen of `lines`: (radius in pixels, brightness). Never under a
## pixel; below its real size the brightness falls with the square of the real size, so the delivered light (brightness
## times pixel area) falls with the inverse square of distance.
static func on_screen(energy_j: float, distance_m: float, lines: float, fov_deg: float) -> Vector2:
	var real_px: float = flash_radius_m(energy_j) * pixels_per_radian(lines, fov_deg) / maxf(distance_m, 0.001)
	if real_px >= 1.0:
		return Vector2(real_px, peak(energy_j))
	return Vector2(1.0, peak(energy_j) * real_px * real_px)


## Where the flash shrinks to its one-pixel floor, m.
static func floor_distance_m(energy_j: float, lines: float, fov_deg: float) -> float:
	return flash_radius_m(energy_j) * pixels_per_radian(lines, fov_deg)


## How far the flash reads (its delivered light above `VISIBLE_DELIVERED`), m.
static func visible_to_m(energy_j: float, lines: float, fov_deg: float) -> float:
	return floor_distance_m(energy_j, lines, fov_deg) * sqrt(maxf(peak(energy_j) / VISIBLE_DELIVERED, 1.0))
