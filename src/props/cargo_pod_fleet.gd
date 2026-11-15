class_name CargoPodFleet
extends Node
## The station's cargo pods (M7-T34; T30's ferry, flown by maintenance bots until then): the craft that carry every freighter's
## cargo between its hull and the cargo bay (`FreighterCargo`, `CargoFerryJob`), and the ambient cargo scene (`pods cargo`, a
## Saturn 3 with pods shuttling, T11). They launch from the cargo bay's back wall and land in it, and hang from the station's frame.
##
## **Fighting near them** stops them as it stops the maintenance crew: they read the crew's own alarm log (`BotFleet.alert`, every
## hit near the station, every grid shot, the grid going weapons free), so a pod out goes home and the blocks wait until the quiet
## has held (T30's habit). A bare fleet keeps its own log. `pods hide` holds them all in.
##
## Console: provider and command `pods`.

const PROVIDER: StringName = &"pods"
const ACTIONS: Array[StringName] = [&"info", &"hide", &"show", &"cargo"]
## How often the alarms are asked, s (as the crew's).
const POLL_S: float = 0.25

var pods: Array[CargoPodCraft] = []
## The cargo scene (a Saturn 3 and its shuttling pods), null in a bare fleet.
var cargo: CargoPodScene = null
## The log of fighting the pods heed (the crew's when there is one), in `origin`'s frame.
var alert := BotAlert.new()
## The station (or any node whose frame the alert's points are in).
var origin: Node3D = null
var station: Station = null
## `pods hide`: every pod goes in and stays in until `pods show`.
var held_in: bool = false
## Where the craft's model is read from.
var asset_root: String = ShipSpec.ASSET_ROOT

var _crew: BotFleet = null
var _now_s: float = 0.0
var _poll_s: float = 0.0
var _alarmed := PackedByteArray()
var _frame_parent: Node3D = null
var _made: int = 0


## The station's pods, on its frame, heeding its crew's alarms (if it has a crew).
func build(p_station: Station) -> void:
	station = p_station
	build_on(p_station, p_station.frame_piece, p_station.bots)
	cargo = CargoPodScene.new()
	cargo.name = "Cargo"
	cargo.fleet = self
	cargo.station = p_station
	add_child(cargo)


## Pods on `frame_parent` (in `p_origin`'s frame), heeding `crew`'s alarm log or, without one, their own. For tests and `build`.
func build_on(p_origin: Node3D, frame_parent: Node3D, crew: BotFleet = null) -> void:
	name = "CargoPods"
	origin = p_origin
	_frame_parent = frame_parent
	_crew = crew
	if crew != null:
		alert = crew.alert


func _ready() -> void:
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	_now_s += delta
	_poll_s += delta
	if _poll_s >= POLL_S:
		_poll_s = 0.0
		_refresh_alarms()
	for i: int in pods.size():
		pods[i].advance(delta, held_in or _alarmed[i] != 0)


## A shot or hit at `point` (World frame) now: the pods near it go home.
func note_combat_at(point: Vector3) -> void:
	alert.note(origin.to_local(point), now_s())


## Fighting on the station that has no place of its own: every pod goes in.
func note_combat_everywhere() -> void:
	alert.note_everywhere(now_s())


## The alarm log's clock, s (the crew's when the log is the crew's).
func now_s() -> float:
	return _crew.now_s() if _crew != null and is_instance_valid(_crew) else _now_s


## Adds a cargo pod flying `motion` on the frame; the craft.
func add_pod(motion: CargoPodMotion) -> CargoPodCraft:
	var craft := CargoPodCraft.new()
	_made += 1
	craft.setup("CargoPod%d" % _made, motion, asset_root)
	_frame_parent.add_child(craft)
	pods.append(craft)
	_alarmed.resize(pods.size())
	return craft


## Takes one pod away (a freighter's crew when its cargo is done).
func remove_pod(craft: CargoPodCraft) -> void:
	var i: int = pods.find(craft)
	if i < 0:
		return
	pods.remove_at(i)
	_alarmed.remove_at(i)
	if is_instance_valid(craft):
		craft.get_parent().remove_child(craft)
		craft.free()


## Takes every pod away.
func clear() -> void:
	for craft: CargoPodCraft in pods:
		craft.get_parent().remove_child(craft)
		craft.free()
	pods.clear()
	_alarmed.clear()


## The node the pods (and the blocks they carry) hang from: the station's frame.
func frame_parent() -> Node3D:
	return _frame_parent


## Pods inside the cargo bay's wall now.
func hidden_count() -> int:
	var count: int = 0
	for craft: CargoPodCraft in pods:
		count += 0 if craft.motion.is_visible() else 1
	return count


func _refresh_alarms() -> void:
	for i: int in pods.size():
		var here: Vector3 = origin.to_local(pods[i].global_position) if pods[i].is_inside_tree() else Vector3.ZERO
		_alarmed[i] = 1 if alert.is_alarmed(here, now_s()) else 0


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"count": {"get": func() -> int: return pods.size(), "type": TYPE_INT, "doc": "Cargo pods out of or in the cargo bay now (each freighter's crew and the cargo scene's)"},
		&"hidden": {"get": hidden_count, "type": TYPE_INT, "doc": "Cargo pods inside the cargo bay's wall"},
		&"held": {"get": func() -> bool: return held_in, "type": TYPE_BOOL, "doc": "pods hide holds them inside until pods show"},
		&"scene": {"get": func() -> String: return "%d pods in the cargo scene%s" % [cargo.own_pods.size() if cargo != null else 0,
				", %s at its hold point" % CargoPodScene.FREIGHTER_NAME if cargo != null and cargo.freighter != null else ""],
				"doc": "The cargo scene (pods cargo): its pods, and whether the Saturn 3 is at the hold point"},
		&"jobs": {"get": _jobs_text, "doc": "Each pod: what it is doing, and its arms (reach 0..1, jaws 1 open to 0 shut)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The station's cargo pods (M7-T34), which carry every freighter's cargo between it and the cargo bay (traffic freighter): info (each pod's phase and arms), hide (every pod goes home and stays), show (they go out again), cargo [n|off|view|bayview] (a Saturn 3 backed in at the cargo bay's hold point and n cargo pods, default 5, shuttling between it and the bay; off removes them; view and bayview put the player where they can be seen)",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"a")]), _cmd_pods, self)


func _jobs_text() -> String:
	var parts := PackedStringArray()
	for craft: CargoPodCraft in pods:
		var m: CargoPodMotion = craft.motion
		parts.append("%s %s (reach %.2f, jaws %.2f)" % [craft.name, m.phase_name(), m.extend, m.jaw_open])
	return "%d pods (%d inside the wall)%s" % [pods.size(), hidden_count(), (": " + "; ".join(parts)) if not parts.is_empty() else ""]


func _cmd_pods(args: Dictionary) -> ConsoleResult:
	var a: String = str(args[&"a"]) if args[&"a"] != null else ""
	match StringName(args[&"action"]):
		&"hide":
			held_in = true
			return ConsoleResult.line("cargo pods going home")
		&"show":
			held_in = false
			if _crew == null:
				alert.clear()
			return ConsoleResult.line("cargo pods free to go out again")
		&"cargo":
			if cargo == null:
				return ConsoleResult.failure("pods cargo: no station in play")
			return cargo.command(a)
	return ConsoleResult.line(_jobs_text())
