class_name MineStandin
extends Node3D
## The battle's proximity mines (M4-T12, Q21): bench-only, replaced by M12's weapons work. Every mine is a static row of kind
## `Targetable.Kind.MINE` in this one node (no node per mine), laid in belts by the bench layout. Each tick a third of the
## mines ask the hit broad phase's grid for a hull hostile to their layer inside the trigger radius; one that finds one goes
## off, hurts every hull within the blast radius through its `Damageable` (friend or foe) and is removed. It is laid again
## in its place after `RELAY_S`, so a belt holds the mix's count over a run.
##
## Spawn it with `WorldFrame.spawn` (identity basis) after setting `world`: it is shiftable, so its mines follow a rebase with
## it. Every mine in play is also a row of `StaticRows` (M4-T29, §17.12) of kind `MINE`, owned by its layer's faction, as big
## as its trigger and registered with `world`, so that world's rebase moves it: its own side's ships steer round it, other
## sides never see it (Q27). A mine leaves the rows when it goes off and comes back when it is laid again.

## A row went off (`index`) and is no longer in play.
signal detonated(index: int)
## A row is in play again after `RELAY_S` (not emitted by `build`).
signal laid(index: int)

const TRIGGER_RADIUS_M: float = 50.0
const BLAST_RADIUS_M: float = 100.0
## Each mine checks once every this many ticks, a third of them each tick.
const TRIGGER_TICKS: int = 3
const DAMAGE: float = 200.0
const RELAY_S: float = 10.0
## What a blast's `HitInfo.cause` says.
const CAUSE: StringName = &"mine"
## Drawn this big, m.
const DRAWN_RADIUS_M: float = 3.0
const COLOR: Color = Color(0.7, 0.15, 0.1)

## What the rows are, for the body registry.
var kind: Targetable.Kind = Targetable.Kind.MINE
## Mines that checked their trigger in the latest step.
var checked_last_tick: int = 0
## Finds the hulls inside a trigger; a test may force its path.
var broad_phase: HitBroadPhase = HitBroadPhase.new()
## The frame the mines' rows are in (the one that spawned this node); set before `build`.
var world: Node = null

var _local := PackedVector3Array()
var _factions: Array[StringName] = []
var _alive := PackedByteArray()
var _relay_at := PackedFloat64Array()
var _dead := PackedInt32Array()
var _alive_count: int = 0
var _mesh: MultiMeshInstance3D = null
var _row_ids := PackedInt64Array()  # each mine's id in `StaticRows`, kept while it is out of play


func _exit_tree() -> void:
	unregister_rows()


## Lays the rows (`offset` m from this node, `faction` the layer's). Call it once, after the node is in the tree.
func build(rows: Array[Dictionary]) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var sphere := SphereMesh.new()
	sphere.radius = DRAWN_RADIUS_M
	sphere.height = 2.0 * DRAWN_RADIUS_M
	sphere.radial_segments = 8
	sphere.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	sphere.material = material
	multimesh.mesh = sphere
	multimesh.instance_count = rows.size()
	for i: int in rows.size():
		var at: Vector3 = rows[i]["offset"]
		_local.append(at)
		_factions.append(StringName(rows[i]["faction"]))
		_alive.append(1)
		_relay_at.append(INF)
		_row_ids.append(StaticRows.new_id())
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		_register(i)
	_alive_count = rows.size()
	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "Mines"
	_mesh.multimesh = multimesh
	add_child(_mesh)


## Mine `i`'s row id in `StaticRows` (the same whenever it is in play).
func row_id(i: int) -> int:
	return _row_ids[i]


## Takes every mine in play out of `StaticRows` (the belts are going).
func unregister_rows() -> void:
	var gone := PackedInt64Array()
	for i: int in _row_ids.size():
		if _alive[i] == 1:
			gone.append(_row_ids[i])
	StaticRows.unregister_many(gone)


func count() -> int:
	return _local.size()


func alive_count() -> int:
	return _alive_count


func is_alive(i: int) -> bool:
	return _alive[i] == 1


## Mine `i`'s place, World frame.
func position_of(i: int) -> Vector3:
	return global_position + _local[i]


func faction_of(i: int) -> StringName:
	return _factions[i]


## One tick (`tick` the director's count): mines due to be laid again come back, a third of the rows check their trigger
## against the hulls (`hulls` with their centres, reaches and factions, index for index) and those set off go off. Returns
## how many went off.
func step(tick: int, now_s: float, hulls: Array[Damageable], hull_at: PackedVector3Array, hull_reach: PackedFloat64Array,
		hull_factions: Array[StringName]) -> int:
	_lay_again(now_s)
	var rows := PackedInt32Array()
	var at := PackedVector3Array()
	var factions: Array[StringName] = []
	var origin: Vector3 = global_position
	for i: int in range(posmod(tick, TRIGGER_TICKS), _local.size(), TRIGGER_TICKS):
		if _alive[i] == 1:
			rows.append(i)
			at.append(origin + _local[i])
			factions.append(_factions[i])
	checked_last_tick = rows.size()
	if rows.is_empty() or hulls.is_empty():
		return 0
	var set_off: PackedInt32Array = triggers(at, factions, hull_at, hull_reach, hull_factions, broad_phase)
	var fired: int = 0
	for k: int in rows.size():
		if set_off[k] >= 0:
			_go_off(rows[k], at[k], now_s, hulls, hull_at, hull_reach)
			fired += 1
	return fired


## For each mine (centre `mine_at`, layer `mine_factions`), the first hull in order hostile to its layer whose sphere (centre
## `hull_at`, radius `hull_reach`) comes within `TRIGGER_RADIUS_M`, or -1.
static func triggers(mine_at: PackedVector3Array, mine_factions: Array[StringName], hull_at: PackedVector3Array,
		hull_reach: PackedFloat64Array, hull_factions: Array[StringName], grid: HitBroadPhase) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(mine_at.size())
	out.fill(-1)
	var hull_count: int = hull_at.size()
	if hull_count == 0 or mine_at.is_empty():
		return out
	var reach := PackedFloat64Array()
	reach.resize(mine_at.size())
	reach.fill(TRIGGER_RADIUS_M)
	var hostile: Dictionary = {}  # "layer|hull faction" -> bool, the relation lookup being the costly part
	for key: int in grid.pairs(mine_at, reach, hull_at, hull_reach):
		var m: int = key / hull_count
		if out[m] >= 0:
			continue
		var j: int = key - m * hull_count
		var pair: String = "%s|%s" % [mine_factions[m], hull_factions[j]]
		if not hostile.has(pair):
			hostile[pair] = Factions.is_hostile(mine_factions[m], hull_factions[j])
		if hostile[pair]:
			out[m] = j
	return out


## The hulls (centres `hull_at`, radii `hull_reach`) whose spheres lie within `BLAST_RADIUS_M` of `at`, in order.
static func blast(at: Vector3, hull_at: PackedVector3Array, hull_reach: PackedFloat64Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for j: int in hull_at.size():
		var reach: float = BLAST_RADIUS_M + hull_reach[j]
		if hull_at[j].distance_squared_to(at) <= reach * reach:
			out.append(j)
	return out


func _go_off(i: int, at: Vector3, now_s: float, hulls: Array[Damageable], hull_at: PackedVector3Array,
		hull_reach: PackedFloat64Array) -> void:
	_alive[i] = 0
	_alive_count -= 1
	_relay_at[i] = now_s + RELAY_S
	_dead.append(i)
	StaticRows.unregister(_row_ids[i])
	_mesh.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 1e-4), _local[i]))
	for j: int in blast(at, hull_at, hull_reach):
		var damageable: Damageable = hulls[j]
		if not is_instance_valid(damageable) or not damageable.is_active():
			continue
		var away: Vector3 = hull_at[j] - at
		var info := HitInfo.new(damageable.body().get_instance_id(), 0, _factions[i], DAMAGE, at,
				-away.normalized() if away.length_squared() > 1e-12 else Vector3.ZERO, 0.0, CAUSE)
		damageable.apply_hit(info)
	detonated.emit(i)


func _lay_again(now_s: float) -> void:
	if _dead.is_empty():
		return
	var still := PackedInt32Array()
	for i: int in _dead:
		if now_s < _relay_at[i]:
			still.append(i)
			continue
		_alive[i] = 1
		_alive_count += 1
		_relay_at[i] = INF
		_mesh.multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, _local[i]))
		_register(i)
		laid.emit(i)
	_dead = still


# Mine `i` in play as a row: where it is now, its side's, the trigger's size.
func _register(i: int) -> void:
	StaticRows.register(_row_ids[i], position_of(i), TRIGGER_RADIUS_M, BodyKind.MINE, _factions[i], world)
