class_name BlastSpec
extends RefCounted
## One kind of blast (M10-T09, D12.6, Q53): its damage at the centre, its radius and its push, and the curve both fall off
## by. Pure: `BlastTable` makes these from `data/capitals/capitals.json`, `BlastResolver` lands them.
##
## Damage `d0 x f(d)` and push `dv = impulse x f(d) x A / m` (capped), with `f(d) = (1 - (d/R)^2)^2`: 1 at the centre, easing to
## nothing at the radius, `d` measured to the hull's nearest hit volume.

## A blast's energy per point of centre damage, J, and the push's cap, m/s (D12.6's defaults; the table overrides them).
const FLASH_J_PER_D0: float = 5.0e6
const PUSH_CAP_MPS: float = 50.0

## The table's row this came from (`fighter_death`, `capital_reactor`, ...), for readouts.
var source: StringName = &""
## Hull points at the centre.
var d0: float = 0.0
var radius_m: float = 0.0
## N s/m^2: the push's impulse per square metre of the hull's face at the centre.
var impulse: float = 0.0
var flash_j_per_d0: float = FLASH_J_PER_D0
var push_cap_mps: float = PUSH_CAP_MPS


static func make(p_source: StringName, p_d0: float, p_radius_m: float, p_impulse: float) -> BlastSpec:
	var out := BlastSpec.new()
	out.source = p_source
	out.d0 = maxf(p_d0, 0.0)
	out.radius_m = maxf(p_radius_m, 0.0)
	out.impulse = maxf(p_impulse, 0.0)
	return out


## The curve at `distance_m` from the centre: 1 at it (or inside a hull), 0 at the radius and beyond.
static func falloff(distance_m: float, radius: float) -> float:
	if not (radius > 0.0) or not (distance_m < radius):
		return 0.0
	var x: float = maxf(distance_m, 0.0) / radius
	var k: float = 1.0 - x * x
	return k * k


## Hull points a hull whose nearest hit volume is `distance_m` away takes.
func damage_at(distance_m: float) -> float:
	return d0 * falloff(distance_m, radius_m)


## The speed a hull of `mass_kg` with a mean box face of `area_m2` gains `distance_m` away, m/s, capped.
func push_at(distance_m: float, area_m2: float, mass_kg: float) -> float:
	if not (mass_kg > 0.0):
		return 0.0
	return minf(impulse * falloff(distance_m, radius_m) * maxf(area_m2, 0.0) / mass_kg, push_cap_mps)


## The blast's energy, J: what the far flashes read (how long one lasts).
func energy_j() -> float:
	return flash_j_per_d0 * d0


## A copy with its damage, radius and push scaled (a death's cargo).
func scaled(d0_scale: float, radius_scale: float, impulse_scale: float) -> BlastSpec:
	var out: BlastSpec = make(source, d0 * d0_scale, radius_m * radius_scale, impulse * impulse_scale)
	out.flash_j_per_d0 = flash_j_per_d0
	out.push_cap_mps = push_cap_mps
	return out


## The mean face area of a box of `size` (full extents), m^2: what a push acts on.
static func mean_face_area(size: Vector3) -> float:
	var s: Vector3 = size.abs()
	return (s.x * s.y + s.y * s.z + s.z * s.x) / 3.0


func _to_string() -> String:
	return "BlastSpec(%s d0 %.0f R %.0f m I0 %.0f)" % [source, d0, radius_m, impulse]
