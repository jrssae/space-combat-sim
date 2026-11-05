class_name SimCore
extends Node
## The native simulation core's facade (M4-T15, architecture §17.13): one `ScsSimCore` in the crate holds every simulated
## entity as a row (kind, radius, faction, flags, position, velocity, attitude, command, per-kind state), filled from the
## engine at the tick's sync points and read by every native kernel, so the contact field, the hit sweep, the flight step
## and the ram broad phase stop loading copies of their own.
##
## Two nodes under `World`: this one at physics priority -11 does `sync_in` before the AI drivers (-10) read the scan,
## and its internal `SimCoreOut` child at 2 000 000 does `sync_out` after everything (the rebase settler runs at
## 1 000 000), closing the tick's engine-call count; it is the seam where later tasks write rows back. The hit resolver
## (200) asks for the bolts again (`ensure_bolts_synced`), since they moved at 0; bodies touched since the first sync
## (a ship back from the pool, a parked or destroyed one) are read again then. A rebase shifts the node and bolt rows
## once (`rebased`); the static rows come again from `StaticRows` at the next sync.
##
## Threads (M4-T18): the core's per-ship passes (the brains, which `BrainBatch`, an internal child at -9, hands one batch a
## tick, and the flight step) run on `perf_threads` worker threads, set at once whenever the setting changes.
##
## The first consumer attaches it to the world (`attach`, as `FlightBatch` does); `for_tree` gives it to the classes
## that read it, or null when the library lacks the class or `perf_native` or `perf_native_core` is off, and then each
## class loads its own copy as before, so a bench pairs the two paths in one process by flipping `perf_native_core`.
## Console: provider `core`.

const NATIVE_CLASS: StringName = &"ScsSimCore"
const NODE_NAME: StringName = &"SimCore"
const OUT_NODE_NAME: StringName = &"SimCoreOut"
const PRIORITY: int = -11
const OUT_PRIORITY: int = 2_000_000

## Row kinds: `BodyKind`'s values, then the projectile kinds the core adds.
const KIND_SHIP: int = 0
const KIND_CAPITAL: int = 1
const KIND_TURRET: int = 2
const KIND_MISSILE: int = 3
const KIND_MINE: int = 4
const KIND_STATIC: int = 5
const KIND_PROP: int = 6
const KIND_BOLT: int = 7
const KIND_BEAM: int = 8
## Row flags (`ScsSimCore`): a rigid body, a hull, an active hull, a row added after the tick's first sync.
const FLAG_RIGID: int = 1
const FLAG_HULL: int = 2
const FLAG_HULL_ACTIVE: int = 4
const FLAG_LATE: int = 8

# The latest core attached to a tree (-1 for the class check: classes never change while the game runs).
static var _current: SimCore = null
static var _native_class_known: int = -1

## The native core (`ScsSimCore`); null until `_ready`.
var core: Object = null
## The world whose rows these are.
var world: WorldFrame = null
## Physics frames of the last `sync_in` and of the last bolt sync (-1 before the first).
var synced_frame: int = -1
var bolts_frame: int = -1
## Wall-clock microseconds of the last `sync_in` and of the last bolt sync (readouts only, never gameplay time).
var sync_us: int = 0
var bolts_us: int = 0
## Markers and hulls that left the tree since the core was made (a scan built from the core checks its bodies when this
## changed).
var removals: int = 0

var _tree: SceneTree = null
var _members_dirty: bool = true
var _statics_version: int = -1
var _out: Node = null
var _bolts_fresh: bool = false  # the bolts were read again since this tick's first sync


## Runs `sync_out` last in every physics tick (an internal child, so World's children stay its world objects).
class Out extends Node:
	var owner_core: SimCore = null

	func _init(p_owner: SimCore) -> void:
		owner_core = p_owner
		name = OUT_NODE_NAME
		process_physics_priority = OUT_PRIORITY

	func _physics_process(_delta: float) -> void:
		owner_core.sync_out_now()


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


func _ready() -> void:
	core = NativeLib.instantiate(NATIVE_CLASS)
	_out = Out.new(self)
	add_child(_out, false, Node.INTERNAL_MODE_BACK)
	add_child(BrainBatch.new(), false, Node.INTERNAL_MODE_BACK)
	_apply_threads()
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	_hook(get_tree())
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)
	_current = self
	_register_console()


func _exit_tree() -> void:
	_unhook()
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	if world != null and is_instance_valid(world) and world.rebased.is_connected(_on_rebased):
		world.rebased.disconnect(_on_rebased)
	if _current == self:
		_current = null
	DebugConsole.registry.unregister_owner(self)


func _physics_process(_delta: float) -> void:
	if enabled():
		ensure_synced()


## Whether the library provides the core and the settings ask for it (read on every call, so a flip takes effect at once).
static func enabled() -> bool:
	if not NativeLib.enabled() or not bool(Settings.get_value(&"perf_native_core")):
		return false
	if _native_class_known < 0:
		_native_class_known = 1 if NativeLib.has_class(NATIVE_CLASS) else 0
	return _native_class_known == 1


## The core under `world`, made on first ask; null without a world or when the core is off.
static func attach(p_world: Node) -> SimCore:
	if p_world == null or not is_instance_valid(p_world) or not p_world.is_inside_tree() or not enabled():
		return null
	var found := p_world.get_node_or_null(NodePath(NODE_NAME)) as SimCore
	if found != null:
		return found
	var made := SimCore.new()
	made.world = p_world as WorldFrame
	p_world.add_child(made)
	return made


## The core the classes of `tree` read now, or null (none attached, or the core is off).
static func for_tree(tree: SceneTree) -> SimCore:
	if _current == null or not is_instance_valid(_current) or _current.core == null or not enabled():
		return null
	if not _current.is_inside_tree() or _current.get_tree() != tree:
		return null
	return _current


## The latest core, whichever tree, or null.
static func current() -> SimCore:
	return _current if _current != null and is_instance_valid(_current) else null


## Makes sure this physics frame's first sync ran; true when the core holds this frame's rows.
func ensure_synced() -> bool:
	if core == null:
		return false
	if synced_frame != Engine.get_physics_frames():
		_sync_in()
	return true


## Runs the first sync now, whatever the frame (tests, and anything that changed bodies by hand).
func sync_now() -> bool:
	if core == null:
		return false
	_sync_in()
	return true


## Makes sure the bolts (and the bodies touched since the first sync) were read again this frame: the hit resolver's
## sync point, after the bolts moved.
func ensure_bolts_synced() -> bool:
	if not ensure_synced():
		return false
	if not _bolts_fresh:
		_sync_bolts()
	else:
		core.resync_touched_now()  # a hull destroyed since the bolts were read leaves the rows for the next reader
	return true


## Reads the bolts again now, whatever the frame.
func sync_bolts_now() -> bool:
	if not ensure_synced():
		return false
	_sync_bolts()
	return true


## Closes the tick (the `SimCoreOut` node does it at 2 000 000).
func sync_out_now() -> void:
	if core != null:
		core.sync_out()


## Asks the core to read `body`'s row again at the next sync point: for code that changes its faction, name, kind,
## radius, place or activity on a body that stays in play (a pool ship hidden and shown again is noticed by itself).
func touch(body: Node) -> void:
	if core != null and body != null:
		core.touch(body.get_instance_id())


## Forgets every body's attributes, so the next sync reads them all again (`ContactScan.invalidate`).
func forget_attributes() -> void:
	if core != null:
		core.forget_attributes()
	_members_dirty = true


## Rows in the core now (bodies, statics and late rows), -1 without a core.
func rows() -> int:
	return int(core.row_count()) if core != null else -1


## The handle of the row `body_id` has now, 0 for none; the row a handle points at, -1 for none.
func handle_of(body_id: int) -> int:
	return int(core.handle_of(body_id)) if core != null else 0


func row_of(handle: int) -> int:
	return int(core.row_of(handle)) if core != null else -1


## A row's name and position, by handle.
func row_name(handle: int) -> String:
	return String(core.row_name(core.row_of(handle))) if core != null else ""


func row_position(handle: int) -> Vector3:
	return core.row_position(core.row_of(handle)) if core != null else Vector3.INF


## Every node row's body id and position, the bolts' positions and the static rows' positions, as the core holds them.
func body_ids() -> PackedInt64Array:
	return core.body_ids() if core != null else PackedInt64Array()


func body_positions() -> PackedVector3Array:
	return core.body_positions() if core != null else PackedVector3Array()


func bolt_positions() -> PackedVector3Array:
	return core.bolt_positions() if core != null else PackedVector3Array()


func static_positions() -> PackedVector3Array:
	return core.static_positions() if core != null else PackedVector3Array()


## Rows with no node (the seam T20 builds on): `add_row` takes a Dictionary (`kind`, `id`, `faction`, `radius`, `flags`,
## `position`, `velocity`, `basis`, `angular`, `command`, `state`) and gives a handle; `row` gives it back.
func add_row(p_row: Dictionary) -> int:
	return int(core.add_row(p_row)) if core != null else -1


func row(handle: int) -> Dictionary:
	return core.row(handle) if core != null else {}


func set_row_command(handle: int, command: PackedFloat64Array) -> void:
	if core != null:
		core.set_row_command(handle, command)


func remove_row(handle: int) -> void:
	if core != null:
		core.remove_row(handle)


## Engine calls of the last closed tick: `[sync, fallbacks]` (the sync points' reads, and the flight step's reads of the
## physics server for ships without a row; the kernels make none by construction, see `native/src/kernels.rs`).
func engine_calls() -> PackedInt64Array:
	return core.engine_calls() if core != null else PackedInt64Array([-1, -1])


## Which path the classes take now: &"native" with the core on, else &"gdscript".
func path() -> StringName:
	return &"native" if core != null and enabled() else &"gdscript"


func _sync_in() -> void:
	var started: int = Time.get_ticks_usec()  # readout only
	var tree: SceneTree = get_tree()
	if _members_dirty:
		_members_dirty = false
		core.set_members(tree.get_nodes_in_group(Targetable.GROUP), tree.get_nodes_in_group(Damageable.GROUP))
	if _statics_version != StaticRows.version:
		_statics_version = StaticRows.version
		core.set_statics(StaticRows.ids, StaticRows.positions, StaticRows.radii, StaticRows.factions, StaticRows.kinds)
	var frame: int = Engine.get_physics_frames()
	core.sync_in(tree.get_nodes_in_group(Projectile.GROUP), frame, get_physics_process_delta_time())
	synced_frame = frame
	bolts_frame = frame
	_bolts_fresh = false
	sync_us = Time.get_ticks_usec() - started


func _sync_bolts() -> void:
	var started: int = Time.get_ticks_usec()  # readout only
	core.sync_bolts(get_tree().get_nodes_in_group(Projectile.GROUP), get_physics_process_delta_time())
	bolts_frame = Engine.get_physics_frames()
	_bolts_fresh = true
	bolts_us = Time.get_ticks_usec() - started


func _on_rebased(offset: Vector3) -> void:
	if core != null:
		core.shift(-offset)


# --- threads (M4-T18) --------------------------------------------------------------------------------------------


# Gives the core the thread count `perf_threads` asks for (0: the performance cores).
func _apply_threads() -> void:
	if core != null and core.has_method(&"set_threads"):
		core.set_threads(int(Settings.get_value(&"perf_threads")))


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"perf_threads":
		_apply_threads()


# --- the tree's changes ------------------------------------------------------------------------------------------


func _hook(tree: SceneTree) -> void:
	_tree = tree
	_members_dirty = true
	_statics_version = -1
	tree.node_added.connect(_on_node_added)
	tree.node_removed.connect(_on_node_removed)
	for group: StringName in [Targetable.GROUP, Damageable.GROUP]:
		for node: Node in tree.get_nodes_in_group(group):
			_watch(node)


func _unhook() -> void:
	if _tree != null and is_instance_valid(_tree):
		if _tree.node_added.is_connected(_on_node_added):
			_tree.node_added.disconnect(_on_node_added)
		if _tree.node_removed.is_connected(_on_node_removed):
			_tree.node_removed.disconnect(_on_node_removed)
	_tree = null


# A marker or hull joined the tree: the members change, and its body is watched for being hidden, shown or destroyed.
func _on_node_added(node: Node) -> void:
	if node is Targetable or node is Damageable:
		_members_dirty = true
		_watch(node)


func _on_node_removed(node: Node) -> void:
	if node is Targetable or node is Damageable:
		_members_dirty = true
		removals += 1


# Reads a body's row again whenever it is hidden or shown (the pool parks and reuses ships that way) or its hull goes.
func _watch(node: Node) -> void:
	var body := node.get_parent() as Node3D
	if body != null and not body.has_meta(&"_scs_core_watch"):
		body.set_meta(&"_scs_core_watch", true)
		body.visibility_changed.connect(_on_body_touched.bind(body.get_instance_id()))
	var hull := node as Damageable
	if hull != null and body != null and not hull.has_meta(&"_scs_core_watch"):
		hull.set_meta(&"_scs_core_watch", true)
		hull.destroyed.connect(_on_hull_destroyed.bind(body.get_instance_id()))


func _on_body_touched(body_id: int) -> void:
	if core != null:
		core.touch(body_id)


func _on_hull_destroyed(_info: HitInfo, body_id: int) -> void:
	if core != null:
		core.touch(body_id)


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"core", ConsoleVars.new({
		&"path": {"get": path, "doc": "native when the core feeds the scan, the hit sweep, the flight step and the ram broad phase, else gdscript (each loads its own copy)"},
		&"rows": {"get": rows, "doc": "Rows in the core: bodies, static rows and rows added after the tick's first sync"},
		&"bodies": {"get": func() -> int: return int(core.node_count()) if core != null else 0, "doc": "Body rows (active markers and hulls)"},
		&"statics": {"get": func() -> int: return int(core.static_count()) if core != null else 0, "doc": "Static rows (rocks, mines)"},
		&"bolts": {"get": func() -> int: return int(core.bolt_count()) if core != null else 0, "doc": "Bolt rows as of the last bolt sync"},
		&"syncs": {"get": func() -> int: return int(core.syncs()) if core != null else 0, "doc": "First syncs so far"},
		&"sync_us": {"get": func() -> int: return sync_us, "unit": "us", "doc": "The last tick's first sync (bodies, statics, bolts); wall clock"},
		&"bolts_us": {"get": func() -> int: return bolts_us, "unit": "us", "doc": "The last tick's bolt sync (the hit resolver's); wall clock"},
		&"sync_calls": {"get": func() -> int: return engine_calls()[0], "doc": "Engine calls the last closed tick's syncs made (they grow with the rows)"},
		&"fallback_calls": {"get": func() -> int: return engine_calls()[1], "doc": "The flight step's reads of the physics server in the last closed tick, for ships the core had no row for (0 outside launch ticks). The kernels themselves hold no engine type: native/src/kernels.rs"},
		&"attribute_reads": {"get": func() -> int: return int(core.attribute_reads()) if core != null else 0, "doc": "Bodies whose faction, name, kind and radius were read (once per activation, not per tick)"},
		&"touched": {"get": func() -> int: return int(core.touched_count()) if core != null else 0, "doc": "Bodies touched since the last sync point and not read again yet"},
		&"threads": {"get": func() -> int: return int(core.threads()) if core != null else 0, "doc": "Worker threads the per-ship passes (the brains, the flight step) run on (perf_threads; M4-T18)"},
		&"parallel_passes": {"get": func() -> int: return int(core.parallel_passes()) if core != null else 0, "doc": "Passes that ran across the threads so far (a pass with fewer ships than parallel_min stays on the main thread)"},
		&"parallel_min": {"get": func() -> int: return int(core.parallel_min()) if core != null else 0, "doc": "The fewest ships a pass runs in parallel with"},
		&"batch_us": {"get": func() -> int: return _batch().call_us if _batch() != null else 0, "unit": "us", "doc": "The last tick's one native call for every native think (BrainBatch); wall clock"},
		&"batch_ships": {"get": func() -> int: return _batch().ships if _batch() != null else 0, "doc": "Ships the last tick's brain batch carried"},
	}), self)


# The brain batch under this core.
func _batch() -> BrainBatch:
	return get_node_or_null(NodePath(BrainBatch.NODE_NAME)) as BrainBatch
