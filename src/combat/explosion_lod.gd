class_name ExplosionLod
extends RefCounted
## The explosion level of detail (M4-T23, fix round 1; architecture §17.14): how a death is drawn from how big its fireball is
## on the current picture. While the fireball's radius is `FULL_PX` or more it is the full `Explosion` (light, flash, fireball,
## sparks, fragments, gas, debris); down to `REDUCED_PX` a reduced one (no light, the gas shell only, no debris); smaller, a
## point flash in one shared multimesh (`FarFlashes`), with no node and no particle. The switches are in pixels, so they move
## with the resolution and the field of view.
##
## The flash takes over where the reduced effect leaves off: as big as the fireball and as bright as the explosion's glow, so
## the light it delivers at the switch is what the reduced effect showed (no pop, no gap). Farther it shrinks to its 1 px floor
## and then keeps the pixel and dims with the inverse square of distance, as T28's running lights and T11's far dots do, until
## the light it delivers drops under `VISIBLE_DELIVERED`. A bigger hull's fireball is bigger, so a capital's death reads across
## hundreds of km and a fighter's across about ten. The blast's energy stays on the event (M12) and sets how long the flash
## lasts. Pure maths; `far_flash.gdshader` draws the same.

enum Level { FULL, REDUCED, FAR }

## The fireball's radius in pixels where the full effect ends and where the reduced one ends.
const FULL_PX: float = 8.0
const REDUCED_PX: float = 2.0
## The fireball's final radius in bounding radii (`Explosion.FIREBALL_FINAL_SCALE`): the flash's radius.
const FIREBALL_RADII: float = 1.2
## The flash's brightness (linear, HDR): the explosion's glow (`Explosion`'s flash quad, 2.4 / 1.7 / 1.0 in `COLOR` times this).
const PEAK: float = 2.0
const COLOR: Color = Color(1.2, 0.85, 0.5)
## A flash reads while the light it delivers (brightness times its pixel area) is above this: a pixel at a quarter of its peak.
const VISIBLE_DELIVERED: float = 0.5
## Its rise, and its length from the blast's energy: a base plus a part that grows with the energy's cube root.
const RISE_S: float = 0.04
const FLASH_BASE_S: float = 0.4
const FLASH_S_PER_CBRT_J: float = 0.0001
## The lines assumed when nothing is drawn (headless runs and tests).
const DEFAULT_LINES: float = 1080.0


## How a death of a hull of `radius_m` at `distance_m` is drawn on a picture of `lines` with a vertical field of view of
## `fov_deg`.
static func level(radius_m: float, distance_m: float, lines: float, fov_deg: float) -> Level:
	var px: float = fireball_px(radius_m, distance_m, lines, fov_deg)
	if px >= FULL_PX:
		return Level.FULL
	if px >= REDUCED_PX:
		return Level.REDUCED
	return Level.FAR


## Pixels per radian at the picture's centre.
static func pixels_per_radian(lines: float, fov_deg: float) -> float:
	return 0.5 * lines / tan(deg_to_rad(fov_deg) * 0.5)


## The fireball's final radius on the picture, px.
static func fireball_px(radius_m: float, distance_m: float, lines: float, fov_deg: float) -> float:
	return flash_radius_m(radius_m) * pixels_per_radian(lines, fov_deg) / maxf(distance_m, 0.001)


## Where the fireball's radius is `px` pixels, m.
static func switch_distance_m(radius_m: float, lines: float, fov_deg: float, px: float) -> float:
	return flash_radius_m(radius_m) * pixels_per_radian(lines, fov_deg) / px


## The flash's radius for a hull of `radius_m`: its fireball's, m.
static func flash_radius_m(radius_m: float) -> float:
	return FIREBALL_RADII * maxf(radius_m, 0.5)


## How long the flash of a blast of `energy_j` lasts, s.
static func flash_s(energy_j: float) -> float:
	return FLASH_BASE_S + FLASH_S_PER_CBRT_J * pow(maxf(energy_j, 1.0), 1.0 / 3.0)


## The flash's brightness `age_s` into a life of `life_s`, 0..1: a fast rise, then a fade to nothing.
static func envelope(age_s: float, life_s: float) -> float:
	if age_s <= 0.0 or age_s >= life_s:
		return 0.0
	if age_s < RISE_S:
		return age_s / RISE_S
	var t: float = (age_s - RISE_S) / maxf(life_s - RISE_S, 1e-6)
	return (1.0 - t) * (1.0 - t)


## The flash of a hull of `radius_m` at `distance_m` at its peak: (radius in pixels, brightness). Never under a pixel; below its
## real size the brightness falls with the square of the real size, so the delivered light falls with the inverse square.
static func on_screen(radius_m: float, distance_m: float, lines: float, fov_deg: float) -> Vector2:
	var real_px: float = fireball_px(radius_m, distance_m, lines, fov_deg)
	if real_px >= 1.0:
		return Vector2(real_px, PEAK)
	return Vector2(1.0, PEAK * real_px * real_px)


## Where the flash shrinks to its one-pixel floor, m.
static func floor_distance_m(radius_m: float, lines: float, fov_deg: float) -> float:
	return switch_distance_m(radius_m, lines, fov_deg, 1.0)


## How far the flash reads (its delivered light above `VISIBLE_DELIVERED`), m.
static func visible_to_m(radius_m: float, lines: float, fov_deg: float) -> float:
	return floor_distance_m(radius_m, lines, fov_deg) * sqrt(maxf(PEAK / VISIBLE_DELIVERED, 1.0))


## The lines the 3D picture of `viewport` is drawn at (the window's, scaled by the 3D scale), as the flash's pixel floor counts;
## `DEFAULT_LINES` with no picture (the headless display draws none).
static func picture_lines(viewport: Viewport) -> float:
	if viewport == null or DisplayServer.get_name() == "headless":
		return DEFAULT_LINES
	return float(Upscaling.internal_lines(int(viewport.get_visible_rect().size.y), viewport.scaling_3d_scale))
