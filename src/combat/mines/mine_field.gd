class_name MineField
extends Node3D
## One field of mines (M10-T15, Q20, D12.9): a scenario's or a mission's placed minefield, the bench's belts, or the one field the
## battle's own layers lay into (`battle`). Every mine is a slot of the native mine rows (`ScsMineRows`, `mine_kernels.rs`), drawn
## by a MultiMesh per kind (no node per mine) and, when placed, a `StaticRows` row so its own side steers round it (Q27). The
## core decides who goes off (a hostile within the trigger of a hull's surface, anything touching the body, a fuse, a flight that
## ended), steers the guided mines and picks what the layers lay (`mine_layers.rs`). The mines set off wait in the rows for the
## field's landing at the end of its step, which runs in the native blast batch (M10-T76, `BlastResolver.land_field`): one blast
## each (T09's falloff, friend or foe alike), and a blast of any source sets off the mines it reaches, so a field goes off as a
## chain, every death it causes blowing in turn. This node draws what went off (`went_off`).
##
## Mines go off whoever's they are when anything touches or hits their 3 m body (M7-T64): `strike` is the hit resolver's. A mine
## in flight (an energy mine, a guided mine homing) is a bolt row that the capitals' interceptors and any hostile ship's bolts and
## missiles shoot down (toughness, Q81: the core's `shots_on_flight`).
##
## Spawn with `MineField.spawn_in` (a shiftable node that rides the anchor), then `build` placed rows or `build_battle`. Stepped
## once a tick by `SimCore.step_now` (`step_all`), after the capital guns and before the bolts move.
##
## Console: provider `mines` and command `mines` (`MineConsole`, registered by `Main`).

## A mine went off (`slot`, its kind, its place in the World) and is no longer in play.
signal detonated(slot: int, kind: int, at: Vector3)
## A mine came into play: placed again after a bench relay, or laid by a ship.
signal laid(slot: int)
## An interceptor shot a mine in flight down.
signal shot_down(slot: int)

const NODE_PREFIX: String = "Mines"
const NATIVE_CLASS: StringName = &"ScsMineRows"
const ASSET_DIR: String = "res://assets/generated/space_mines"
## A mine's body, m: what a touch or a shot must reach (M7-T64).
const BODY_RADIUS_M: float = 3.0
## A bench's spent mine is laid again this long after it went off, s.
const RELAY_S: float = 10.0
## Mines the battle's field holds at once.
const BATTLE_CAPACITY: int = 256
## What `HitInfo` readouts name a mine's blast.
const CAUSE: StringName = &"mine"
## What set a mine off, in `mine_kernels::CAUSE_*` order.
const CAUSES: Array[StringName] = [&"trigger", &"touch", &"shot", &"blast", &"fuse", &"flight"]
const CAUSE_SHOT: int = 2
const CAUSE_BLAST: int = 3
## Radar contact ids of a field's mines: below any body's id, a block of `ID_STRIDE` a field.
const RADAR_ID_BASE: int = -(1 << 40)
const ID_STRIDE: int = 1 << 20
## Drawn this big when the generated mesh is missing, m.
const FALLBACK_RADIUS_M: float = 3.0
const COLORS: Array[Color] = [Color(0.7, 0.15, 0.1), Color(0.9, 0.55, 0.15), Color(0.25, 0.6, 0.8)]

## Every field in the tree, for the hit resolver's shots and the radar, and a count that changes when one comes or goes.
static var fields: Array[MineField] = []
static var fields_version: int = 0
static var _next_number: int = 0

## Which field this is: its radar ids lie in its own block.
var number: int = 0
## Whether this is a placed layout (a scenario's field, the bench's belts: shootable, registered as static rows) rather than the
## battle's own field, whose mines move.
var placed: bool = true
## The frame the mines' rows are in (the one that spawned this node).
var world: Node = null
## Whether a placed mine that went off is laid again after `RELAY_S`; only during a bench run.
var relays: bool = false
## The native mine rows (`ScsMineRows`), made when the field is built.
var rows: Object = null
## How many slots the field has (its draw's instance count).
var capacity: int = 0
## Mines gone off so far, by what did it (`CAUSES`), and shot down in flight.
var by_cause := PackedInt32Array([0, 0, 0, 0, 0, 0])
var by_trigger: int:
	get:
		return by_cause[0]
var by_touch: int:
	get:
		return by_cause[1]
var by_shot: int:
	get:
		return by_cause[2]
var by_blast: int:
	get:
		return by_cause[3]
var by_fuse: int:
	get:
		return by_cause[4]
var by_flight: int:
	get:
		return by_cause[5]
var shot_down_count: int = 0
var mines_laid: int = 0
var step_us: float = 0.0
## What the rows are, for the body registry.
var kind: Targetable.Kind = Targetable.Kind.MINE

var _instances: Array[MultiMeshInstance3D] = [null, null, null]
var _offsets := PackedVector3Array()  # placed mines' offsets from the node
var _kinds := PackedByteArray()  # per slot: the kind it was laid as (draw and rows)
var _factions: Array[StringName] = []  # per slot: its side, for what is registered
var _row_ids := PackedInt64Array()  # per slot: its row in `StaticRows` (placed fields)
var _registered := PackedByteArray()
var _went: int = 0  # mines that went off in the landing under way
var _relay_at := PackedFloat64Array()
var _hostility := NativeHostility.new()
var _faction_names: Array = []
var _now_s: float = 0.0  # the sim clock of the step being landed
var _steps: int = 0  # `step_all` calls on this field: the tick its trigger cadence counts by, the same in every run


## A field of `p_world`, a child of `parent` (or the World), at `anchor` (a `UniversePos`): shiftable, riding the anchor. Call
## `build` or `build_battle` next.
static func spawn_in(p_world: WorldFrame, anchor: UniversePos, p_placed: bool, parent: Node3D = null) -> MineField:
	var made := MineField.new()
	made.world = p_world
	made.placed = p_placed
	made.name = "%s%d" % [NODE_PREFIX, _next_number]
	SimCore.attach(p_world)  # the core steps the mines
	p_world.spawn(made, anchor, Basis.IDENTITY, parent)
	made.add_to_group(WorldFrame.ANCHORED_GROUP)
	return made


## The battle's own field in `p_world`, made at the World's origin the first time (the layers lay into it).
static func battle(p_world: WorldFrame) -> MineField:
	for f: MineField in fields:
		if is_instance_valid(f) and not f.placed and f.world == p_world:
			return f
	var made: MineField = spawn_in(p_world, p_world.to_universe(Vector3.ZERO), false)
	made.build_battle(BATTLE_CAPACITY)
	return made


## Steps every field once (`SimCore.step_now` calls it): the core's step and what it says, in field order.
static func step_all(now_s: float, delta: float) -> void:
	for f: MineField in fields.duplicate():
		if is_instance_valid(f) and f.is_inside_tree() and f.rows != null:
			f._steps += 1
			f.step_now(f._steps, now_s, delta)


## Every mine on the radar of a ship of `faction` at `from` within `range_m`: `[ids, positions, core faction indices]` with the
## hostile ones only inside their kind's radar range (own and friendly ones always).
static func radar_contacts(from: Vector3, faction: StringName, range_m: float) -> Array:
	var ids := PackedInt64Array()
	var places := PackedVector3Array()
	var sides := PackedInt32Array()
	for f: MineField in fields:
		if not is_instance_valid(f) or f.rows == null or not f.is_inside_tree():
			continue
		var sim: SimCore = SimCore.for_tree(f.get_tree())
		if sim == null:
			continue
		f._hostility.refresh(f.rows, sim)  # the relations are the core's current ones even before the field's first step
		var found: Array = f.rows.radar(f.global_position, from, faction, range_m)
		if found.is_empty():
			continue
		var slots: PackedInt32Array = found[0]
		for k: int in slots.size():
			ids.append(RADAR_ID_BASE - f.number * ID_STRIDE - slots[k])
		places.append_array(found[1] as PackedVector3Array)
		sides.append_array(found[2] as PackedInt32Array)
	return [ids, places, sides]


## Total mines in play in every field.
static func total_in_play() -> int:
	var n: int = 0
	for f: MineField in fields:
		if is_instance_valid(f) and f.rows != null:
			n += f.alive_count()
	return n


func _enter_tree() -> void:
	number = _next_number
	_next_number += 1
	fields.append(self)
	fields_version += 1
	BlastResolver.add_field(self)


func _exit_tree() -> void:
	unregister_rows()
	BlastResolver.remove_field(self)
	fields.erase(self)
	fields_version += 1


## Lays the placed rows: `{offset, faction, kind}` (kind `mine_prox` when it is left out), `offset` m from this node. Call it
## once, after the node is in the tree. Returns how many were laid.
func build(p_rows: Array[Dictionary]) -> int:
	if not _make_rows(p_rows.size()):
		return 0
	var made: int = 0
	var now_s: float = SimClock.now()
	for row: Dictionary in p_rows:
		var k: int = maxi(MineKinds.index_of(StringName(row.get("kind", MineKinds.NAMES[MineKinds.PROX]))), 0)
		var at: Vector3 = row["offset"]
		var side := StringName(row["faction"])
		var slot: int = int(rows.lay(-1, k, side, at, Vector3.ZERO, true, now_s, 0))
		if slot < 0:
			continue
		_kinds[slot] = k
		_factions[slot] = side
		_offsets[slot] = at
		_show(slot, k, at)
		_register(slot)
		made += 1
	return made


## Makes the battle field: `p_capacity` empty slots the layers (and `lay`) fill, every kind drawn.
func build_battle(p_capacity: int) -> void:
	placed = false
	_make_rows(p_capacity)


## Lays one mine of `kind_name` for `faction` at World point `at` moving at `velocity` (against the anchor's rest) into the
## first free slot, armed; returns its slot or -1. For the console and scripts; the layers lay natively.
func lay(kind_name: StringName, faction: StringName, at: Vector3, velocity: Vector3 = Vector3.ZERO, owner_id: int = 0) -> int:
	var k: int = MineKinds.index_of(kind_name)
	if rows == null or k < 0:
		return -1
	var local: Vector3 = at - global_position
	var slot: int = int(rows.lay(-1, k, faction, local, velocity, true, SimClock.now(), owner_id))
	if slot < 0:
		return -1
	_kinds[slot] = k
	_factions[slot] = faction
	_offsets[slot] = local
	_show(slot, k, local)
	if placed and velocity == Vector3.ZERO:
		_register(slot)
	mines_laid += 1
	laid.emit(slot)
	return slot


## Mine `i`'s row id in `StaticRows` (the same whenever it is in play).
func row_id(i: int) -> int:
	return _row_ids[i]


## Takes every mine in play out of `StaticRows` (the field is going).
func unregister_rows() -> void:
	var gone := PackedInt64Array()
	for i: int in _row_ids.size():
		if _registered[i] == 1:
			gone.append(_row_ids[i])
			_registered[i] = 0
	StaticRows.unregister_many(gone)


func count() -> int:
	return capacity


## Mines set off so far, whatever set them off.
func total_set_off() -> int:
	var n: int = 0
	for c: int in by_cause:
		n += c
	return n


## Hostile shots that met a mine in flight since the field was built: each takes one of its hits (an energy mine's three, Q81).
func shots_on_flight() -> int:
	return int(rows.shots_on_flight()) if rows != null else 0


func alive_count() -> int:
	return int(rows.alive_count()) if rows != null else 0


func is_alive(i: int) -> bool:
	return rows != null and i >= 0 and i < capacity and bool(rows.is_alive(i))


## Mine `i`'s place, World frame.
func position_of(i: int) -> Vector3:
	return global_position + _offsets[i]


## Every placed mine's offset from this node, in play or not.
func offsets() -> PackedVector3Array:
	return _offsets


func kind_of(i: int) -> int:
	return _kinds[i]


func faction_of(i: int) -> StringName:
	return _factions[i]


## Whether a shot can still set mine `i` off: a placed one in play and not already hit since the last step.
func can_strike(i: int) -> bool:
	return placed and i >= 0 and i < capacity and not bool(rows.is_queued(i)) and bool(rows.is_alive(i))


## A shot hit mine `i` (M7-T64): it goes off at the next step, whoever's it is. False when it cannot be struck.
func strike(i: int) -> bool:
	if not can_strike(i):
		return false
	_queue(i, CAUSE_SHOT)
	return true


## Moves every mine of a side in `map` (old faction -> new) to its new side, its row in `StaticRows` with it (M7-T50: a bench's
## own sides go when the run ends).
func change_factions(map: Dictionary) -> void:
	for i: int in capacity:
		if not map.has(_factions[i]):
			continue
		_factions[i] = map[_factions[i]]
		if bool(rows.is_alive(i)):
			rows.set_faction(i, _factions[i])
			if _registered[i] == 1:
				StaticRows.unregister(_row_ids[i])
				_registered[i] = 0
				_register(i)


## One tick of the field (`tick` the physics frame, `now_s` the sim clock): the core's step, then what it names is landed.
## Returns how many mines went off.
func step_now(tick: int, now_s: float, delta: float) -> int:
	var started: int = Time.get_ticks_usec()  # a readout, never gameplay time
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null or not sim.ensure_synced():
		return 0
	_now_s = now_s
	_hostility.refresh(rows, sim)
	_faction_names = sim.core.factions()
	_lay_again(now_s)
	var origin: Vector3 = global_position
	var out: Array = rows.step(tick, now_s, delta, origin)
	if out.is_empty():
		return 0
	var native_dets: PackedInt32Array = out[0]
	var causes: PackedByteArray = out[1]
	for k: int in native_dets.size():
		_queue(native_dets[k], causes[k])
	for slot: int in (out[4] as PackedInt32Array):
		_hide(slot)
		shot_down_count += 1
		shot_down.emit(slot)
	var laid_slots: PackedInt32Array = out[5]
	var laid_kinds: PackedByteArray = out[6]
	for k: int in laid_slots.size():
		var info: Array = rows.info(laid_slots[k])
		_kinds[laid_slots[k]] = laid_kinds[k]
		if not info.is_empty():
			_show(laid_slots[k], laid_kinds[k], info[4])
		mines_laid += 1
		laid.emit(laid_slots[k])
	var moved: PackedInt32Array = out[2]
	var places: PackedVector3Array = out[3]
	for k: int in moved.size():
		_move(moved[k], places[k])
	var went: int = _land_going(origin)
	step_us = float(Time.get_ticks_usec() - started)
	return went


## Mine `i` goes off at the next step whatever field it is in (the console's `set_off`).
func strike_any(i: int) -> void:
	_queue(i, CAUSE_SHOT)


## Takes every mine in the field out of play without a blast; how many there were.
func clear() -> int:
	var n: int = 0
	for i: int in capacity:
		if bool(rows.is_alive(i)) and bool(rows.detonate(i)):
			_hide(i)
			_unregister(i)
			n += 1
	return n


## Mine `i`'s side (an empty name for a mine not in play).
func side_of(i: int) -> StringName:
	var info: Array = rows.info(i)
	if info.is_empty():
		return &""
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim != null:
		_faction_names = sim.core.factions()
	return _side_name(int(info[1]), i)


## The mine nearest World point `at` in play, or -1.
func nearest_to(at: Vector3) -> int:
	var best: int = -1
	var best_sq: float = INF
	for i: int in capacity:
		if not bool(rows.is_alive(i)):
			continue
		var info: Array = rows.info(i)
		var d_sq: float = at.distance_squared_to(global_position + (info[4] as Vector3))
		if d_sq < best_sq:
			best_sq = d_sq
			best = i
	return best


## One mount of ship `owner_id` that lays mines (`MineLayers` registers them): see `ScsMineRows.add_layer`.
func add_layer(owner_id: int, at: Vector3, forward: Vector3, kind_index: int, numbers: PackedFloat64Array) -> int:
	return int(rows.add_layer(owner_id, at, forward, kind_index, numbers)) if rows != null else -1


# Makes the rows, the draw and the per-slot arrays for `slots` mines; false without a core.
func _make_rows(slots: int) -> bool:
	var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
	if sim == null or sim.core == null:
		push_warning("MineField: no core in this tree, so no mines (build the field under a WorldFrame)")
		return false
	rows = NativeLib.instantiate(NATIVE_CLASS)
	if rows == null:
		return false
	rows.attach_core(sim.core)
	for k: int in MineKinds.NAMES.size():
		rows.set_spec(k, MineKinds.numbers(k))
	rows.reserve(slots)
	BlastResolver.add_field(self)  # blasts set its mines off from now on
	capacity = slots
	_kinds.resize(slots)
	_registered.resize(slots)
	_row_ids.resize(slots)
	_relay_at.resize(slots)
	_relay_at.fill(INF)
	_offsets.resize(slots)
	_factions.resize(slots)
	_factions.fill(&"")
	for i: int in slots:
		_row_ids[i] = StaticRows.new_id()
	for k: int in MineKinds.NAMES.size():
		_instances[k] = _make_instances(k, slots)
		add_child(_instances[k])
	var destruction: DestructionDirector = DestructionDirector.current()
	if destruction != null:
		destruction.watch_mines(self)  # a mine that goes off is drawn exploding (M7-T64)
	return true


# The MultiMesh drawing every slot of kind `k`, all hidden until a mine of that kind is laid there.
func _make_instances(k: int, slots: int) -> MultiMeshInstance3D:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _mesh_of(k)
	multimesh.instance_count = slots
	var hidden := Transform3D(Basis.from_scale(Vector3.ONE * 1e-4), Vector3.ZERO)
	for i: int in slots:
		multimesh.set_instance_transform(i, hidden)
	var instance := MultiMeshInstance3D.new()
	instance.name = String(MineKinds.NAMES[k])
	instance.multimesh = multimesh
	return instance


static func _mesh_of(k: int) -> Mesh:
	var path: String = ASSET_DIR.path_join("manifest.json")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if manifest is Dictionary:
		var entry: Variant = ((manifest as Dictionary).get("mines", {}) as Dictionary).get(String(MineKinds.NAMES[k]))
		if entry is Dictionary:
			var mesh: Mesh = MeshAssets.load_textured(ASSET_DIR, entry, false)
			if mesh != null:
				return mesh
	var sphere := SphereMesh.new()
	sphere.radius = FALLBACK_RADIUS_M
	sphere.height = 2.0 * FALLBACK_RADIUS_M
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = COLORS[k]
	sphere.material = material
	return sphere


# Slot `i` shows a mine of kind `k` at offset `at`, and hides in the other kinds' draws.
func _show(i: int, k: int, at: Vector3) -> void:
	for other: int in _instances.size():
		var t := Transform3D(Basis.IDENTITY, at) if other == k else Transform3D(Basis.from_scale(Vector3.ONE * 1e-4), at)
		MultiMeshUpload.set_instance_transform(_instances[other].multimesh, i, t)


func _hide(i: int) -> void:
	rows.unqueue(i)
	for instance: MultiMeshInstance3D in _instances:
		MultiMeshUpload.set_instance_transform(instance.multimesh, i, Transform3D(Basis.from_scale(Vector3.ONE * 1e-4), _offsets[i]))


func _move(i: int, at: Vector3) -> void:
	_offsets[i] = at
	MultiMeshUpload.set_instance_transform(_instances[_kinds[i]].multimesh, i, Transform3D(Basis.IDENTITY, at))


# Mine `i` in play as a row of `StaticRows`: where it is now, its side's, as big as its trigger.
func _register(i: int) -> void:
	if not placed or _registered[i] == 1:
		return
	StaticRows.register(_row_ids[i], position_of(i), MineKinds.number(_kinds[i], "trigger_m"), BodyKind.MINE, _factions[i], world)
	_registered[i] = 1


func _unregister(i: int) -> void:
	if _registered[i] == 1:
		StaticRows.unregister(_row_ids[i])
		_registered[i] = 0


# Mine `i` goes off at this step's end (or the next step, when queued outside one).
func _queue(i: int, cause: int) -> void:
	rows.queue(i, cause)


# Lands every mine set off since the last landing, one blast each, in the order they were set off, in the native batch: a blast
# that reaches more adds them, so the chain runs out. Returns how many went off.
func _land_going(origin: Vector3) -> int:
	_went = 0
	BlastResolver.land_field(self, origin)
	return _went


## Mine `slot` went off at `at` (World frame), for `cause`, a mine of `kind` (`BlastResolver`, as the batch lands its blast):
## counted, drawn out, out of the rows, its signal.
func went_off(slot: int, cause: int, kind: int, at: Vector3) -> void:
	_went += 1
	by_cause[cause] += 1
	_hide(slot)
	_unregister(slot)
	if relays and placed:
		_relay_at[slot] = _now_s + RELAY_S
	detonated.emit(slot, kind, at)


# The name of core faction `index`; the slot's own record when the core does not know it.
func _side_name(index: int, slot: int) -> StringName:
	if index >= 0 and index < _faction_names.size():
		return StringName(_faction_names[index])
	return _factions[slot]


# Spent bench mines come back after `RELAY_S`.
func _lay_again(now_s: float) -> void:
	if not relays or not placed:
		return
	for i: int in capacity:
		if _relay_at[i] > now_s:
			continue
		_relay_at[i] = INF
		var at: Vector3 = _offsets[i]
		if int(rows.lay(i, _kinds[i], _factions[i], at, Vector3.ZERO, true, now_s, 0)) < 0:
			continue
		_show(i, _kinds[i], at)
		_register(i)
		laid.emit(i)
