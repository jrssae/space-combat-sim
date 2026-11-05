class_name NativeWeapons
extends RefCounted
## The stand-ins' weapons on the native rows (M4-T20, architecture §17.13): an `ScsWeaponRows` attached to the simulation
## core, holding the capitals' guns, interceptors and beam emitters and the mine belt, which `StandinDirector` steps once
## per tick instead of the GDScript stand-ins. This class binds the stand-ins to the rows (their state taken from the
## nodes), keeps the hostility table the kernels read in step with `Factions` and the core's factions, and hands the state
## back to the nodes when the GDScript takes over again. The GDScript stand-ins stay the reference.

const NATIVE_CLASS: StringName = &"ScsWeaponRows"

static var _class_known: int = -1

## The native rows, an `ScsWeaponRows`.
var rows: Object = null
## The core they read.
var sim: SimCore = null
## The capitals bound, in the director's order (a freed one keeps its place), and every turret in row order (guns,
## interceptors and beam emitters of each capital in turn).
var capitals: Array = []
var turrets: Array[Node3D] = []
var mines: MineStandin = null

var _relations_count: int = -1
var _relations_table: FactionTable = null


## Whether the library has the native rows.
static func available() -> bool:
	if _class_known < 0:
		_class_known = 1 if NativeLib.has_class(NATIVE_CLASS) else 0
	return _class_known == 1


## Binds `p_capitals` (with their turrets' state) and `p_mines` (or null) to new rows on `p_sim`'s core.
static func bind(p_sim: SimCore, p_capitals: Array, p_mines: MineStandin) -> NativeWeapons:
	var made := NativeWeapons.new()
	made.sim = p_sim
	made.rows = ClassDB.instantiate(NATIVE_CLASS)
	made.rows.attach_core(p_sim.core)
	made.capitals = p_capitals.duplicate()
	var body_ids := PackedInt64Array()
	var owners := PackedInt32Array()
	var locals := PackedVector3Array()
	var roles := PackedByteArray()
	for c: int in made.capitals.size():
		var cap: CapitalStandin = made.capitals[c] if is_instance_valid(made.capitals[c]) else null
		body_ids.append(cap.get_instance_id() if cap != null else 0)
		if cap == null:
			continue
		for role: int in 3:
			var group: Array = cap.guns() if role == 0 else (cap.interceptors() if role == 1 else cap.beams())
			for turret: Node3D in group:
				made.turrets.append(turret)
				owners.append(c)
				locals.append(turret.position)
				roles.append(role)
	made.rows.set_capitals(body_ids)
	made.rows.set_turrets(owners, locals, roles)
	made.push_turrets()
	if p_mines != null and is_instance_valid(p_mines):
		made.mines = p_mines
		p_mines.bind_native(made.rows)
	return made


## Gives the rows every turret's state from its node.
func push_turrets() -> void:
	var axes := PackedVector3Array()
	var targets := PackedInt64Array()
	var aim_errors := PackedFloat64Array()
	var ready_ats := PackedFloat64Array()
	var shots := PackedInt64Array()
	var missile_shots := PackedInt64Array()
	for turret: Node3D in turrets:
		var gun := turret as TurretStandin
		var state: Array = gun.native_state() if gun != null else [Vector3.ZERO, 0, PI, -INF, 0, 0]
		axes.append(state[0])
		targets.append(state[1])
		aim_errors.append(state[2])
		ready_ats.append(state[3])
		shots.append(state[4])
		missile_shots.append(state[5])
	rows.set_turret_state(axes, targets, aim_errors, ready_ats, shots, missile_shots)


## Gives every turret's node the state the rows hold now.
func pull_turrets() -> void:
	var state: Array = rows.turret_state()
	var axes: PackedVector3Array = state[0]
	var targets: PackedInt64Array = state[1]
	var aim_errors: PackedFloat64Array = state[2]
	var ready_ats: PackedFloat64Array = state[3]
	var shots: PackedInt64Array = state[4]
	var missile_shots: PackedInt64Array = state[5]
	for k: int in turrets.size():
		var gun := turrets[k] as TurretStandin
		if gun != null and is_instance_valid(gun):
			gun.take_native_state(axes[k], targets[k], aim_errors[k], ready_ats[k], shots[k], missile_shots[k])


## Gives the rows the capitals' strike state: `strike` (capital -> [target body id, tick looked up]) and whose turn it is.
func push_strike(strike: Dictionary, turn: int) -> void:
	var targets := PackedInt64Array()
	var ticks := PackedInt64Array()
	var known := PackedByteArray()
	for cap: Variant in capitals:
		var held: Array = strike.get(cap, []) if is_instance_valid(cap) else []
		targets.append(int(held[0]) if not held.is_empty() else 0)
		ticks.append(int(held[1]) if not held.is_empty() else 0)
		known.append(0 if held.is_empty() else 1)
	rows.set_strike_state(targets, ticks, known, turn)


## Writes the rows' strike state into `strike` (as `push_strike` takes it); returns whose turn it is.
func pull_strike(strike: Dictionary) -> int:
	var state: Array = rows.strike_state()
	var targets: PackedInt64Array = state[0]
	var ticks: PackedInt64Array = state[1]
	var known: PackedByteArray = state[2]
	for c: int in capitals.size():
		if not is_instance_valid(capitals[c]):
			continue
		if known[c] == 1:
			strike[capitals[c]] = [targets[c], ticks[c]]
		else:
			strike.erase(capitals[c])
	return int(state[3])


## The mines go back to the GDScript.
func unbind_mines() -> void:
	if mines != null and is_instance_valid(mines):
		mines.bind_native(null)
	mines = null


## Builds the hostility table again when the core knows a new faction or the faction table changed (the bench installs
## its own for a battle).
func refresh_relations() -> void:
	var count: int = rows.faction_count()
	var table: FactionTable = Factions.table()
	if count == _relations_count and table == _relations_table:
		return
	_relations_count = count
	_relations_table = table
	var names: Array = sim.core.factions()
	var matrix := PackedByteArray()
	matrix.resize(count * count)
	for a: int in count:
		for b: int in count:
			matrix[a * count + b] = 1 if Factions.is_hostile(names[a], names[b]) else 0
	rows.set_hostility(count, matrix)
