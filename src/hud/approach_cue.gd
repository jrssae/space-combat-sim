class_name ApproachCue
extends RefCounted
## The approach cue on a navigation target with an interaction (M8-T18, D84): tells the player in time whether to keep coming,
## brake, or turn, so they stop inside the target's reach instead of overshooting it. Pure: the ship's offset and velocity against
## the target's rest, the reach and the ship's braking in; closing speed, time to reach, stopping distance, the closest approach on
## the present course and one state out. The braking maths is `StoppingDistance`'s, shared with the docking autopilot.

enum State { ON_COURSE, BRAKE, OVERSHOOT, ADJUST_COURSE }
const STATE_NAMES: Array[String] = ["ON COURSE", "BRAKE", "OVERSHOOT", "ADJUST COURSE"]

## The pilot's reaction before the brake bites, s: flown at full speed first.
const REACTION_S: float = 1.0
## BRAKE shows this much flight time (and at least `BRAKE_MARGIN_M`) before braking becomes due, so it reads in time.
const BRAKE_LEAD_S: float = 2.0
const BRAKE_MARGIN_M: float = 50.0
## Slower than this against the target the ship counts as at rest: it has no course to judge.
const MIN_SPEED_MPS: float = 1.0
## A bay's lane is approached from within this angle of its axis; from farther round the ship must come about first.
const LANE_CONE_DEG: float = 60.0
## The bar's scale is the larger of the room and the stopping distance, times this, so the mark never sits at its end.
const BAR_HEADROOM: float = 1.25

var state: State = State.ADJUST_COURSE
## m/s toward the target (negative opening).
var closing_mps: float = 0.0
## m/s against the target's rest, any direction.
var speed_mps: float = 0.0
var distance_m: float = 0.0
var reach_m: float = 0.0
## Metres along the present course to the reach's edge (0 inside it, INF when the course misses it), and to where it leaves it.
var entry_m: float = INF
var exit_m: float = INF
## Seconds to the reach's edge on the present course (0 inside, INF when it misses).
var time_to_reach_s: float = INF
## Metres to rest from now with the brake, the reaction included.
var stopping_m: float = 0.0
## How close the present course comes to the target, m.
var closest_m: float = 0.0


## The cue from `offset` (target minus ship, World) and `velocity` (the ship's against the target's rest), the target's `reach`,
## the ship's braking `decel_mps2`, and, for a bay, its lane's `lane_axis` (unit, the way ships fly in; zero for none).
static func read(offset: Vector3, velocity: Vector3, reach: float, decel_mps2: float, lane_axis: Vector3 = Vector3.ZERO) -> ApproachCue:
	var cue := ApproachCue.new()
	cue.reach_m = reach
	cue.distance_m = offset.length()
	cue.speed_mps = velocity.length()
	cue.closing_mps = velocity.dot(offset) / cue.distance_m if cue.distance_m > 1e-6 else 0.0
	cue.stopping_m = StoppingDistance.distance_m(cue.speed_mps, decel_mps2, REACTION_S)
	var inside: bool = cue.distance_m <= reach
	if cue.speed_mps < MIN_SPEED_MPS:
		cue.closest_m = cue.distance_m
		if inside:
			cue.entry_m = 0.0
			cue.time_to_reach_s = 0.0
			cue.state = State.ON_COURSE
		return cue
	var heading: Vector3 = velocity / cue.speed_mps
	var along: float = heading.dot(offset)
	cue.closest_m = sqrt(maxf(cue.distance_m * cue.distance_m - along * along, 0.0)) if along > 0.0 else cue.distance_m
	var disc: float = along * along - cue.distance_m * cue.distance_m + reach * reach
	if not inside and (along <= 0.0 or disc < 0.0 or _off_lane(offset, lane_axis)):
		return cue  # ADJUST COURSE: this course never enters the reach
	var half_chord: float = sqrt(maxf(disc, 0.0))
	cue.entry_m = 0.0 if inside else along - half_chord
	cue.exit_m = along + half_chord
	cue.time_to_reach_s = cue.entry_m / cue.speed_mps
	var room: float = cue.exit_m if inside else cue.entry_m
	var margin: float = maxf(BRAKE_MARGIN_M, cue.speed_mps * BRAKE_LEAD_S)
	if cue.stopping_m > cue.exit_m:
		cue.state = State.OVERSHOOT
	elif cue.stopping_m >= room - margin:
		cue.state = State.BRAKE
	else:
		cue.state = State.ON_COURSE
	return cue


## The same from World positions and velocities: `target_rest` is the velocity the target sits at rest in (a gate's or a bay's).
static func between(ship_position: Vector3, ship_velocity: Vector3, target_position: Vector3, target_rest: Vector3, reach: float,
		decel_mps2: float, lane_axis: Vector3 = Vector3.ZERO) -> ApproachCue:
	return read(target_position - ship_position, ship_velocity - target_rest, reach, decel_mps2, lane_axis)


func state_name() -> String:
	return STATE_NAMES[state]


## The room the bar measures against: to the reach's edge, or inside it to where the ship would leave it (INF when it misses).
func room_m() -> float:
	return exit_m if entry_m == 0.0 else entry_m


## The bar's fill, 0..1: the stopping distance on the bar's scale.
func bar_fill() -> float:
	var scale: float = _bar_scale()
	return clampf(stopping_m / scale, 0.0, 1.0) if scale > 0.0 else 0.0


## Where the bar's brake mark sits, 0..1: the room left; -1 for no mark (the course misses the reach, or the ship is at rest).
func bar_mark() -> float:
	var scale: float = _bar_scale()
	return clampf(room_m() / scale, 0.0, 1.0) if scale > 0.0 else -1.0


## The readout on the target's box: `+450 m/s  BRAKE`.
func readout_text() -> String:
	return "%+.0f m/s  %s" % [closing_mps, state_name()]


## What the status line adds after the interaction's prompt or status (`— +450 m/s  BRAKE: HOLD S`), from the brake's live
## binding names; "" while the ship is at rest against the target.
func status_suffix(brake_buttons: String) -> String:
	if speed_mps < MIN_SPEED_MPS:
		return ""
	var text: String = " — " + readout_text()
	return text + ": HOLD " + brake_buttons if state == State.BRAKE and not brake_buttons.is_empty() else text


func _bar_scale() -> float:
	var room: float = room_m()
	if not is_finite(room) or speed_mps < MIN_SPEED_MPS:
		return 0.0
	return maxf(room, stopping_m) * BAR_HEADROOM


# Outside a bay's approach cone: the ship is round the side or behind it.
static func _off_lane(offset: Vector3, lane_axis: Vector3) -> bool:
	if lane_axis.is_zero_approx() or offset.is_zero_approx():
		return false
	return (-offset).angle_to(-lane_axis) > deg_to_rad(LANE_CONE_DEG)
