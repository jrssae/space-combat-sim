class_name PilotBrain
extends RefCounted
## The seam between a ship and whatever flies it when the player does not (architecture §15.8, D20): a brain looks at a
## `Perception` and writes a `PilotCommand`, flight and combat only, the same two commands the `InputAdapter` writes for the
## player. M2's brains are scripted tactics; M3's `AiPilot` extends this class and changes nothing around it.
##
## Rules for brains: randomness only from a seed set by the spawner (deterministic runs); no wall clock; no scene tree;
## places are remembered as `UniversePos` and turned into World-local points through the perception every tick.

## One tick. `dt` is the physics step. Returns a command the caller owns (a fresh one each call).
func think(_p: Perception, _dt: float) -> PilotCommand:
	return PilotCommand.new()


## For the console (`raiders.selected_brain`): at least `behaviour` and `state`.
func describe() -> Dictionary:
	return {"behaviour": "none", "state": "none"}


## Back to the starting state (a ship acquired again).
func reset() -> void:
	pass
