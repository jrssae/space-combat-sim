class_name Trigger
extends RefCounted
## A mission condition (architecture §18 D52): a pure predicate over a `MissionWorld` snapshot, tested once per physics tick
## while it is live (awaited by a step, or an active objective's success or fail). Each kind is its own class and builds from
## JSON through `TriggerSpec`.
##
## Skipping (D51): `make_true` forces an awaited trigger, so the world ends where the step would have left it. A kind's
## `force` sits next to its `test` and changes the world (places an actor, releases ships, finishes a line); kinds with nothing
## to change (a timer, an input) only latch.

## The kind's name in JSON (`proximity`, `area`, `timer`, `destroyed`, `dialog_finished`, `input_performed`, `arrived`).
var kind: StringName = &""
## Made true by a skip: the trigger holds from now on.
var forced: bool = false


## The actor names this trigger reads, so the stage refreshes only those.
func actors() -> PackedStringArray:
	return PackedStringArray()


## The fixed place this trigger is about (an area's centre, a point to reach), or null: the target menu offers an objective
## with one as a waypoint (M5-T25).
func place() -> UniversePos:
	return null


## Called when the trigger goes live (a timer starts counting here).
func arm(_world: MissionWorld) -> void:
	pass


## The condition itself, on this tick's snapshot.
func test(_world: MissionWorld) -> bool:
	return false


## Changes the world so the condition holds (D51's skip).
func force(_world: MissionWorld) -> void:
	pass


## One line for the console and the log.
func describe() -> String:
	return String(kind)


## Whether the trigger holds this tick: forced, or its test passes. Counts one unit of work.
func check(world: MissionWorld) -> bool:
	world.work += 1
	return forced or test(world)


## Forces the condition and latches it.
func make_true(world: MissionWorld) -> void:
	force(world)
	forced = true
