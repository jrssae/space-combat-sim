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
## motion), and nothing blends across the jump. The reset walks the nodes the rebase moved, not the group again (M4-T21), and a
## body parked for the low-attention tier is left where it stands: its row moves with the core and promotion places it. The
## cost is at most one tick of stalled motion per rebase (AC22 (H)). Not
## resetting at all would draw every node sweeping by the offset over that tick: smooth on screen, but anything that mixes
## drawn and tick positions (the HUD's markers through the chase camera, the sky in the cockpit, nodes spawned in that tick) is
## kilometres off for that tick. Hidden (parked) nodes and silent voices are skipped: they are re-placed and reset when they
## come back; so are the nodes that are not interpolated (a far dot's ship, M4-T14). A rebase outside a tick (the console
## between frames) resets at once. The velocity rebase (§14.1) is M6-T05: `origin_velocity` stays zero until then.
##
## The native core (M4-T42): every world attaches its `SimCore` as it becomes ready, so every hull read in it is the core's.
##
## The free-falling frame (M6-T04, D64): with a star system set, the World falls with an anchor (a place on a rail, such as
## the station, or a free-falling test particle on an orbit), and `origin` is measured from that anchor, so every `UniversePos`
## is relative to it. The core holds the anchor in 64-bit. The tick's gravity sample is taken first in the tick
## (`SAMPLE_PRIORITY`), so every mover reads the same one, and the anchor steps last (`FRAME_STEP_PRIORITY`, after the core's
## `sync_out`), with that same sample. Local physics feels only the residual: the pull at a point less the anchor's. With no
## system, or far from every body's zone, the residual is exactly zero and nothing changes from M5.

signal rebased(offset: Vector3)

const SHIFTABLE_GROUP := &"world_shiftable"
const FRAME_ACTIONS: PackedStringArray = ["status", "orbit", "rail", "off"]
## The body `frame orbit` circles when none is named.
const DEFAULT_ORBIT_BODY: StringName = &"epsilon_iii"
## Physics priority of the end-of-tick interpolation reset after a rebase: after every other node of the tick.
const SETTLE_PRIORITY: int = 1_000_000
## The tick's gravity sample: before every mover, the low-attention tier's step (-12) included (M6-T04).
const SAMPLE_PRIORITY: int = -100
## The anchor's own step: last in the tick, after the core's `sync_out`, so the frame moves with Jolt (D64).
const FRAME_STEP_PRIORITY: int = SimCore.OUT_PRIORITY + 1

## Universe position of the local origin (64-bit), measured from the frame's anchor (M6-T04).
var origin: UniversePos = UniversePos.new()
## A pull of the World's own, `func(local_pos: Vector3) -> Vector3`, beside the frame's residual, or empty for none (M4-T07:
## the battle's moon stand-in, removed by M6-T07).
var environment_field: Callable = Callable()
## Velocity of the local frame against its anchor, m/s, as [x, y, z]. Zero while the frame rides its anchor; the velocity
## rebase (M6-T05) moves it.
var origin_velocity: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The star system the frame falls in, or null for none (no pull at all), and the name of its anchor: a place, or the body a
## free-falling anchor circles.
var star_system: StarSystem = null
var anchor_name: StringName = &""
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
## Nodes the last interpolation reset reached (M4-T14): a node that is not interpolated, such as a far dot's ship, is left out.
var last_settle_resets: int = 0

var _settler: Settler = null
var _sim: SimCore = null
# The last sample found a pull near the local space: only then does anything read the residual.
var _gravity_active: bool = false
var _settle_pending: bool = false
var _settled_frame: int = -1
# The nodes the last rebase moved: the end-of-tick reset walks this list, not the group again (M4-T21).
var _shifted: Array[Node3D] = []


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


## Runs one of the frame's two slots of the tick: the gravity sample first, the anchor's step last (D64).
class FrameSlot extends Node:
	var world: WorldFrame = null
	var sample: bool = false

	func _init(p_world: WorldFrame, p_sample: bool) -> void:
		world = p_world
		sample = p_sample
		name = "FrameSample" if sample else "FrameStep"
		process_physics_priority = SAMPLE_PRIORITY if sample else FRAME_STEP_PRIORITY

	func _physics_process(delta: float) -> void:
		if sample:
			world.sample_gravity(SimClock.now())
		else:
			world.step_anchor(delta)


func _ready() -> void:
	_settler = Settler.new(self)
	add_child(_settler, false, Node.INTERNAL_MODE_BACK)
	add_child(FrameSlot.new(self, true), false, Node.INTERNAL_MODE_BACK)
	add_child(FrameSlot.new(self, false), false, Node.INTERNAL_MODE_BACK)
	_sim = SimCore.attach(self)  # every world simulates on the native core (M4-T42), pools or none
	# Console seam (architecture §6.4): `rebase` shifts the origin by hand; `rebases` and `rebase_us` watch the automatic one.
	DebugConsole.registry.register_provider(&"world", ConsoleVars.new({
		&"origin": {"get": _origin_array, "unit": "m", "doc": "Universe position of the local origin (64-bit)"},
		&"origin_velocity": {"get": func() -> PackedFloat64Array: return origin_velocity, "unit": "m/s",
				"doc": "Velocity of the local frame against its anchor; zero while it rides the anchor"},
		&"anchor": {"get": anchor_text, "doc": "What the frame falls with: none, rail <place> or orbit <body>"},
		&"anchor_state": {"get": _anchor_state_km, "unit": "km, m/s",
				"doc": "The anchor against the centre of the body it circles: position (km) then velocity (m/s), game axes"},
		&"gravity": {"get": func() -> bool: return _gravity_active,
				"doc": "Whether anything pulls near the local space this tick (the residual is read only then)"},
		&"anchor_pull": {"get": func() -> Vector3: return _frame_call(&"frame_pull", [], Vector3.ZERO), "unit": "m/s^2",
				"doc": "The pull at the anchor this tick, which the whole frame falls with"},
		&"auto_rebase_distance_m": {"get": func() -> float: return auto_rebase_distance_m, "unit": "m",
				"doc": "Automatic rebase threshold; 0 = off (a bare World), 5 000 in the main scene"},
		&"rebases": {"get": func() -> int: return rebases, "doc": "Rebases so far, automatic and console"},
		&"rebase_us": {"get": func() -> int: return last_rebase_us, "unit": "us",
				"doc": "Cost of the last rebase (profiling only, wall clock)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"frame",
			"The free-falling frame's anchor: status, orbit <altitude km> [body] (a free-falling anchor on a circular orbit, prograde along -Z; default body epsilon_iii), rail <place> (ride a place's orbit, such as babylon5), off (no pull)",
			[ConsoleArg.enum_optional(&"action", FRAME_ACTIONS, &"status"),
			ConsoleArg.string_optional(&"value", null),
			ConsoleArg.string_optional(&"body", null)] as Array[ConsoleArg]), _cmd_frame, self)
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
	# A second rebase before the settle keeps the first one's nodes, so the settle still reaches each of them once.
	var kept: Dictionary[Node3D, bool] = {}
	if _settle_pending:
		for node: Node3D in _shifted:
			if is_instance_valid(node):
				kept[node] = true
	else:
		_shifted.clear()
	for member: Node in get_tree().get_nodes_in_group(SHIFTABLE_GROUP):
		var node := member as Node3D
		if node == null or not is_ancestor_of(node):
			continue
		if node.has_meta(TierDirector.TIER_META):
			continue  # parked for the low-attention tier (M4-T21): its row moves with the core; promotion places the body
		node.global_translate(shift)
		if not kept.has(node):
			_shifted.append(node)
	ContactScan.shift_statics(shift, self)  # this world's scan rows with no node move with its nodes (M4-T09)
	origin = origin.plus_local(offset)
	_push_origin()
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
	last_settle_resets = 0
	for node: Node3D in _shifted:
		if not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree() \
				or not node.is_physics_interpolated_and_enabled():
			continue
		var voice := node as AudioStreamPlayer3D
		if voice == null or voice.playing:
			node.reset_physics_interpolation()
			last_settle_resets += 1
	_shifted.clear()
	last_rebase_us += Time.get_ticks_usec() - started_us


func _origin_array() -> PackedFloat64Array:
	return PackedFloat64Array([origin.x, origin.y, origin.z])


func _cmd_rebase(args: Dictionary) -> ConsoleResult:
	rebase(args[&"offset"])
	return ConsoleResult.line(ConsoleFormat.key_value("world.origin", _origin_array(), "m"))


## Acceleration, m/s^2, that the environment applies at a local position: the frame's residual (M6-T04) plus the World's own
## field. A GDScript mover adds `mass * environment_accel(position)` every physics tick; the flight batch packs only
## `field_accel` and the core adds the residual itself.
func environment_accel(local_pos: Vector3) -> Vector3:
	return field_accel(local_pos) + gravity_residual(local_pos)


## The World's own field at a local position, without the frame's residual: the battle benchmark's moon (M4-T07,
## `GravityStandin`) until M6-T07 removes it.
func field_accel(local_pos: Vector3) -> Vector3:
	if environment_field.is_valid():
		return environment_field.call(local_pos)
	return Vector3.ZERO


## What the frame's fall leaves at a local position this tick: the pull there less the anchor's. Zero with no star system
## or far from every body.
func gravity_residual(local_pos: Vector3) -> Vector3:
	if not _gravity_active:
		return Vector3.ZERO
	return _sim.core.frame_residual(local_pos)


## Whether the tick's sample found anything pulling near the local space.
func gravity_active() -> bool:
	return _gravity_active


## Falls with place `place`'s rail (the station's orbit): nothing integrates, the ephemeris gives its state at each tick's
## time. False, with a warning, when the system or the place cannot be used.
func anchor_on_rail(system: StarSystem, place: StringName) -> bool:
	if not _take_system(system, place):
		return false
	if not _sim.core.frame_anchor_on_rail(system.index_of(place)):
		push_warning("WorldFrame: %s cannot anchor on %s" % [name, place])
		return false
	return _anchored(system, place)


## Falls with a free-falling test particle: `state` is its position then velocity (six numbers, m and m/s, game axes)
## against `body`'s centre now. False, with a warning, when the system, the body or the state cannot be used.
func anchor_in_orbit(system: StarSystem, body: StringName, state: PackedFloat64Array) -> bool:
	if not _take_system(system, body):
		return false
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	if not _sim.core.frame_anchor_in_orbit(system.index_of(body), state, SimClock.now(), dt):
		push_warning("WorldFrame: %s cannot fall round %s from %s" % [name, body, state])
		return false
	return _anchored(system, body)


## No star system: nothing pulls (a bare World's state).
func clear_anchor() -> void:
	star_system = null
	anchor_name = &""
	_gravity_active = false
	if _has_core():
		_sim.core.frame_clear()


## The tick's gravity sample at sim time `time_s`; the first slot of the tick calls it.
func sample_gravity(time_s: float) -> void:
	_gravity_active = _sim.core.frame_sample(time_s) if star_system != null and _has_core() else false


## The anchor's own step; the last slot of the tick calls it.
func step_anchor(dt: float) -> void:
	if star_system != null and _has_core():
		_sim.core.frame_step(dt)


## The anchor against the centre of the body it circles: position then velocity (six numbers, m and m/s, game axes, 64-bit);
## empty with none.
func anchor_state() -> PackedFloat64Array:
	if star_system == null or not _has_core():
		return PackedFloat64Array()
	var raw: PackedFloat64Array = _sim.core.frame_anchor_state(1.0 / float(Engine.physics_ticks_per_second))
	return raw.slice(1) if raw.size() == 7 else PackedFloat64Array()


## What the frame falls with, for the console: `none`, `rail <place>` or `orbit <body>`.
func anchor_text() -> String:
	if star_system == null or not _has_core():
		return "none"
	return "%s %s" % [_sim.core.frame_anchor_kind(), anchor_name]


func _has_core() -> bool:
	return _sim != null and is_instance_valid(_sim) and _sim.core != null


func _take_system(system: StarSystem, id: StringName) -> bool:
	if not _has_core():
		push_warning("WorldFrame: %s has no core, so no frame" % name)
		return false
	if system == null or not system.is_valid() or not system.has_id(id):
		push_warning("WorldFrame: %s: no usable star system with %s" % [name, id])
		return false
	_sim.core.frame_set_system(system.ephemeris(), system.a_min)
	return true


func _anchored(system: StarSystem, id: StringName) -> bool:
	star_system = system
	anchor_name = id
	_push_origin()
	sample_gravity(SimClock.now())
	return true


func _push_origin() -> void:
	if _has_core():
		_sim.core.frame_set_origin(origin.x, origin.y, origin.z)


func _frame_call(method: StringName, args: Array, fallback: Variant) -> Variant:
	if star_system == null or not _has_core():
		return fallback
	return _sim.core.callv(method, args)


func _anchor_state_km() -> PackedFloat64Array:
	var s: PackedFloat64Array = anchor_state()
	for i: int in mini(3, s.size()):
		s[i] /= 1000.0
	return s


func _cmd_frame(args: Dictionary) -> ConsoleResult:
	var action: StringName = args[&"action"]
	var value: Variant = args[&"value"]
	match action:
		&"orbit":
			var altitude_km: float = float(value) if value != null and String(value).is_valid_float() else NAN
			var body: StringName = StringName(args[&"body"]) if args[&"body"] != null else DEFAULT_ORBIT_BODY
			var system: StarSystem = star_system if star_system != null else StarSystem.load_system(StarSystemHost.DEFAULT_SYSTEM)
			if is_nan(altitude_km) or altitude_km < 0.0:
				return ConsoleResult.failure("frame orbit: give an altitude in km of at least 0")
			if not system.is_valid() or system.info(body).is_empty():
				return ConsoleResult.failure("frame orbit: no body %s in the star system" % body)
			var radius_m: float = float(system.info(body)["radius_m"]) + altitude_km * 1000.0
			var speed: float = sqrt(float(system.info(body)["gm"]) / radius_m)
			if not anchor_in_orbit(system, body, PackedFloat64Array([radius_m, 0.0, 0.0, 0.0, 0.0, -speed])):
				return ConsoleResult.failure("frame orbit: refused (see the log)")
		&"rail":
			var system: StarSystem = star_system if star_system != null else StarSystem.load_system(StarSystemHost.DEFAULT_SYSTEM)
			if value == null or not anchor_on_rail(system, StringName(value)):
				return ConsoleResult.failure("frame rail: name a place of the star system, such as babylon5")
		&"off":
			clear_anchor()
	return ConsoleResult.line("world.anchor = %s; world.gravity = %s; world.anchor_pull = %s m/s^2" % [anchor_text(),
			_gravity_active, _frame_call(&"frame_pull", [], Vector3.ZERO)])
