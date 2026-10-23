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
## flag before every `think`; a brain that delegates to another clears the inner brain's flag the same way and copies both
## fields back (`AggroBrain`).

## World frame, m/s: the velocity this tick's thrust steers toward. Valid while `has_desired_velocity`.
var desired_velocity: Vector3 = Vector3.ZERO
var has_desired_velocity: bool = false


## One tick. `dt` is the physics step. Returns a command the caller owns (a fresh one each call).
func think(_p: Perception, _dt: float) -> PilotCommand:
	return PilotCommand.new()


## For the console (`raiders.selected_brain`): at least `behaviour` and `state`.
func describe() -> Dictionary:
	return {"behaviour": "none", "state": "none"}


## Back to the starting state (a ship acquired again).
func reset() -> void:
	pass


## Writes the thrust that moves the velocity toward `v_des` (`PilotSteering.seek`) into `flight` and records `v_des` as
## this tick's desired velocity, for the driver's avoidance filter.
func seek_velocity(flight: FlightCommand, p: Perception, v_des: Vector3) -> void:
	desired_velocity = v_des
	has_desired_velocity = true
	PilotSteering.apply_seek(flight, PilotSteering.seek(p.velocity, v_des, p.basis, p.capability))
