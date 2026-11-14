class_name StationTraffic
extends Node
## Traffic at the station (M7-T10, AC9, Q8 as refined): civilians into and out of the main docking bay, freighters at the
## cargo bay, raids sent at the station and its defenders scrambled from the Cobra bays. Main's child; every ship is a
## pooled ship flown by the native brains on a `Route` (a `DockingPlan` lane near the station), so this node only starts
## things and looks at its own few ships once a tick.
##
## - **Docking**: a hull that fits the tunnel flies the lane in, matching the drum's turn, and goes back to its pool at the
##   inner airlock (it left the world). **Undocking** is the same lane outward, from the airlock, already turning with the drum.
## - **Freighter cycle**: any of the five Saturns flies to the cargo bay's lane, turns short of the hold point, backs in (stern and
##   pods to the bay), waits while the station's maintenance bots carry its pods or tanks into the bay one by one (or, loading,
##   out of the bay onto it; `FreighterCargo`, M7-T30), and leaves nose first when they are done.
## - **Raid**: raiders with the station as their objective (they aim at the grid's mounts, native), and the wings named in
##   the data scrambled against them.
## - Arrivals come out of the scene's jumpgate when it has one, and departures leave through it; without one they start
##   and end a few kilometres out.
## - **Light traffic by itself** while free-flight encounters are on (`data/station/traffic.json`: the interval, the kinds'
##   weights; each event a hash of the session seed and its index).
##
## Console: command and provider `traffic`.

const NODE_NAME: StringName = &"StationTraffic"
const DATA_PATH: String = "res://data/station/traffic.json"
const PROVIDER: StringName = &"traffic"
const ACTIONS: Array[StringName] = [&"status", &"dock", &"undock", &"freighter", &"raid", &"scramble", &"auto", &"clear"]
const KINDS: Array[StringName] = [&"dock", &"undock", &"freighter", &"raid"]
const CIVILIAN_AI: Dictionary = {"type": "ai", "profile": "civilian"}
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider", "orders": "attack"}
const TRANSIT_CRUISE_MPS: float = 120.0
## Without a gate: how far beyond a lane's first point a ship starts, and how far out a leaving ship is let go, metres.
const START_OUT_M: float = 2500.0
const LEAVE_OUT_M: float = 12000.0
## Without a gate a raid starts this far off the bow, above it (station frame).
const RAID_FROM: Vector3 = Vector3(0.0, 2500.0, -11000.0)
const RAID_SPEED_MPS: float = 120.0
const RAID_SPREAD_M: float = 150.0
## A docking ship this near the airlock has left the world.
const AIRLOCK_M: float = 30.0
const DEFAULT_RAID: int = 6
## `traffic freighter show`: the Saturn starts this far short of the hold point backing in at this speed (m, m/s), and the player
## watches from toward the bay, to the side and above, looking a little toward the bay from the hold point (m).
const SHOW_BACK_M: float = 300.0
const SHOW_BACK_MPS: float = 8.0
const VIEW_TOWARD_M: float = 240.0
const VIEW_SIDE_M: float = 120.0
const VIEW_UP_M: float = 45.0
const VIEW_LOOK_M: float = 70.0

signal docked(ship_name: String)
signal undocked(ship_name: String)
signal freighter_unloading(ship_name: String)
signal freighter_loading(ship_name: String)
signal freighter_left(ship_name: String)

var main: Main = null
var plan: DockingPlan = null
## Whether light traffic starts by itself (set when encounters are on; the console's `traffic auto on|off` overrides).
var auto: bool = false
var auto_forced: bool = false
var interval_s: float = 150.0
var weights: Dictionary = {}
var raid_size: Vector2i = Vector2i(4, 6)
var scramble_wings: PackedStringArray = PackedStringArray()
var max_ships: int = 8
var elapsed_s: float = 0.0
var events: int = 0
var docked_count: int = 0
var undocked_count: int = 0
var freighters_done: int = 0
## Cargo pods the bots carried into the cargo bay, and onto freighters.
var pods_in: int = 0
var pods_out: int = 0
var raids: int = 0
var last_event: String = "none"
# One entry a ship: {combatant, brain, kind, state, cargo, loading, cargo_state} (the last three for freighters).
var _own: Array[Dictionary] = []
var _spawned: int = 0


func _init() -> void:
	name = NODE_NAME
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _ready() -> void:
	_load_data()
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func station() -> Station:
	if main == null or main.far_props == null:
		return null
	var s: Station = main.far_props.station
	return s if s != null and is_instance_valid(s) and s.hardpoints != null else null


## The traffic's ships in play, and those of one kind.
func alive_count() -> int:
	return _own.size()


func alive_of(kind: StringName) -> int:
	var n: int = 0
	for entry: Dictionary in _own:
		n += 1 if entry["kind"] == kind else 0
	return n


## The traffic ship called `ship_name`, or null.
func ship_named(ship_name: String) -> Combatant:
	for entry: Dictionary in _own:
		if (entry["combatant"] as Combatant).display_name == ship_name:
			return entry["combatant"]
	return null


## The last ship started, or null.
func last_ship() -> Combatant:
	return _own[_own.size() - 1]["combatant"] if not _own.is_empty() else null


## A civilian flies into the main docking bay. `near` starts it on the lane's first point instead of far out or at the
## gate. Returns "" or why not.
func dock(type: StringName = &"", near: bool = false) -> String:
	var why: String = _ready_plan()
	if not why.is_empty():
		return why
	var hull: StringName = _tunnel_type(type)
	if hull == &"":
		return "%s does not fit the docking tunnel (%s do)" % [type, ", ".join(DockingPlan.TUNNEL_TYPES)]
	return _arrive(hull, &"dock", plan.dock_in, near)


## A civilian comes out of the main docking bay and leaves. Returns "" or why not.
func undock(type: StringName = &"") -> String:
	var why: String = _ready_plan()
	if not why.is_empty():
		return why
	var hull: StringName = _tunnel_type(type)
	if hull == &"":
		return "%s does not fit the docking tunnel (%s do)" % [type, ", ".join(DockingPlan.TUNNEL_TYPES)]
	var s: Station = station()
	var xform: Transform3D = s.global_transform
	var airlock: Vector3 = plan.airlock
	var out_dir: Vector3 = ((plan.dock_out[0]["at"] as Vector3) - airlock).normalized()
	# Lying square in the tunnel as the drum has turned it.
	var basis: Basis = Basis.looking_at(xform.basis * out_dir, s.drum_body.global_basis.y)
	var velocity: Vector3 = main.world.rest_velocity() + xform.basis * out_dir * (DockingPlan.DOCK_CRUISE_MPS * 0.5)
	var route: Route = DockingPlan.route_of(plan.dock_out, xform, main.world, DockingPlan.DOCK_CRUISE_MPS, "UNDOCKING")
	var c: Combatant = _take(hull, route, xform * airlock, basis, velocity, &"undock", &"lane")
	if c == null:
		return "no %s is free in the ship pool" % hull
	c.ship.angular_velocity = xform.basis * plan.spin  # it comes out turning with the drum
	return ""


## A Saturn of `type` (any of `DockingPlan.FREIGHTER_TYPES`; "" picks one) flies the cargo bay's cycle, unloading or `loading`.
## `start`: "" out of the gate (or far out), `near` on the lane's first point, `hold` already holding at the bay, `show` backing in
## its last `SHOW_BACK_M` with the bots already on their way and the player put beside the lane to watch. Returns "" or why not.
func freighter(type: StringName = &"", loading: bool = false, start: StringName = &"") -> String:
	var why: String = _ready_plan()
	if not why.is_empty():
		return why
	var hull: StringName = type
	if hull == &"":
		hull = DockingPlan.FREIGHTER_TYPES[_spawned % DockingPlan.FREIGHTER_TYPES.size()]
	if not DockingPlan.FREIGHTER_TYPES.has(hull):
		return "%s does not come to the cargo bay (%s do)" % [type, ", ".join(DockingPlan.FREIGHTER_TYPES)]
	if start == &"hold" or start == &"show":
		var xform: Transform3D = station().global_transform
		var lane: Array[Dictionary] = [plan.freighter[plan.freighter_hold_index], plan.freighter[plan.freighter.size() - 1]]
		var at: Vector3 = xform * (lane[0]["at"] as Vector3)
		var velocity: Vector3 = main.world.rest_velocity()
		if start == &"show":
			at += xform.basis * plan.away * SHOW_BACK_M
			velocity += xform.basis * -plan.away * SHOW_BACK_MPS
		var c: Combatant = _take(hull, _lane_route(&"freighter", lane), at, Basis.looking_at(xform.basis * plan.away, xform.basis.y),
				velocity, &"freighter", &"lane", {"loading": loading, "hold_index": 0})
		if c == null:
			return "no %s is free in the ship pool" % hull
		if start == &"show":
			_start_cargo(_own[_own.size() - 1], true)
			return view_cargo_bay()
		return ""
	return _arrive(hull, &"freighter", plan.freighter, start == &"near", {"loading": loading})


## Puts the player beside the freighters' lane, toward the bay from the hold point, looking at a held Saturn's pods: the bots come
## past on their way out and back. "" or why not.
func view_cargo_bay() -> String:
	var s: Station = station()
	if s == null or not main.player_alive:
		return "no player to move"
	var hold: Vector3 = s.hardpoints.cargo_bay["cargo_bay_hold"]
	var toward: Vector3 = -plan.away
	var at: Vector3 = s.to_global(hold + toward * VIEW_TOWARD_M + Vector3(VIEW_SIDE_M, VIEW_UP_M, 0.0))
	var look: Vector3 = s.to_global(hold + toward * VIEW_LOOK_M)
	main.ship.reset_to(Transform3D(Basis.looking_at((look - at).normalized(), s.global_basis.y), at))
	main.ship.linear_velocity = main.world.rest_velocity()
	main.ship.angular_velocity = Vector3.ZERO
	return ""


## `count` raiders sent at the station, and the data's wings scrambled against them. Returns "" or why not.
func raid(count: int = DEFAULT_RAID, scramble_defenders: bool = true) -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario"
	count = clampi(count, 1, 12)
	_ensure_free(ShipPool.DEFAULT_TYPE, count)
	var behaviour: Dictionary = RAIDER_AI.duplicate()
	behaviour["objective"] = Station.DISPLAY_NAME
	var gate: Jumpgate = _gate()
	var placed: int = 0
	for k: int in count:
		var made: Dictionary = BrainFactory.from_behaviour(behaviour, main.world.to_universe(s.global_position),
				hash([main.scenario_seed, "station raid", raids, k]))
		# Ships asked of the gate are taken from the pool later, when its vortex is open.
		if not bool(made["ok"]) or main.ships.free_count(ShipPool.DEFAULT_TYPE) <= (placed if gate != null else 0):
			break
		var brain: PilotBrain = made["brain"]
		var offset := Vector3((float(k) - float(count - 1) * 0.5) * RAID_SPREAD_M, 0.0, 0.0)
		placed += 1
		if gate != null:
			gate.request_arrival(func() -> void:
				var xform: Transform3D = gate.arrival_transform(offset)
				var c: Combatant = main.ships.acquire(main.ships.next_name(), main.world.to_universe(xform.origin), xform.basis,
						gate.arrival_velocity() + main.world.rest_velocity(), brain, ShipPool.DEFAULT_TYPE)
				if c != null:
					gate.bring_through(c.ship)
					_own.append({"combatant": c, "brain": brain, "kind": &"raid", "state": &"raid", "cargo": null}))
		else:
			var at: Vector3 = s.global_transform * (RAID_FROM + offset)
			var toward: Vector3 = (s.global_position - at).normalized()
			var c: Combatant = main.ships.acquire(main.ships.next_name(), main.world.to_universe(at),
					Basis.looking_at(toward, Vector3.UP), main.world.rest_velocity() + toward * RAID_SPEED_MPS, brain, ShipPool.DEFAULT_TYPE)
			if c != null:
				_own.append({"combatant": c, "brain": brain, "kind": &"raid", "state": &"raid", "cargo": null})
	if placed == 0:
		return "no raider is free in the ship pool"
	raids += 1
	if scramble_defenders:
		for wing: String in scramble_wings:
			scramble(wing)
	return ""


## The station's wing `wing` launches from its Cobra arm (T08's sequence: two waves of six). Returns "" or why not.
func scramble(wing: String) -> String:
	if main.launches == null:
		return "no launch director"
	return main.launches.launch_wing(wing)


## Every traffic ship back to its pool. Returns how many.
func clear() -> int:
	var n: int = 0
	for i: int in range(_own.size() - 1, -1, -1):
		if _still_ours(_own[i]):
			_release(i)
			n += 1
		else:
			_own.remove_at(i)
	return n


func _physics_process(delta: float) -> void:
	var director: EncounterDirector = main.encounter_director if main != null else null
	if not auto_forced:
		auto = director != null and director.on and station() != null
	if auto:
		elapsed_s += delta
		if elapsed_s >= interval_s * float(events + 1):
			_start_auto()
	for i: int in range(_own.size() - 1, -1, -1):
		_step(i)


# --- starting ---------------------------------------------------------------------------------------------------


func _ready_plan() -> String:
	var s: Station = station()
	if s == null:
		return "no station in this scenario"
	if plan == null or not plan.valid:
		plan = DockingPlan.build(s.hardpoints, s.drum_origin)
	return "" if plan.valid else plan.error


func _tunnel_type(type: StringName) -> StringName:
	if type == &"":
		return DockingPlan.TUNNEL_TYPES[_spawned % DockingPlan.TUNNEL_TYPES.size()]
	return type if DockingPlan.TUNNEL_TYPES.has(type) else &""


func _gate() -> Jumpgate:
	return main.gates.gate() if main.gates != null else null


# A ship of `type` on its way to `lane`: out of the gate and across to the lane's first point, or with no gate (or `near`)
# straight onto the lane from a little way out.
func _arrive(type: StringName, kind: StringName, lane: Array[Dictionary], near: bool, extra: Dictionary = {}) -> String:
	var s: Station = station()
	var xform: Transform3D = s.global_transform
	_ensure_free(type, 1)
	if main.ships.free_count(type) < 1:
		return "no %s is free in the ship pool" % type
	var first: Vector3 = xform * (lane[0]["at"] as Vector3)
	var gate: Jumpgate = null if near else _gate()
	if gate != null:
		var transit := Route.new()
		transit.name = "TO THE STATION"
		transit.pace = Route.PACE_NONE
		transit.cruise_mps = TRANSIT_CRUISE_MPS
		transit.add(main.world.to_universe(first))
		gate.request_arrival(func() -> void:
			var at: Transform3D = gate.arrival_transform()
			var c: Combatant = _take(type, transit, at.origin, at.basis, gate.arrival_velocity() + main.world.rest_velocity(),
					kind, &"transit", extra)
			if c != null:
				gate.bring_through(c.ship))
		return ""
	var inward: Vector3 = ((lane[1]["at"] as Vector3) - (lane[0]["at"] as Vector3)).normalized()
	var start: Vector3 = xform * ((lane[0]["at"] as Vector3) - inward * (0.0 if near else START_OUT_M))
	var heading: Vector3 = xform.basis * inward
	var route: Route = _lane_route(kind, lane)
	var c: Combatant = _take(type, route, start, Basis.looking_at(heading, xform.basis.y),
			main.world.rest_velocity() + heading * route.cruise_mps, kind, &"lane", extra)
	return "" if c != null else "no %s is free in the ship pool" % type


# Grows `type`'s pool until `count` of it are free (a hitch when it builds; a mission sizes its pools beforehand).
func _ensure_free(type: StringName, count: int) -> void:
	var short: int = count - main.ships.free_count(type)
	if short > 0:
		main.ensure_pool(type, main.ships.pool_size(type) + short)
		main.debris.prepare(type)
		for pooled: Combatant in main.ships.all_ships():
			main.director.watch(pooled)


func _lane_route(kind: StringName, lane: Array[Dictionary]) -> Route:
	var cruise: float = DockingPlan.FREIGHTER_CRUISE_MPS if kind == &"freighter" else DockingPlan.DOCK_CRUISE_MPS
	return DockingPlan.route_of(lane, station().global_transform, main.world, cruise, String(kind).to_upper())


# Takes a ship of `type` out of the pool at `at` (World) flying `route`; null when the pool has none.
func _take(type: StringName, route: Route, at: Vector3, basis: Basis, velocity: Vector3, kind: StringName, state: StringName,
		extra: Dictionary = {}) -> Combatant:
	_ensure_free(type, 1)
	var made: Dictionary = BrainFactory.from_behaviour(CIVILIAN_AI, main.world.to_universe(at), hash([main.scenario_seed, "traffic", _spawned]))
	if not bool(made["ok"]):
		push_error("StationTraffic: %s" % made["error"])
		return null
	var brain: PilotBrain = made["brain"]
	BehaviourFollowPath.attach(brain as AiPilot, route)
	var callsign: String = main.ships.next_name(EncounterDirector.CIVILIAN_CALLSIGNS.get(type, "CIVILIAN"), 1)
	var c: Combatant = main.ships.acquire(callsign, main.world.to_universe(at), basis, velocity, brain, type)
	if c == null:
		return null
	_spawned += 1
	c.ship.tier_exempt = true  # a lane is flown in full, wherever the player is
	c.targetable.broadcast_range_m = ShipPool.CIVILIAN_BROADCAST_RANGE_M
	var entry: Dictionary = {"combatant": c, "brain": brain, "kind": kind, "state": state, "cargo": null, "loading": false,
			"cargo_state": &"", "hold_index": plan.freighter_hold_index if plan != null else -1}
	entry.merge(extra, true)
	# A freighter come to load arrives without its pods.
	if kind == &"freighter" and bool(entry["loading"]):
		entry["cargo"] = FreighterCargo.attach(c.ship, false)
	_own.append(entry)
	last_event = "%s %s" % [kind, callsign]
	return c


func _start_auto() -> void:
	var index: int = events
	events += 1
	if alive_count() >= max_ships:
		return
	var kind: StringName = _draw_kind(index)
	var why: String = ""
	match kind:
		&"dock":
			why = dock()
		&"undock":
			why = undock()
		&"freighter":
			var pick: int = hash([main.scenario_seed, "traffic freighter", index])
			var hull: StringName = DockingPlan.FREIGHTER_TYPES[absi(pick) % DockingPlan.FREIGHTER_TYPES.size()]
			why = freighter(hull, (absi(pick) >> 8) % 2 == 1) if alive_of(&"freighter") == 0 \
					else "a freighter is at the cargo bay already"
		&"raid":
			var u: float = float(hash([main.scenario_seed, "traffic size", index])) / 4294967296.0
			why = raid(raid_size.x + mini(floori(u * float(raid_size.y - raid_size.x + 1)), raid_size.y - raid_size.x))
	last_event = "%s (auto)%s" % [kind, "" if why.is_empty() else ": " + why]


func _draw_kind(index: int) -> StringName:
	var total: float = 0.0
	for kind: StringName in KINDS:
		total += maxf(float(weights.get(kind, 0.0)), 0.0)
	var pick: float = float(hash([main.scenario_seed, "traffic kind", index])) / 4294967296.0 * total
	for kind: StringName in KINDS:
		var w: float = maxf(float(weights.get(kind, 0.0)), 0.0)
		if pick < w:
			return kind
		pick -= w
	return KINDS[0]


# --- following --------------------------------------------------------------------------------------------------


# One of the traffic's ships this tick: a transit that reached the lane takes the lane, a freighter at the hold point
# has its cargo carried and leaves when the bots are done, a ship at its lane's end docks or leaves, and one that left is let go.
func _step(i: int) -> void:
	var entry: Dictionary = _own[i]
	if not _still_ours(entry):
		_drop_pods(entry)
		_own.remove_at(i)
		return
	var c: Combatant = entry["combatant"]
	var kind: StringName = entry["kind"]
	if kind == &"raid":
		return
	var path := (entry["brain"] as AiPilot).behaviour(&"follow_path") as BehaviourFollowPath
	var done: bool = path != null and path.phase == BehaviourFollowPath.Phase.DONE
	match entry["state"]:
		&"transit":
			if done:
				BehaviourFollowPath.attach(entry["brain"] as AiPilot, _lane_route(kind, plan.freighter if kind == &"freighter" else plan.dock_in))
				entry["state"] = &"lane"
		&"lane":
			if kind == &"dock":
				var s: Station = station()
				var airlock: Vector3 = s.global_transform * plan.airlock
				if done or c.ship.global_position.distance_to(airlock) < AIRLOCK_M:
					docked_count += 1
					docked.emit(c.display_name)
					_release(i)
				return
			var holding_at_bay: bool = path != null and path.phase == BehaviourFollowPath.Phase.HOLD \
					and path.index == int(entry["hold_index"])
			if kind == &"freighter" and entry["cargo_state"] == &"" and holding_at_bay:
				_start_cargo(entry)
			elif kind == &"freighter" and entry["cargo_state"] == &"working" and holding_at_bay and not bool(entry.get("berthed", true)):
				entry["berthed"] = true
				(entry["cargo"] as FreighterCargo).berth(station())
			if kind == &"freighter" and entry["cargo_state"] == &"done":
				_depart(entry)
			if done:
				_leave(entry)
		&"leave":
			if done:
				_finish(i)


# The bots come for a freighter's cargo now it holds at the bay (or, `early`, while it backs in: they wait for it to stop); with
# no bots (or no plan) it just goes on.
func _start_cargo(entry: Dictionary, early: bool = false) -> void:
	var c: Combatant = entry["combatant"]
	var loading: bool = entry["loading"]
	entry["cargo_state"] = &"working"
	var cargo := entry["cargo"] as FreighterCargo
	if cargo == null:
		cargo = FreighterCargo.attach(c.ship, true)
		entry["cargo"] = cargo
	var why: String = "no cargo chunks" if cargo == null else cargo.start(station(), early)
	entry["berthed"] = not early
	if not why.is_empty():
		push_warning("StationTraffic: %s's cargo stays put: %s" % [c.display_name, why])
		entry["cargo_state"] = &"done"
		return
	cargo.pod_done.connect(func(_pod: String) -> void:
		if loading:
			pods_out += 1
		else:
			pods_in += 1)
	cargo.finished.connect(func() -> void: entry["cargo_state"] = &"done")
	if loading:
		freighter_loading.emit(c.display_name)
	else:
		freighter_unloading.emit(c.display_name)


# The bots are done: the freighter leaves its hold point now, out along its lane.
func _depart(entry: Dictionary) -> void:
	entry["cargo_state"] = &"gone"
	var lane: Array[Dictionary] = [plan.freighter[plan.freighter.size() - 1]]
	BehaviourFollowPath.attach(entry["brain"] as AiPilot, _lane_route(&"freighter", lane))


# The way out after a lane: through the gate when there is one, else straight on to where it is let go.
func _leave(entry: Dictionary) -> void:
	var c: Combatant = entry["combatant"]
	var brain: PilotBrain = entry["brain"]
	entry["state"] = &"leave"
	var gate: Jumpgate = _gate()
	if gate != null:
		BehaviourFollowPath.attach(brain as AiPilot, gate.departure_route(main.world, TRANSIT_CRUISE_MPS))
		gate.send_departure(c.ship, func(_ship: Node3D) -> void:
			for k: int in _own.size():
				if _own[k]["combatant"] == c and _own[k]["brain"] == brain:
					_finish(k)
					return)
		return
	var route := Route.new()
	route.name = "LEAVING"
	route.pace = Route.PACE_NONE
	route.cruise_mps = TRANSIT_CRUISE_MPS
	var heading: Vector3 = -c.ship.global_basis.z
	route.add(main.world.to_universe(c.ship.global_position + heading * LEAVE_OUT_M))
	BehaviourFollowPath.attach(brain as AiPilot, route)


func _finish(i: int) -> void:
	var entry: Dictionary = _own[i]
	var c: Combatant = entry["combatant"]
	if entry["kind"] == &"freighter":
		freighters_done += 1
		freighter_left.emit(c.display_name)
	else:
		undocked_count += 1
		undocked.emit(c.display_name)
	_release(i)


func _release(i: int) -> void:
	var entry: Dictionary = _own[i]
	var c: Combatant = entry["combatant"]
	_own.remove_at(i)
	_drop_pods(entry)
	var gate: Jumpgate = _gate()
	if gate != null:
		gate.cancel_departure(c.ship)
	c.ship.tier_exempt = false
	c.targetable.broadcast_range_m = 0.0
	main.ships.release(c)
	main.audio.reallocate_engines()


static func _drop_pods(entry: Dictionary) -> void:
	var cargo: Variant = entry.get("cargo")
	if cargo is FreighterCargo and is_instance_valid(cargo) and not (cargo as FreighterCargo).restored:
		(cargo as FreighterCargo).restore()
	entry["cargo"] = null


# Whether the entry's ship still flies for the traffic (a destroyed one went back to its pool and may fly for someone else).
static func _still_ours(entry: Dictionary) -> bool:
	var c: Combatant = entry["combatant"]
	return is_instance_valid(c.ship) and c.driver != null and c.driver.brain == entry["brain"]


func _load_data() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)) if FileAccess.file_exists(DATA_PATH) else null
	if not (parsed is Dictionary):
		push_warning("StationTraffic: %s is missing or not a JSON object; no traffic by itself" % DATA_PATH)
		return
	var data: Dictionary = parsed
	interval_s = maxf(float(data.get("interval_s", interval_s)), 10.0)
	max_ships = maxi(int(data.get("max_ships", max_ships)), 0)
	var raw_weights: Variant = data.get("weights", {})
	if raw_weights is Dictionary:
		for kind: StringName in KINDS:
			weights[kind] = float((raw_weights as Dictionary).get(String(kind), 0.0))
	var size: Variant = data.get("raid_size", [])
	if size is Array and (size as Array).size() == 2:
		raid_size = Vector2i(maxi(int(size[0]), 1), maxi(int(size[1]), int(size[0])))
	var wings: Variant = data.get("scramble", [])
	if wings is Array:
		for wing: Variant in wings:
			scramble_wings.append(str(wing))


# --- console ----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	registry.register_provider(PROVIDER, ConsoleVars.new({
		&"auto": {"get": func() -> bool: return auto, "doc": "Whether light traffic starts by itself (free-flight encounters on, or traffic auto on)"},
		&"interval_s": {"get": func() -> float: return interval_s, "unit": "s", "doc": "Time between the traffic's own events"},
		&"alive": {"get": alive_count, "doc": "Traffic ships in play"},
		&"docking": {"get": func() -> int: return alive_of(&"dock"), "doc": "Of them, flying into the main docking bay"},
		&"undocking": {"get": func() -> int: return alive_of(&"undock"), "doc": "Of them, leaving the main docking bay"},
		&"freighters": {"get": func() -> int: return alive_of(&"freighter"), "doc": "Of them, freighters at the cargo bay"},
		&"raiders": {"get": func() -> int: return alive_of(&"raid"), "doc": "Of them, raiders sent at the station"},
		&"docked": {"get": func() -> int: return docked_count, "doc": "Ships that left the world at the inner airlock"},
		&"undocked": {"get": func() -> int: return undocked_count, "doc": "Ships that came out of the bay and left"},
		&"freighters_done": {"get": func() -> int: return freighters_done, "doc": "Freighter cycles finished"},
		&"pods_in": {"get": func() -> int: return pods_in, "doc": "Cargo pods the maintenance bots carried into the cargo bay"},
		&"pods_out": {"get": func() -> int: return pods_out, "doc": "Cargo pods the maintenance bots carried onto freighters"},
		&"cargo": {"get": _cargo_text, "doc": "Each freighter at the cargo bay: its hull, unloading or loading, and pods carried"},
		&"raids": {"get": func() -> int: return raids, "doc": "Raids sent at the station"},
		&"last_event": {"get": func() -> String: return last_event, "doc": "The last thing the traffic started"},
	}), self)
	registry.register_command(ConsoleCommand.new(&"traffic",
			"Station traffic: status, dock [near] (a civilian into the main docking bay), undock (one out of it), freighter [type] [near|hold|show] [load] (a Saturn's cargo cycle: the station's bots carry its pods or tanks into the cargo bay, or with load onto it; near starts it on the lane, hold already at the bay, show backing in its last 300 m with the bots on their way and you beside the lane to watch; type is one of %s, default each in turn), raid [n] (raiders at the station, its wings scrambled), scramble <wing>, auto <on|off>, clear" % ", ".join(DockingPlan.FREIGHTER_TYPES),
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"), _rest_arg()] as Array[ConsoleArg]),
			_cmd_traffic, self)


func _cmd_traffic(args: Dictionary) -> ConsoleResult:
	var arg: String = str(args.get(&"arg", "")).to_lower()
	var why: String = ""
	match StringName(args[&"action"]):
		&"dock":
			why = dock(&"", arg == "near")
			return _answer(why, "a civilian is on its way into the main docking bay")
		&"undock":
			why = undock()
			return _answer(why, "a civilian is coming out of the main docking bay")
		&"freighter":
			var words: PackedStringArray = arg.split(" ", false)
			var type: StringName = &""
			var start: StringName = &""
			for word: String in words:
				if ["near", "hold", "show"].has(word):
					start = StringName(word)
				elif word != "load":
					type = StringName(word)
			var loading: bool = words.has("load")
			why = freighter(type, loading, start)
			var c: Combatant = last_ship()
			var hull: String = String(main.ships.type_of(c)) if c != null and why.is_empty() and main.ships.type_of(c) != &"" else "a Saturn"
			return _answer(why, "%s is on its way to the cargo bay to %s" % [hull, "load" if loading else "unload"])
		&"raid":
			var n: int = int(arg) if arg.is_valid_int() else DEFAULT_RAID
			why = raid(n)
			return _answer(why, "%d raiders sent at the station%s" % [clampi(n, 1, 12),
					"" if scramble_wings.is_empty() else "; scrambling %s" % ", ".join(scramble_wings)])
		&"scramble":
			why = scramble(arg) if not arg.is_empty() else "traffic scramble <%s>" % "|".join(LaunchDirector.WINGS)
			return _answer(why, "wing %s is launching" % arg)
		&"auto":
			if arg != "on" and arg != "off":
				return ConsoleResult.failure("traffic auto <on|off>")
			auto_forced = true
			auto = arg == "on"
			return ConsoleResult.line("traffic by itself %s (every %.0f s)" % [arg, interval_s])
		&"clear":
			return ConsoleResult.line("returned %d traffic ship(s) to their pools" % clear())
	return ConsoleResult.line("traffic: %d in play (%d docking, %d undocking, %d freighters, %d raiders); docked %d, undocked %d, freighter cycles %d, pods in %d, pods out %d, raids %d; auto %s; cargo: %s; last: %s" % [
			alive_count(), alive_of(&"dock"), alive_of(&"undock"), alive_of(&"freighter"), alive_of(&"raid"), docked_count,
			undocked_count, freighters_done, pods_in, pods_out, raids, "on" if auto else "off", _cargo_text(), last_event])


func _cargo_text() -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in _own:
		if entry["kind"] != &"freighter":
			continue
		var c: Combatant = entry["combatant"]
		var cargo: Variant = entry.get("cargo")
		var carried: String = ""
		if cargo is FreighterCargo and is_instance_valid(cargo):
			carried = ", %d of %d pods" % [(cargo as FreighterCargo).pods_done(), (cargo as FreighterCargo).pod_count()]
		parts.append("%s %s %s (%s%s)" % [c.display_name, main.ships.type_of(c), "loading" if bool(entry["loading"]) else "unloading",
				entry["cargo_state"] if entry["cargo_state"] != &"" else "on its way", carried])
	return "; ".join(parts) if not parts.is_empty() else "none"


static func _rest_arg() -> ConsoleArg:
	var arg := ConsoleArg.string_optional(&"arg", "")
	arg.rest = true
	return arg


static func _answer(why: String, done: String) -> ConsoleResult:
	return ConsoleResult.failure("traffic: %s" % why) if not why.is_empty() else ConsoleResult.line(done)
