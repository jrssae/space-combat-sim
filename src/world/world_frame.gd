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

signal rebased(offset: Vector3)

const SHIFTABLE_GROUP := &"world_shiftable"

## Universe position of the local origin (64-bit).
var origin: UniversePos = UniversePos.new()
## Velocity of the local frame in the system frame, m/s, as [x, y, z]. Always zero in M1: the velocity rebase
## (§14.1) is a roadmap milestone, but the field exists so nothing has to be retrofitted.
var origin_velocity: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## Automatic position rebase: when `focus` is farther than this many metres from the local origin, rebase onto it.
## 0 disables it. M1 leaves it disabled because the play area (about 20 km) does not need it.
@export var auto_rebase_distance_m: float = 0.0
## The object the auto-rebase keeps near the origin (the player ship once it exists). Only read when
## `auto_rebase_distance_m > 0`.
var focus: Node3D = null


func _ready() -> void:
	## TODO(M1-T07): register provider "world" (keys: origin, origin_velocity, auto_rebase_distance_m) and command
	## "rebase <dx> <dy> <dz>" with DebugConsole here, and unregister both in _exit_tree.
	pass


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


## Adds `node` as a child at universe position `at` with orientation `basis`, and makes it shiftable. The transform
## is set before the node enters the tree so a physics body is created where it belongs rather than teleported.
func spawn(node: Node3D, at: UniversePos, basis: Basis = Basis.IDENTITY) -> void:
	assert(node.get_parent() == null, "spawn: %s already has a parent" % node.name)
	node.transform = Transform3D(basis, universe_to_local(at))
	node.add_to_group(SHIFTABLE_GROUP)
	add_child(node)
	node.reset_physics_interpolation()


## Re-centres the local space: every shiftable node moves by `-offset` and `origin` moves by `+offset`, so no
## object's universe position changes. Velocities are untouched (the frame does not move, only its origin label).
## `reset_physics_interpolation()` stops the renderer smearing the jump over the next physics tick.
func rebase(offset: Vector3) -> void:
	for member: Node in get_tree().get_nodes_in_group(SHIFTABLE_GROUP):
		var node := member as Node3D
		if node == null or not is_ancestor_of(node):
			continue
		node.global_position -= offset
		node.reset_physics_interpolation()
	origin = origin.plus_local(offset)
	rebased.emit(offset)


## Acceleration, m/s^2, that the environment applies at a local position (gravity, hyperspace fields). Ships add
## `mass * environment_accel(position)` every physics tick. None exists in M1.
func environment_accel(_local_pos: Vector3) -> Vector3:
	return Vector3.ZERO
