class_name EncounterDirector
extends Node
## Free-flight encounters in play (architecture §18 D58, Q3, Q9, Q12, AC14): starts each `EncounterPlan` event when it is
## due, from pools built when encounters turn on (behind the loading screen when the menu asked for them), and returns its
## ships to their pools once they are 40 km from the player or their route has ended. Raiders come out of a jump point;
## patrols and traffic cruise in from past the radar's reach. An event that would pass `encounter_max_ships` waits.
##
## Cost (AC16): a tick only compares the encounter clock with the next event's time; the release check runs once a second
## over the director's own ships (at most the cap), never over every ship in play (`check_work`).
##
## Encounters run only when asked for (D58): the menu's request turns them on at load; every other run keeps them off
## until the console's `encounters on`, which builds the pools then (a hitch, for debugging).
##
## The jumpgate (M6-T14): a pools file's `gate` table (`EncounterPlan.gate_use`) sends a share of each kind's events through the
## scene's gate while the player is within `GATE_REACH_M` of it: arrivals come out of its blue vortex (raiders instead of a jump
## point, patrols and traffic flying out along its axis), departures fly their way in and leave through its orange one. With no
## table, no gate or the player far from it, every event is placed as before.
##
## Console (`EncounterConsole`): command `encounters`, provider `encounters`.

## A director sits in any scenario with a pools file here, named after the scenario.
const POOLS_DIR: String = "res://data/encounters/"
const NODE_NAME: StringName = &"EncounterDirector"
## A ship this far from the player goes back to its pool.
const RELEASE_M: float = 40000.0
const CHECK_S: float = 1.0
## A raid goes for a civilian at most this far from the player.
const CIVILIAN_REACH_M: float = 20000.0
## Encounter civilians call out their position this far (a transponder), so a raid sent at one from 6-12 km finds it.
const TRANSPONDER_M: float = ShipPool.CIVILIAN_BROADCAST_RANGE_M
const JUMP_POINTS: int = 4
## Forced events' indices start here, far past any session's schedule.
const FORCED_INDEX: int = 1000000
## Events use the gate only while the player is this close to it, so its traffic is seen (and not released at once at 40 km).
const GATE_REACH_M: float = 25000.0
## Ships of one gate arrival come out this far apart, side by side.
const GATE_SPREAD_M: float = 150.0
## Patrols and traffic out of the gate fly this far along its axis before their route ends.
const GATE_OUT_M: float = 15000.0
const PATROL_CALLSIGNS: Array[String] = ["BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT"]
const CIVILIAN_CALLSIGNS: Dictionary[StringName, String] = {
	&"saturn_3_freighter": "SATURN", &"saturn_4_transport": "SATURN", &"saturn_4_tanker": "SATURN",
	&"saturn_8_transport": "SATURN", &"saturn_8_tanker": "SATURN", &"skylark_transport": "SKYLARK",
	&"narn_transport": "NARN", &"centauri_brezebel": "BREZEBEL", &"brakiri_bokmai": "BOKMAI",
}
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider"}
const ALLY_AI: Dictionary = {"type": "ai", "profile": "ally_starfury", "orders": "engage"}
const CIVILIAN_AI: Dictionary = {"type": "ai", "profile": "civilian"}

signal event_started(event: EncounterEvent)
signal ship_released(combatant: Combatant)

var main: Main = null
## Ships to build a type when encounters turn on, and the kinds' weights (the pools file).
var pools: Dictionary[StringName, int] = {}
var weights: Dictionary = EncounterPlan.DEFAULT_WEIGHTS
var pools_path: String = ""
var on: bool = false
var pools_built: bool = false
## The session seed (the request's), so the same seed brings the same encounters.
var seed_value: int = 0
var plan: EncounterPlan = null
## Sim seconds with encounters on: the plan's clock.
var elapsed_s: float = 0.0
## The next event the plan has not handed out yet.
var next_index: int = 0
## Events forced from the console so far: they draw from their own indices, so the schedule stays as it was.
var forced: int = 0
## An event that is due but held by the cap or the pools.
var waiting: EncounterEvent = null
var last_event: EncounterEvent = null
var events_started: int = 0
var ships_released: int = 0
## Ships the last release check looked at (its work count), and checks so far.
var check_work: int = 0
var checks: int = 0
## Milliseconds the pools took to build.
var build_ms: int = 0
var jumps: JumpPointPool = null
## The pools file's `gate` table (`EncounterPlan.parse_gate_shares`); empty for none.
var gate_shares: Dictionary = {}
## Events that used the gate so far, and ships waiting for the arrival vortex (counted against the cap).
var gate_events: int = 0
var in_transit: int = 0

var _check_in_s: float = 0.0
# One entry a ship in play: {combatant, brain, path (BehaviourFollowPath or null), index, kind}.
var _own: Array[Dictionary] = []


## The pools file for `scenario_id`, or "" when it has none.
static func pools_file(scenario_id: StringName) -> String:
	var path: String = POOLS_DIR + String(scenario_id) + ".json"
	return path if FileAccess.file_exists(path) else ""


## A director for `main` from the pools file at `path`, under `main`, off. Null (with a warning) when the file is broken.
static func create(p_main: Main, path: String) -> EncounterDirector:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("EncounterDirector: %s is not a JSON object; no encounters" % path)
		return null
	var director := EncounterDirector.new()
	director.name = NODE_NAME
	director.main = p_main
	director.pools_path = path
	director.seed_value = p_main.scenario_seed
	var raw_pools: Variant = (parsed as Dictionary).get("pools", {})
	if raw_pools is Dictionary:
		for type: Variant in raw_pools:
			if ShipCatalog.has_type(StringName(str(type))):
				director.pools[StringName(str(type))] = maxi(int(raw_pools[type]), 0)
			else:
				push_warning("EncounterDirector: %s: unknown ship type '%s'" % [path, type])
	var raw_weights: Variant = (parsed as Dictionary).get("weights", {})
	if raw_weights is Dictionary and not (raw_weights as Dictionary).is_empty():
		var w: Dictionary = {}
		for kind: StringName in EncounterPlan.KINDS:
			w[kind] = float((raw_weights as Dictionary).get(String(kind), 0.0))
		director.weights = w
	director.gate_shares = EncounterPlan.parse_gate_shares((parsed as Dictionary).get("gate"))
	director.process_mode = Node.PROCESS_MODE_PAUSABLE
	p_main.add_child(director)
	return director


func _ready() -> void:
	jumps = JumpPointPool.new()
	jumps.name = "EncounterJumpPoints"
	jumps.world = main.world
	main.effects.add_child(jumps)
	jumps.prepare(JUMP_POINTS)
	main.director.ship_destroyed.connect(_on_ship_destroyed)
	EncounterConsole.register(self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Turns encounters on, building the pools the first time. Returns what it built, as a line for the console.
func enable() -> String:
	var built: int = 0
	if not pools_built:
		var t0: int = Time.get_ticks_msec()
		for type: StringName in pools:
			built += main.ensure_pool(type, pools[type])
			main.debris.prepare(type)
		# Ships built after load still break up and go back to their pools when destroyed (watching twice is harmless).
		for pooled: Combatant in main.ships.all_ships():
			main.director.watch(pooled)
		build_ms = Time.get_ticks_msec() - t0
		pools_built = true
	if plan == null:
		plan = EncounterPlan.new(seed_value, float(Settings.get_value(&"encounter_interval_s")), weights)
		plan.gate_shares = gate_shares
	on = true
	return "encounters on (seed %d, every %.0f s, at most %d ships)%s" % [seed_value, plan.interval_s, cap(),
			" - built %d pooled ships in %d ms" % [built, build_ms] if built > 0 else ""]


## Stops new encounters; ships in play fly on until they are released.
func disable() -> void:
	on = false


## Ships the encounters may have in play at once (`encounter_max_ships`, live).
func cap() -> int:
	return int(Settings.get_value(&"encounter_max_ships"))


## The encounters' ships in play.
func alive() -> Array[Combatant]:
	var out: Array[Combatant] = []
	for entry: Dictionary in _own:
		out.append(entry["combatant"])
	return out


func alive_count() -> int:
	return _own.size()


## Ships in play of one kind (raid, patrol, traffic).
func alive_of(kind: StringName) -> int:
	var n: int = 0
	for entry: Dictionary in _own:
		n += 1 if entry["kind"] == kind else 0
	return n


## Seconds of encounter time to the next event (0 while one waits).
func next_in_s() -> float:
	if plan == null:
		return -1.0
	return 0.0 if waiting != null else maxf(plan.time_of(next_index) - elapsed_s, 0.0)


func _physics_process(delta: float) -> void:
	if on:
		elapsed_s += delta
		_start_due()
	_check_in_s -= delta
	if _check_in_s <= 0.0:
		_check_in_s = CHECK_S
		check_releases()


# At most one event a tick: the one waiting, else the next once its time has come.
func _start_due() -> void:
	if waiting == null and plan.time_of(next_index) <= elapsed_s:
		waiting = take_next()
	if waiting != null and start(waiting):
		waiting = null


## The plan's next event, and moves past it.
func take_next() -> EncounterEvent:
	var e: EncounterEvent = plan.event(next_index)
	next_index += 1
	return e


## An event of `kind` off the schedule (the console's `force`), drawn from indices the schedule never reaches.
func take_forced(kind: StringName) -> EncounterEvent:
	var e: EncounterEvent = plan.event(FORCED_INDEX + forced, kind)
	forced += 1
	return e


## Starts `e` now when the cap and the pools allow it; false (nothing placed) when it must wait.
func start(e: EncounterEvent) -> bool:
	var admitted: int = EncounterPlan.admit(_own.size() + in_transit, e.count(), cap())
	if admitted == 0:
		return false
	if admitted < e.count():
		e.trim(admitted)
	var types: Array[StringName] = _available_types(e)
	if types.is_empty():
		return false
	var target: Combatant = _raid_target(e) if e.kind == &"raid" else null
	var anchor: UniversePos = _anchor_of(e, target)
	var anchor_velocity: Vector3 = _reference_rest()  # planned velocities are against the player's reference (M6-T08, T09)
	if e.anchor == EncounterEvent.ANCHOR_TARGET:
		anchor_velocity = target.ship.linear_velocity if target != null else main.ship.linear_velocity
	var target_name: String = target.display_name if target != null else main.combatant.display_name
	var gate: Jumpgate = _gate_for(e)
	var via: StringName = plan.gate_use(e.index, e.kind) if gate != null else &""
	if via != &"":
		gate_events += 1
	for k: int in e.count():
		if via == EncounterPlan.GATE_ARRIVE:
			_arrive_at_gate(e, k, types[k], target_name, gate)
		else:
			_place(e, k, types[k], anchor, anchor_velocity, target_name, gate if via == EncounterPlan.GATE_DEPART else null)
	last_event = e
	events_started += 1
	event_started.emit(e)
	return true


## Looks at the director's own ships (never every ship in play): one gone from play is forgotten, one 40 km from the
## player or at its route's end goes back to its pool, and the engine voices are re-ranked once after releases.
func check_releases() -> void:
	checks += 1
	check_work = 0
	var player_at: Vector3 = main.ship.global_position
	var released: bool = false
	for i: int in range(_own.size() - 1, -1, -1):
		check_work += 1
		var entry: Dictionary = _own[i]
		var c: Combatant = entry["combatant"]
		if not _still_ours(entry):
			_own.remove_at(i)
			continue
		var path := entry["path"] as BehaviourFollowPath
		var route_done: bool = path != null and path.phase == BehaviourFollowPath.Phase.DONE
		if route_done or _local_position(c).distance_to(player_at) > RELEASE_M:
			_release_at(i)
			released = true
	if released:
		main.audio.reallocate_engines()


## Returns every encounter ship to its pool now (the console's `clear`). Returns how many.
func release_all() -> int:
	var n: int = _own.size()
	for i: int in range(_own.size() - 1, -1, -1):
		if _still_ours(_own[i]):
			_release_at(i)
		else:
			_own.remove_at(i)
	if n > 0:
		main.audio.reallocate_engines()
	return n


## The route a ship of the encounters flies, or null (a raider, or not one of them).
func path_of(combatant: Combatant) -> BehaviourFollowPath:
	for entry: Dictionary in _own:
		if entry["combatant"] == combatant:
			return entry["path"]
	return null


# --- placing ----------------------------------------------------------------------------------------------------


# Each ship's type with the pools as they are: raids and patrols need their own type free; a traffic hull whose pool is
# spent gives way to the next civilian hull with one free. Empty when the event must wait.
func _available_types(e: EncounterEvent) -> Array[StringName]:
	var free: Dictionary = {}
	var out: Array[StringName] = []
	for k: int in e.count():
		var type: StringName = e.types[k]
		if e.kind == &"traffic":
			type = _free_civilian(type, free)
		if type == &"" or _free_of(type, free) <= 0:
			return [] as Array[StringName]
		free[type] = _free_of(type, free) - 1
		out.append(type)
	return out


func _free_of(type: StringName, taken: Dictionary) -> int:
	return int(taken[type]) if taken.has(type) else main.ships.free_count(type)


func _free_civilian(wanted: StringName, taken: Dictionary) -> StringName:
	var types: Array[StringName] = ShipCatalog.CIVILIAN_TYPES
	var start: int = maxi(types.find(wanted), 0)
	for step: int in types.size():
		var type: StringName = types[(start + step) % types.size()]
		if _free_of(type, taken) > 0:
			return type
	return &""


# A raid for a civilian takes one of the encounters' civilians within reach of the player, by the event's pick; else (or
# with none near) it goes for the player.
func _raid_target(e: EncounterEvent) -> Combatant:
	if not e.at_civilian:
		return null
	var player_at: Vector3 = main.ship.global_position
	var near: Array[Combatant] = []
	for entry: Dictionary in _own:
		var c: Combatant = entry["combatant"]
		if entry["kind"] == &"traffic" and _still_ours(entry) and c.damageable.is_active() \
				and _local_position(c).distance_to(player_at) <= CIVILIAN_REACH_M:
			near.append(c)
	if near.is_empty():
		return null
	return near[mini(floori(e.target_pick * float(near.size())), near.size() - 1)]


# What "at rest" is where the player is (M6-T09): the player's reference's velocity (a station, a gate, or the circular orbit
# under a planet), else the World's anchor's.
func _reference_rest() -> Vector3:
	var reference: FlightReference = main.flight_reference
	if reference != null and is_instance_valid(reference) and reference.frame.is_set():
		return reference.frame.rest_velocity
	return main.world.rest_velocity()


func _anchor_of(e: EncounterEvent, target: Combatant) -> UniversePos:
	var at: Vector3 = _local_position(target) if target != null else main.ship.global_position
	return main.world.to_universe(at)


func _place(e: EncounterEvent, k: int, type: StringName, anchor: UniversePos, anchor_velocity: Vector3,
		target_name: String, depart_by: Jumpgate = null) -> void:
	var ships: ShipPool = main.ships
	var ship_name: String = _name_for(e, type)
	var behaviour: Dictionary = _behaviour_for(e, target_name)
	var at: UniversePos = anchor.plus_local(e.positions[k])
	var made: Dictionary = BrainFactory.from_behaviour(behaviour, at, hash([seed_value, e.index, k]))
	if not bool(made["ok"]):
		push_error("EncounterDirector: %s: %s" % [ship_name, made["error"]])
		return
	var brain: PilotBrain = made["brain"]
	var path: BehaviourFollowPath = null
	if not e.routes[k].is_empty() and brain is AiPilot:
		var route: Route = depart_by.departure_route(main.world, e.cruise_mps) if depart_by != null else _route(e, k, anchor)
		path = BehaviourFollowPath.attach(brain as AiPilot, route)
	var velocity: Vector3 = e.velocities[k] + anchor_velocity
	var basis: Basis = ScenarioLoader.basis_facing(velocity if velocity.length() > 1.0 else -e.positions[k])
	var placed: Combatant = ships.acquire(ship_name, at, basis, velocity, brain, type)
	if placed == null:
		return
	if e.jumps and jumps != null:
		jumps.open_for(at, -basis.z, placed.ship.bounding_radius())
	if placed.cargo_pods != null and e.cargo_pods[k] >= 0:
		placed.cargo_pods.set_count(e.cargo_pods[k])
	if ShipCatalog.is_civilian(type):
		placed.targetable.broadcast_range_m = TRANSPONDER_M
	_own.append({"combatant": placed, "brain": brain, "path": path, "index": e.index, "kind": e.kind})
	if depart_by != null and path != null:
		placed.ship.tier_exempt = true  # the gate watches its node fly in
		depart_by.send_departure(placed.ship, func(_ship: Node3D) -> void: _release_ship(placed, brain))


# One ship of an event that comes out of the gate: taken from its pool once the blue vortex is open, beside the others of its
# event, flying out along the gate's axis; a raider goes for its target, a patrol or traffic flies on along the axis.
func _arrive_at_gate(e: EncounterEvent, k: int, type: StringName, target_name: String, gate: Jumpgate) -> void:
	var ship_name: String = _name_for(e, type)
	var behaviour: Dictionary = _behaviour_for(e, target_name)
	var offset := Vector3((float(k) - float(e.count() - 1) * 0.5) * GATE_SPREAD_M, 0.0, 0.0)
	var made: Dictionary = BrainFactory.from_behaviour(behaviour, main.world.to_universe(gate.global_position),
			hash([seed_value, e.index, k]))
	if not bool(made["ok"]):
		push_error("EncounterDirector: %s: %s" % [ship_name, made["error"]])
		return
	in_transit += 1
	gate.request_arrival(func() -> void:
		in_transit -= 1
		var brain: PilotBrain = made["brain"]
		var xform: Transform3D = gate.arrival_transform(offset)
		var path: BehaviourFollowPath = null
		if e.kind != &"raid" and brain is AiPilot:
			var route := Route.new()
			route.name = "ENCOUNTER %d" % e.index
			route.pace = Route.PACE_NONE
			route.yield_to_attack = e.kind == &"patrol"
			route.cruise_mps = e.cruise_mps
			route.add(main.world.to_universe(xform.origin + gate.arrival_velocity().normalized() * GATE_OUT_M))
			path = BehaviourFollowPath.attach(brain as AiPilot, route)
		var placed: Combatant = main.ships.acquire(ship_name, main.world.to_universe(xform.origin), xform.basis,
				gate.arrival_velocity() + main.world.rest_velocity(), brain, type)
		if placed == null:
			return
		if ShipCatalog.is_civilian(type):
			placed.targetable.broadcast_range_m = TRANSPONDER_M
		_own.append({"combatant": placed, "brain": brain, "path": path, "index": e.index, "kind": e.kind}))


# The scene's gate when this event may use it: a gate table, a gate, and the player within reach of it.
func _gate_for(_e: EncounterEvent) -> Jumpgate:
	if gate_shares.is_empty() or main.gates == null:
		return null
	var gate: Jumpgate = main.gates.gate()
	if gate == null or gate.global_position.distance_to(main.ship.global_position) > GATE_REACH_M:
		return null
	return gate


func _name_for(e: EncounterEvent, type: StringName) -> String:
	match e.kind:
		&"raid":
			return main.ships.next_name()
		&"patrol":
			return main.ships.next_name(PATROL_CALLSIGNS[e.index % PATROL_CALLSIGNS.size()], 1)
	return main.ships.next_name(CIVILIAN_CALLSIGNS.get(type, "CIVILIAN"), 1)


func _behaviour_for(e: EncounterEvent, target_name: String) -> Dictionary:
	match e.kind:
		&"raid":
			var behaviour: Dictionary = RAIDER_AI.duplicate()
			behaviour["objective"] = target_name
			return behaviour
		&"patrol":
			return ALLY_AI.duplicate()
	return CIVILIAN_AI.duplicate()


# A departing ship went through the gate: back to its pool, if it still flies for the encounters.
func _release_ship(c: Combatant, brain: PilotBrain) -> void:
	for i: int in _own.size():
		if _own[i]["combatant"] == c and _own[i]["brain"] == brain and _still_ours(_own[i]):
			_release_at(i)
			main.audio.reallocate_engines()
			return


# A straight route that ends where it ends: a patrol stands aside to fight what it meets, traffic keeps going.
func _route(e: EncounterEvent, k: int, anchor: UniversePos) -> Route:
	var route := Route.new()
	route.name = "ENCOUNTER %d" % e.index
	route.pace = Route.PACE_NONE
	route.loop = false
	route.yield_to_attack = e.kind == &"patrol"
	route.cruise_mps = e.cruise_mps
	for point: Vector3 in e.routes[k]:
		route.add(anchor.plus_local(point))
	return route


# --- releasing --------------------------------------------------------------------------------------------------


# Whether the entry's ship is still flying for the encounters: a destroyed ship went back to its pool and may already fly
# for someone else (a new brain).
func _still_ours(entry: Dictionary) -> bool:
	var c: Combatant = entry["combatant"]
	return is_instance_valid(c.ship) and c.driver != null and c.driver.brain == entry["brain"]


func _release_at(i: int) -> void:
	var c: Combatant = _own[i]["combatant"]
	_own.remove_at(i)
	if ShipCatalog.is_civilian(main.ships.type_of(c)):
		c.targetable.broadcast_range_m = 0.0
	main.ships.release(c)
	ships_released += 1
	ship_released.emit(c)


func _on_ship_destroyed(combatant: Combatant, _info: HitInfo) -> void:
	for i: int in _own.size():
		if _own[i]["combatant"] == combatant:
			if ShipCatalog.is_civilian(main.ships.type_of(combatant)):
				combatant.targetable.broadcast_range_m = 0.0
			_own.remove_at(i)
			return


# Where a ship flies now in the World frame: its tier row's place while it is in the low-attention tier.
func _local_position(c: Combatant) -> Vector3:
	var pose: Array = TierDirector.row_pose(c.ship)
	return (pose[0] as Transform3D).origin if not pose.is_empty() else c.ship.global_position
