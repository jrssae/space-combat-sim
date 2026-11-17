class_name MineStandin
extends Node3D
## The battle's proximity mines (M4-T12, Q21): bench-only, replaced by M12's weapons work. Every mine is a static row of kind
## `Targetable.Kind.MINE` in this one node (no node per mine), laid in belts by the bench layout. A mine goes off when a
## hull hostile to its layer comes inside its trigger (a third of the mines check each tick), when any hull of any side
## touches its body, when any shot hits it (the hit resolver calls `strike`) or when another mine's blast reaches it
## (M7-T64). Going off, it hurts every hull within the blast radius through its `Damageable` (friend or foe) and is removed;
## `DestructionDirector.watch_mines` draws its explosion from `detonated`.
## During a bench run it is laid again in its place after `RELAY_S`, so a belt holds the mix's count over the run.
##
## Spawn it with `WorldFrame.spawn` (identity basis) after setting `world`: it is shiftable, so its mines follow a rebase with
## it. Every mine in play is also a row of `StaticRows` (M4-T29, §17.16) of kind `MINE`, owned by its layer's faction, as big
## as its trigger and registered with `world`, so that world's rebase moves it: its own side's ships steer round it, other
## sides never see it (Q27). A mine leaves the rows when it goes off and comes back when it is laid again.
##
## The director binds the belt to its `ScsWeaponRows` (M4-T20) and calls `step_native`: the trigger, touch and blast queries
## run over the core's rows, and this node lays, retires and hurts. `triggers` and `blast` state the trigger and blast rules
## in GDScript for their tests. Mines are not in the target list: the player shoots at the drawn sphere (M7-T64).
##
## Console: provider `mines` (what is in play, what set them off, the nearest to the player) and command `mines view|set_off`
## (look at the nearest mine, set it off as a shot would: for captures and play-tests of the blasts).

## A row went off (`index`) and is no longer in play.
signal detonated(index: int)
## A row is in play again after `RELAY_S` (not emitted by `build`).
signal laid(index: int)

const TRIGGER_RADIUS_M: float = 50.0
const BLAST_RADIUS_M: float = 100.0
## Each mine checks once every this many ticks, a third of them each tick.
const TRIGGER_TICKS: int = 3
const DAMAGE: float = 200.0
## A blast's energy, J (about a fighter's death): how long its far flash lasts.
const BLAST_ENERGY_J: float = 1.0e9
const RELAY_S: float = 10.0
## What a blast's `HitInfo.cause` says.
const CAUSE: StringName = &"mine"
## What set a mine off.
enum Cause { TRIGGER, TOUCH, SHOT, BLAST }
const ACTIONS: Array[StringName] = [&"view", &"set_off"]
## How far `mines view` puts the player from the nearest mine, m.
const VIEW_M: float = 800.0
## Drawn this big, m; also its body, what a touch or a shot must reach (M7-T64).
const DRAWN_RADIUS_M: float = 3.0
const COLOR: Color = Color(0.7, 0.15, 0.1)

## Every belt in the tree, for the hit resolver's shots (M7-T64), and a count that changes when one comes or goes.
static var belts: Array[MineStandin] = []
static var belts_version: int = 0

## What the rows are, for the body registry.
var kind: Targetable.Kind = Targetable.Kind.MINE
## Mines set off so far, by what did it (M7-T64): a hostile in the trigger, a touch, a shot, another mine's blast.
var by_trigger: int = 0
var by_touch: int = 0
var by_shot: int = 0
var by_blast: int = 0
## Mines that checked their trigger in the latest step.
var checked_last_tick: int = 0
## Whether a mine that went off is laid again; off once a bench run is over, so a spent mine stays gone (M7-T59 fix).
var relays: bool = true
## The frame the mines' rows are in (the one that spawned this node); set before `build`.
var world: Node = null
## The native weapon rows (`ScsWeaponRows`) holding these mines while they answer the triggers and blasts (M4-T20), or
## null for the GDScript (`bind_native`).
var native_rows: Object = null

var _local := PackedVector3Array()
var _factions: Array[StringName] = []
var _alive := PackedByteArray()
var _relay_at := PackedFloat64Array()
var _dead := PackedInt32Array()
var _alive_count: int = 0
var _mesh: MultiMeshInstance3D = null
var _row_ids := PackedInt64Array()  # each mine's id in `StaticRows`, kept while it is out of play
var _struck := PackedInt32Array()  # mines a shot hit since the last step, in the order they were hit
var _queued := PackedByteArray()  # per mine: already going off in this step or struck


func _ready() -> void:
	DebugConsole.registry.register_provider(&"mines", ConsoleVars.new({
		&"laid": {"get": count, "doc": "Mines in the belts, in play or spent"},
		&"in_play": {"get": alive_count, "doc": "Mines in play"},
		&"set_off": {"get": func() -> int: return by_trigger + by_touch + by_shot + by_blast, "doc": "Mines set off so far"},
		&"by_trigger": {"get": func() -> int: return by_trigger, "doc": "Set off by a hull hostile to their layer within 50 m"},
		&"by_touch": {"get": func() -> int: return by_touch, "doc": "Set off by a hull of any side touching them"},
		&"by_shot": {"get": func() -> int: return by_shot, "doc": "Set off by a bolt, beam or missile of any side"},
		&"by_blast": {"get": func() -> int: return by_blast, "doc": "Set off by another mine's blast"},
		&"relays": {"get": func() -> bool: return relays, "doc": "Whether a spent mine is laid again (only during a bench run)"},
		&"nearest_m": {"get": func() -> float: return _nearest_to_player()[1], "unit": "m",
				"doc": "The nearest mine in play to the player, centre to centre (-1 with none)"},
		&"nearest_side": {"get": func() -> String: return _nearest_to_player()[2], "doc": "That mine's side"},
		&"nearest_hostile": {"get": func() -> bool: return _nearest_to_player()[3],
				"doc": "Whether that mine's side is hostile to the player (only then does its 50 m trigger go off on the player)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"mines",
			"Look at the nearest mine in play from [metres] away, or set it off as a shot would (its group goes with it)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"view"), ConsoleArg.float_optional(&"metres", VIEW_M, 50.0)]),
			_cmd_mines, self)


func _exit_tree() -> void:
	unregister_rows()
	belts.erase(self)
	belts_version += 1
	DebugConsole.registry.unregister_owner(self)


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
		_queued.append(0)
		_relay_at.append(INF)
		_row_ids.append(StaticRows.new_id())
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
		_register(i)
	_alive_count = rows.size()
	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "Mines"
	_mesh.multimesh = multimesh
	add_child(_mesh)
	belts.append(self)
	belts_version += 1


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


## Every mine's offset from this node, in play or not.
func offsets() -> PackedVector3Array:
	return _local


## Whether a shot can still set mine `i` off: in play, and not already hit since the last step.
func can_strike(i: int) -> bool:
	return i >= 0 and i < _alive.size() and _alive[i] == 1 and _queued[i] == 0


## A shot hit mine `i` (M7-T64): it goes off at the next step, whoever's it is. False when it cannot be struck.
func strike(i: int) -> bool:
	if not can_strike(i):
		return false
	_queued[i] = 1
	_struck.append(i)
	return true


func faction_of(i: int) -> StringName:
	return _factions[i]


## Moves every mine of a layer in `map` (old faction -> new) to its new side, its row in `StaticRows` with it (M7-T50: a
## bench's own sides go when the run ends). Native rows bound before still hold the old sides: bind them again.
func change_factions(map: Dictionary) -> void:
	for i: int in _factions.size():
		if not map.has(_factions[i]):
			continue
		_factions[i] = map[_factions[i]]
		if _alive[i] == 1:
			StaticRows.unregister(_row_ids[i])
			_register(i)


## Hands the mines to the native rows (`rows`, an `ScsWeaponRows` on the core), or takes them back with null.
func bind_native(rows: Object) -> void:
	native_rows = rows
	if rows != null:
		rows.set_mines(_local, _factions, _alive)


## One tick of the mines with the native rows answering the triggers, touches and blasts over the core's rows (`bind_native`
## first); `delta` is the tick's length. Returns how many went off. The mines shot since the last step go off first, then
## those triggered or touched, and each blast sets off the mines it reaches in the same tick. A blast hurts the hulls the
## core names, near and low-attention tier rows alike, in the core's order (M4-T23: one path, no walk of the hulls here).
func step_native(tick: int, now_s: float, delta: float) -> int:
	_lay_again(now_s)
	var origin: Vector3 = global_position
	var out: Array = native_rows.mine_step(tick, origin, delta)
	checked_last_tick = out[0]
	var found: PackedInt32Array = out[1]
	var touched: PackedByteArray = out[2]
	var going := PackedInt32Array(_struck)
	var causes := PackedByteArray()
	causes.resize(going.size())
	causes.fill(Cause.SHOT)
	_struck.clear()
	for k: int in found.size():
		var i: int = found[k]
		if _queued[i] == 0:
			_queued[i] = 1
			going.append(i)
			causes.append(Cause.TOUCH if touched[k] == 1 else Cause.TRIGGER)
	for i: int in _touched_by_big_hulls(origin, out):
		if _queued[i] == 0:
			_queued[i] = 1
			going.append(i)
			causes.append(Cause.TOUCH)
	var went: int = 0
	var n: int = 0
	while n < going.size():
		var i: int = going[n]
		var cause: int = causes[n]
		n += 1
		_queued[i] = 0
		if _alive[i] == 0:
			continue
		var at: Vector3 = origin + _local[i]
		_retire(i, now_s)
		went += 1
		_count_cause(cause)
		var in_blast: Array = native_rows.blast(at)
		var hull_ids: PackedInt64Array = in_blast[0]
		var places: PackedVector3Array = in_blast[1]
		for k: int in hull_ids.size():
			var hull_id: int = hull_ids[k]
			_hurt(i, at, instance_from_id(hull_id) as Damageable if is_instance_id_valid(hull_id) else null, places[k])
		for m: int in native_rows.mines_in_blast(origin, at):
			if _queued[m] == 0:
				_queued[m] = 1
				going.append(m)
				causes.append(Cause.BLAST)
		detonated.emit(i)
	return went


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


# The mines a hull bigger than a fighter touches with its hit volumes, from the candidates `mine_step` handed back (its
# sphere reaches them): the hull's pose as the core read it, so a far capital's row counts too.
func _touched_by_big_hulls(origin: Vector3, out: Array) -> PackedInt32Array:
	var touched := PackedInt32Array()
	var near_mines: PackedInt32Array = out[3]
	var near_hulls: PackedInt64Array = out[4]
	var near_at: PackedVector3Array = out[5]
	var near_axes: PackedVector3Array = out[6]
	for k: int in near_mines.size():
		var i: int = near_mines[k]
		var hull_id: int = near_hulls[k]
		if _queued[i] == 1 or touched.has(i) or not is_instance_id_valid(hull_id):
			continue
		var damageable := instance_from_id(hull_id) as Damageable
		if damageable == null:
			continue
		var basis := Basis(near_axes[3 * k], near_axes[3 * k + 1], near_axes[3 * k + 2])
		var local: Vector3 = basis.inverse() * (origin + _local[i] - near_at[k])
		for shape: HitShape in damageable.shapes:
			if shape.sweep(local, local, DRAWN_RADIUS_M) >= 0.0:
				touched.append(i)
				break
	return touched


func _count_cause(cause: int) -> void:
	match cause:
		Cause.TOUCH:
			by_touch += 1
		Cause.SHOT:
			by_shot += 1
		Cause.BLAST:
			by_blast += 1
		_:
			by_trigger += 1


func _cmd_mines(args: Dictionary) -> ConsoleResult:
	var nearest: Array = _nearest_to_player()
	var i: int = nearest[0]
	if i < 0:
		return ConsoleResult.failure("mines: no player or no mine in play")
	if StringName(args[&"action"]) == &"set_off":
		strike(i)
		return ConsoleResult.line("mine %d (%s, %.0f m off) set off" % [i, nearest[2], nearest[1]])
	var ship := _player().body() as Ship
	if ship == null:
		return ConsoleResult.failure("mines: no player ship to move")
	var metres: float = float(args[&"metres"])
	var look: Vector3 = position_of(i)
	var at: Vector3 = look + Vector3(0.6, 0.35, 0.72).normalized() * metres
	ship.reset_to(Transform3D(Basis.looking_at((look - at).normalized(), Vector3.UP), at))
	var frame: WorldFrame = WorldFrame.of(self)
	ship.linear_velocity = frame.rest_velocity() if frame != null else Vector3.ZERO
	ship.angular_velocity = Vector3.ZERO
	return ConsoleResult.line("%.0f m from mine %d (%s)" % [metres, i, nearest[2]])


# The player's hull, or null.
func _player() -> Damageable:
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var d := node as Damageable
		if d != null and d.respects_god_mode and d.body() != null:
			return d
	return null


# The nearest mine in play to the player, for the console: [index or -1, distance or -1, side, hostile to the player].
func _nearest_to_player() -> Array:
	var player: Damageable = _player()
	if player == null:
		return [-1, -1.0, "", false]
	var from: Vector3 = player.body().global_position
	var best: int = -1
	var best_sq: float = INF
	for i: int in _local.size():
		var d_sq: float = from.distance_squared_to(position_of(i))
		if _alive[i] == 1 and d_sq < best_sq:
			best_sq = d_sq
			best = i
	if best < 0:
		return [-1, -1.0, "", false]
	return [best, sqrt(best_sq), String(_factions[best]), Factions.is_hostile(_factions[best], player.faction)]


# Mine `i` leaves play until it is laid again.
func _retire(i: int, now_s: float) -> void:
	_alive[i] = 0
	_alive_count -= 1
	_relay_at[i] = now_s + RELAY_S
	_dead.append(i)
	StaticRows.unregister(_row_ids[i])
	MultiMeshUpload.set_instance_transform(_mesh.multimesh, i, Transform3D(Basis.from_scale(Vector3.ONE * 1e-4), _local[i]))
	if native_rows != null:
		native_rows.set_mine_alive(i, false)


# Mine `i`'s blast at `at` on one hull whose body (or tier row) is at `hull_at`, if it can still be hurt.
func _hurt(i: int, at: Vector3, damageable: Damageable, hull_at: Vector3) -> void:
	if damageable == null or not is_instance_valid(damageable) or damageable.hull.destroyed:
		return
	var body: Node3D = damageable.body()
	if not damageable.is_active() and not (body != null and body.has_meta(TierDirector.TIER_META)):
		return
	var away: Vector3 = hull_at - at
	var info := HitInfo.new(damageable.body().get_instance_id(), 0, _factions[i], DAMAGE, at,
			-away.normalized() if away.length_squared() > 1e-12 else Vector3.ZERO, 0.0, CAUSE)
	damageable.apply_hit(info)


func _lay_again(now_s: float) -> void:
	if _dead.is_empty() or not relays:
		return
	var still := PackedInt32Array()
	for i: int in _dead:
		if now_s < _relay_at[i]:
			still.append(i)
			continue
		_alive[i] = 1
		_alive_count += 1
		_relay_at[i] = INF
		MultiMeshUpload.set_instance_transform(_mesh.multimesh, i, Transform3D(Basis.IDENTITY, _local[i]))
		_register(i)
		if native_rows != null:
			native_rows.set_mine_alive(i, true)
		laid.emit(i)
	_dead = still


# Mine `i` in play as a row: where it is now, its side's, the trigger's size.
func _register(i: int) -> void:
	StaticRows.register(_row_ids[i], position_of(i), TRIGGER_RADIUS_M, BodyKind.MINE, _factions[i], world)
