class_name PilotBrain
extends RefCounted
## The seam between a ship and whatever flies it when the player does not (architecture §15.8, D20): a brain looks at a
## `Perception` and writes a `PilotCommand`, flight and combat only, the same two commands the `InputAdapter` writes for the
## player. M2's brains are scripted tactics; M3's `AiPilot` extends this class and changes nothing around it.
##
## Rules for brains: randomness only from a seed set by the spawner (deterministic runs); no wall clock; no scene tree;
## places are remembered as `UniversePos` and turned into World-local points through the perception every tick.
##
## Collision avoidance (§16 D33) is not the brain's job: the `AiPilotDriver` filters the velocity the brain steers toward.
## A brain that seeks a velocity does it through `seek_velocity`, which records it as `desired_velocity`; a brain that
## coasts leaves `has_desired_velocity` false and the driver takes the current velocity as the wish. The driver clears the
## flag before every `think`; a brain that delegates to another clears the inner brain's flag the same way and copies the
## three fields back (`AggroBrain`). `desired_all_axes` says how the thrust was allocated (`PilotSteering.seek`'s
## `all_axes`, for a ship whose nose is held elsewhere: formation keeping, M3-T07), so the driver's avoidance re-seek
## allocates its filtered wish the same way.
##
## A brain whose think landed elsewhere and is read later (`AiPilot` on the core's rows, M4-T33) sets `_native_pending`;
## reading any of the fields below first brings the brain up to date (`_settle_native`).

## World frame, m/s: the velocity this tick's thrust steers toward. Valid while `has_desired_velocity`.
var desired_velocity: Vector3 = Vector3.ZERO:
	get:
		if _native_pending:
			_settle_native()
		return desired_velocity
var has_desired_velocity: bool = false:
	get:
		if _native_pending:
			_settle_native()
		return has_desired_velocity
## The wish was sought with `all_axes` (valid while `has_desired_velocity`).
var desired_all_axes: bool = false:
	get:
		if _native_pending:
			_settle_native()
		return desired_all_axes
## `wanted_target_id`: the driver keeps the nearest hostile selected (M2's rule; every M2 brain leaves it at this).
const TARGET_NEAREST_HOSTILE: int = 0
## `wanted_target_id`: nothing selected (the brain is not attacking anything).
const TARGET_NONE: int = -1

## What the brain wants its ship's targeting computer to select: a `Targetable` id (`Contact.id`), or one of the two
## `TARGET_*` values. The selection is what other ships read as this ship's target (`Contact.target_id`). `AiPilot` sets
## its attack's target, or `TARGET_NONE` while it does something else (M3-T06).
var wanted_target_id: int = TARGET_NEAREST_HOSTILE:
	get:
		if _native_pending:
			_settle_native()
		return wanted_target_id
## A `Contact.id` the driver's avoidance filter leaves out this tick (a committed rammer's target, M3-T13), 0 for none.
var avoid_exempt_id: int = 0:
	get:
		if _native_pending:
			_settle_native()
		return avoid_exempt_id
## Hides with its running lights off until it attacks (M3-T27, Q27; `BrainFactory` sets it). Once it attacks it has stopped hiding,
## for the rest of this life.
var flies_dark: bool = false
## A think that landed elsewhere is still to be read into this brain (M4-T33; see the fields above).
var _native_pending: bool = false


## Brings the fields up to date with a think that landed elsewhere (`AiPilot` overrides it; nothing to do here).
func _settle_native() -> void:
	_native_pending = false


## One tick. `dt` is the physics step. Returns a command the caller owns (a fresh one each call).
func think(_p: Perception, _dt: float) -> PilotCommand:
	return PilotCommand.new()


## For the console (`raiders.selected_brain`): at least `behaviour` and `state`.
func describe() -> Dictionary:
	return {"behaviour": "none", "state": "none"}


## Back to the starting state (a ship acquired again).
func reset() -> void:
	pass


## Whether the brain reads `Perception.target`. A brain that chooses its targets from the contacts (`AiPilot`) says no,
## and the driver saves the `TargetInfo` (AC13's budget): `target` is then null and `target_hostile` false.
func reads_target() -> bool:
	return true


## The `Contact.id`s the driver keeps in this brain's contacts beyond the nearest k (M4-T04): the target it wants.
func keep_ids() -> PackedInt64Array:
	return PackedInt64Array([wanted_target_id]) if wanted_target_id > 0 else PackedInt64Array()


## Display names kept the same way (case-insensitive): none by default.
func keep_names() -> PackedStringArray:
	return PackedStringArray()


## Writes the thrust that moves the velocity toward `v_des` (`PilotSteering.seek`, with `all_axes` for a held nose) into
## `flight` and records the wish, for the driver's avoidance filter.
func seek_velocity(flight: FlightCommand, p: Perception, v_des: Vector3, all_axes: bool = false) -> void:
	desired_velocity = v_des
	has_desired_velocity = true
	desired_all_axes = all_axes
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, v_des, p.basis, p.capability,
			PilotSteering.HORIZON_S, all_axes))
