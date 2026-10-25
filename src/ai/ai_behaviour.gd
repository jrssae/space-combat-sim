class_name AiBehaviour
extends RefCounted
## One thing an `AiPilot` can do (architecture §16 D34): it scores how much it wants control this tick and, while it has
## control, flies the ship. The base class does nothing; M3 has attack, evade, retreat and idle (T06), formation (T07),
## follow path (T09) and guard (T10).
##
## Contract:
## - `id`: the behaviour's name, also its key in `AiProfile.weights` and its place in `AiPilot.TIE_ORDER`.
## - `score(ctx)`: 0..1, every tick, for every behaviour the profile weighs above 0 (one weighted 0 is not asked), before any
##   `think`. A score of 0 means "cannot run now" (no target, nothing to retreat from): the pilot then takes control away
##   at once, dwell or not. Scoring may cache what `think` needs this tick (the chosen target).
## - `enter()`: control was just handed over (start the manoeuvre afresh).
## - `think(ctx, dt)`: only for the behaviour in control; returns a fresh `PilotCommand`. A behaviour that steers toward a
##   velocity uses `seek_velocity`, so the driver's avoidance filter sees the wish and how its thrust was allocated (the
##   `PilotBrain` protocol, M3-T05; `all_axes` for a held nose, M3-T07).
## - `target_id()`: the `Contact.id` the ship's targeting computer should select while this behaviour flies, or
##   `PilotBrain.TARGET_NONE` (the default: a behaviour that does not attack shows no target).
## - `describe()`: at least `state`, for the console.
## - `reset()`: back to the starting state, seeds included (a ship acquired again).
## Randomness only from a seeded generator; time only from `dt` and the perception.

var id: StringName = &""
## The velocity this tick's `think` sought (`seek_velocity`), valid while `has_desired_velocity`.
var desired_velocity: Vector3 = Vector3.ZERO
var has_desired_velocity: bool = false
## The wish was sought with `all_axes` (`PilotBrain.desired_all_axes`).
var desired_all_axes: bool = false


func score(_ctx: AiContext) -> float:
	return 0.0


func enter() -> void:
	pass


func think(_ctx: AiContext, _dt: float) -> PilotCommand:
	return PilotCommand.new()


func target_id() -> int:
	return PilotBrain.TARGET_NONE


func describe() -> Dictionary:
	return {"state": "none"}


func reset() -> void:
	pass


## Writes the thrust toward `v_des` into `flight` (`all_axes` for a held nose) and records the wish for this tick.
func seek_velocity(flight: FlightCommand, p: Perception, v_des: Vector3, all_axes: bool = false) -> void:
	desired_velocity = v_des
	has_desired_velocity = true
	desired_all_axes = all_axes
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, v_des, p.basis, p.capability,
			PilotSteering.HORIZON_S, all_axes))
