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
## once (`rebased`); the static rows' new places come from `StaticRows` at the next sync, alone when only they changed
## (M6-T06).
##
## Threads (M4-T18): the core's per-ship passes (the brains, which `BrainBatch`, an internal child at -9, hands one batch a
## tick, and the flight step) run on `perf_threads` worker threads, set at once whenever the setting changes.
##
## The core's state from events (M4-T35b): a body's activity is checked again only when it is
## touched (hidden, shown, destroyed: the events this facade already watched), its hull column follows `Damageable.damaged`
## and `restored`, its selection column every change a `TargetingController` makes (`note_selection_changed`); the columns are written to the rows at the
## sync points, so the rows hold what a read at the sync would. The AI targeting controllers' selection check runs here at
## their priority (`SimCoreTargeting`), and the ram resolver's contact read in one native call.
##
## Bolts as rows (M4-T35): the core owns its bolts. Every cannon but the player's registers with
## `ScsCannons` (`register_cannon`), and an internal `SimCoreStep` child at priority 1 (after the drivers, `Main` and the
## World's rebase at 0, before the targeting at 100 and the resolvers) steps every cannon's gate in one call, spawns each
## shot as an owned bolt row, hands the shots back to their cannons (the flash, the signal), and then steps every owned
## bolt (`step_bolts`: expiry, then `velocity * delta`). The hit resolver sweeps and spends the rows; the next tick's first
## sync drops the spent ones, as a spent node is gone by then. Beams and missiles keep their nodes and follow the owned rows in the table at each sync. A `BoltMesh` child
## draws the rows, one multimesh a look, interpolated between ticks as the nodes were.
##
## Defensive turrets (M5-T21, D61): `turrets` (`TurretRows`) binds every `TurretMount` to a mount row in the core and is
## stepped in `step_now` after the cannons, its shots owned bolt rows like theirs; the hit resolver notes each hit's shooter
## and victim here (`note_hit`, the attacker memory), a destroyed hull is forgotten there, and the turrets' pick rides in
## the AI job (`BrainBatch`), which launches for them even when no AI ship thinks.
##
## Every world attaches its core as it becomes ready (M4-T42, `WorldFrame`), so it is the one hull read: `for_tree` gives
## it to the classes that read it, or null in a tree with no world. One world per tree: a second world, while the first
## world's core is live, is refused its core (with one error).
## Console: provider `core`.

const NATIVE_CLASS: StringName = &"ScsSimCore"
## The cheaper bolt read at the sync points (M4-T34); the core's own read stays the reference.
const BOLT_SYNC_CLASS: StringName = &"ScsBoltSync"
## The cannons as rows and the bolt kernel (M4-T35).
const CANNONS_CLASS: StringName = &"ScsCannons"
const NODE_NAME: StringName = &"SimCore"
const OUT_NODE_NAME: StringName = &"SimCoreOut"
const STEP_NODE_NAME: StringName = &"SimCoreStep"
const TARGETING_NODE_NAME: StringName = &"SimCoreTargeting"
const PRIORITY: int = -11
const OUT_PRIORITY: int = 2_000_000
## The cannon and bolt step: after every priority-0 node (the drivers' commands, the player's, the World's rebase), before
## the targeting (100) and the hit resolver (200).
const STEP_PRIORITY: int = 1
## Floats per bolt instance in a multimesh buffer, and the look of a bolt no multimesh draws.
const BOLT_INSTANCE_FLOATS: int = 12
const LOOK_NONE: int = 255

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
## Row flags (`ScsSimCore`) GDScript reads: a rigid body, a hull, an active hull, a low-attention tier row (M4-T21).
const FLAG_RIGID: int = 1
const FLAG_HULL: int = 2
const FLAG_HULL_ACTIVE: int = 4
const FLAG_TIER: int = 16

# The latest core attached to a tree.
static var _current: SimCore = null
# The civilian ships by body id (M5-T21): every core is told, so the turrets defend them.
static var _civilians: Dictionary[int, bool] = {}
## Warnings that bodies were asked about in a tree with no world (said once a run).
static var no_world_warnings: int = 0

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
## Wall-clock microseconds of the last tick's native `sync_in` call alone, and of the last `snapshot` and `select` calls
## (readouts only).
var core_sync_us: int = 0
var snapshot_us: int = 0
var select_us: int = 0
## Markers and hulls that left the tree since the core was made (a scan built from the core checks its bodies when this
## changed).
var removals: int = 0
## The cannons as rows (`ScsCannons`, M4-T35); null without the class.
var cannons: Object = null
## Wall-clock microseconds of the last tick's cannon step and bolt step (readouts only), and the shots and expiries it made.
var cannon_us: int = 0
var bolt_step_us: int = 0
var shots_last_tick: int = 0
var expired_last_tick: int = 0

var _tree: SceneTree = null
var _members_dirty: bool = true
# The readouts summed since `reset_window` (a bench's measured window): first syncs, their time, the native call's share,
# the bolt syncs' time, and the snapshot and select calls with their time.
var _window_syncs: int = 0
var _window_sync_us: int = 0
var _window_core_sync_us: int = 0
var _window_bolts_us: int = 0
var _window_snapshots: int = 0
var _window_snapshot_us: int = 0
var _window_selects: int = 0
var _window_parts_us: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0])
var _window_select_us: int = 0
var _statics_version: int = -1
var _statics_moves: int = -1
var _out: Node = null
var _bolts_fresh: bool = false  # the bolts were read again since this tick's first sync
var _bolt_sync: Object = null  # the bolt reader (M4-T34), made on first use
var _tick_open: bool = false  # a sync_in since the last sync_out: the next sync_in closes the tick's count, as the core's does
var _cannons_by_slot: Dictionary[int, PulseCannon] = {}
var _selection_controllers: Dictionary[int, TargetingController] = {}
var _refused_a_world: bool = false  # a second world was refused while this core was live (said once)
## Selections the core's check cleared in the last tick (a readout).
var selection_clears_last_tick: int = 0
var _bolt_mesh: BoltMesh = null
## The defensive turrets on the core (M5-T21).
var turrets: TurretRows = null


## Runs `sync_out` last in every physics tick (an internal child, so World's children stay its world objects).
class Out extends Node:
	var owner_core: SimCore = null

	func _init(p_owner: SimCore) -> void:
		owner_core = p_owner
		name = OUT_NODE_NAME
		process_physics_priority = OUT_PRIORITY

	func _physics_process(_delta: float) -> void:
		owner_core.sync_out_now()


## Runs the watched AI controllers' selection check at their priority (M4-T35; an internal child).
class Targeting extends Node:
	var owner_core: SimCore = null

	func _init(p_owner: SimCore) -> void:
		owner_core = p_owner
		name = TARGETING_NODE_NAME
		process_physics_priority = TargetingController.LATE_PRIORITY

	func _physics_process(_delta: float) -> void:
		owner_core.check_selections_now()


## Steps the cannons and the owned bolts once a tick at `STEP_PRIORITY` (M4-T35; an internal child).
class Step extends Node:
	var owner_core: SimCore = null

	func _init(p_owner: SimCore) -> void:
		owner_core = p_owner
		name = STEP_NODE_NAME
		process_physics_priority = STEP_PRIORITY

	func _physics_process(delta: float) -> void:
		owner_core.step_now(delta)


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


func _ready() -> void:
	core = NativeLib.instantiate(NATIVE_CLASS)
	cannons = NativeLib.instantiate(CANNONS_CLASS)
	turrets = TurretRows.new(self)
	_out = Out.new(self)
	add_child(_out, false, Node.INTERNAL_MODE_BACK)
	add_child(BrainBatch.new(), false, Node.INTERNAL_MODE_BACK)
	add_child(Step.new(self), false, Node.INTERNAL_MODE_BACK)
	add_child(Targeting.new(self), false, Node.INTERNAL_MODE_BACK)
	_bolt_mesh = BoltMesh.new(self)
	add_child(_bolt_mesh, false, Node.INTERNAL_MODE_BACK)
	_apply_threads()
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	_hook(get_tree())
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)
	_current = self
	_register_console()
	PulseCannon.rebind_all()
	TargetingController.rebind_all()
	for body_id: int in _civilians.keys():
		if is_instance_id_valid(body_id):
			core.set_civilian(body_id, true)
		else:
			_civilians.erase(body_id)  # a ship freed with an earlier scene (code review 2026-11-12: the set only grew)
	TurretMount.rebind_all()


func _exit_tree() -> void:
	_unhook()
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)
	if world != null and is_instance_valid(world) and world.rebased.is_connected(_on_rebased):
		world.rebased.disconnect(_on_rebased)
	DebugConsole.registry.unregister_owner(self)
	NativeBrains.drop_for(core)
	if _current == self:
		_current = null
	PulseCannon.rebind_all()
	TargetingController.rebind_all()
	TurretMount.rebind_all()


func _physics_process(_delta: float) -> void:
	ensure_synced()


## The core under `world`, made on first ask; null without a world, and null with
## one error when another world's core is live: one world per tree.
static func attach(p_world: Node) -> SimCore:
	if p_world == null or not is_instance_valid(p_world) or not p_world.is_inside_tree():
		return null
	var found := p_world.get_node_or_null(NodePath(NODE_NAME)) as SimCore
	if found != null:
		return found
	var live: SimCore = current()
	if live != null and live.is_inside_tree():
		if not live._refused_a_world:
			live._refused_a_world = true
			push_error("SimCore: %s is a second world while %s has the core; one world per tree, so it gets none"
					% [p_world.get_path(), live.get_parent().get_path()])
		return null
	var made := SimCore.new()
	made.world = p_world as WorldFrame
	p_world.add_child(made)
	return made


## The core the classes of `tree` read now, or null (no world in the tree, so none attached). Bodies in a tree with no
## world get no contacts, hits or rams, so the first such ask in a run warns.
static func for_tree(tree: SceneTree) -> SimCore:
	if _current != null and is_instance_valid(_current) and _current.core != null and _current.is_inside_tree() \
			and _current.get_tree() == tree:
		return _current
	if no_world_warnings == 0 and tree != null and (tree.has_group(Damageable.GROUP) or tree.has_group(Targetable.GROUP)):
		no_world_warnings += 1
		push_warning("SimCore: bodies in a tree with no world, so no core: they get no contacts, hits or rams "
				+ "(build them under a WorldFrame)")
	return null


## The latest core, whichever tree, or null.
static func current() -> SimCore:
	return _current if _current != null and is_instance_valid(_current) else null


## A ship's selection changed (`TargetingController` says so on every change): the latest core notes it for its selection
## column and its selection check (M4-T35).
## A body moved by script after the tick's first sync (a nav buoy's drift): its row is read again before the late systems.
static func touch_moved(body: Node) -> void:
	var sim: SimCore = current()
	if sim != null:
		sim.touch(body)


static func note_selection_changed(body_id: int, selected_id: int) -> void:
	if _current != null and is_instance_valid(_current) and _current.core != null:
		_current.core.note_selection(body_id, selected_id)


## Marks body `body_id` as a civilian ship (M5-T21): any turret not hostile to it defends it within 2 km.
static func set_civilian(body_id: int, on: bool) -> void:
	if on:
		_civilians[body_id] = true
	else:
		_civilians.erase(body_id)
	var sim: SimCore = current()
	if sim != null and sim.core != null:
		sim.core.set_civilian(body_id, on)


## A bolt of `shooter_id` hit `victim_id` (the hit resolver, in the sweep's order): the turrets' attacker memory (M5-T21).
func note_hit(victim_id: int, shooter_id: int) -> void:
	if core != null and turrets != null and turrets.count() > 0:
		core.note_attackers(PackedInt64Array([victim_id]), PackedInt64Array([shooter_id]), SimClock.now())


## Turrets mounted on this core (M5-T21).
func turret_count() -> int:
	return turrets.count() if turrets != null else 0


## Whether this core owns its bolts now.
func bolt_rows_on() -> bool:
	return core != null and cannons != null


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


## The cannon step and the bolt step of this tick (the `SimCoreStep` node does it at `STEP_PRIORITY`): every cannon's gate
## over the rows, each shot an owned bolt handed back to its cannon, the turrets' step (M5-T21), then every owned bolt
## expired or moved.
func step_now(delta: float) -> void:
	if core == null or not bolt_rows_on() or not ensure_synced():
		return
	var started: int = Time.get_ticks_usec()  # readout only
	var now_s: float = SimClock.now()
	var out: Array = cannons.step(core, now_s, delta)
	var shots: PackedInt64Array = out[0]
	var positions: PackedVector3Array = out[1]
	for slot: int in (out[2] as PackedInt32Array):
		var cannon: PulseCannon = _cannons_by_slot.get(slot)
		if cannon != null:
			var late: Array = cannon.step_without_row(now_s)
			shots.append_array(late[0])
			positions.append_array(late[1])
	shots_last_tick = positions.size()
	for k: int in positions.size():
		var cannon: PulseCannon = _cannons_by_slot.get(int(shots[k * 3]))
		if cannon != null:
			cannon.on_kernel_fired(int(shots[k * 3 + 1]), positions[k])
	turrets.step(now_s, delta)
	var fired: int = Time.get_ticks_usec()
	cannon_us = fired - started
	expired_last_tick = int(core.step_bolts(now_s, delta))
	bolt_step_us = Time.get_ticks_usec() - fired


## The watched AI controllers' selection check (the `SimCoreTargeting` node does it at their priority): the core names the
## ships whose selection the controller would clear now, and each clears it (the same signal).
func check_selections_now() -> void:
	selection_clears_last_tick = 0
	if core == null or not ensure_synced():
		return
	core.resync_touched_now()  # a target moved by script since the first sync (a drifting buoy) is read where it is now
	if _selection_controllers.is_empty():
		return
	for body_id: int in (core.selection_clears() as PackedInt64Array):
		var controller: TargetingController = _selection_controllers.get(body_id)
		if controller != null and is_instance_valid(controller):
			controller.clear_selection()
			selection_clears_last_tick += 1


## Runs `controller`'s selection check on the core from now on (M4-T35): the ship's body and the controller's sensor range.
func watch_selection(controller: TargetingController, body_id: int, sensor_range_m: float) -> void:
	if core != null:
		_selection_controllers[body_id] = controller
		core.watch_selection(body_id, sensor_range_m)


func unwatch_selection(body_id: int) -> void:
	_selection_controllers.erase(body_id)
	if core != null:
		core.unwatch_selection(body_id)


## Closes the tick (the `SimCoreOut` node does it at 2 000 000).
func sync_out_now() -> void:
	if core != null:
		core.sync_out()
	if _bolt_sync != null:
		_bolt_sync.close_tick()
	_tick_open = false


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


## The ships with a node within `radius_m` of `centre`, nearest first, from the rows as of the tick's last sync (M5-T28, the
## engine voices' query): `[body_ids, squared_distances]`; both empty without the core.
func ships_near(centre: Vector3, radius_m: float) -> Array:
	if core == null:
		return [PackedInt64Array(), PackedFloat64Array()]
	return core.ships_near(centre, radius_m)


## Every node row's body id and position, the bolts' positions and the static rows' positions, as the core holds them.
func body_ids() -> PackedInt64Array:
	return core.body_ids() if core != null else PackedInt64Array()


func body_positions() -> PackedVector3Array:
	return core.body_positions() if core != null else PackedVector3Array()


func bolt_positions() -> PackedVector3Array:
	return core.bolt_positions() if core != null else PackedVector3Array()


func static_positions() -> PackedVector3Array:
	return core.static_positions() if core != null else PackedVector3Array()


# --- bolts as rows (M4-T35) ---------------------------------------------------------------------------------------


## Registers `cannon` with the kernel: its ship's body, its muzzles in the ship's frame, its weapon and faction. Returns the
## slot, or -1.
func register_cannon(cannon: PulseCannon, body_id: int, muzzles: PackedVector3Array, weapon: WeaponSpec,
		faction: StringName) -> int:
	if cannons == null:
		return -1
	var slot: int = int(cannons.register(body_id, muzzles, weapon.shot_interval_s, weapon.capacitor_capacity,
			weapon.capacitor_cost_per_shot, weapon.capacitor_recharge_per_s, weapon.muzzle_speed_mps, weapon.convergence_range_m,
			weapon.lifetime_s, weapon.damage, weapon.hit_radius_m, weapon.bolt_color, BoltMesh.look_for(weapon), faction))
	if slot >= 0:
		_cannons_by_slot[slot] = cannon
	return slot


func unregister_cannon(slot: int) -> void:
	_cannons_by_slot.erase(slot)
	if cannons != null:
		cannons.unregister(slot)


## Cannons firing through the kernel now.
func cannon_count() -> int:
	return _cannons_by_slot.size()


## Adds an owned bolt (a stand-in's gun shot) and returns its id (negative); -1 when the core does not own the bolts.
func add_bolt(at: Vector3, velocity: Vector3, faction: StringName, shooter_id: int, weapon: WeaponSpec, now_s: float,
		kind: int = KIND_BOLT) -> int:
	if not bolt_rows_on():
		return -1
	return int(core.add_bolt(at, velocity, faction, shooter_id, kind, weapon.hit_radius_m, weapon.damage, weapon.bolt_color,
			BoltMesh.look_for(weapon), weapon.lifetime_s, now_s))


## Spends the owned bolt `id` (an interceptor shot it down); false when there is none.
func spend_bolt(id: int) -> bool:
	return core != null and bool(core.spend_bolt(id))


## Owned bolt rows now.
func owned_bolts() -> int:
	return int(core.owned_bolts()) if core != null else 0


## Engine calls of the last closed tick: `[sync, fallbacks]` (the sync points' reads, and the flight step's reads of the
## physics server for ships without a row; the kernels make none by construction, see `native/src/kernels.rs`).
func engine_calls() -> PackedInt64Array:
	if core == null:
		return PackedInt64Array([-1, -1])
	var calls: PackedInt64Array = core.engine_calls()
	if _bolt_sync != null:
		calls[0] += int(_bolt_sync.last_reads())
	return calls


## Which path the classes take now: &"native" with the core's native class, else &"none" (the game refuses to start then).
func path() -> StringName:
	return &"native" if core != null else &"none"


func _sync_in() -> void:
	var started: int = Time.get_ticks_usec()  # readout only
	var tree: SceneTree = get_tree()
	if _members_dirty:
		_members_dirty = false
		core.set_members(tree.get_nodes_in_group(Targetable.GROUP), tree.get_nodes_in_group(Damageable.GROUP))
	if _statics_version != StaticRows.version:
		_statics_version = StaticRows.version
		_statics_moves = StaticRows.moves
		core.set_statics(StaticRows.ids, StaticRows.positions, StaticRows.radii, StaticRows.factions, StaticRows.kinds)
	elif _statics_moves != StaticRows.moves:
		_statics_moves = StaticRows.moves  # the same rows, shifted (M6-T06): only their places go over
		core.move_statics(StaticRows.positions)
	var frame: int = Engine.get_physics_frames()
	var delta: float = get_physics_process_delta_time()
	var reader: Object = _bolt_reader()
	if _tick_open:
		reader.close_tick()
	_tick_open = true
	var before_core: int = Time.get_ticks_usec()
	core.sync_in(frame, delta)
	core_sync_us = Time.get_ticks_usec() - before_core
	reader.read(core, tree.get_nodes_in_group(Projectile.GROUP), frame, delta, true, false)
	synced_frame = frame
	bolts_frame = frame
	_bolts_fresh = false
	sync_us = Time.get_ticks_usec() - started
	_window_syncs += 1
	_window_sync_us += sync_us
	_window_core_sync_us += core_sync_us
	var parts: PackedInt64Array = core.sync_parts_us()
	for i: int in parts.size():
		_window_parts_us[i] += parts[i]


func _sync_bolts() -> void:
	var started: int = Time.get_ticks_usec()  # readout only
	var delta: float = get_physics_process_delta_time()
	core.sync_bolts()
	_bolt_reader().read(core, get_tree().get_nodes_in_group(Projectile.GROUP), core.tick(), delta, false, true)
	bolts_frame = Engine.get_physics_frames()
	_bolts_fresh = true
	bolts_us = Time.get_ticks_usec() - started
	_window_bolts_us += bolts_us


## The scan's rows (`ScsSimCore.snapshot`), timed for the readouts.
func snapshot_rows() -> Array:
	var started: int = Time.get_ticks_usec()  # readout only
	var rows: Array = core.snapshot()
	snapshot_us = Time.get_ticks_usec() - started
	_window_snapshots += 1
	_window_snapshot_us += snapshot_us
	return rows


## The broadcast scan's rows (`ScsSimCore.select`), timed for the readouts.
func select_rows(marker_ids: PackedInt64Array) -> Array:
	var started: int = Time.get_ticks_usec()  # readout only
	var rows: Array = core.select(marker_ids)
	select_us = Time.get_ticks_usec() - started
	_window_selects += 1
	_window_select_us += select_us
	return rows


## Starts the window's sums over (a bench's measured window).
func reset_window() -> void:
	_window_syncs = 0
	_window_sync_us = 0
	_window_core_sync_us = 0
	_window_bolts_us = 0
	_window_snapshots = 0
	_window_snapshot_us = 0
	_window_selects = 0
	_window_select_us = 0
	_window_parts_us.fill(0)


## The sync points' and the snapshots' cost since `reset_window`, mean microseconds a tick (wall clock, readouts), and how
## many snapshot and select calls a tick there were.
func window_summary() -> Dictionary:
	var ticks: float = float(maxi(_window_syncs, 1))
	return {"ticks": _window_syncs, "sync_us": float(_window_sync_us) / ticks,
			"core_sync_us": float(_window_core_sync_us) / ticks, "bolts_us": float(_window_bolts_us) / ticks,
			"snapshot_us": float(_window_snapshot_us) / ticks, "snapshots_per_tick": float(_window_snapshots) / ticks,
			"select_us": float(_window_select_us) / ticks, "selects_per_tick": float(_window_selects) / ticks,
			"sync_parts_us": {"tier_step": float(_window_parts_us[0]) / ticks, "bodies": float(_window_parts_us[1]) / ticks,
					"statics": float(_window_parts_us[2]) / ticks, "tier_rows": float(_window_parts_us[3]) / ticks,
					"lookups": float(_window_parts_us[4]) / ticks}}


func _on_rebased(offset: Vector3) -> void:
	if core != null:
		core.shift(-offset)


# The node bolts' reader (M4-T34), made on first use (the library is required, M4-T37).
func _bolt_reader() -> Object:
	if _bolt_sync == null:
		_bolt_sync = ClassDB.instantiate(BOLT_SYNC_CLASS)
	return _bolt_sync


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


# Reads a body's row again whenever it is hidden or shown (the pool parks and reuses ships that way) or its hull goes; with
# the event columns (M4-T35) the hull's points and the ship's selection reach the core's columns from their events too.
func _watch(node: Node) -> void:
	var body := node.get_parent() as Node3D
	if body != null and not body.has_meta(&"_scs_core_watch"):
		body.set_meta(&"_scs_core_watch", true)
		body.visibility_changed.connect(_on_body_touched.bind(body.get_instance_id()))
	var marker := node as Node3D
	if marker != null and body != null and not marker.has_meta(&"_scs_core_watch"):
		marker.set_meta(&"_scs_core_watch", true)
		marker.visibility_changed.connect(_on_body_touched.bind(body.get_instance_id()))  # a marker hidden on its own
	var hull := node as Damageable
	if hull != null and body != null and not hull.has_meta(&"_scs_core_watch"):
		hull.set_meta(&"_scs_core_watch", true)
		var body_id: int = body.get_instance_id()
		hull.destroyed.connect(_on_hull_destroyed.bind(body_id))
		hull.damaged.connect(_on_hull_damaged.bind(hull, body_id))
		hull.restored.connect(_on_hull_restored.bind(hull, body_id))


func _on_hull_damaged(_info: HitInfo, _applied: float, hull: Damageable, body_id: int) -> void:
	if core != null:
		core.note_hull(body_id, hull.hull.hp, hull.hull.max_hp)


func _on_hull_restored(hull: Damageable, body_id: int) -> void:
	if core != null:
		core.note_hull(body_id, hull.hull.hp, hull.hull.max_hp)
		core.touch(body_id)  # a restored hull is active again, as the per-tick read of its destroyed flag would find



func _on_body_touched(body_id: int) -> void:
	if core != null:
		core.touch(body_id)


func _on_hull_destroyed(_info: HitInfo, body_id: int) -> void:
	if core != null:
		core.touch(body_id)
		core.forget_attacker(body_id)  # a ship back from the pool is someone new to the turrets


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"core", ConsoleVars.new({
		&"path": {"get": path, "doc": "native: the core feeds the scan, the hit sweep, the flight step and the ram broad phase (every world since M4-T42); none without the library"},
		&"rows": {"get": rows, "doc": "Rows in the core: bodies, static rows and rows added after the tick's first sync"},
		&"bodies": {"get": func() -> int: return int(core.node_count()) if core != null else 0, "doc": "Body rows (active markers and hulls)"},
		&"statics": {"get": func() -> int: return int(core.static_count()) if core != null else 0, "doc": "Static rows (rocks, mines)"},
		&"bolts": {"get": func() -> int: return int(core.bolt_count()) if core != null else 0, "doc": "Bolt rows as of the last bolt sync"},
		&"syncs": {"get": func() -> int: return int(core.syncs()) if core != null else 0, "doc": "First syncs so far"},
		&"sync_us": {"get": func() -> int: return sync_us, "unit": "us", "doc": "The last tick's first sync (bodies, statics, bolts); wall clock"},
		&"bolts_us": {"get": func() -> int: return bolts_us, "unit": "us", "doc": "The last tick's bolt sync (the hit resolver's); wall clock"},
		&"core_sync_us": {"get": func() -> int: return core_sync_us, "unit": "us", "doc": "The native sync_in call's share of sync_us (the bodies, statics and tier rows into the rows); wall clock"},
		&"snapshot_us": {"get": func() -> int: return snapshot_us, "unit": "us", "doc": "The last snapshot call (the scan's rows handed to GDScript); wall clock"},
		&"select_us": {"get": func() -> int: return select_us, "unit": "us", "doc": "The last select call (the broadcast scan's rows); wall clock"},
		&"sync_calls": {"get": func() -> int: return engine_calls()[0], "doc": "Engine calls the last closed tick's syncs made (they grow with the rows)"},
		&"fallback_calls": {"get": func() -> int: return engine_calls()[1], "doc": "The flight step's reads of the physics server in the last closed tick, for ships the core had no row for (0 outside launch ticks). The kernels themselves hold no engine type: native/src/kernels.rs"},
		&"attribute_reads": {"get": func() -> int: return int(core.attribute_reads()) if core != null else 0, "doc": "Bodies whose faction, name, kind and radius were read (once per activation, not per tick)"},
		&"touched": {"get": func() -> int: return int(core.touched_count()) if core != null else 0, "doc": "Bodies touched since the last sync point and not read again yet"},
		&"threads": {"get": func() -> int: return int(core.threads()) if core != null else 0, "doc": "Worker threads the per-ship passes (the brains, the flight step) run on (perf_threads; M4-T18)"},
		&"parallel_passes": {"get": func() -> int: return int(core.parallel_passes()) if core != null else 0, "doc": "Passes that ran across the threads so far (a pass below its parallel_min stays on the main thread)"},
		&"parallel_min": {"get": func() -> int: return int(core.parallel_min()) if core != null else 0,
				"set": func(value: Variant) -> void: if core != null: core.set_parallel_min(int(value)),
				"type": TYPE_INT, "doc": "The fewest thinks the brains' pass runs in parallel with (settable for the benches that chose it)"},
		&"flight_parallel_min": {"get": func() -> int: return int(core.flight_parallel_min()) if core != null else 0,
				"set": func(value: Variant) -> void: if core != null: core.set_flight_parallel_min(int(value)),
				"type": TYPE_INT, "doc": "The fewest ships the flight step's pass runs in parallel with"},
		&"batch_us": {"get": func() -> int: return _batch().call_us if _batch() != null else 0, "unit": "us", "doc": "The last tick's one native call for every native think (BrainBatch); wall clock"},
		&"live_workers": {"get": func() -> int: return int(core.live_workers()) if core != null else 0, "doc": "Worker threads running now (0 with one thread: a pool is joined before the next starts)"},
		&"batch_ships": {"get": func() -> int: return _batch().ships if _batch() != null else 0, "doc": "Ships the last tick's brain batch carried"},
		&"step_mode": {"get": func() -> String: return String(Settings.get_value(&"sim_step")), "doc": "Where the AI step runs (sim_step, M4-T24): threaded (the worker thread, one tick behind) or delayed (the main thread, one tick behind)"},
		&"step_launched": {"get": func() -> bool: return _batch() != null and _batch().step_launched(), "doc": "A tick's job is out (launched, not yet joined; M4-T24)"},
		&"step_us": {"get": func() -> int: return int(_host().step_us()) if _host() != null else 0, "unit": "us", "doc": "The last job's own run time (the brains' batch on its thread; M4-T24); wall clock"},
		&"step_wait_us": {"get": func() -> int: return int(_host().step_wait_us()) if _host() != null else 0, "unit": "us", "doc": "How long the last join waited for the job (0 when it had finished; M4-T24); wall clock"},
		&"join_us": {"get": func() -> int: return _batch().join_us if _batch() != null else 0, "unit": "us", "doc": "The last tick's join and handover (the wait, the commands into the rows, the drivers' events; M4-T24); wall clock"},
		&"step_misses": {"get": func() -> int: return int(_host().deadline_misses()) if _host() != null else 0, "doc": "Ticks whose join found the job still running and waited for it (a missed deadline, never skipped; M4-T24)"},
		&"step_early_joins": {"get": func() -> int: return int(_host().early_joins()) if _host() != null else 0, "doc": "Joins forced before the tick's by a reader or writer of the brains that could not wait (a new pilot's slot, a ship leaving; M4-T24)"},
		&"step_early_waits": {"get": func() -> int: return int(_host().early_waits()) if _host() != null else 0, "doc": "Early joins that found the job still running and waited for it (M4-T24)"},
		&"step_off_main": {"get": func() -> bool: return _host() != null and bool(_host().step_off_main()), "doc": "The last joined job ran off the main thread (M4-T24)"},
		&"step_threads": {"get": func() -> int: return int(_host().step_threads()) if _host() != null else 0, "doc": "Step worker threads alive (1 once a threaded job ran; M4-T24)"},
		&"step_pool": {"get": func() -> int: return int(_host().step_threads_setting()) if _host() != null else 0, "doc": "Where the job's pass runs (perf_step_threads): 1 the step's thread alone, n its own pool of n, 0 the core's pool (M4-T24)"},
		&"step_pool_workers": {"get": func() -> int: return int(_host().step_pool_workers()) if _host() != null else 0, "doc": "Worker threads of the job's own pool running now (M4-T24)"},
		&"step_stale": {"get": func() -> int: return _batch().stale_total if _batch() != null else 0, "doc": "Results dropped at the handover because the ship was parked or re-piloted while its job ran (M4-T24)"},
		&"owned_bolts": {"get": owned_bolts, "doc": "Bolt rows the core owns now (M4-T35)"},
		&"cannons": {"get": cannon_count, "doc": "Cannons firing through the kernel (M4-T35)"},
		&"cannon_us": {"get": func() -> int: return cannon_us, "unit": "us", "doc": "The last tick's cannon step (every gate, the shots handed back); wall clock"},
		&"bolt_step_us": {"get": func() -> int: return bolt_step_us, "unit": "us", "doc": "The last tick's bolt step (expiry and the move of every owned bolt); wall clock"},
		&"shots": {"get": func() -> int: return shots_last_tick, "doc": "Shots the kernel fired in the last tick"},
		&"expired": {"get": func() -> int: return expired_last_tick, "doc": "Owned bolts that expired in the last tick"},
		&"bolt_draws": {"get": func() -> int: return _bolt_mesh.instances_drawn if _bolt_mesh != null else 0, "doc": "Bolt instances the multimesh drew in the last frame (M4-T35)"},
		&"watched_selections": {"get": func() -> int: return _selection_controllers.size(), "doc": "AI targeting controllers whose selection check runs on the core (M4-T35)"},
		&"selection_clears": {"get": func() -> int: return selection_clears_last_tick, "doc": "Selections the core's check cleared in the last tick"},
		&"turrets": {"get": turret_count, "doc": "Defensive turrets mounted on the core (M5-T21)"},
		&"turret_shots": {"get": func() -> int: return turrets.shots_last_tick if turrets != null else 0, "doc": "Shots the turrets fired in the last tick (M5-T21)"},
		&"turret_shots_total": {"get": func() -> int: return int(core.turret_readouts()[0]) if core != null else 0, "doc": "Shots the turrets fired so far (M5-T21)"},
		&"turret_us": {"get": func() -> int: return turrets.step_us if turrets != null else 0, "unit": "us", "doc": "The last tick's turret step (aim, gate, shots, handed back); wall clock"},
		&"turret_picks_stale": {"get": func() -> int: return int(core.turret_readouts()[2]) if core != null else 0, "doc": "Turret picks dropped at the AI job's join because the mount was rebound meanwhile (M5-T21)"},
		&"attackers": {"get": func() -> int: return int(core.attacker_count()) if core != null else 0, "doc": "Attacker and victim pairs the turrets remember (each for 30 s after a hit; M5-T21)"},
	}), self)


# The brain batch under this core.
func _batch() -> BrainBatch:
	return get_node_or_null(NodePath(BrainBatch.NODE_NAME)) as BrainBatch


# The brain host the batch launches on, or null.
func _host() -> Object:
	var batch: BrainBatch = _batch()
	return batch.host() if batch != null else null
