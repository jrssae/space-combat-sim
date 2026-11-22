class_name CapitalBeams
extends Node
## Every capital's beam emitters (M10-T12, D12.9) on the native rows (`ScsBeamRows`, `beam_kernels.rs`): pulsed and sustained
## beams with no node per shot. A ship's emitters join with it (`BeamMounts` reads its hardpoints and weapon specs) and leave
## with it; when a mount is lost, a section falls, the ship is disabled or made whole, its emitters' state is pushed to the rows.
## Each tick, after the core's sync, the rows step every emitter (charge, fire, cool; targets by what the ship perceives) and
## this lands their hits through each target's `Damageable` (cause `beam`, a capital's on the section its surface volume
## names, friend or foe stopping the line, damage only where a bolt of its side could hurt) and hands the lines to `BeamDraw`.
## A hit on its own side's friend reveals a disguised shooter (`Transponder.note_hit`). A child of `World`, after the flight and
## before the hit resolver.
##
## Console: provider `beams` and command `beam` (`BeamConsole`).

const NODE_NAME: StringName = &"CapitalBeams"
const NATIVE_CLASS: StringName = &"ScsBeamRows"
const PRIORITY: int = HitResolver.LATE_PRIORITY - 5
## The rows' phases a line is drawn in: a sustained beam on, a pulse just fired.
const PHASE_FIRING: int = 2
const PHASE_COOLING: int = 3

## Readouts (wall clock, never gameplay): the native step's cost (and its kernel's alone), the landing's, and the hits since
## `reset_stats`.
var step_us: float = 0.0
var kernel_us: float = 0.0
var land_us: int = 0
var hits: int = 0
var damage_landed: float = 0.0
## Beams drawn on the last tick (sustained ones on, pulses fired).
var lines_last: int = 0

var _rows: Object = null
var _ships: Array[CapitalShip] = []
# Per emitter, in the rows' order: its ship and its mount (`BeamMounts` entry).
var _owners: Array[CapitalShip] = []
var _mounts: Array[Dictionary] = []
var _console: BeamConsole = null
var _held: Dictionary = {}  # ship -> true: told to hold its beams' fire
var _links: Dictionary = {}  # ship -> [[signal, callable], ...]: what tells it a ship's emitters changed
var _relations_count: int = -1
var _relations_table: FactionTable = null
var _relations_revision: int = -1


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


static func attach(world: Node) -> CapitalBeams:
	var found: CapitalBeams = of(world)
	if found != null:
		return found
	var made := CapitalBeams.new()
	world.add_child(made)
	return made


static func of(world: Node) -> CapitalBeams:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as CapitalBeams


func _ready() -> void:
	_console = BeamConsole.new(self)
	_console.register()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Takes `ship`'s beam emitters into the rows (again, after its rotors changed).
func join(ship: CapitalShip) -> void:
	if ship == null or _native() == null:
		return
	if _ships.has(ship):
		leave(ship)
	var mounts: Array[Dictionary] = BeamMounts.of_hardpoints(ship.hardpoints(), ship.type_id)
	if mounts.is_empty():
		return
	_ships.append(ship)
	BeamDraw.attach(get_parent())  # drawn from the first ship with beams on
	var bodies := PackedInt64Array([ship.get_instance_id()])
	for rotor: CapitalRotor in ship.rotors:
		bodies.append(rotor.get_instance_id())
	_rows.add_owner(ship.get_instance_id(), bodies)
	for m: Dictionary in mounts:
		var index: int = int(_rows.add_beam(ship.get_instance_id(), m["position"], m["forward"], m["arc_half_deg"], m["packed"]))
		if index < 0:
			continue
		_owners.append(ship)
		_mounts.append(m)
	var changed: Callable = refresh.bind(ship)
	var links: Array = [[ship.mount_lost, changed.unbind(1)], [ship.section_changed, changed.unbind(2)],
			[ship.ship_disabled, changed], [ship.damageable.restored, changed], [ship.damageable.destroyed, changed.unbind(1)]]
	for link: Array in links:
		(link[0] as Signal).connect(link[1])
	_links[ship] = links
	refresh(ship)


func leave(ship: CapitalShip) -> void:
	if not _ships.has(ship):
		return
	_ships.erase(ship)
	_rows.remove_owner(ship.get_instance_id())
	for k: int in range(_owners.size() - 1, -1, -1):
		if _owners[k] == ship:
			_owners.remove_at(k)
			_mounts.remove_at(k)
	for link: Array in _links.get(ship, []):
		if (link[0] as Signal).is_connected(link[1]):
			(link[0] as Signal).disconnect(link[1])
	_links.erase(ship)
	_held.erase(ship)


## Pushes whether each of `ship`'s emitters works, and its rate of fire, to the rows.
func refresh(ship: CapitalShip) -> void:
	if not is_instance_valid(ship) or not _ships.has(ship):
		return
	var rate: float = ship.damage.fire_rate()
	var alive: bool = not ship.damageable.hull.destroyed and not _held.has(ship)
	for k: int in _owners.size():
		if _owners[k] == ship:
			_rows.set_works(k, alive and ship.mount_works(str(_mounts[k]["name"])), rate)


## `ship`'s beams hold their fire (`held`), or are free to fire again: an order for the AI and the missions.
func hold(ship: CapitalShip, held: bool) -> void:
	if held:
		_held[ship] = true
	else:
		_held.erase(ship)
	refresh(ship)


## The target `ship`'s brain gives its beams (null: they pick their own).
func set_order(ship: CapitalShip, target: Node3D) -> void:
	if _rows != null and ship != null:
		_rows.set_order(ship.get_instance_id(), target.get_instance_id() if target != null else 0)


## The capital ships with beams, in join order.
func ships() -> Array[CapitalShip]:
	return _ships


## Emitters on the rows, every ship's.
func emitter_count() -> int:
	return _mounts.size()


## The emitter indices of `ship`, in its mounts' order.
func beams_of(ship: CapitalShip) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in _owners.size():
		if _owners[k] == ship:
			out.append(k)
	return out


## Emitter `index`'s mount (`BeamMounts` entry) and its state from the rows: `{mount, phase, timer, target, aim, works, rate}`.
func state(index: int) -> Dictionary:
	if _rows == null or index < 0 or index >= _mounts.size():
		return {}
	var s: Array = _rows.state(index)
	return {"mount": _mounts[index], "phase": int(s[0]), "timer": float(s[1]), "target": int(s[2]), "aim": s[3] as Vector3,
			"works": bool(s[4]), "rate": float(s[5])}


## `ship`'s cooling emitters ready at once and looking for a target now (the console's test shot); how many it has.
func ready_now(ship: CapitalShip) -> int:
	return int(_rows.ready_now(ship.get_instance_id())) if _rows != null and ship != null else 0


func reset_stats() -> void:
	hits = 0
	damage_landed = 0.0
	land_us = 0


func _physics_process(delta: float) -> void:
	if _rows == null or _owners.is_empty():
		if lines_last > 0 and BeamDraw.of(get_parent()) != null:
			BeamDraw.of(get_parent()).set_lines([])
		lines_last = 0
		return
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null or not sim.ensure_synced():
		return
	_refresh_relations(sim)
	var out: Array = _rows.step(delta)
	step_us = float(_rows.last_us())
	kernel_us = float(_rows.kernel_us())
	var started: int = Time.get_ticks_usec()  # readout only
	_land(out)
	_draw(out)
	land_us = Time.get_ticks_usec() - started


# The step's hits, in its order: each through its hull's Damageable when a bolt of the shooter's side could hurt it.
func _land(out: Array) -> void:
	var emitters: PackedInt32Array = out[0]
	var hull_ids: PackedInt64Array = out[1]
	var body_ids: PackedInt64Array = out[2]
	var points: PackedVector3Array = out[3]
	var volumes: PackedInt32Array = out[4]
	var damage: PackedFloat64Array = out[5]
	var friendly_fire: bool = bool(Settings.get_value(&"friendly_fire"))
	var sim: SimCore = SimCore.for_tree(get_tree())
	for k: int in emitters.size():
		var shooter: CapitalShip = _owners[emitters[k]]
		var damageable: Damageable = BlastResolver.hurtable(hull_ids[k])
		if damageable == null or not is_instance_valid(shooter):
			continue
		if not damageable.can_be_hit_by(shooter.faction, friendly_fire):
			continue  # the line stops on a hull its side may not hurt
		var shooter_id: int = shooter.get_instance_id()
		var from: Vector3 = shooter.global_transform * (_mounts[emitters[k]]["position"] as Vector3)
		var facing: Vector3 = from - points[k]
		var info := HitInfo.new(body_ids[k], shooter_id, shooter.faction, damage[k], points[k],
				facing.normalized() if facing.length_squared() > 1e-12 else Vector3.ZERO, 0.0, HitInfo.CAUSE_BEAM)
		info.volume = volumes[k]
		if sim != null:
			sim.note_hit(info.target_id, shooter_id)  # the turrets' attacker memory (M5-T21)
		Transponder.note_hit(shooter_id, damageable)  # a disguised shooter that hit its own side's friend is found out
		damageable.apply_hit(info)
		hits += 1
		damage_landed += damage[k]


# The step's lines to `BeamDraw`: the sustained beams on now, and each pulse just fired.
func _draw(out: Array) -> void:
	var draw: BeamDraw = BeamDraw.of(get_parent())
	var emitters: PackedInt32Array = out[6]
	var phases: PackedByteArray = out[7]
	var starts: PackedVector3Array = out[8]
	var ends: PackedVector3Array = out[9]
	var lines: Array[Array] = []
	lines_last = 0
	for k: int in emitters.size():
		var spec: WeaponSpec = _mounts[emitters[k]]["spec"]
		if phases[k] == PHASE_FIRING:
			lines.append([starts[k], ends[k], spec.bolt_color, spec.beam_width_m])
			lines_last += 1
		elif phases[k] == PHASE_COOLING:
			lines_last += 1
			if draw != null:
				draw.add_pulse(starts[k], ends[k], spec.bolt_color, spec.beam_width_m)
	if draw != null:
		draw.set_lines(lines)


# The hostility table again when the core knows a new faction, another table is active or a relation changed.
func _refresh_relations(sim: SimCore) -> void:
	var count: int = int(_rows.faction_count())
	var table: FactionTable = Factions.table()
	if count == _relations_count and table == _relations_table and table.revision == _relations_revision:
		return
	_relations_count = count
	_relations_table = table
	_relations_revision = table.revision
	var names: Array = sim.core.factions()
	var matrix := PackedByteArray()
	matrix.resize(count * count)
	for a: int in count:
		for b: int in count:
			matrix[a * count + b] = 1 if Factions.is_hostile(names[a], names[b]) else 0
	_rows.set_hostility(count, matrix)


func _native() -> Object:
	if _rows == null:
		var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
		if sim == null or sim.core == null:
			return null
		_rows = NativeLib.instantiate(NATIVE_CLASS)
		if _rows != null:
			_rows.attach_core(sim.core)
	return _rows
