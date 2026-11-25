class_name CapitalGuns
extends Node
## Every capital's gun turrets and missile launchers (M10-T14, D12.9) on the native rows (`ScsCapitalGuns`,
## `capital_gun_kernels.rs`), with no node per mount or shot. A ship's mounts join with it (`CapitalGunMounts` reads its
## hardpoints and weapon specs) and leave with it; when a mount is lost, a section falls, the ship is disabled or made whole,
## its mounts' state is pushed to the rows. Each tick `SimCore.step_now` steps them after the station turrets and before the
## bolts move: missiles in flight are steered, then every mount picks (by what its ship perceives: the disguise), aims and
## fires, its shots added as the core's own bolt rows. The hit sweep lands them like any bolt, by section on a capital (T08);
## a missile's or torpedo's warhead then blasts there (`warhead_blast`). A disguised shooter that fires on its transponder's
## friend gives itself away (`Transponder.note_shot_at`). A child of `World`.
##
## Interceptor batteries (M10-T13, Q81) are mounts of the same rows: each fires pulses at hostile missiles, torpedoes and bolts
## headed for its ship or a friendly capital or station (`capital_intercepts.rs`); this node shows each pulse's muzzle flash and
## the grid's battery sound pitched up, a spark where a pulse meets a shot, and spends a shot down that a node draws.
##
## Console: provider `capital_guns` and command `gun` (`GunConsole`); provider `interceptors` and command `intercept`
## (`InterceptConsole`).

const NODE_NAME: StringName = &"CapitalGuns"
const NATIVE_CLASS: StringName = &"ScsCapitalGuns"
## `ScsCapitalGuns.state` fields, in order.
const STATE_FIELDS: Array[String] = ["target", "azimuth", "elevation", "ready_at", "shots", "works", "rate"]
## Each warhead's blast row in `BlastTable` (M10-T09), by `WeaponSpec.WARHEAD_*`.
const WARHEAD_BLASTS: Array[StringName] = [&"", &"missile", &"torpedo"]
## What a shot down was (`capital_intercepts::SHOT_*`), for the counters.
const SHOT_KINDS: Array[String] = ["bolt", "heavy", "missile", "torpedo"]
## A battery's muzzle glow and a meeting's flash, as the station grid's batteries show them (M7-T41).
const PULSE_GLOW: Color = Color(0.53, 1.0, 2.0)
const MEET_FLASH_SCALE: float = 0.6

## A battery fired a pulse from `at` (World), or a pulse met a shot at `at` (`color` the shot's): for the sound.
signal pulse_fired(at: Vector3)
signal pulse_met(at: Vector3, color: Color)

## Readouts (wall clock, never gameplay): the last step's cost (and its kernel's alone), the shots since `reset_stats`.
var step_us: float = 0.0
var kernel_us: float = 0.0
var shots: int = 0
var missiles_launched: int = 0
var shots_last: int = 0
## Pulses the batteries fired and shots they brought down (by `SHOT_KINDS`) since `reset_stats`.
var pulses: int = 0
var downed: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])

var _rows: Object = null
var _ships: Array[CapitalShip] = []
# Per mount, in the rows' order: its ship and its mount (`CapitalGunMounts` entry).
var _owners: Array[CapitalShip] = []
var _mounts: Array[Dictionary] = []
var _console: GunConsole = null
var _intercept_console: InterceptConsole = null
var _held: Dictionary = {}  # ship -> true: told to hold its guns' fire
var _intercepts_held: Dictionary = {}  # ship -> true: its interceptors told to hold
var _pool: MuzzleFlashPool = null
var _fx: FxPool = null
var _links: Dictionary = {}  # ship -> [[signal, callable], ...]: what tells it a ship's mounts changed
var _hostility := NativeHostility.new()


func _init() -> void:
	name = NODE_NAME


static func attach(world: Node) -> CapitalGuns:
	var found: CapitalGuns = of(world)
	if found != null:
		return found
	var made := CapitalGuns.new()
	world.add_child(made)
	return made


static func of(world: Node) -> CapitalGuns:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as CapitalGuns


## The blast row a missile or torpedo bolt `bolt_id` of the current core sets off where it strikes, `&""` for none.
static func warhead_blast(bolt_id: int) -> StringName:
	var sim: SimCore = SimCore.current()
	var guns: CapitalGuns = sim.capital_guns if sim != null else null
	if guns == null or not is_instance_valid(guns) or guns._rows == null:
		return &""
	return WARHEAD_BLASTS[clampi(int(guns._rows.warhead_of(bolt_id)), 0, WARHEAD_BLASTS.size() - 1)]


func _ready() -> void:
	_console = GunConsole.new(self)
	_console.register()
	_intercept_console = InterceptConsole.new(self)
	_intercept_console.register()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	var sim: SimCore = SimCore.current()
	if sim != null and sim.capital_guns == self:
		sim.capital_guns = null


## Takes `ship`'s gun, launcher and interceptor mounts into the rows (again, after its rotors changed).
func join(ship: CapitalShip) -> void:
	if ship == null or _native() == null:
		return
	if _ships.has(ship):
		leave(ship)
	var mounts: Array[Dictionary] = CapitalGunMounts.of_hardpoints(ship.hardpoints(), ship.type_id)
	mounts.append_array(CapitalGunMounts.interceptors_of(ship.hardpoints(), ship.type_id))
	if mounts.is_empty():
		return
	_ships.append(ship)
	var bodies := PackedInt64Array([ship.get_instance_id()])
	for rotor: CapitalRotor in ship.rotors:
		bodies.append(rotor.get_instance_id())
	_rows.add_owner(ship.get_instance_id(), bodies)
	for m: Dictionary in mounts:
		var spec: WeaponSpec = m["spec"]
		var index: int = int(_rows.add_mount(ship.get_instance_id(), m["position"], m["axis"], m["zero"], m["half_deg"],
				m["pick_half_deg"], m["on_axis"], m["barrel_m"], m["packed"], spec.bolt_color))
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
	_intercepts_held.erase(ship)


## Pushes whether each of `ship`'s mounts works, and its rate of fire, to the rows: a gun held by `hold`, an interceptor by
## `hold_interceptors`; none of them on a hulk, a wreck or a lost mount or section (no power, no pulses).
func refresh(ship: CapitalShip) -> void:
	if not is_instance_valid(ship) or not _ships.has(ship):
		return
	var rate: float = ship.damage.fire_rate()
	var alive: bool = not ship.damageable.hull.destroyed
	for k: int in _owners.size():
		if _owners[k] == ship:
			var held: bool = _intercepts_held.has(ship) if is_interceptor(k) else _held.has(ship)
			_rows.set_works(k, alive and not held and ship.mount_works(str(_mounts[k]["name"])), rate)


## Whether mount `index` is an interceptor battery.
func is_interceptor(index: int) -> bool:
	return index >= 0 and index < _mounts.size() and str(_mounts[index]["kind"]) == "interceptor"


## `ship`'s interceptors hold their pulses (`held`), or are free again (the `intercept` console; missions).
func hold_interceptors(ship: CapitalShip, held: bool) -> void:
	if held:
		_intercepts_held[ship] = true
	else:
		_intercepts_held.erase(ship)
	refresh(ship)


func interceptors_held(ship: CapitalShip) -> bool:
	return _intercepts_held.has(ship)


## `[pulses fired, pulses that met a shot, bolts down, heavy bolts down, missiles down, torpedoes down, pulses in flight]` since
## the rows were made.
func intercept_readouts() -> PackedInt64Array:
	return _rows.intercept_readouts() if _rows != null else PackedInt64Array([0, 0, 0, 0, 0, 0, 0])


## `ship`'s share: `[hostile shots its batteries saw headed for its hull, of those shot down]` since it joined.
func intercept_share(ship: CapitalShip) -> PackedInt64Array:
	return _rows.intercept_share(ship.get_instance_id()) if _rows != null and ship != null else PackedInt64Array([0, 0])


## `ship`'s guns and launchers hold their fire (`held`), or are free to fire again: an order for the AI and the missions.
func hold(ship: CapitalShip, held: bool) -> void:
	if held:
		_held[ship] = true
	else:
		_held.erase(ship)
	refresh(ship)


func is_held(ship: CapitalShip) -> bool:
	return _held.has(ship)


## The target `ship`'s brain gives its anti-capital and dual mounts (null: they pick their own).
func set_order(ship: CapitalShip, target: Node3D) -> void:
	if _rows != null and ship != null:
		_rows.set_order(ship.get_instance_id(), target.get_instance_id() if target != null else 0)


## The capital ships with guns or launchers, in join order.
func ships() -> Array[CapitalShip]:
	return _ships


## Mounts on the rows, every ship's (guns, launchers and interceptors).
func mount_count() -> int:
	return _mounts.size()


## Interceptor batteries on the rows, every ship's.
func battery_count() -> int:
	var n: int = 0
	for m: Dictionary in _mounts:
		n += 1 if str(m["kind"]) == "interceptor" else 0
	return n


## Missiles and torpedoes in flight now.
func missiles_in_flight() -> int:
	return int(_rows.missile_count()) if _rows != null else 0


## The indices of `ship`'s gun and launcher mounts, in its mounts' order (its interceptors: `interceptors_of`).
func mounts_of(ship: CapitalShip) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in _owners.size():
		if _owners[k] == ship and not is_interceptor(k):
			out.append(k)
	return out


## The indices of `ship`'s interceptor batteries, in its mounts' order.
func interceptors_of(ship: CapitalShip) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in _owners.size():
		if _owners[k] == ship and is_interceptor(k):
			out.append(k)
	return out


## Mount `index`'s entry (`CapitalGunMounts`) and its state from the rows: `{mount, target, azimuth, elevation, ready_at, shots,
## works, rate}`.
func state(index: int) -> Dictionary:
	if _rows == null or index < 0 or index >= _mounts.size():
		return {}
	var s: Array = _rows.state(index)
	var out: Dictionary = {"mount": _mounts[index]}
	for k: int in STATE_FIELDS.size():
		out[STATE_FIELDS[k]] = s[k]
	return out


## `ship`'s mounts ready at once and looking for a target now (the console's test shot); how many it has.
func ready_now(ship: CapitalShip) -> int:
	return int(_rows.ready_now(ship.get_instance_id())) if _rows != null and ship != null else 0


## A hash of every mount's aim, target, gate and shots and of the missiles in flight (for comparing runs).
func digest() -> int:
	return int(_rows.digest()) if _rows != null else 0


## `[bolts fired, missiles launched, shots the own hull blocked, picks that found a target, candidates the own hull hid]` since
## the rows were made.
func readouts() -> PackedInt64Array:
	return _rows.readouts() if _rows != null else PackedInt64Array([0, 0, 0, 0, 0])


func reset_stats() -> void:
	shots = 0
	missiles_launched = 0
	pulses = 0
	downed = PackedInt64Array([0, 0, 0, 0])


## One tick (from `SimCore.step_now`, after the station turrets and before the bolts move): the rows' step, then each
## disguised shooter's shot checked against the body it aimed at, and the interceptors' pulses and meetings shown.
func step_now(sim: SimCore, now_s: float, delta: float) -> void:
	shots_last = 0
	if _rows == null or _owners.is_empty():
		return
	_hostility.refresh(_rows, sim)
	var out: Array = _rows.step(now_s, delta)
	step_us = float(_rows.last_us())
	kernel_us = float(_rows.kernel_us())
	if out.size() < 5:
		return
	var fired: PackedInt32Array = out[0]
	var missile: PackedByteArray = out[3]
	var targets: PackedInt64Array = out[4]
	shots_last = fired.size()
	for k: int in fired.size():
		shots += 1
		missiles_launched += missile[k]
		var shooter: CapitalShip = _owners[fired[k]]
		if SimCore.is_disguised(shooter.get_instance_id()):
			Transponder.note_shot_at(shooter.get_instance_id(), targets[k])
	if out.size() >= 14:
		_show_pulses(out[5], out[6], out[7])
		_show_meetings(sim, out[8], out[9], out[10], out[11], out[12], out[13])


# Each pulse a battery fired: a blue-white flash at its muzzle and the battery's sound.
func _show_pulses(mounts: PackedInt32Array, starts: PackedVector3Array, _barrels: PackedInt32Array) -> void:
	pulses += mounts.size()
	for k: int in mounts.size():
		var ship: CapitalShip = _owners[mounts[k]] if mounts[k] >= 0 and mounts[k] < _owners.size() else null
		if ship == null or not is_instance_valid(ship):
			continue
		if _pool == null or not is_instance_valid(_pool):
			_pool = MuzzleFlashPool.attach(get_parent())
		if _pool != null:
			_pool.trigger(ship, Transform3D(Basis.IDENTITY, ship.to_local(starts[k])), PULSE_GLOW)
		pulse_fired.emit(starts[k])


# Each pulse that met a shot: a small flash and a scatter of sparks in the shot's colour, the sound, and a shot down that a
# node draws spent (the core's own rows are spent already).
func _show_meetings(sim: SimCore, _mounts: PackedInt32Array, ids: PackedInt64Array, points: PackedVector3Array,
		colors: PackedColorArray, down: PackedByteArray, kinds: PackedByteArray) -> void:
	var world: Node3D = get_parent() as Node3D
	for k: int in ids.size():
		if down[k] != 0:
			downed[clampi(kinds[k], 0, 3)] += 1
			if ids[k] >= 0:
				var node := instance_from_id(ids[k]) as Projectile
				if node != null:
					node.spend()
			else:
				sim.spend_bolt(ids[k])
		if world == null:
			continue
		var flash := ImpactFlash.create(colors[k], 0, MEET_FLASH_SCALE)
		world.add_child(flash)
		flash.global_position = points[k]
		flash.reset_physics_interpolation()
		if _fx == null or not is_instance_valid(_fx):
			_fx = world.get_node_or_null(^"Fx") as FxPool
		if _fx != null:
			_fx.tint(_fx.burst(FxSpecs.INTERCEPT, points[k], Vector3.UP, Vector3.ZERO), colors[k])
		pulse_met.emit(points[k], colors[k])


func _native() -> Object:
	if _rows == null:
		var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
		if sim == null or sim.core == null:
			return null
		_rows = NativeLib.instantiate(NATIVE_CLASS)
		if _rows != null:
			_rows.attach_core(sim.core)
			sim.capital_guns = self
	return _rows
