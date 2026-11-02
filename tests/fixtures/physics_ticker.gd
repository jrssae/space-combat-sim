class_name PhysicsTicker
extends Node
## Test fixture (M3-T06): counts physics ticks and calls `on_tick` at the end of each one (priority 500, after the drivers,
## the ships and the resolvers), so a Jolt test runs for an exact number of ticks and samples every one of them.

var ticks: int = 0
var on_tick: Callable = Callable()


func _init() -> void:
	process_physics_priority = 500


func _physics_process(_delta: float) -> void:
	ticks += 1
	if on_tick.is_valid():
		on_tick.call()
