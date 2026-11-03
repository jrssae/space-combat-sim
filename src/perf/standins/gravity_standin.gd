class_name GravityStandin
extends Node
## A moon's pull for the battle benchmark (M4-T07, Q22): bench-only, replaced by M6's Kepler bodies and true gravity. A point
## source at a fixed universe position, installed as `WorldFrame.environment_field`, so every ship and capital feels
## `gm / r^2` toward it through the force step it already has. No body and no visual.

var world: WorldFrame = null
var source: UniversePos = UniversePos.new()
## The source's gravitational parameter, m^3/s^2.
var gm: float = 0.0

var _local: Vector3 = Vector3.ZERO


## Makes `p_world`'s environment pull toward `at` with parameter `p_gm`.
func install(p_world: WorldFrame, at: UniversePos, p_gm: float) -> void:
	world = p_world
	source = at
	gm = p_gm
	_refresh()
	world.environment_field = accel
	if not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)


## Takes the pull away again.
func uninstall() -> void:
	if world == null or not is_instance_valid(world):
		return
	if world.environment_field == Callable(self, &"accel"):
		world.environment_field = Callable()
	if world.rebased.is_connected(_on_rebased):
		world.rebased.disconnect(_on_rebased)


## The pull at a World-local position, m/s^2.
func accel(local_pos: Vector3) -> Vector3:
	var to_source: Vector3 = _local - local_pos
	var r_sq: float = to_source.length_squared()
	if r_sq < 1.0:
		return Vector3.ZERO
	return to_source * (gm / (r_sq * sqrt(r_sq)))


func _exit_tree() -> void:
	uninstall()


func _on_rebased(_offset: Vector3) -> void:
	_refresh()


func _refresh() -> void:
	_local = world.universe_to_local(source)
