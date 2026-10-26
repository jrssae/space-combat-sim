class_name WorldFrame
extends Node3D
## The `World` node: the local Jolt and render space, and the single place that maps it to universe coordinates
## (architecture §10, §14.1). Every world object is spawned under it from a `UniversePos`, so that large-world
## support (rebasing now, moving frames and tidal gravity later) never has to re-parent scenes or audit raw
## `Vector3` positions.
##
## The node itself stays at the identity transform; only its children move. `origin` is the universe position of
## local (0, 0, 0). A rebase by `offset` moves every `world_shiftable` object by `-offset` and adds `offset` to
## `origin`, so `to_universe(local)` of any object is unchanged.
##
## Group `world_shiftable` is for objects that are direct children of this node, or `top_level` nodes (which do not
## follow their parent). Never put a node in it whose parent is also in it: it would be shifted twice.
##
## The automatic position rebase (§14.1) keeps `focus` (the player) within `auto_rebase_distance_m` of the local origin, so
## float32 positions stay fine-grained however far the player flies (maintainer Q13: at 900 km a float32 coordinate steps in
## 6.25 cm). A bare `WorldFrame` keeps it off (0); the main scene sets 5 000 m (M3-T14). It runs in this node's
## `_physics_process` at priority 0: after the AI drivers (-10), the console and `Main`, before every node below `World` (ships,
## bolts, props, effects) and the late systems (targeting 100, hits 200, rams 210, wings 290, waves 300). Commands built before
## it are levels and rates, so they stay valid; everything after it sees the new frame. Systems that keep a place between ticks
## keep a `UniversePos` (or rebuild it from the live nodes each tick); the few that must keep a World-local point listen to
## `rebased` and shift it (`RamResolver`).
##
## Physics interpolation: every shifted node's interpolation is reset, so the frame after a rebase draws the bodies at their
## current tick with no blend (a hitch of at most one tick, the same for every body; nodes that move themselves later in the
## tick, such as bolts, blend from their shifted place). Nothing is left blending across the jump. The velocity rebase (§14.1)
## is roadmap M5: `origin_velocity` stays zero.

signal rebased(offset: Vector3)

const SHIFTABLE_GROUP := &"world_shiftable"

## Universe position of the local origin (64-bit).
var origin: UniversePos = UniversePos.new()
## Velocity of the local frame in the system frame, m/s, as [x, y, z]. Always zero in M1: the velocity rebase
## (§14.1) is a roadmap milestone, but the field exists so nothing has to be retrofitted.
var origin_velocity: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## Automatic position rebase: when `focus` is farther than this many metres from the local origin, rebase onto it.
## 0 disables it (the default, which bare-World tests rely on); `main.tscn` sets 5 000 m.
@export var auto_rebase_distance_m: float = 0.0
## The object the auto-rebase keeps near the origin (the player ship once it exists). Only read when
## `auto_rebase_distance_m > 0`.
var focus: Node3D = null
## Rebases so far (automatic and `rebase` alike), and the wall-clock cost of the last one in microseconds (a profiling
## readout, never gameplay time; 0 before the first).
var rebases: int = 0
var last_rebase_us: int = 0


func _ready() -> void:
	# Console seam (architecture §6.4): `rebase` shifts the origin by hand; `rebases` and `rebase_us` watch the automatic one.
	DebugConsole.registry.register_provider(&"world", ConsoleVars.new({
		&"origin": {"get": _origin_array, "unit": "m", "doc": "Universe position of the local origin (64-bit)"},
		&"origin_velocity": {"get": func() -> PackedFloat64Array: return origin_velocity, "unit": "m/s",
				"doc": "Velocity of the local frame; zero in M1"},
		&"auto_rebase_distance_m": {"get": func() -> float: return auto_rebase_distance_m, "unit": "m",
				"doc": "Automatic rebase threshold; 0 = off (a bare World), 5 000 in the main scene"},
		&"rebases": {"get": func() -> int: return rebases, "doc": "Rebases so far, automatic and console"},
		&"rebase_us": {"get": func() -> int: return last_rebase_us, "unit": "us",
				"doc": "Cost of the last rebase (profiling only, wall clock)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"rebase",
			"Shift the local origin by an offset in metres (World.rebase); nothing moves in universe terms. With the automatic rebase on, the next one brings the player back",
			[ConsoleArg.vec3_required(&"offset", PackedStringArray(["dx", "dy", "dz"]))]), _cmd_rebase, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(_delta: float) -> void:
	if auto_rebase_distance_m <= 0.0 or focus == null or not is_instance_valid(focus):
		return
	var focus_pos: Vector3 = focus.global_position
	if focus_pos.length() > auto_rebase_distance_m:
		rebase(focus_pos)


## Local `World` coordinates of a universe position (the milestone doc calls this `to_local`). Only meaningful for
## positions near the origin (see `UniversePos.offset_to`). Named `universe_to_local` because `Node3D.to_local` is a
## native method: GDScript refuses an override with a different signature.
func universe_to_local(u: UniversePos) -> Vector3:
	return origin.offset_to(u)


## Universe position of a local `World` coordinate, summed in 64-bit. Inverse of `universe_to_local`.
func to_universe(local: Vector3) -> UniversePos:
	return origin.plus_local(local)


## Adds `node` at universe position `at` with orientation `basis`, and makes it shiftable. The transform is set
## before the node enters the tree so a physics body is created where it belongs rather than teleported. `parent`
## (default: World itself) may be any container below World, e.g. Main's `Targets`; it must already be in the tree.
func spawn(node: Node3D, at: UniversePos, basis: Basis = Basis.IDENTITY, parent: Node3D = null) -> void:
	assert(node.get_parent() == null, "spawn: %s already has a parent" % node.name)
	var world_local := Transform3D(basis, universe_to_local(at))
	if parent == null or parent == self:
		node.transform = world_local
		parent = self
	else:
		assert(is_ancestor_of(parent), "spawn: parent %s is not inside World" % parent.name)
		var parent_in_world: Transform3D = global_transform.affine_inverse() * parent.global_transform
		node.transform = parent_in_world.affine_inverse() * world_local
	node.add_to_group(SHIFTABLE_GROUP)
	parent.add_child(node)
	node.reset_physics_interpolation()


## Re-centres the local space: every shiftable node moves by `-offset` and `origin` moves by `+offset`, so no
## object's universe position changes. Velocities are untouched (the frame does not move, only its origin label).
## `reset_physics_interpolation()` stops the renderer smearing the jump over the next physics tick. `rebased` is emitted
## last, with everything already shifted.
func rebase(offset: Vector3) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	for member: Node in get_tree().get_nodes_in_group(SHIFTABLE_GROUP):
		var node := member as Node3D
		if node == null or not is_ancestor_of(node):
			continue
		node.global_position -= offset
		node.reset_physics_interpolation()
	origin = origin.plus_local(offset)
	rebases += 1
	rebased.emit(offset)
	last_rebase_us = Time.get_ticks_usec() - started_us


func _origin_array() -> PackedFloat64Array:
	return PackedFloat64Array([origin.x, origin.y, origin.z])


func _cmd_rebase(args: Dictionary) -> ConsoleResult:
	rebase(args[&"offset"])
	return ConsoleResult.line(ConsoleFormat.key_value("world.origin", _origin_array(), "m"))


## Acceleration, m/s^2, that the environment applies at a local position (gravity, hyperspace fields). Ships add
## `mass * environment_accel(position)` every physics tick. None exists in M1.
func environment_accel(_local_pos: Vector3) -> Vector3:
	return Vector3.ZERO
