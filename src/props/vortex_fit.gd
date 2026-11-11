class_name VortexFit
extends RefCounted
## The size and place of a jump vortex (M6-T19): its mouth's radius, how deep the funnel goes behind the mouth, and where the
## mouth lies along its opener's axis. Pure.
##
## At a jumpgate (from its markers): the mouth lies in the gate's front plane, its rim a few metres short of the arms' inner
## tips, the funnel as deep as an arm is long. At a ship-made point: sized for the ship that comes through (`for_ship`), with the
## gate's proportions, and widened when more ships of the same group come out of it (`widen_for`).

## The rim stops this far short of the nearest inner tip (it fades out there, so it never seems to touch the arms).
const RIM_CLEARANCE_M: float = 8.0
## A ship-made point: the mouth is this many times the ship's bounding radius across (a fighter sits well inside it), never
## smaller than `MIN_POINT_RADIUS_M`; the funnel is `POINT_DEPTH_RATIO` mouth radii deep, about a gate's 1 200 m to 782 m.
const POINT_RADII_PER_SHIP: float = 4.0
const MIN_POINT_RADIUS_M: float = 60.0
const POINT_DEPTH_RATIO: float = 1.5
## Where a gate's markers are missing: the generator's 1 200 m arms.
const FALLBACK_TIP_M: float = 790.0
const FALLBACK_ARM_M: float = 1200.0

## The rim's radius, metres.
var mouth_radius_m: float = 0.0
## From the mouth to the funnel's narrow end, metres.
var depth_m: float = 0.0
## Where the mouth lies along the opener's normal, metres (gate-local z; 0 for a ship-made point).
var mouth_z_m: float = 0.0


func _init(p_mouth_radius_m: float = MIN_POINT_RADIUS_M, p_depth_m: float = MIN_POINT_RADIUS_M * POINT_DEPTH_RATIO,
		p_mouth_z_m: float = 0.0) -> void:
	mouth_radius_m = maxf(p_mouth_radius_m, 1.0)
	depth_m = maxf(p_depth_m, 1.0)
	mouth_z_m = p_mouth_z_m


## A gate's vortex from its `hardpoints.json` and the manifest's `aabb_min` (the gate faces -Z, so its front plane is the lowest
## z of its mesh): the rim just inside the nearest inner tip (an arm's `inner` end or a tip's emitter lens), the depth the arm's
## length, the mouth in the front plane.
static func for_gate(hardpoints: Dictionary, manifest: Dictionary) -> VortexFit:
	var tip: float = INF
	for key: String in ["arms", "emitters"]:
		var list: Variant = hardpoints.get(key)
		if not (list is Array):
			continue
		for entry: Variant in list as Array:
			if entry is Dictionary:
				var p: Variant = (entry as Dictionary).get("inner" if key == "arms" else "position")
				if p is Array and (p as Array).size() >= 2:
					tip = minf(tip, Vector2(float(p[0]), float(p[1])).length())
	if tip == INF:
		tip = FALLBACK_TIP_M
	var arm: float = float(hardpoints.get("arm_length_m", FALLBACK_ARM_M))
	var front: float = 0.0
	var lo: Variant = manifest.get("aabb_min")
	if lo is Array and (lo as Array).size() == 3:
		front = minf(float(lo[2]), 0.0)
	return VortexFit.new(tip - RIM_CLEARANCE_M, arm, front)


## A ship-made point for a ship of `ship_radius_m` (its bounding radius).
static func for_ship(ship_radius_m: float) -> VortexFit:
	var r: float = maxf(POINT_RADII_PER_SHIP * maxf(ship_radius_m, 0.0), MIN_POINT_RADIUS_M)
	return VortexFit.new(r, r * POINT_DEPTH_RATIO)


## The mouth wide enough for another ship of the group, `lateral_m` off the axis: its whole point fits inside the rim.
func widen_for(lateral_m: float, ship_radius_m: float) -> void:
	var need: float = lateral_m + for_ship(ship_radius_m).mouth_radius_m
	if need > mouth_radius_m:
		mouth_radius_m = need
		depth_m = need * POINT_DEPTH_RATIO
