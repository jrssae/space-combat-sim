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
## follow their parent). Never put a node in it whose parent is also in it: it would be shifted twice. A rebase walks the
## group's nodes in play, which `ShiftableRegistry` keeps as they enter and leave the tree (M6-T21): a node its pool or the
## tier parks (`ShiftableRegistry.set_out`) is not walked, and its pool or the tier places it when it comes back.
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
## between frames) resets at once.
##
## The native core (M4-T42): every world attaches its `SimCore` as it becomes ready, so every hull read in it is the core's.
##
## The free-falling frame (M6-T04, D64): with a star system set, the World falls with an anchor (a place on a rail, such as
## the station, or a free-falling test particle on an orbit), and `origin` is measured from that anchor, so every `UniversePos`
## is relative to it. The core holds the anchor in 64-bit. The tick's gravity sample is taken first in the tick
## (`SAMPLE_PRIORITY`), so every mover reads the same one, and the anchor steps last (`FRAME_STEP_PRIORITY`, after the core's
## `sync_out`), with that same sample. Local physics feels only the residual: the pull at a point less the anchor's. With no
## system, or far from every body's zone, the residual is exactly zero and nothing changes from M5.
##
## The velocity rebase (M6-T05, D64, Q8): float32 speeds stay small because the frame takes the focus's velocity when it
## passes `auto_boost_speed_mps`. A boost by `dv` adds `dv` to `origin_velocity` and takes it off every local velocity: the
## core's rows, tier rows and bolts, every body, every shiftable node with `frame_boost(dv)`, and the holders that listen to
## `boosted`. No position changes, so nothing is reset and nothing is seen. A boost is asked for at any time (`boost`, the
## automatic rule in this node's slot at priority 0, after the position rebase) and taken in the frame's last slot of the
## tick, between the movers that step themselves (bolts, debris, the tier) and Jolt's step, so that all of them fly a tick
## in one frame. From then on the local origin falls by itself:
## `origin` moves every tick, and what is tied to the anchor and has no velocity of its own (group `world_anchored`, the
## static rows, the listeners of `drifted`) moves the other way. The core steps the origin in the frame's last slot; `origin`
## and the anchor-tied things take that step when the next tick starts, as the bodies take Jolt's. Under half the threshold against
## the anchor the frame boosts back onto it and rides again. So a shiftable node is one of three things: a mover (a body, or
## it has `frame_boost`), tied to the anchor (also in `world_anchored`), or placed from other nodes every frame (a camera,
## the far dots), which needs neither. A local speed is a speed against the anchor only while the frame rides: readers take
## `rest_velocity()` off (M6-T08).

signal rebased(offset: Vector3)
## A velocity rebase took `dv` off every local velocity: whoever keeps one outside a shiftable node takes it off too.
signal boosted(dv: Vector3)
## The frame is off its anchor and moved this tick: everything tied to the anchor moved by `shift` in local coordinates.
signal drifted(shift: Vector3)

const SHIFTABLE_GROUP := &"world_shiftable"
## Shiftable nodes that stand still against the anchor (a buoy, a gate, a rock field): they move with it while the frame is
## off it. Same rule as `world_shiftable`: never a node whose parent is in it too.
const ANCHORED_GROUP := &"world_anchored"
## The method a shiftable node has when it keeps its own velocity: `frame_boost(dv: Vector3)` takes `dv` off it.
## Meta on a shiftable node its pool has parked out of play (hidden, not processing, out of Jolt): a rebase leaves it where
## it is, since the pool places it when it comes back (M6-T06, L4).
const PARKED_META := &"_scs_pool_parked"
const BOOST_METHOD := &"frame_boost"
## The frame boosts back onto its anchor when the focus is under this part of the threshold against the anchor (Q8).
const RETURN_PART: float = 0.5
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
## Velocity of the local frame against its anchor, m/s, as [x, y, z] (64-bit; the core integrates it). Zero while the frame
## rides its anchor; a boost moves it, and so does the frame's own fall while it is off the anchor.
var origin_velocity: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## Every boost so far, summed (64-bit): what a body that sat out some boosts (parked for the tier) still owes.
var boost_sum: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The star system the frame falls in, or null for none (no pull at all), and the name of its anchor: a place, or the body a
## free-falling anchor circles.
var star_system: StarSystem = null
var anchor_name: StringName = &""
## Where the scenario's origin (a `UniversePos` of zero) stands from the place the World rides (M6-T09): game axes, m, 64-bit;
## zero on an orbit. The anchor is that point, carried along the place's rail.
var anchor_offset: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The system time at sim time 0 (M6-T09, Q9): the scenario's epoch. Everything that asks the ephemeris uses `system_time()`.
var epoch_s: float = 0.0
## Automatic position rebase: when `focus` is farther than this many metres from the local origin, rebase onto it.
## 0 disables it (the default, which bare-World tests rely on); `main.tscn` sets 5 000 m.
@export var auto_rebase_distance_m: float = 0.0
## Automatic velocity rebase (Q8): when `focus` is faster than this against the frame, boost onto it; when it is under half
## of this against the anchor, boost back onto the anchor. 0 disables it (the default, a bare World).
@export var auto_boost_speed_mps: float = 0.0
## The object the automatic rebases follow (the player ship once it exists). Only read when one of them is on.
var focus: Node3D = null
## Rebases so far (automatic and `rebase` alike), and the wall-clock cost of the last one in microseconds (a profiling
## readout, never gameplay time; 0 before the first). The cost covers the shift, the `rebased` handlers and the end-of-tick
## interpolation reset.
var rebases: int = 0
var last_rebase_us: int = 0
## Velocity rebases so far (automatic and console alike), and the wall-clock cost of the last one in microseconds (a
## profiling readout, never gameplay time).
var boosts: int = 0
var last_boost_us: int = 0
## Nodes the last interpolation reset reached (M4-T14): a node that is not interpolated, such as a far dot's ship, is left out.
var last_settle_resets: int = 0

## The rule that destroys a ship on a planet's surface or below its atmosphere's top (M6-T08, D67).
var impact: PlanetImpact = null
var _settler: Settler = null
var _sim: SimCore = null
# The last sample found a pull near the local space: only then does anything read the residual.
var _gravity_active: bool = false
var _settle_pending: bool = false
var _settled_frame: int = -1
# The nodes the last rebase moved: the end-of-tick reset walks this list, not the group again (M4-T21).
var _shifted: Array[Node3D] = []
# The shiftable nodes in play (M6-T21).
var _registry: ShiftableRegistry = null
# What the anchor-tied things still have to move, below what 32 bits could carry in one tick's shift: carried over, so a
# steady drift does not round the same way every tick.
var _drift_owed: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
# The core stepped the local origin at the end of the last tick and `origin` has not taken it yet.
var _origin_stepped: bool = false
# The velocity rebases asked for and not yet taken: a boost (summed), or the way back onto the anchor.
var _boost_asked := Vector3.ZERO
var _return_asked: bool = false


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
			world.sample_gravity(world.system_time())
		else:
			world._take_boosts()
			world.step_anchor(delta)


func _ready() -> void:
	_settler = Settler.new(self)
	add_child(_settler, false, Node.INTERNAL_MODE_BACK)
	add_child(FrameSlot.new(self, true), false, Node.INTERNAL_MODE_BACK)
	add_child(FrameSlot.new(self, false), false, Node.INTERNAL_MODE_BACK)
	impact = PlanetImpact.new(self)
	add_child(impact, false, Node.INTERNAL_MODE_BACK)
	_sim = SimCore.attach(self)  # every world simulates on the native core (M4-T42), pools or none
	_registry = ShiftableRegistry.of_tree(get_tree())
	get_tree().physics_frame.connect(_adopt_origin)
	# Console seam (architecture §6.4): `rebase` shifts the origin by hand; `rebases` and `rebase_us` watch the automatic one.
	DebugConsole.registry.register_provider(&"world", ConsoleVars.new({
		&"origin": {"get": _origin_array, "unit": "m", "doc": "Universe position of the local origin (64-bit)"},
		&"origin_velocity": {"get": func() -> PackedFloat64Array: return origin_velocity, "unit": "m/s",
				"doc": "Velocity of the local frame against its anchor; zero while it rides the anchor"},
		&"riding": {"get": riding, "doc": "Whether the frame rides its anchor (false after a velocity rebase, until it returns)"},
		&"auto_boost_speed_mps": {"get": func() -> float: return auto_boost_speed_mps, "unit": "m/s",
				"doc": "Automatic velocity rebase threshold; 0 = off. Back onto the anchor under half of it"},
		&"boosts": {"get": func() -> int: return boosts, "doc": "Velocity rebases so far, automatic and console"},
		&"boost_us": {"get": func() -> int: return last_boost_us, "unit": "us",
				"doc": "Cost of the last velocity rebase (profiling only, wall clock)"},
		&"anchor": {"get": anchor_text, "doc": "What the frame falls with: none, rail <place> or orbit <body>"},
		&"anchor_state": {"get": _anchor_state_km, "unit": "km, m/s",
				"doc": "The anchor against the centre of the body it circles: position (km) then velocity (m/s), game axes"},
		&"gravity": {"get": func() -> bool: return _gravity_active,
				"doc": "Whether anything pulls near the local space this tick (the residual is read only then)"},
		&"anchor_pull": {"get": func() -> Vector3: return _frame_call(&"frame_pull", [], Vector3.ZERO), "unit": "m/s^2",
				"doc": "The pull at the anchor this tick, which the whole frame falls with"},
		&"rest_velocity": {"get": rest_velocity, "unit": "m/s",
				"doc": "The anchor's velocity in the local frame: what at rest means for the AI and for a ship with no reference (M6-T08)"},
		&"planet_impacts": {"get": func() -> int: return impact.destroyed if impact != null else 0,
				"doc": "Ships destroyed on a planet's surface or below its atmosphere's top so far (M6-T08)"},
		&"last_impact": {"get": func() -> String: return impact.last if impact != null else "",
				"doc": "The last ship destroyed on a planet, and the planet"},
		&"auto_rebase_distance_m": {"get": func() -> float: return auto_rebase_distance_m, "unit": "m",
				"doc": "Automatic rebase threshold; 0 = off (a bare World), 5 000 in the main scene"},
		&"rebases": {"get": func() -> int: return rebases, "doc": "Rebases so far, automatic and console"},
		&"rebase_us": {"get": func() -> int: return last_rebase_us, "unit": "us",
				"doc": "Cost of the last rebase (profiling only, wall clock)"},
		&"shiftables_in_play": {"get": func() -> int: return _registry.in_play(self).size() if _registry != null else 0,
				"doc": "Shiftable nodes a rebase walks: the group less what pools and the tier parked (M6-T21)"},
		&"rocks_live": {"get": func() -> int: return RockBodies.live_total,
				"doc": "Rocks that live as Jolt bodies now, near a ship; the rest are static rows only (M6-T21)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"frame",
			"The free-falling frame's anchor: status, orbit <altitude km> [body] (a free-falling anchor on a circular orbit, prograde along -Z; default body epsilon_iii), rail <place> (ride a place's orbit, such as babylon5), off (no pull)",
			[ConsoleArg.enum_optional(&"action", FRAME_ACTIONS, &"status"),
			ConsoleArg.string_optional(&"value", null),
			ConsoleArg.string_optional(&"body", null)] as Array[ConsoleArg]), _cmd_frame, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"rebase",
			"Shift the local origin by an offset in metres (World.rebase); nothing moves in universe terms. With the automatic rebase on, the next one brings the player back",
			[ConsoleArg.vec3_required(&"offset", PackedStringArray(["dx", "dy", "dz"]))]), _cmd_rebase, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"boost",
			"Velocity rebase by hand (World.boost): the frame gains this velocity in m/s and every local velocity loses it, at the end of the tick; nothing moves differently. With the automatic one on, it brings the frame back",
			[ConsoleArg.vec3_required(&"dv", PackedStringArray(["dvx", "dvy", "dvz"]))]), _cmd_boost, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"ride",
			"Velocity rebase back onto the anchor (World.boost_to_anchor), at the end of the tick: the frame rides its anchor again",
			[] as Array[ConsoleArg]), _cmd_ride, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _registry != null:
		_registry.forget_world(self)
	if get_tree().physics_frame.is_connected(_adopt_origin):
		get_tree().physics_frame.disconnect(_adopt_origin)


func _physics_process(_delta: float) -> void:
	if focus == null or not is_instance_valid(focus):
		return
	if auto_rebase_distance_m > 0.0:
		var focus_pos: Vector3 = focus.global_position
		if focus_pos.length() > auto_rebase_distance_m:
			rebase(focus_pos)
	if auto_boost_speed_mps > 0.0:
		_auto_boost()


## The World `node` lives in (itself or an ancestor), or null outside one.
static func of(node: Node) -> WorldFrame:
	var at: Node = node
	while at != null and not at is WorldFrame:
		at = at.get_parent()
	return at as WorldFrame


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


## Re-centres the local space: every shiftable node in play moves by `-offset` (parked ones wait for their pool or the tier
## to place them) and `origin` moves by `+offset`, so no object's universe position changes. Velocities are untouched
## (the frame does not move, only its origin label).
## `rebased` is emitted last, with everything already shifted. Inside a physics tick the interpolation reset waits for the
## end of the tick (class notes); outside one it happens here.
func rebase(offset: Vector3) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	_adopt_origin()  # between ticks: the core's point is a step ahead, and the new origin is pushed over it below
	var shift: Vector3 = -offset
	# A second rebase before the settle keeps the first one's nodes, so the settle still reaches each of them once.
	var kept: Dictionary[Node3D, bool] = {}
	if _settle_pending:
		for node: Node3D in _shifted:
			if is_instance_valid(node):
				kept[node] = true
	else:
		_shifted.clear()
	# Parked ones are not in play (M6-T21): a tier row moves with the core and promotion places the body (M4-T21); a pool's
	# `acquire` or launch places its node (M6-T06, L4).
	for node: Node3D in _in_play():
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


## Asks for a velocity rebase: the frame gains `dv` against its anchor and every local velocity loses it, so no universe
## position or velocity changes and nothing needs an interpolation reset. It is taken in the frame's last slot of the tick
## (the next tick's when called between ticks); several asked in one tick add up. The frame is off its anchor afterwards
## (class notes).
func boost(dv: Vector3) -> void:
	if dv.is_finite():
		_boost_asked += dv
		_return_asked = false


## Asks for the velocity rebase back onto the anchor, taken in the frame's last slot like `boost`: the frame's own velocity
## goes back into every local velocity and the frame rides its anchor again. Nothing to do while it rides.
func boost_to_anchor() -> void:
	_boost_asked = Vector3.ZERO
	_return_asked = not riding()


## Takes a velocity rebase of `dv` now. Only the frame's last slot is the right moment (hence `boost`): there every mover
## that steps itself has flown this tick in the old frame, and Jolt and the frame's own step are still to come, in the new
## one. Anywhere else those movers and the bodies would change frames a tick apart, `dv` times a tick out of place.
## `boosted` is emitted last.
func apply_boost(dv: Vector3) -> void:
	if dv == Vector3.ZERO or not dv.is_finite():
		return
	if not _has_core():
		push_warning("WorldFrame: %s has no core, so no velocity rebase" % name)
		return
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	_sim.core.boost(dv)
	_boost_nodes(dv, started_us)


## Takes the velocity rebase back onto the anchor now (see `apply_boost` for when).
func apply_boost_to_anchor() -> void:
	if riding():
		return
	var started_us: int = Time.get_ticks_usec()  # profiling readout only
	_boost_nodes(_sim.core.boost_to_anchor(1.0 / float(Engine.physics_ticks_per_second)), started_us)


# The velocity rebases asked for during the tick, taken as one.
func _take_boosts() -> void:
	if _return_asked:
		_return_asked = false
		apply_boost_to_anchor()
	elif _boost_asked != Vector3.ZERO:
		var dv: Vector3 = _boost_asked
		_boost_asked = Vector3.ZERO
		apply_boost(dv)


## Whether the frame rides its anchor: no velocity of its own, `origin` moved only by position rebases.
func riding() -> bool:
	return not _has_core() or _sim.core.frame_riding()


## The anchor's velocity in the local frame, m/s: what "at rest" means here. Zero while the frame rides.
func rest_velocity() -> Vector3:
	return -Vector3(origin_velocity[0], origin_velocity[1], origin_velocity[2])


## The anchor's acceleration in the local frame, m/s^2 (M6-T08): what a ship at rest against it falls with beyond the pull at
## its own place. Zero while the frame rides.
func rest_accel() -> Vector3:
	if not _has_core() or (riding() and origin_velocity[0] == 0.0 and origin_velocity[1] == 0.0 \
			and origin_velocity[2] == 0.0):
		return Vector3.ZERO
	var rest: PackedVector3Array = _sim.core.frame_rest_state()
	return rest[1]


## The body that pulls hardest at a local position, for the HUD's reference (M6-T08): `{index, id, position, velocity, pull}`,
## its centre and velocity in the local frame (64-bit numbers, `PackedFloat64Array` of three) and its pull there; empty
## where nothing pulls.
func reference_body(local_pos: Vector3) -> Dictionary:
	if star_system == null or not _has_core():
		return {}
	var raw: PackedFloat64Array = _sim.core.frame_reference_body(local_pos, _tick_s())
	if raw.size() != 10:
		return {}
	var index: int = int(raw[0])
	return {"index": index, "id": star_system.id_at(index), "position": raw.slice(1, 4), "velocity": raw.slice(4, 7),
			"pull": Vector3(raw[7], raw[8], raw[9])}


## The ships and capitals that hit a body this tick, as `[body id, body index, ...]` (the core checks every row).
func impacts() -> PackedInt64Array:
	if star_system == null or not _has_core():
		return PackedInt64Array()
	return _sim.core.frame_impacts()


## A body or place's centre and velocity in the local frame (six numbers, 64-bit), empty when it cannot be placed.
func body_state(id: StringName) -> PackedFloat64Array:
	if star_system == null or not _has_core() or not star_system.has_id(id):
		return PackedFloat64Array()
	return _sim.core.frame_body_state(star_system.index_of(id), _tick_s())


# The sim time one physics tick covers (what `delta` is), with the engine's time scale in it.
func _tick_s() -> float:
	return Engine.time_scale / float(Engine.physics_ticks_per_second)


## What the boosts since `mark` (an earlier copy of `boost_sum`) took off every local velocity.
func boost_since(mark: PackedFloat64Array) -> Vector3:
	if mark.size() != 3:
		return Vector3.ZERO
	return Vector3(boost_sum[0] - mark[0], boost_sum[1] - mark[1], boost_sum[2] - mark[2])


# The rule of Q8: onto the focus above the threshold against the frame, back onto the anchor under half of it against the
# anchor.
func _auto_boost() -> void:
	var body := focus as RigidBody3D
	if body == null or not _has_core():
		return
	var local: Vector3 = body.linear_velocity
	if not riding() and (local - rest_velocity()).length() < auto_boost_speed_mps * RETURN_PART:
		boost_to_anchor()
	elif local.length() > auto_boost_speed_mps:
		_return_asked = false
		_boost_asked = local  # onto the focus, whatever was asked before


# The nodes' part of a boost the core has already taken: bodies, the nodes that keep a velocity, then the listeners.
func _boost_nodes(dv: Vector3, started_us: int) -> void:
	for node: Node3D in _in_play():
		if node.process_mode == Node.PROCESS_MODE_DISABLED:
			continue  # parked: a tier row holds its velocity (the director settles the body), a pooled one gets a new one
		if node.has_method(BOOST_METHOD):
			node.call(BOOST_METHOD, dv)
		elif node is RigidBody3D:
			(node as RigidBody3D).linear_velocity -= dv
	for axis: int in 3:
		boost_sum[axis] += dv[axis]
	origin_velocity = _sim.core.frame_origin_velocity()
	boosts += 1
	boosted.emit(dv)
	last_boost_us = Time.get_ticks_usec() - started_us


# The frame moved by `moved` (metres, 64-bit) against its anchor this tick: what is tied to the anchor moves the other way.
func _drift_anchored(moved: PackedFloat64Array) -> void:
	var shift := Vector3.ZERO
	for axis: int in 3:
		_drift_owed[axis] -= moved[axis]
		shift[axis] = _drift_owed[axis]
		_drift_owed[axis] -= shift[axis]
	if shift == Vector3.ZERO:
		return
	for member: Node in get_tree().get_nodes_in_group(ANCHORED_GROUP):
		var node := member as Node3D
		if node != null and is_ancestor_of(node):
			node.global_translate(shift)
	ContactScan.shift_statics(shift, self)
	drifted.emit(shift)


# This world's shiftable nodes in play (`ShiftableRegistry`): walk the keys, never change them.
func _in_play() -> Dictionary:
	if _registry == null:
		_registry = ShiftableRegistry.of_tree(get_tree())
	return _registry.in_play(self)


func _origin_array() -> PackedFloat64Array:
	return PackedFloat64Array([origin.x, origin.y, origin.z])


func _cmd_boost(args: Dictionary) -> ConsoleResult:
	boost(args[&"dv"])
	return ConsoleResult.line("boost of %s m/s asked for; world.origin_velocity is %s m/s until the tick ends" % [
			_boost_asked, ConsoleFormat.value(origin_velocity)])


func _cmd_ride(_args: Dictionary) -> ConsoleResult:
	boost_to_anchor()
	return ConsoleResult.line("back onto the anchor when the tick ends" if _return_asked else "the frame rides its anchor")


func _cmd_rebase(args: Dictionary) -> ConsoleResult:
	rebase(args[&"offset"])
	return ConsoleResult.line(ConsoleFormat.key_value("world.origin", _origin_array(), "m"))


## Acceleration, m/s^2, that the environment applies at a local position: gravity, as the frame's residual (D66; the only
## pull since M6-T07). A GDScript mover adds `mass * environment_accel(position)` every physics tick; the flight batch packs
## zero and the core adds the residual itself, as it does for the tier's rows and the bolts.
func environment_accel(local_pos: Vector3) -> Vector3:
	return gravity_residual(local_pos)


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
## time. `offset` is where the scenario's origin stands from the place (`anchor_offset`). False, with a warning, when the
## system or the place cannot be used.
func anchor_on_rail(system: StarSystem, place: StringName, offset: PackedFloat64Array = PackedFloat64Array()) -> bool:
	if not _take_system(system, place):
		return false
	if not _sim.core.frame_anchor_on_rail(system.index_of(place)):
		push_warning("WorldFrame: %s cannot anchor on %s" % [name, place])
		return false
	anchor_offset = offset.duplicate() if offset.size() == 3 else PackedFloat64Array([0.0, 0.0, 0.0])
	return _anchored(system, place)


## The system time now (M6-T09): the scenario's epoch plus the sim clock.
func system_time() -> float:
	return epoch_s + SimClock.now()


## Falls with a free-falling test particle: `state` is its position then velocity (six numbers, m and m/s, game axes)
## against `body`'s centre now. False, with a warning, when the system, the body or the state cannot be used.
func anchor_in_orbit(system: StarSystem, body: StringName, state: PackedFloat64Array) -> bool:
	if not _take_system(system, body):
		return false
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	if not _sim.core.frame_anchor_in_orbit(system.index_of(body), state, system_time(), dt):
		push_warning("WorldFrame: %s cannot fall round %s from %s" % [name, body, state])
		return false
	anchor_offset = PackedFloat64Array([0.0, 0.0, 0.0])
	return _anchored(system, body)


## No star system: nothing pulls (a bare World's state).
func clear_anchor() -> void:
	star_system = null
	anchor_name = &""
	anchor_offset = PackedFloat64Array([0.0, 0.0, 0.0])
	_gravity_active = false
	if _has_core():
		_sim.core.frame_clear()


## The tick's gravity sample at sim time `time_s`; the first slot of the tick calls it.
func sample_gravity(time_s: float) -> void:
	_gravity_active = _sim.core.frame_sample(time_s) if star_system != null and _has_core() else false


## The frame's step; the last slot of the tick calls it. The anchor moves on its orbit, and off the anchor the local origin
## moves too, in the core's 64 bits. `origin` takes the new place when the next tick starts (`_adopt_origin`), with the bodies.
func step_anchor(dt: float) -> void:
	if not _has_core():
		return
	var free: bool = not _sim.core.frame_riding()
	# The tick of the way back still owes the frame one kick; after it the velocity reads zero again.
	var settling: bool = free or origin_velocity[0] != 0.0 or origin_velocity[1] != 0.0 or origin_velocity[2] != 0.0
	if free:
		_push_origin()
	if settling or star_system != null:
		_sim.core.frame_step(dt)
	if settling:
		origin_velocity = _sim.core.frame_origin_velocity()
	_origin_stepped = free


# The start of a tick, before any node's `_physics_process`: Jolt's step is in the bodies now, so the frame's own step of
# the last tick is taken here too. `origin` moves to the core's point and what is tied to the anchor moves the other way.
# Any earlier and the frames drawn between the ticks would hold a new origin beside the bodies' old places.
func _adopt_origin() -> void:
	if not _origin_stepped:
		return
	_origin_stepped = false
	if not _has_core():
		return
	# The core measures from the place itself; `origin` from the scenario's origin beside it.
	var raw: PackedFloat64Array = _sim.core.frame_origin()
	var at := PackedFloat64Array([raw[0] - anchor_offset[0], raw[1] - anchor_offset[1], raw[2] - anchor_offset[2]])
	var moved := PackedFloat64Array([at[0] - origin.x, at[1] - origin.y, at[2] - origin.z])
	origin = UniversePos.new(at[0], at[1], at[2], origin.system_id)
	_drift_anchored(moved)


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
	_sim.core.frame_set_impact_radii(system.impact_radii())
	return true


func _anchored(system: StarSystem, id: StringName) -> bool:
	star_system = system
	anchor_name = id
	_push_origin()
	sample_gravity(system_time())
	return true


func _push_origin() -> void:
	if _has_core():
		_sim.core.frame_set_origin(origin.x + anchor_offset[0], origin.y + anchor_offset[1], origin.z + anchor_offset[2])


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
