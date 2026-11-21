class_name CapitalHelm
extends RefCounted
## A capital ship's helm (M10-T07, Q51): it holds a heading and a wanted velocity and gives the `FlightCommand` the flight step
## flies, as a pilot would. Pure, one per ship (it remembers whether it is mid-flip). The `capital` brain (T16) and the player
## at the helm (M11) set `heading` and `velocity`; nothing else steers a capital.
##
## - A gravitic hull, or a reaction hull with retros, keeps its bow on the heading and pushes along every axis it has.
## - A reaction hull with no retros cannot push backward: when it must slow by more than `FLIP_ENTER_MPS` it turns toward the
##   velocity change, burns its mains, and turns back to its heading once the change is met.
## - Turns are paced so the hull can stop on the heading with the torque it has (a 300 m hull turns slowly and must not
##   swing past).

## Mid-flip below this much backward change left, m/s, the helm turns back; above `FLIP_ENTER_MPS` it starts a flip.
const FLIP_EXIT_MPS: float = 0.5
const FLIP_ENTER_MPS: float = 3.0
## The velocity error is met in about this long at full thrust, s: gentle, as a big hull's helm is.
const HORIZON_S: float = 4.0
## The share of the turn rate a hull could still stop from that the helm asks for.
const TURN_MARGIN: float = 0.7

## The way the bow should point (World, unit); zero: hold the bow where it is.
var heading: Vector3 = Vector3.ZERO
## The velocity to hold (World frame, m/s).
var velocity: Vector3 = Vector3.ZERO
## True while a reaction hull with no retros is turned to burn against its motion.
var flipping: bool = false

var _gravitic: bool = false
var _retros: bool = true
var _capability: ShipCapability = null


## A helm for a hull of `spec` with `layout`'s nozzles (its flight spec, `CapitalPropulsion.flight_spec`).
static func make(spec: ShipSpec, layout: ThrusterLayout) -> CapitalHelm:
	var helm := CapitalHelm.new()
	helm._gravitic = CapitalPropulsion.is_gravitic(spec)
	helm._retros = CapitalPropulsion.has_retros(spec)
	helm._capability = ShipCapability.from_spec(spec, layout)
	return helm


## Whether it steers a gravitic drive.
func is_gravitic() -> bool:
	return _gravitic


## What the helm can do (for the console and tests).
func capability() -> ShipCapability:
	return _capability


## This tick's command for a hull at `basis` moving at `current` (World frame).
func command(basis: Basis, current: Vector3) -> FlightCommand:
	var cmd := FlightCommand.new()
	var dv: Vector3 = velocity - current
	var nose: Vector3 = -basis.z
	var aft_need: float = -dv.dot(nose)
	if _retros:
		flipping = false
	elif flipping:
		flipping = dv.length() > FLIP_EXIT_MPS
	else:
		flipping = aft_need > FLIP_ENTER_MPS
	var face: Vector3 = dv if flipping else (heading if heading.length_squared() > 1e-12 else nose)
	cmd.rot = _turn(basis, face)
	var seek: Dictionary = PilotSteering.seek(current, velocity, basis, _capability, HORIZON_S, not flipping)
	if not _retros:
		seek["retro"] = 0.0
	PilotSteering.apply_seek(cmd, seek)
	return cmd


# Pilot `rot` toward `direction`, slowed so the hull can stop on it with the torque it has.
func _turn(basis: Basis, direction: Vector3) -> Vector3:
	var angle: float = PilotSteering.angle_to(basis, direction)
	if angle < 1e-6:
		return Vector3.ZERO
	var alpha: float = minf(_capability.alpha_max_rad.x, _capability.alpha_max_rad.y)
	var gain: float = minf(PilotSteering.K_FACE, TURN_MARGIN * sqrt(2.0 * maxf(alpha, 1e-9) / angle))
	return PilotSteering.face(basis, direction, _capability.rate_max_rad, gain)
