class_name CapitalBrains
extends Node
## Every capital ship's helm and `capital` brain on the native core (M10-T16, D12.10, Q70): a child of `World` that joins each
## `CapitalShip` to the core's capital table (`ScsSimCore.capital_add`, from `CapitalBrainSpec`), pushes what changes per event
## (a mount, engine or bay lost, the reactor's share, a refitted drive), and once a tick hands on what the brains decided at
## the AI job's join: each ship's order to its guns and beams (`set_order_id`, a subsystem to aim at with it), and a withdraw's
## exit (`CapitalWithdraw`: its own point, a friendly one, a gate, or none). The helm flies every tick in `CapitalFlight`.
##
## M10-T17: a carrier's count of hostiles within reach goes to its hangar (`CapitalHangar.on_threat`), and its withdraw waits
## for its craft: the exit is searched once the hangar is ready to jump (`ready_to_jump`).
##
## Priority -5: after `BrainBatch` (-9) joins the job, before the flight (-1) and the guns (`SimCore.step_now`).
## Console: command `capbrain`, provider `capital_brain` (`CapitalBrainConsole`); command `hangar`, provider `hangars`
## (`HangarConsole`).

## A ship went through its exit and left play (D12.10's withdraw).
signal withdrew(ship: CapitalShip, via: StringName)

const NODE_NAME: StringName = &"CapitalBrains"
const PRIORITY: int = -5

## Withdrawals asked for, exits found by kind, ships that went through (readouts).
var withdraw_asks: int = 0
var exits: Dictionary = {}
var gone: int = 0

var _ships: Array[CapitalShip] = []
var _mount_names: Dictionary = {}  # ship -> PackedStringArray, in `capital_add`'s order
var _point_keys: Dictionary = {}  # ship -> PackedStringArray
var _links: Dictionary = {}  # ship -> [[signal, callable], ...]
var _via: Dictionary = {}  # ship -> how it is withdrawing
var _hostility := NativeHostility.new()
var _tuned_core: Object = null
var _pool: JumpPointPool = null
var _console: CapitalBrainConsole = null
var _hangar_console: HangarConsole = null
var _waiting_to_jump: Array[CapitalShip] = []  # withdraws held until their hangars have their craft back


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PRIORITY


static func attach(world: Node) -> CapitalBrains:
	var found: CapitalBrains = of(world)
	if found != null:
		return found
	var made := CapitalBrains.new()
	world.add_child(made)
	return made


static func of(world: Node) -> CapitalBrains:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as CapitalBrains


func _ready() -> void:
	_console = CapitalBrainConsole.new(self)
	_console.register()
	_hangar_console = HangarConsole.new(self)
	_hangar_console.register()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Takes `ship` into the table (again: a refitted drive keeps its course, memory and orders).
func join(ship: CapitalShip) -> void:
	var core: Object = _core()
	if ship == null or core == null:
		return
	_tune(core)
	var mounts: Dictionary = CapitalBrainSpec.mounts(ship)
	var points: Dictionary = CapitalBrainSpec.points(ship)
	core.capital_add(ship.get_instance_id(), CapitalBrainSpec.helm_numbers(ship.flight_spec, ship.layout),
			CapitalBrainSpec.brain_numbers(ship), mounts["packed"], points["packed"])
	_mount_names[ship] = mounts["names"]
	_point_keys[ship] = points["keys"]
	if not _ships.has(ship):
		_ships.append(ship)
		var changed: Callable = refresh.bind(ship)
		var links: Array = [[ship.mount_lost, changed.unbind(1)], [ship.section_changed, changed.unbind(2)],
				[ship.ship_disabled, changed], [ship.damageable.restored, changed]]
		for link: Array in links:
			(link[0] as Signal).connect(link[1])
		_links[ship] = links
	refresh(ship)


func leave(ship: CapitalShip) -> void:
	var core: Object = _core()
	if core != null:
		core.capital_remove(ship.get_instance_id())
	_ships.erase(ship)
	_mount_names.erase(ship)
	_point_keys.erase(ship)
	_via.erase(ship)
	_waiting_to_jump.erase(ship)
	for link: Array in _links.get(ship, []):
		if (link[0] as Signal).is_connected(link[1]):
			(link[0] as Signal).disconnect(link[1])
	_links.erase(ship)


## Pushes what changed on `ship` since it joined: which mounts and subsystems work, its reactor and engines.
func refresh(ship: CapitalShip) -> void:
	var core: Object = _core()
	if core == null or not is_instance_valid(ship) or not _ships.has(ship):
		return
	var w: Array[PackedByteArray] = CapitalBrainSpec.works(ship, _mount_names[ship], _point_keys[ship])
	core.capital_set_works(ship.get_instance_id(), w[0], w[1])
	var s: Array = CapitalBrainSpec.status(ship)
	core.capital_set_status(ship.get_instance_id(), float(s[0]), int(s[1]), int(s[2]), _charge_of(ship))


## The capital ships in the table, in join order.
func ships() -> Array[CapitalShip]:
	return _ships


## How `ship` is withdrawing (`CapitalWithdraw.VIA_*`), empty when it is not.
func withdrawing_via(ship: CapitalShip) -> StringName:
	return _via.get(ship, &"")


## `ship`'s brain as the core holds it: `{state, target, aim, attitude, thinks, held, exit, withdraw_asked, order}`, empty
## when it has none.
func brain_state(ship: CapitalShip) -> Dictionary:
	var core: Object = _core()
	var raw: Array = core.capital_brain_state(ship.get_instance_id()) if core != null and ship != null else []
	if raw.size() < 9:
		return {}
	return {"state": StringName(raw[0]), "target": int(raw[1]), "aim": raw[2], "attitude": int(raw[3]), "thinks": int(raw[4]),
			"held": int(raw[5]) == 1, "exit": int(raw[6]), "withdraw_asked": bool(raw[7]), "order": int(raw[8])}


func _physics_process(_delta: float) -> void:
	var core: Object = _core()
	if core == null or _ships.is_empty():
		return
	_tune(core)
	_jump_when_ready(core)
	var changes: Array = core.capital_take_changes()
	var bodies: PackedInt64Array = changes[0]
	if bodies.is_empty():
		return
	var targets: PackedInt64Array = changes[1]
	var aims: PackedVector3Array = changes[2]
	var flags: PackedByteArray = changes[3]
	var guns: CapitalGuns = CapitalGuns.of(get_parent())
	var beams: CapitalBeams = CapitalBeams.of(get_parent())
	for i: int in bodies.size():
		var ship: CapitalShip = CapitalShip.of_body(bodies[i])
		if ship == null:
			continue
		if flags[i] & 1:
			var has_aim: bool = flags[i] & 2 != 0
			if guns != null:
				guns.set_order_id(ship, targets[i], aims[i], has_aim)
			if beams != null:
				beams.set_order_id(ship, targets[i], aims[i], has_aim)
		if flags[i] & 4:
			withdraw(ship, core)
		if flags[i] & 8 and ship.hangar != null and changes.size() >= 6:
			ship.hangar.on_threat((changes[4] as PackedInt32Array)[i], (changes[5] as PackedInt32Array)[i])


## `ship` wants out (its brain asked, or the console): the exit is booked and its place handed to the brain, or none (it
## fights on). A carrier first calls its craft home and waits for them (M10-T17).
func withdraw(ship: CapitalShip, core: Object) -> void:
	if ship.hangar != null and not ship.hangar.ready_to_jump():
		if not _waiting_to_jump.has(ship):
			_waiting_to_jump.append(ship)
		return
	withdraw_asks += 1
	var world: WorldFrame = get_parent() as WorldFrame
	var found: Dictionary = CapitalWithdraw.find_exit(ship, world, _jump_pool(), _on_through.bind(ship))
	var via: StringName = found["via"]
	exits[via] = int(exits.get(via, 0)) + 1
	var at: UniversePos = found["at"]
	if at == null:
		core.capital_set_exit(ship.get_instance_id(), 2, 0.0, 0.0, 0.0)
		return
	_via[ship] = via
	core.capital_set_exit(ship.get_instance_id(), 1, at.x, at.y, at.z)


# Carriers waiting for their craft before a withdraw: each goes once its hangar is ready.
func _jump_when_ready(core: Object) -> void:
	for ship: CapitalShip in _waiting_to_jump.duplicate():
		if not is_instance_valid(ship) or ship.hangar == null:
			_waiting_to_jump.erase(ship)
		elif ship.hangar.ready_to_jump():
			_waiting_to_jump.erase(ship)
			withdraw(ship, core)


# Through its exit: it leaves play (a mission sees it go).
func _on_through(_body: Node, ship: CapitalShip) -> void:
	if not is_instance_valid(ship):
		return
	gone += 1
	var via: StringName = _via.get(ship, &"")
	withdrew.emit(ship, via)
	ship.leave_play()


# The ship an escort screens (0: none): set by a mission or the console as `capital_charge` meta, a body id.
func _charge_of(ship: CapitalShip) -> int:
	return int(ship.get_meta(&"capital_charge", 0))


func _tune(core: Object) -> void:
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim != null:
		_hostility.refresh_with(int(sim.core.factions().size()), core.capital_set_hostility, sim)
	if _tuned_core == core:
		return
	_tuned_core = core
	core.capital_set_tuning(CapitalBrainSpec.tuning())


func _jump_pool() -> JumpPointPool:
	if _pool == null or not is_instance_valid(_pool):
		_pool = JumpPointPool.new()
		_pool.name = "CapitalWithdrawPoints"
		_pool.world = get_parent() as WorldFrame
		get_parent().add_child(_pool)
		_pool.prepare(2)
	return _pool


func _core() -> Object:
	var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
	return sim.core if sim != null else null
