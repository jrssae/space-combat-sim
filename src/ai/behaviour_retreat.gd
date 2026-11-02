class_name BehaviourRetreat
extends AiBehaviour
## Run for it (architecture §16 D34): below the profile's `retreat_below` hull, with a hostile ship in sensor range, fly away
## from the hostiles at `cruise_mps + EXTRA_MPS`, nearer ones counting more (each pulls with 1 / distance). A faster chaser
## still catches up: a retreat opens the range, it is not an escape. Never fires.
##
## Scores 0 with `retreat_below` 0 (the instructor, raiders that fight to the death), above the threshold, with no hostile in
## sight, or under FORM ON ME (`AiContext.may_retreat`, M3-T07). Below it, `SCORE_MIN` at the threshold up to 1 at zero hull,
## so it outranks an attack. A profile's `retreat_within_m` (M3-T13) also scores `SCORE_MIN` whenever a hostile is that
## near. The threshold comes from the effective profile (`retune`).

const EXTRA_MPS: float = 50.0
const SCORE_MIN: float = 0.85

var retreat_below: float = 0.25
var speed_mps: float = 150.0
var retreat_within_m: float = 0.0

var _from_name: String = ""
var _from_range_m: float = -1.0


func _init(profile: AiProfile) -> void:
	id = &"retreat"
	retreat_below = profile.retreat_below
	speed_mps = profile.cruise_mps + EXTRA_MPS


func retune(profile: AiProfile, _temperament: AiTemperament) -> void:
	retreat_below = profile.retreat_below
	speed_mps = profile.cruise_mps + EXTRA_MPS
	retreat_within_m = profile.retreat_within_m


func score(ctx: AiContext) -> float:
	if ctx.hostiles.is_empty() or not ctx.may_retreat():
		return 0.0
	var hull: float = ctx.perception.hull_fraction
	var low: float = 0.0
	if retreat_below > 0.0 and hull < retreat_below:
		low = SCORE_MIN + (1.0 - SCORE_MIN) * (1.0 - hull / retreat_below)
	if retreat_within_m > 0.0 and low < SCORE_MIN:
		for d: float in ctx.hostile_ranges:
			if d <= retreat_within_m:
				return SCORE_MIN
	return low


func think(ctx: AiContext, _dt: float) -> PilotCommand:
	var p: Perception = ctx.perception
	var cmd := PilotCommand.new()
	var away := Vector3.ZERO
	_from_name = ""
	_from_range_m = INF
	for c: Contact in ctx.hostiles:
		var off: Vector3 = p.position - c.position
		var d: float = maxf(off.length(), 1.0)
		away += off / (d * d)
		if d < _from_range_m:
			_from_range_m = d
			_from_name = c.name
	if away.length_squared() < 1e-18:
		away = p.forward()
	var dir: Vector3 = away.normalized()
	cmd.flight.rot = PilotSteering.face(p.basis, dir, p.capability.rate_max_rad)
	seek_velocity(cmd.flight, p, dir * speed_mps)
	return cmd


func describe() -> Dictionary:
	return {"state": "extend", "from": _from_name,
			"range_m": snappedf(_from_range_m, 1.0) if _from_range_m < INF and _from_range_m >= 0.0 else -1.0}
