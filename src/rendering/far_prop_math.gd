class_name FarPropMath
extends RefCounted
## How a big prop (the jumpgate, the station's stand-in) is drawn at every distance (M6-T15, D70, AC9). Pure.
##
## Three draw paths, one after another as it goes away from the camera:
## - **near**: its own mesh where it is; the importer's levels of detail do the rest (§14.4).
## - **shrunk**: past `pull_m` (just inside the cameras' 50 km far plane) the same mesh is drawn shrunk toward the eye by
##   `pull_m / distance`, so it covers the same angle, with the same materials and light. Its size is continuous by construction.
## - **dot**: once its bounding radius is under `DOT_PX` pixels, a far dot (M4's rule: the angular size, a 1 px floor, dimmer
##   under it), sized so it covers what the mesh covered from this direction (the generator's silhouette table, manifest `far`).
##   It turns back a tenth inside the dot distance, as a ship's far dot does (`LodSwitcherMath`), and the two cross-fade.
##
## Positions and directions are in the prop's own frame where it says so.

## The bounding radius on screen, pixels, at which the mesh hands over to the dot: below about this a thin truss (the gate's
## rails are a fortieth of its size) hits or misses whole pixels and its light jumps from frame to frame (measured on the
## RX 6950 XT, M6-T15's Done notes), while the dot carries the same light steadily.
const DOT_PX: float = 4.0
## The shrunk mesh's level-of-detail bias: the importer's coarsest levels drop the gate's rails altogether at a few pixels.
const FAR_LOD_BIAS: float = 100.0
## The shrunk prop's far side stays this far inside the camera's far plane, m.
const PULL_MARGIN_M: float = 500.0
## `hull_phase`'s fit: the broad term's share at quarter phase, the back-lit lobe's height and sharpness.
const HULL_BROAD: float = 0.78
const HULL_RIM: float = 8.2
const HULL_RIM_POWER: float = 8.0
## Seconds the mesh and the dot take to cross-fade at a hand-off.
const FADE_S: float = 0.35

## The bounding sphere, in the prop's frame.
var centre: Vector3 = Vector3.ZERO
var radius_m: float = 0.0
## The silhouette's area seen along each direction (one hemisphere; the other side looks the same), m^2.
var directions: PackedVector3Array = PackedVector3Array()
var areas_m2: PackedFloat64Array = PackedFloat64Array()


## The model of a prop from its manifest's `far` section (`tools/procgen/core/silhouette.py`); null when it has none.
static func from_section(far: Dictionary) -> FarPropMath:
	var dirs: Array = far.get("directions", [])
	var areas: Array = far.get("areas_m2", [])
	var c: Array = far.get("centre", [])
	if dirs.is_empty() or dirs.size() != areas.size() or c.size() != 3 or float(far.get("radius_m", 0.0)) <= 0.0:
		return null
	var made := FarPropMath.new()
	made.centre = Vector3(float(c[0]), float(c[1]), float(c[2]))
	made.radius_m = float(far["radius_m"])
	for i: int in dirs.size():
		var d: Array = dirs[i]
		made.directions.append(Vector3(float(d[0]), float(d[1]), float(d[2])).normalized())
		made.areas_m2.append(float(areas[i]))
	return made


## The silhouette's area, m^2, seen from direction `to_eye` (prop frame, any length): the table's value at its own directions and
## blended smoothly between them, the nearest weighing most (Shepard's rule, inverse distance cubed: 3 % mean error against the
## true outline, M6-T15's Done notes).
func area_toward(to_eye: Vector3) -> float:
	var d: Vector3 = to_eye.normalized()
	var weighted: float = 0.0
	var total: float = 0.0
	for i: int in directions.size():
		# About half the squared angle to the direction or its opposite (a silhouette is the same from both sides).
		var q: float = 1.0 - absf(d.dot(directions[i]))
		if q < 1e-10:
			return areas_m2[i]
		var w: float = 1.0 / (q * sqrt(q))
		weighted += w * areas_m2[i]
		total += w
	return weighted / total if total > 0.0 else 0.0


## Pixels per radian at the screen's centre for a vertical field of view of `fov_deg` and a picture `height_px` tall.
static func px_per_rad(height_px: float, fov_deg: float) -> float:
	return 0.5 * height_px / tan(deg_to_rad(fov_deg) * 0.5)


## How far out the prop is drawn where it is; beyond, shrunk toward the eye (its far side inside `far_plane_m`).
func pull_m(far_plane_m: float) -> float:
	return maxf(far_plane_m - 1.02 * radius_m - PULL_MARGIN_M, 1.0)


## The factor the prop is shrunk toward the eye by at `distance_m`: 1 inside `pull`.
static func shrink(distance_m: float, pull: float) -> float:
	return minf(1.0, pull / distance_m) if distance_m > 0.0 else 1.0


## Where the mesh hands over to the dot: its bounding radius is `DOT_PX` there.
func dot_distance_m(k_px_per_rad: float) -> float:
	return radius_m * k_px_per_rad / DOT_PX


## Whether the prop is a dot at `distance_m`, given whether it is one now (M4's hysteresis).
func is_dot(distance_m: float, was_dot: bool, k_px_per_rad: float) -> bool:
	return LodSwitcherMath.far_dot(distance_m, was_dot, dot_distance_m(k_px_per_rad))


## The dot's radius, m, for a silhouette of `area_m2`: its falloff (1 - r^2) covers half its disc, so it covers the mesh's area.
static func dot_radius_m(area_m2: float) -> float:
	return sqrt(2.0 * maxf(area_m2, 0.0) / PI)


## Pixels the mesh covers at `distance_m` from a silhouette of `area_m2`.
static func mesh_cover_px2(area_m2: float, distance_m: float, k_px_per_rad: float) -> float:
	var px_per_m: float = k_px_per_rad / distance_m
	return area_m2 * px_per_m * px_per_m


## Pixels the dot covers (its alpha summed over the screen): half its disc, the same under the 1 px floor, since it dims by
## the square there (`far_prop_dot.gdshader`).
static func dot_cover_px2(dot_radius: float, distance_m: float, k_px_per_rad: float) -> float:
	var r_px: float = dot_radius * k_px_per_rad / distance_m
	return 0.5 * PI * r_px * r_px


## Pixels covered on screen during a cross-fade `fade` (0 the mesh, 1 the dot) from `to_eye` at `distance_m`.
func cover_px2(to_eye: Vector3, distance_m: float, fade: float, k_px_per_rad: float) -> float:
	var area: float = area_toward(to_eye)
	return lerpf(mesh_cover_px2(area, distance_m, k_px_per_rad), dot_cover_px2(dot_radius_m(area), distance_m, k_px_per_rad), fade)


## The bounding radius on screen, pixels: the same whether drawn where it is or shrunk.
func bounding_px(distance_m: float, k_px_per_rad: float) -> float:
	return asin(minf(radius_m / distance_m, 1.0)) * k_px_per_rad if distance_m > 0.0 else INF


## The cross-fade one frame of `delta_s` on toward the dot (`dot`) or the mesh.
static func step_fade(fade: float, dot: bool, delta_s: float) -> float:
	return move_toward(fade, 1.0 if dot else 0.0, delta_s / FADE_S)


## How bright a far prop is per unit albedo, relative to full sun: the ambient plus a Lambert sphere's share of its disc lit,
## seen at the angle `phase_rad` between the sun and the eye from the prop (0: the sun behind the eye), times `key_light`.
static func lit_share(phase_rad: float, key_light: float, ambient: float) -> float:
	var a: float = clampf(phase_rad, 0.0, PI)
	var lambert: float = ((PI - a) * cos(a) + sin(a)) / PI
	return ambient + (1.0 - ambient) * key_light * lambert


## How bright a far textured hull is per unit albedo in the key star's light at `phase_rad` (0: the sun behind the eye),
## relative to full phase: fitted to the gate's mesh on the RX 6950 XT (M6-T15's Done notes). The hull's sheen keeps it bright
## well past quarter phase and lights its rims against the sun, so it is no Lambert sphere: a broad term and a back-lit lobe.
static func hull_phase(phase_rad: float) -> float:
	var c: float = cos(clampf(phase_rad, 0.0, PI))
	return HULL_BROAD + (1.0 - HULL_BROAD) * c + HULL_RIM * pow(maxf(-c, 0.0), HULL_RIM_POWER)


## A Lambert sphere's mean N.L over its whole disc, lit and dark parts together, seen at `phase_rad` (2/3 at full phase): what a
## sphere lit as `max(N.L, 0)` shows per pixel on average, so its dot can carry the same light (the planet's, M6-T15).
static func disc_mean_lit(phase_rad: float) -> float:
	return 2.0 / 3.0 * lit_share(phase_rad, 1.0, 0.0)
