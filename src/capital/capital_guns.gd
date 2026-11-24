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
## Console: provider `capital_guns` and command `gun` (`GunConsole`).

const NODE_NAME: StringName = &"CapitalGuns"
const NATIVE_CLASS: StringName = &"ScsCapitalGuns"
## `ScsCapitalGuns.state` fields, in order.
const STATE_FIELDS: Array[String] = ["target", "azimuth", "elevation", "ready_at", "shots", "works", "rate"]
## Each warhead's blast row in `BlastTable` (M10-T09), by `WeaponSpec.WARHEAD_*`.
const WARHEAD_BLASTS: Array[StringName] = [&"", &"missile", &"torpedo"]

## Readouts (wall clock, never gameplay): the last step's cost (and its kernel's alone), the shots since `reset_stats`.
var step_us: float = 0.0
var kernel_us: float = 0.0
var shots: int = 0
var missiles_launched: int = 0
var shots_last: int = 0

var _rows: Object = null
var _ships: Array[CapitalShip] = []
# Per mount, in the rows' order: its ship and its mount (`CapitalGunMounts` entry).
var _owners: Array[CapitalShip] = []
var _mounts: Array[Dictionary] = []
var _console: GunConsole = null
var _held: Dictionary = {}  # ship -> true: told to hold its guns' fire
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


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	var sim: SimCore = SimCore.current()
	if sim != null and sim.capital_guns == self:
		sim.capital_guns = null


## Takes `ship`'s gun and launcher mounts into the rows (again, after its rotors changed).
func join(ship: CapitalShip) -> void:
	if ship == null or _native() == null:
		return
	if _ships.has(ship):
		leave(ship)
	var mounts: Array[Dictionary] = CapitalGunMounts.of_hardpoints(ship.hardpoints(), ship.type_id)
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


## Pushes whether each of `ship`'s mounts works, and its rate of fire, to the rows.
func refresh(ship: CapitalShip) -> void:
	if not is_instance_valid(ship) or not _ships.has(ship):
		return
	var rate: float = ship.damage.fire_rate()
	var alive: bool = not ship.damageable.hull.destroyed and not _held.has(ship)
	for k: int in _owners.size():
		if _owners[k] == ship:
			_rows.set_works(k, alive and ship.mount_works(str(_mounts[k]["name"])), rate)


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


## Mounts on the rows, every ship's.
func mount_count() -> int:
	return _mounts.size()


## Missiles and torpedoes in flight now.
func missiles_in_flight() -> int:
	return int(_rows.missile_count()) if _rows != null else 0


## The mount indices of `ship`, in its mounts' order.
func mounts_of(ship: CapitalShip) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in _owners.size():
		if _owners[k] == ship:
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


## One tick (from `SimCore.step_now`, after the station turrets and before the bolts move): the rows' step, then each
## disguised shooter's shot checked against the body it aimed at.
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
