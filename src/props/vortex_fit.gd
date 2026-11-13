class_name VortexFit
extends RefCounted
## The size and place of a jump vortex (M6-T19): its mouth's semi-axes, how deep the funnel goes behind the mouth, and where the
## mouth lies along its opener's axis. Pure.
##
## At a jumpgate (from its markers): the four arms run parallel to the vortex's axis at its top, bottom and sides, the side arms
## further out; the mouth lies at their front ends, an ellipse wider than tall whose rim comes within a metre of the arms, and
## the funnel runs back to their back ends (as deep as an arm is long). At a ship-made point: round (no arms shape it), sized
## for the ship that comes through (`for_ship`), with the gate's proportions, and widened when more ships of the same group
## come out of it (`widen_for`).
##
## The mouth is where ships may pass; the funnel's bright body ends further in (`body_share`) and a faint veil carries on to the
## rim. At a gate the body ends inside the arms' back ends as `jumpgate.png` shows, while the mouth still reaches the arms.

## A ship-made point: the mouth is this many times the ship's bounding radius across (a fighter sits well inside it), never
## smaller than `MIN_POINT_RADIUS_M`; the funnel is `POINT_DEPTH_RATIO` mouth radii deep, about a gate's 1 200 m to 754 m.
const POINT_RADII_PER_SHIP: float = 4.0
const MIN_POINT_RADIUS_M: float = 60.0
const POINT_DEPTH_RATIO: float = 1.6
## Where a gate's markers are missing: the generator's 1 200 m arms 800 m from the axis (the sides 1 240 m).
const FALLBACK_RIM_M: float = 753.9
const FALLBACK_HALF_WIDTH_M: float = 1198.0
const FALLBACK_ARM_M: float = 1200.0
## How much of the mouth's radius the bright body fills. A gate's: fitted to the still's visible edge from its acceptance pose
## (T19 round 4), which lies on the arms' back ends. A ship-made point's: nearly all of it, so a ship of a widened group still
## comes out of the body, not the veil.
const GATE_BODY_SHARE: float = 0.665
const POINT_BODY_SHARE: float = 0.9

## The rim's half height, metres: the radius of a round mouth, and of the largest circle inside an elliptical one.
var mouth_radius_m: float = 0.0
## The rim's half width, metres (the mouth's local x); the same as the radius for a round mouth.
var mouth_half_width_m: float = 0.0
## From the mouth to the funnel's narrow end, metres.
var depth_m: float = 0.0
## Where the mouth lies along the opener's axis, metres (gate-local z; 0 for a ship-made point).
var mouth_z_m: float = 0.0
## The share of the mouth's radius the bright body fills; a faint veil carries on to the rim.
var body_share: float = POINT_BODY_SHARE


func _init(p_mouth_radius_m: float = MIN_POINT_RADIUS_M, p_depth_m: float = MIN_POINT_RADIUS_M * POINT_DEPTH_RATIO,
		p_mouth_z_m: float = 0.0, p_half_width_m: float = 0.0) -> void:
	mouth_radius_m = maxf(p_mouth_radius_m, 1.0)
	mouth_half_width_m = p_half_width_m if p_half_width_m > 0.0 else mouth_radius_m
	depth_m = maxf(p_depth_m, 1.0)
	mouth_z_m = p_mouth_z_m


## A gate's vortex from its `hardpoints.json`: the `vortex` marker's semi-axes (across, up; the generator measures them off the
## arms), depth and centre, else its radius for a round mouth, the arm length for the depth and the arms' front ends for the mouth.
static func for_gate(hardpoints: Dictionary) -> VortexFit:
	var v: Dictionary = hardpoints.get("vortex", {}) if hardpoints.get("vortex") is Dictionary else {}
	var marked: bool = v.has("radius_m") or v.has("semi_axes_m")
	var rim: float = float(v.get("radius_m", FALLBACK_RIM_M))
	var half_width: float = rim if marked else FALLBACK_HALF_WIDTH_M
	var axes: Variant = v.get("semi_axes_m")
	if axes is Array and (axes as Array).size() == 2:
		half_width = float(axes[0])
		rim = float(axes[1])
	var depth: float = float(v.get("depth_m", hardpoints.get("arm_length_m", FALLBACK_ARM_M)))
	var mouth: float = 0.0
	var centre: Variant = v.get("center")
	if centre is Array and (centre as Array).size() == 3:
		mouth = float(centre[2])
	var fit := VortexFit.new(rim, depth, mouth, half_width)
	fit.body_share = GATE_BODY_SHARE
	return fit


## A ship-made point for a ship of `ship_radius_m` (its bounding radius).
static func for_ship(ship_radius_m: float) -> VortexFit:
	var r: float = maxf(POINT_RADII_PER_SHIP * maxf(ship_radius_m, 0.0), MIN_POINT_RADIUS_M)
	return VortexFit.new(r, r * POINT_DEPTH_RATIO)


## The mouth's half width and half height, metres.
func semi_axes() -> Vector2:
	return Vector2(mouth_half_width_m, mouth_radius_m)


## The mouth's width over its height: 1 for a round one.
func aspect() -> float:
	return mouth_half_width_m / mouth_radius_m


## Whether a point `lateral` off the axis (the mouth's local x and y, metres) lies inside the rim grown by `margin` (a share).
func contains(lateral: Vector2, margin: float = 1.0) -> bool:
	return (lateral / (semi_axes() * margin)).length_squared() <= 1.0


## The mouth wide enough for another ship of the group, `lateral_m` off the axis: its whole point fits inside the rim.
func widen_for(lateral_m: float, ship_radius_m: float) -> void:
	var need: float = lateral_m + for_ship(ship_radius_m).mouth_radius_m
	if need > mouth_radius_m:
		mouth_half_width_m *= need / mouth_radius_m
		mouth_radius_m = need
		depth_m = need * POINT_DEPTH_RATIO
