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
## Physics interpolation: the whole world stalls together for the one tick of a rebase. A rebase inside a physics tick leaves
## the interpolation alone and resets it last in that tick (`SETTLE_PRIORITY`), after every node has moved, on every visible,
## interpolated shiftable node; so the frames until the next tick draw everything at its tick pose with no blend (bodies,
## bolts, debris, effects and the cameras alike: what the HUD projects is what is drawn, and view-relative positions keep their
## motion), and nothing blends across the jump. The cost is at most one tick of stalled motion per rebase (AC22 (H)). Not
## resetting at all would draw every node sweeping by the offset over that tick: smooth on screen, but anything that mixes
## drawn and tick positions (the HUD's markers through the chase camera, the sky in the cockpit, nodes spawned in that tick) is
## kilometres off for that tick. Hidden (parked) nodes and silent voices are skipped: they are re-placed and reset when they
## come back. A rebase outside a tick (the console between frames) resets at once. The velocity rebase (§14.1) is roadmap
## M6: `origin_velocity` stays zero.

signal rebased(offset: Vector3)

const SHIFTABLE_GROUP := &"world_shiftable"
## Physics priority of the end-of-tick interpolation reset after a rebase: after every other node of the tick.
const SETTLE_PRIORITY: int = 1_000_000

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
## readout, never gameplay time; 0 before the first). The cost covers the shift, the `rebased` handlers and the end-of-tick
## interpolation reset.
var rebases: int = 0
var last_rebase_us: int = 0

var _settler: Settler = null
var _settle_pending: bool = false
var _settled_frame: int = -1


## Runs `WorldFrame._settle` last in every physics tick (an internal child, so World's children stay its world objects).
class Settler extends Node:
	var world: WorldFrame = null

	func _init(p_world: WorldFrame) -> void:
		world = p_world
		name = "RebaseSettler"
		process_physics_priority = SETTLE_PRIORITY
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _physics_process(_delta: float) -> void:
		world._settled_frame = Engine.get_physics_frames()
		if world._settle_pending:
			world._settle()


func _ready() -> void:
	_settler = Settler.new(self)
	add_child(_settler, false, Node.INTERNAL_MODE_BACK)
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
## `rebased` is emitted last, with everything already shifted. Inside a physics tick the interpolation reset waits for the
## end of the tick (class notes); outside one it happens here.
func rebase(offset: Vector3) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	var shift: Vector3 = -offset
	for member: Node in get_tree().get_nodes_in_group(SHIFTABLE_GROUP):
		var node := member as Node3D
		if node != null and is_ancestor_of(node):
			node.global_translate(shift)
	origin = origin.plus_local(offset)
	rebases += 1
	rebased.emit(offset)
	last_rebase_us = Time.get_ticks_usec() - started_us
	if Engine.is_in_physics_frame() and _settled_frame != Engine.get_physics_frames():
		_settle_pending = true
	else:
		_settle()


## Drops the interpolation history of every visible, interpolated shiftable node, so the frames until the next tick draw
## each at its tick pose (class notes). Hidden nodes (parked pool ships and debris) and silent voices are skipped: nothing
## draws or hears them, and `acquire`, `launch` and `AudioDirector.play` place and reset them when they come back. Its cost
## is added to `last_rebase_us`.
func _settle() -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only
	_settle_pending = false
	for member: Node in get_tree().get_nodes_in_group(SHIFTABLE_GROUP):
		var node := member as Node3D
		if node == null or not node.is_visible_in_tree() or not node.is_physics_interpolated_and_enabled() \
				or not is_ancestor_of(node):
			continue
		var voice := node as AudioStreamPlayer3D
		if voice == null or voice.playing:
			node.reset_physics_interpolation()
	last_rebase_us += Time.get_ticks_usec() - started_us


func _origin_array() -> PackedFloat64Array:
	return PackedFloat64Array([origin.x, origin.y, origin.z])


func _cmd_rebase(args: Dictionary) -> ConsoleResult:
	rebase(args[&"offset"])
	return ConsoleResult.line(ConsoleFormat.key_value("world.origin", _origin_array(), "m"))


## Acceleration, m/s^2, that the environment applies at a local position (gravity, hyperspace fields). Ships add
## `mass * environment_accel(position)` every physics tick. None exists in M1.
func environment_accel(_local_pos: Vector3) -> Vector3:
	return Vector3.ZERO
