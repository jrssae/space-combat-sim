class_name StationTraffic
extends Node
## Traffic at the station (M7-T10, AC9, Q8 as refined): civilians into and out of the main docking bay, freighters at the
## cargo bay, raids sent at the station and its defenders scrambled from the Cobra bays. Main's child; every ship is a
## pooled ship flown by the native brains on a `Route` (a `DockingPlan` lane near the station), so this node only starts
## things and looks at its own few ships once a tick.
##
## - **Docking**: a hull that fits the mouth flies the lane in, matching the drum's turn; the inner doors open ahead of it, it
##   flies through into the black void behind them, they shut, and it goes back to its pool (it left the world; M7-T25).
##   **Undocking** is the same backwards: it waits in the void, the doors open, it comes out turning with the drum and they shut.
## - **Freighter cycle**: any of the five Saturns flies to the cargo bay's lane, turns short of the hold point, backs in (stern and
##   pods to the bay), waits while the station's cargo pods carry its cargo blocks or tanks into the bay one by one (or, loading,
##   out of the bay onto it; `FreighterCargo`, M7-T30, M7-T34), and leaves nose first when they are done.
## - **Raid**: raiders with the station as their objective (they aim at the grid's mounts, native), and the wings named in
##   the data scrambled against them.
## - Arrivals come out of the scene's jumpgate when it has one, and departures leave through it; without one they start
##   and end a few kilometres out.
## - **The run** (M7-T56) while free-flight encounters are on with a pools file that asks for it (`station_run`;
##   `data/station/traffic.json`): `lane_ships` civilians on their way between the gate and the station at all times, the run
##   filled when traffic starts and one more started whenever one has docked or left (arriving through the gate, or undocking), each a hash of the session seed and its index. The encounters'
##   traffic events join the run as arriving convoys (`lane_event`), and their raids on the station scramble the wings.
##
## Console: command and provider `traffic`.

const NODE_NAME: StringName = &"StationTraffic"
const DATA_PATH: String = "res://data/station/traffic.json"
const PROVIDER: StringName = &"traffic"
const ACTIONS: Array[StringName] = [&"status", &"dock", &"undock", &"freighter", &"raid", &"scramble", &"auto", &"clear"]
## What the run's own starts may be (raids at the station come with the encounters).
const KINDS: Array[StringName] = [&"dock", &"undock", &"freighter"]
const CIVILIAN_AI: Dictionary = {"type": "ai", "profile": "civilian"}
const RAIDER_AI: Dictionary = {"type": "ai", "profile": "raider", "orders": "attack"}
const TRANSIT_CRUISE_MPS: float = 120.0
## Without a gate: how far beyond a lane's first point a ship starts, and how far out a leaving ship is let go, metres.
const START_OUT_M: float = 2500.0
const LEAVE_OUT_M: float = 12000.0
## The run's ends kept clear when ships are put on it (the gate's vortex, the station's lanes), metres.
const RUN_END_M: float = 3000.0
## Arrivals keep this far to one side of the run's line and departures to the other, so they never meet head on (metres).
const RUN_SIDE_M: float = 600.0
## An arrival from the gate's side slows into a point this far out on its lane's axis before it takes the lane, so it comes
## onto the lane straight and slow (M7-T56: at 120 m/s across the axis it overshot and rammed the drum beside the mouth).
const ENTRY_OUT_M: float = 3000.0
const ENTRY_HOLD_S: float = 1.0
## Arrivals for the docking bay queue at their own points along its axis, this far apart, and take the lane one at a time.
const QUEUE_SPACING_M: float = 700.0
## Arrivals turn off, and departures turn in, this far out from the gate on their own side.
const GATE_CLEAR_M: float = 3000.0
## An encounter's convoy joins the run this far from the station, pushed toward the gate until it is past the player's radar.
const JOIN_RUN_M: Vector2 = Vector2(22000.0, 40000.0)
const JOIN_CLEAR_OF_PLAYER_M: float = 26000.0
const JOIN_STEP_M: float = 2000.0
const CONVOY_SPACING_M: float = 800.0
## Share of the run's arrivals that are a Saturn for the cargo bay, when no freighter is there or on its way.
const FREIGHTER_SHARE: float = 0.5
## Without a gate a raid starts this far off the bow, above it (station frame).
const RAID_FROM: Vector3 = Vector3(0.0, 2500.0, -11000.0)
const RAID_SPEED_MPS: float = 120.0
const RAID_SPREAD_M: float = 150.0
const DEFAULT_RAID: int = 6
## The most raiders one raid sends (the console's clamp); the pool is built for this many.
const MAX_RAID: int = 12
## A scrambled wing at or above this share of a full wing is still out and takes the next raid; below it the next wing goes.
const WING_FIT_SHARE: float = 0.5
## An undocking ship waits in the void behind the inner doors at most this long for them to open, seconds.
const UNDOCK_WAIT_S: float = 600.0
## `traffic freighter show`: the Saturn starts this far short of the hold point backing in at this speed (m, m/s), and the player
## watches from toward the bay, on the left (the side whose pods come off first) and above, looking a little toward the bay
## from the hold point (m).
const SHOW_BACK_M: float = 300.0
const SHOW_BACK_MPS: float = 8.0
const VIEW_TOWARD_M: float = 190.0
const VIEW_SIDE_M: float = -85.0
const VIEW_UP_M: float = 35.0
const VIEW_LOOK_M: float = 20.0

signal docked(ship_name: String)
signal undocked(ship_name: String)
signal freighter_unloading(ship_name: String)
signal freighter_loading(ship_name: String)
signal freighter_left(ship_name: String)

var main: Main = null
var plan: DockingPlan = null
## Whether the run keeps itself going (set when encounters are on; the console's `traffic auto on|off` overrides).
var auto: bool = false
var auto_forced: bool = false
## Civilians the run keeps on their way at once, and the least time between two of its own starts.
var lane_ships: int = 5
var lane_spacing_s: float = 40.0
var weights: Dictionary = {}
var scramble_wings: PackedStringArray = PackedStringArray()
var elapsed_s: float = 0.0
var events: int = 0
var docked_count: int = 0
var undocked_count: int = 0
var freighters_done: int = 0
## Freighters' cargo blocks the cargo pods carried into the cargo bay, and onto freighters.
var pods_in: int = 0
var pods_out: int = 0
var raids: int = 0
## Milliseconds the load spent building the ships the raids and wings need (`reserve_pools`).
var reserved_ms: float = 0.0
var last_event: String = "none"
# One entry a ship: {combatant, brain, kind, state, cargo, loading, cargo_state} (the last three for freighters).
var _own: Array[Dictionary] = []
var _spawned: int = 0
var _seeded: bool = false
var _last_flow_s: float = -INF
# The run's arrivals asked of the gate and not out of its vortex yet.
var _pending_flow: int = 0
# Every arrival asked of the gate (the run's and the console's) and not out of its vortex yet, for `status` and the replies.
var _pending_gate: int = 0


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


## Arrivals asked of the gate that wait for its vortex to open (a few seconds).
func waiting_for_gate() -> int:
	return _pending_gate


## The traffic's ships in play, and those of one kind.
func alive_count() -> int:
	return _own.size()


func alive_of(kind: StringName) -> int:
	var n: int = 0
	for entry: Dictionary in _own:
		n += 1 if entry["kind"] == kind else 0
	return n


## Of them, ships inside the station now (M7-T62: in the docking bay's black void, unavailable to everyone outside).
func inside_count() -> int:
	var n: int = 0
	for entry: Dictionary in _own:
		var c: Combatant = entry["combatant"]
		n += 1 if is_instance_valid(c.ship) and c.ship.inside_station else 0
	return n


## Of them, ships an encounter's traffic event sent onto the run: they count against the encounters' cap.
func encounter_count() -> int:
	var n: int = 0
	for entry: Dictionary in _own:
		n += 1 if bool(entry.get("encounter", false)) else 0
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
func dock(type: StringName = &"", near: bool = false, extra: Dictionary = {}) -> String:
	var why: String = _ready_plan()
	if not why.is_empty():
		return why
	var hull: StringName = _tunnel_type(type)
	if hull == &"":
		return "%s does not fit the docking tunnel (%s do)" % [type, ", ".join(DockingPlan.TUNNEL_TYPES)]
	return _arrive(hull, &"dock", plan.dock_in, near, extra)


## A civilian comes out of the main docking bay and leaves. Returns "" or why not.
func undock(type: StringName = &"", extra: Dictionary = {}) -> String:
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
	# Lying square in the black void behind the inner doors as the drum has turned it, waiting there until they open (M7-T25).
	var basis: Basis = Basis.looking_at(xform.basis * out_dir, s.drum_body.global_basis.y)
	var wait: Array[Dictionary] = [{"at": airlock, "hold_s": UNDOCK_WAIT_S, "face": Vector3.ZERO, "spin": plan.spin}]
	var route: Route = DockingPlan.route_of(wait, xform, main.world, DockingPlan.DOCK_CRUISE_MPS, "UNDOCKING")
	var c: Combatant = _take(hull, route, xform * airlock, basis, main.world.rest_velocity(), &"undock", &"airlock", extra)
	if c == null:
		return "no %s is free in the ship pool" % hull
	c.ship.angular_velocity = xform.basis * plan.spin  # it comes out turning with the drum
	_shelter(_own[_own.size() - 1])  # inside the station from its first tick
	_ask_doors(_own[_own.size() - 1])
	return ""


## A Saturn of `type` (any of `DockingPlan.FREIGHTER_TYPES`; "" picks one) flies the cargo bay's cycle, unloading or `loading`.
## `start`: "" out of the gate (or far out), `near` on the lane's first point, `hold` already holding at the bay, `show` backing in
## its last `SHOW_BACK_M` with the cargo pods already on their way and the player put beside the lane to watch. Returns "" or why not.
func freighter(type: StringName = &"", loading: bool = false, start: StringName = &"", extra: Dictionary = {}) -> String:
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
	var more: Dictionary = extra.duplicate()
	more["loading"] = loading
	return _arrive(hull, &"freighter", plan.freighter, start == &"near", more)


## Puts the player beside the freighters' lane, toward the bay from the hold point, looking at a held Saturn's cargo: the cargo pods come
## past on their way out and back. "" or why not.
func view_cargo_bay() -> String:
	var s: Station = station()
	if s == null or not main.player_alive:
		return "no player to move"
	main.world.return_home()  # the station's rail first (M7-T71)
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
	count = clampi(count, 1, MAX_RAID)
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
		scramble_for_raid()
	return ""


## Builds, at load, the ships the station's raids and wings take from the pools, so none is built in the middle of a fight: the
## largest raid's raiders, and a full wing for each wing the data scrambles (on top of the allies already in play). Nothing
## in a scenario without the station (a scenario asks for it: `station.reserve_traffic`), nor for a pool whose size the caller fixed (`Main.raider_pool_size`, `ally_pool_size`).
func reserve_pools() -> void:
	if station() == null:
		return
	var t0: int = Time.get_ticks_usec()
	# A pool size asked for outright (the benchmark's layouts, tests of a dry pool) is the whole answer.
	if main.raider_pool_size < 0:
		_ensure_free(ShipPool.DEFAULT_TYPE, MAX_RAID)
	if main.ally_pool_size < 0:
		_ensure_free(ShipPool.ALLY_TYPE, LaunchDirector.WING_SIZE * maxi(scramble_wings.size(), 1))
	reserved_ms = float(Time.get_ticks_usec() - t0) / 1000.0


## Ships of `type` that `reserve_pools` keeps for the station's raids and wings: none without the station, nor for a pool size
## the caller fixed. The encounters build their own on top (M7-T56).
func reserved_count(type: StringName) -> int:
	if station() == null:
		return 0
	if type == ShipPool.DEFAULT_TYPE and main.raider_pool_size < 0:
		return MAX_RAID
	if type == ShipPool.ALLY_TYPE and main.ally_pool_size < 0:
		return LaunchDirector.WING_SIZE * maxi(scramble_wings.size(), 1)
	return 0


## Whether the station and its lanes are there for traffic.
func lanes_ready() -> bool:
	return _ready_plan().is_empty()


## The traffic's ships in play, in the order they started; with `flow_only`, the run's own (those still to come out of the
## gate are not in play yet).
func ships(flow_only: bool = false) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for entry: Dictionary in _own:
		if not flow_only or bool(entry.get("flow", false)):
			out.append(entry["combatant"])
	return out


## The traffic state of `c` (`transit`, `lane`, `airlock`, `leave`; &"" for a ship that is not traffic's).
func state_of(c: Combatant) -> StringName:
	for entry: Dictionary in _own:
		if entry["combatant"] == c:
			return entry["state"]
	return &""


## The run's own civilians on their way, and those asked of the gate.
func flow_count() -> int:
	var n: int = _pending_flow
	for entry: Dictionary in _own:
		n += 1 if bool(entry.get("flow", false)) else 0
	return n


## Starts an encounter's traffic event on the run: its ships come in one behind the other toward the station, joining the run
## past the player's radar where it can. A Saturn goes to the cargo bay when no freighter is there or on its way; every other hull,
## and any Saturn after that, flies to the docking bay in a hull that fits its tunnel. Whether any ship started.
func lane_event(e: EncounterEvent, seed_value: int) -> bool:
	if not lanes_ready() or _gate() == null:
		return false
	var along: float = _join_along(hash([seed_value, "traffic join", e.index]))
	var step: float = CONVOY_SPACING_M / maxf(_run_length(plan.dock_in), 1.0)
	var freighter_taken: bool = alive_of(&"freighter") > 0
	var placed: int = 0
	for k: int in e.count():
		var type: StringName = e.types[k]
		if DockingPlan.FREIGHTER_TYPES.has(type) and not freighter_taken:
			freighter_taken = true
			type = _free_hull(DockingPlan.FREIGHTER_TYPES, DockingPlan.FREIGHTER_TYPES.find(type))
		else:
			type = _free_hull(DockingPlan.TUNNEL_TYPES, DockingPlan.TUNNEL_TYPES.find(type) if DockingPlan.TUNNEL_TYPES.has(type) else e.index + k)
		if _join_inbound(type, along + step * float(k), {"loading": _unit("load", e.index * 4 + k) < 0.5, "encounter": true}) != null:
			placed += 1
	return placed > 0


## Sends the defenders against a new raid (maintainer, 2026-11-15): a scrambled wing that is still out (launching, or at least
## half strong) takes the raid at will and nothing launches; the next wing in the data's order goes only when the ones before it
## are gone or weaker than half. When every wing has flown and is spent, the first is refilled to full. Returns "" or why not.
func scramble_for_raid() -> String:
	if main.launches == null or scramble_wings.is_empty():
		return ""
	var launches: LaunchDirector = main.launches
	var floor_strength: int = ceili(float(LaunchDirector.WING_SIZE) * WING_FIT_SHARE)
	for wing: String in scramble_wings:
		if launches.is_launching(wing) or launches.wing_strength(wing) >= floor_strength:
			_engage_at_will(wing)
			return ""
		if not launches.has_flown(wing):
			return scramble(wing)
	var first: String = scramble_wings[0]
	return scramble(first, LaunchDirector.WING_SIZE - launches.wing_strength(first))


## The station's wing `wing` launches from its Cobra arm (T08's sequence: two waves of six). Returns "" or why not.
func scramble(wing: String, count: int = LaunchDirector.WING_SIZE) -> String:
	if main.launches == null:
		return "no launch director"
	return main.launches.launch_wing(wing, count)


# A wing already out engages the raid at will (a wing the player leads keeps its own order).
func _engage_at_will(wing_name: String) -> void:
	if main.wings == null:
		return
	for flight: Wing in main.wings.flights_of(wing_name):  # the station's wings fly as flights of three (M8-T19)
		if not (flight.leader != null and flight.leader.is_player):
			flight.order = AiContext.Order.ENGAGE_AT_WILL


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
		auto = director != null and director.on and director.station_run and director.kind_on(&"traffic") and station() != null
	if auto:
		elapsed_s += delta
		_keep_flow()
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
		var transit: Route = _transit_route(lane, true)
		var flow: bool = bool(extra.get("flow", false))
		_pending_flow += 1 if flow else 0
		_pending_gate += 1
		last_event = "%s waiting for the gate" % kind
		gate.request_arrival(func() -> void:
			_pending_flow -= 1 if flow else 0
			_pending_gate -= 1
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


# The way in from the gate's side, kept to its legs: out of the gate onto the arrivals' side when `from_gate`, then slowing into
# the entry point on `lane`'s axis, where the lane takes over.
func _transit_route(lane: Array[Dictionary], from_gate: bool) -> Route:
	var xform: Transform3D = station().global_transform
	var out_m: float = ENTRY_OUT_M + QUEUE_SPACING_M * float(_queue_slot() if lane == plan.dock_in else 0)
	var inward: Vector3 = ((lane[1]["at"] as Vector3) - (lane[0]["at"] as Vector3)).normalized()
	var transit := Route.new()
	transit.name = "TO THE STATION"
	transit.pace = Route.PACE_NONE
	transit.lane = true
	transit.cruise_mps = TRANSIT_CRUISE_MPS
	var gate: Jumpgate = _gate()
	if from_gate and gate != null:
		transit.add_lane(main.world.to_universe(_gate_side(gate, 1.0)))
	transit.add_lane(main.world.to_universe(xform * ((lane[0]["at"] as Vector3) - inward * out_m)), ENTRY_HOLD_S)
	return transit


# The way out through the gate, turning in from the departures' side.
func _departure_route(gate: Jumpgate) -> Route:
	var through: Route = gate.departure_route(main.world, TRANSIT_CRUISE_MPS)
	var route := Route.new()
	route.name = through.name
	route.pace = Route.PACE_NONE
	route.cruise_mps = TRANSIT_CRUISE_MPS
	route.add(main.world.to_universe(_gate_side(gate, -1.0)))
	for i: int in through.count():
		route.add(through.waypoint(i).position)
	return route


# A point `GATE_CLEAR_M` from the gate toward the station, on the arrivals' (`side` 1) or the departures' (-1) side of the run.
func _gate_side(gate: Jumpgate, side: float) -> Vector3:
	var toward: Vector3 = (station().global_position - gate.global_position).normalized()
	return gate.global_position + toward * GATE_CLEAR_M + _run_side() * side


# The arrivals' offset from the run's line (the departures take its opposite).
func _run_side() -> Vector3:
	var along: Vector3 = (_gate().global_position - station().global_position).normalized()
	var side: Vector3 = along.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = along.cross(Vector3.RIGHT)
	return side.normalized() * RUN_SIDE_M


# --- the run ----------------------------------------------------------------------------------------------------


# Keeps `lane_ships` of the run's civilians on their way: the run filled once when traffic starts, then one more whenever one has
# docked or left, never two within `lane_spacing_s`.
func _keep_flow() -> void:
	if not lanes_ready():
		return
	if not _seeded:
		_seeded = true
		_seed_run()
	if flow_count() < lane_ships and elapsed_s - _last_flow_s >= lane_spacing_s:
		_start_auto()


# The run as the player finds it: civilians already on their way, spread from the station to the gate, arriving and leaving by
# turns, so the traffic is there from the start.
func _seed_run() -> void:
	if _gate() == null:
		return
	for k: int in lane_ships:
		var along: float = (float(k) + 0.25 + 0.5 * _unit("seed", k)) / float(maxi(lane_ships, 1))
		if k % 2 == 0:
			_join_inbound(_arrival_hull(k), along, {"flow": true, "loading": _unit("load", k) < 0.5})
		else:
			_join_outbound(_free_hull(ShipCatalog.CIVILIAN_TYPES, hash([main.scenario_seed, "traffic out", k])), along, {"flow": true})
	_last_flow_s = elapsed_s


# A point of the run from `lane`'s first point to the gate, `along` 0 at the station's end and 1 at the gate's, its ends kept clear,
# on the arrivals' (`side` 1) or the departures' (-1) side.
func _run_point(lane: Array[Dictionary], along: float, side: float) -> Vector3:
	var a: Vector3 = station().global_transform * (lane[0]["at"] as Vector3)
	var b: Vector3 = _gate().global_position
	var length: float = a.distance_to(b)
	var d: float = lerpf(minf(RUN_END_M, length * 0.5), maxf(length - RUN_END_M, length * 0.5), clampf(along, 0.0, 1.0))
	return a + (b - a).normalized() * d + _run_side() * side


func _run_length(lane: Array[Dictionary]) -> float:
	return (station().global_transform * (lane[0]["at"] as Vector3)).distance_to(_gate().global_position)


# Where on the run (0..1) a convoy joins: `JOIN_RUN_M` from the station by its draw, moved toward the gate until it is past the
# player's radar or the run ends.
func _join_along(draw: int) -> float:
	var length: float = maxf(_run_length(plan.dock_in), 1.0)
	var d: float = lerpf(JOIN_RUN_M.x, JOIN_RUN_M.y, float(draw) / 4294967296.0)
	while d < length - RUN_END_M and _run_point(plan.dock_in, d / length, 1.0).distance_to(main.ship.global_position) < JOIN_CLEAR_OF_PLAYER_M:
		d += JOIN_STEP_M
	return clampf(d / length, 0.0, 1.0)


# A ship of `type` already on the run at `along`, flying in to its lane: a Saturn to the cargo bay, any other hull to the docking bay.
func _join_inbound(type: StringName, along: float, extra: Dictionary) -> Combatant:
	var freighter_hull: bool = DockingPlan.FREIGHTER_TYPES.has(type)
	var lane: Array[Dictionary] = plan.freighter if freighter_hull else plan.dock_in
	var transit: Route = _transit_route(lane, false)
	var at: Vector3 = _run_point(lane, along, 1.0)
	var heading: Vector3 = (main.world.universe_to_local(transit.waypoint(0).position) - at).normalized()
	return _take(type, transit, at, Basis.looking_at(heading, Vector3.UP),
			main.world.rest_velocity() + heading * TRANSIT_CRUISE_MPS, &"freighter" if freighter_hull else &"dock", &"transit", extra)


# A ship of `type` already on the run at `along`, on its way out through the gate.
func _join_outbound(type: StringName, along: float, extra: Dictionary) -> Combatant:
	var gate: Jumpgate = _gate()
	var route: Route = _departure_route(gate)
	var at: Vector3 = _run_point(plan.dock_in, along, -1.0)
	var heading: Vector3 = (main.world.universe_to_local(route.waypoint(0).position) - at).normalized()
	var c: Combatant = _take(type, route, at, Basis.looking_at(heading, Vector3.UP),
			main.world.rest_velocity() + heading * TRANSIT_CRUISE_MPS, &"undock", &"leave", extra)
	if c != null:
		_watch_departure(_own[_own.size() - 1], gate)
	return c


# The run's next arrival: a Saturn for the cargo bay by its share while none is there or on its way, else a hull for the tunnel.
func _arrival_hull(index: int) -> StringName:
	if alive_of(&"freighter") == 0 and _pending_flow == 0 and _unit("freighter", index) < FREIGHTER_SHARE:
		return _free_hull(DockingPlan.FREIGHTER_TYPES, hash([main.scenario_seed, "traffic freighter", index]))
	return _free_hull(DockingPlan.TUNNEL_TYPES, hash([main.scenario_seed, "traffic hull", index]))


# The first of `types` from `start` on with a ship free in its pool (so a start never builds one mid-flight); `start`'s own when none is.
func _free_hull(types: Array[StringName], start: int) -> StringName:
	var first: int = absi(start) % types.size()
	for step: int in types.size():
		var type: StringName = types[(first + step) % types.size()]
		if main.ships.free_count(type) > 0:
			return type
	return types[first]


## Whether one of the traffic's ships has the docking bay (its lane, tunnel or void): a fighter docking for repair waits (M8-T06).
func bay_busy() -> bool:
	for entry: Dictionary in _own:
		if (entry["kind"] == &"dock" and entry["state"] == &"lane") \
				or (entry["kind"] == &"undock" and (entry["state"] == &"airlock" or entry["state"] == &"lane")):
			return true
	return false


# Whether a ship is on the docking bay's lane, in its tunnel or its void (docking or undocking): the bay takes one at a time.
# A fighter docking for repair counts (M8-T06).
func _bay_busy() -> bool:
	return bay_busy() or (main != null and main.docking != null and main.docking.holds_bay())


# The next free waiting place for an arrival bound for the docking bay: one past every docking ship still on its way in.
func _queue_slot() -> int:
	var n: int = 0
	for entry: Dictionary in _own:
		n += 1 if entry["kind"] == &"dock" and entry["state"] == &"transit" else 0
	return n


# 0..1 from the session seed, what is drawn and its index.
func _unit(what: String, index: int) -> float:
	return float(hash([main.scenario_seed, "traffic " + what, index])) / 4294967296.0


# Grows `type`'s pool until `count` of it are free (a hitch when it builds: `reserve_pools` does it at load).
func _ensure_free(type: StringName, count: int) -> void:
	main.ensure_free(type, count)


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


# One more of the run's civilians: arriving through the gate (to the docking bay, or a Saturn to the cargo bay) or undocking.
func _start_auto() -> void:
	var index: int = events
	events += 1
	_last_flow_s = elapsed_s
	var kind: StringName = _draw_kind(index)
	if kind == &"freighter" and (alive_of(&"freighter") > 0 or _pending_flow > 0):
		kind = &"dock"  # one freighter at the cargo bay at a time
	if kind == &"undock" and _bay_busy():
		kind = &"dock"
	var flow: Dictionary = {"flow": true}
	var why: String = ""
	match kind:
		&"dock":
			why = dock(_free_hull(DockingPlan.TUNNEL_TYPES, hash([main.scenario_seed, "traffic hull", index])), false, flow)
		&"undock":
			why = undock(_free_hull(DockingPlan.TUNNEL_TYPES, hash([main.scenario_seed, "traffic hull", index])), flow)
		&"freighter":
			var hull: StringName = _free_hull(DockingPlan.FREIGHTER_TYPES, hash([main.scenario_seed, "traffic freighter", index]))
			why = freighter(hull, _unit("load", index) < 0.5, &"", flow)
	last_event = "%s (auto)%s" % [kind, "" if why.is_empty() else ": " + why]


func _draw_kind(index: int) -> StringName:
	var total: float = 0.0
	for kind: StringName in KINDS:
		total += maxf(float(weights.get(kind, 0.0)), 0.0)
	var pick: float = _unit("kind", index) * total
	for kind: StringName in KINDS:
		var w: float = maxf(float(weights.get(kind, 0.0)), 0.0)
		if pick < w:
			return kind
		pick -= w
	return KINDS[0]


# --- following --------------------------------------------------------------------------------------------------


# One of the traffic's ships this tick: a transit that reached the lane takes the lane, a freighter at the hold point
# has its cargo carried and leaves when the cargo pods are done, a ship at its lane's end docks or leaves, and one that left is let go.
func _step(i: int) -> void:
	var entry: Dictionary = _own[i]
	if not _still_ours(entry):
		_drop_pods(entry)
		_let_doors_go(entry)
		_own.remove_at(i)
		return
	var c: Combatant = entry["combatant"]
	var kind: StringName = entry["kind"]
	if kind == &"raid":
		return
	if kind == &"dock" or kind == &"undock":
		_shelter(entry)
	var path := (entry["brain"] as AiPilot).behaviour(&"follow_path") as BehaviourFollowPath
	var done: bool = path != null and path.phase == BehaviourFollowPath.Phase.DONE
	match entry["state"]:
		&"transit":
			if done and not (kind == &"dock" and _bay_busy()):  # a docking ship waits its turn at its entry point
				BehaviourFollowPath.attach(entry["brain"] as AiPilot, _lane_route(kind, plan.freighter if kind == &"freighter" else plan.dock_in))
				entry["state"] = &"lane"
		&"airlock":  # an undocking ship waits in the void until the inner doors stand open
			var lock: StationAirlock = _airlock()
			if lock == null or lock.doors.is_open():
				BehaviourFollowPath.attach(entry["brain"] as AiPilot, DockingPlan.route_of(plan.dock_out, station().global_transform,
						main.world, DockingPlan.DOCK_CRUISE_MPS, "UNDOCKING"))
				entry["state"] = &"lane"
		&"lane":
			if kind == &"dock":
				_dock_step(i, entry, path, done)
				return
			if kind == &"undock":
				_undock_step(entry)
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


# The cargo pods come for a freighter's cargo now it holds at the bay (or, `early`, while it backs in: they wait for it to stop); with
# no cargo pods (or no plan) it just goes on.
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


# The cargo pods are done: the freighter leaves its hold point now, out along its lane.
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
		BehaviourFollowPath.attach(brain as AiPilot, _departure_route(gate))
		_watch_departure(entry, gate)
		return
	var route := Route.new()
	route.name = "LEAVING"
	route.pace = Route.PACE_NONE
	route.cruise_mps = TRANSIT_CRUISE_MPS
	var heading: Vector3 = -c.ship.global_basis.z
	route.add(main.world.to_universe(c.ship.global_position + heading * LEAVE_OUT_M))
	BehaviourFollowPath.attach(brain as AiPilot, route)


# The gate lets the entry's ship go once it has flown through its departure vortex.
func _watch_departure(entry: Dictionary, gate: Jumpgate) -> void:
	var c: Combatant = entry["combatant"]
	var brain: PilotBrain = entry["brain"]
	gate.send_departure(c.ship, func(_ship: Node3D) -> void:
		for k: int in _own.size():
			if _own[k]["combatant"] == c and _own[k]["brain"] == brain:
				_finish(k)
				return)


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


# The main docking bay (M7-T25): a docking ship asks the inner doors open on its way in and lets go once it lies wholly past their
# plane, in the black void; once they have shut it has docked and leaves the world.
func _dock_step(i: int, entry: Dictionary, path: BehaviourFollowPath, done: bool) -> void:
	if not bool(entry.get("inner", false)) and path != null and path.index > DockingPlan.DOCK_INNER_FROM:
		# Past the approach's far point: the rest of the lane slower, to stop in the void.
		entry["inner"] = true
		BehaviourFollowPath.attach(entry["brain"] as AiPilot, DockingPlan.route_of(plan.dock_in.slice(DockingPlan.DOCK_INNER_FROM + 1),
				station().global_transform, main.world, DockingPlan.DOCK_INNER_MPS, "DOCKING"))
	var lock: StationAirlock = _airlock()
	if lock == null:
		if done:
			_docked(i)
		return
	if bool(entry.get("through", false)):
		if lock.doors.is_shut():
			_docked(i)
		return
	var depth: float = _depth(entry, lock)
	var reach: Vector2 = entry["reach"]
	if depth + reach.x > -lock.ask_ahead_m:
		_ask_doors(entry)
	if depth - reach.y > lock.clear_m:  # its tail is past the doors' plane
		entry["through"] = true
		_let_doors_go(entry)


# An undocking ship lets the doors go once it lies wholly ahead of their plane.
func _undock_step(entry: Dictionary) -> void:
	var lock: StationAirlock = _airlock()
	if lock == null or not lock.doors.has_ask(entry.get("airlock_key", 0)):
		return
	if _depth(entry, lock) + (entry["reach"] as Vector2).y < -lock.clear_m:
		_let_doors_go(entry)


# A ship is inside the station while its origin is in the docking bay's black void (M7-T62): unavailable to everyone outside.
func _shelter(entry: Dictionary) -> void:
	var lock: StationAirlock = _airlock()
	var c: Combatant = entry["combatant"]
	c.ship.inside_station = lock != null and lock.holds(station().global_transform.affine_inverse() * c.ship.global_position)


func _docked(i: int) -> void:
	docked_count += 1
	docked.emit((_own[i]["combatant"] as Combatant).display_name)
	_release(i)


func _airlock() -> StationAirlock:
	var s: Station = station()
	return s.airlock if s != null else null


# How far the ship's origin lies past the doors' plane, into the bay; caches its hull's reach along its nose.
func _depth(entry: Dictionary, lock: StationAirlock) -> float:
	var c: Combatant = entry["combatant"]
	if not entry.has("reach"):
		entry["reach"] = StationAirlock.hull_reach(c.ship)
	return lock.depth_of(station().global_transform.affine_inverse() * c.ship.global_position)


func _ask_doors(entry: Dictionary) -> void:
	var lock: StationAirlock = _airlock()
	if lock == null:
		return
	var c: Combatant = entry["combatant"]
	if not entry.has("reach"):
		entry["reach"] = StationAirlock.hull_reach(c.ship)
	entry["airlock_key"] = c.ship.get_instance_id()
	lock.doors.ask(entry["airlock_key"])


func _let_doors_go(entry: Dictionary) -> void:
	var lock: StationAirlock = _airlock()
	if lock != null and entry.has("airlock_key"):
		lock.doors.release(entry["airlock_key"])


func _release(i: int) -> void:
	var entry: Dictionary = _own[i]
	var c: Combatant = entry["combatant"]
	_own.remove_at(i)
	_drop_pods(entry)
	_let_doors_go(entry)
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
	lane_ships = maxi(int(data.get("lane_ships", lane_ships)), 0)
	lane_spacing_s = maxf(float(data.get("lane_spacing_s", lane_spacing_s)), 1.0)
	var raw_weights: Variant = data.get("weights", {})
	if raw_weights is Dictionary:
		for kind: StringName in KINDS:
			weights[kind] = float((raw_weights as Dictionary).get(String(kind), 0.0))
	var wings: Variant = data.get("scramble", [])
	if wings is Array:
		for wing: Variant in wings:
			scramble_wings.append(str(wing))


# --- console ----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	registry.register_provider(PROVIDER, ConsoleVars.new({
		&"auto": {"get": func() -> bool: return auto, "doc": "Whether the run between the gate and the station keeps itself going (free-flight encounters on, or traffic auto on)"},
		&"lane_ships": {"get": func() -> int: return lane_ships, "doc": "Civilians the run keeps on their way between the gate and the station at once"},
		&"lane_spacing_s": {"get": func() -> float: return lane_spacing_s, "unit": "s", "doc": "Least time between two of the run's own starts"},
		&"flow": {"get": flow_count, "doc": "The run's own civilians on their way now (with those still to come out of the gate)"},
		&"alive": {"get": alive_count, "doc": "Traffic ships in play"},
		&"docking": {"get": func() -> int: return alive_of(&"dock"), "doc": "Of them, flying into the main docking bay"},
		&"undocking": {"get": func() -> int: return alive_of(&"undock"), "doc": "Of them, leaving the main docking bay"},
		&"inside": {"get": inside_count, "doc": "Of them, inside the station: in the docking bay's black void, off the radar and out of every target list and shot (M7-T62)"},
		&"freighters": {"get": func() -> int: return alive_of(&"freighter"), "doc": "Of them, freighters at the cargo bay"},
		&"raiders": {"get": func() -> int: return alive_of(&"raid"), "doc": "Of them, raiders sent at the station"},
		&"docked": {"get": func() -> int: return docked_count, "doc": "Ships that docked: flew into the void behind the inner doors, which shut behind them"},
		&"undocked": {"get": func() -> int: return undocked_count, "doc": "Ships that came out of the bay and left"},
		&"freighters_done": {"get": func() -> int: return freighters_done, "doc": "Freighter cycles finished"},
		&"pods_in": {"get": func() -> int: return pods_in, "doc": "Freighters' cargo blocks the cargo pods carried into the cargo bay"},
		&"pods_out": {"get": func() -> int: return pods_out, "doc": "Freighters' cargo blocks the cargo pods carried onto freighters"},
		&"cargo": {"get": _cargo_text, "doc": "Each freighter at the cargo bay: its hull, unloading or loading, and pods carried"},
		&"raids": {"get": func() -> int: return raids, "doc": "Raids sent at the station"},
		&"reserved_ms": {"get": func() -> float: return reserved_ms, "doc": "Milliseconds the load spent building the raids' and wings' ships"},
		&"last_event": {"get": func() -> String: return last_event, "doc": "The last thing the traffic started"},
	}), self)
	registry.register_command(ConsoleCommand.new(&"traffic",
			"Station traffic: status, dock [near] (a civilian into the main docking bay), undock (one out of it), freighter [type] [near|hold|show] [load] (a Saturn's cargo cycle: the station's cargo pods carry its cargo blocks or tanks into the cargo bay, or with load onto it; near starts it on the lane, hold already at the bay, show backing in its last 300 m with the cargo pods on their way and you beside the lane to watch; type is one of %s, default each in turn), raid [n] (raiders at the station; a scrambled wing still out takes it, else the next wing launches), scramble <wing>, auto <on|off>, clear" % ", ".join(DockingPlan.FREIGHTER_TYPES),
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"status"), _rest_arg()] as Array[ConsoleArg]),
			_cmd_traffic, self)


func _cmd_traffic(args: Dictionary) -> ConsoleResult:
	var arg: String = str(args.get(&"arg", "")).to_lower()
	var why: String = ""
	match StringName(args[&"action"]):
		&"dock":
			why = dock(&"", arg == "near")
			return _answer(why, "a civilian is on its way into the main docking bay%s" % _gate_wait_note())
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
			return _answer(why, "%d raiders sent at the station%s" % [clampi(n, 1, MAX_RAID),
					"" if scramble_wings.is_empty() else "; defenders: %s" % ", ".join(scramble_wings)])
		&"scramble":
			why = scramble(arg) if not arg.is_empty() else "traffic scramble <%s>" % "|".join(LaunchDirector.WINGS)
			return _answer(why, "wing %s is launching" % arg)
		&"auto":
			if arg != "on" and arg != "off":
				return ConsoleResult.failure("traffic auto <on|off>")
			auto_forced = true
			auto = arg == "on"
			return ConsoleResult.line("traffic by itself %s (%d civilians on the run between the gate and the station)" % [arg, lane_ships])
		&"clear":
			return ConsoleResult.line("returned %d traffic ship(s) to their pools" % clear())
	return ConsoleResult.line("traffic: %d in play%s (%d docking, %d undocking, %d inside, %d freighters, %d raiders); docked %d, undocked %d, freighter cycles %d, pods in %d, pods out %d, raids %d; auto %s; cargo: %s; last: %s" % [
			alive_count(), "" if _pending_gate == 0 else " + %d waiting for the gate to open" % _pending_gate, alive_of(&"dock"), alive_of(&"undock"), inside_count(), alive_of(&"freighter"), alive_of(&"raid"), docked_count,
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


# Tells that a start is held until the gate's vortex is open, which takes a few seconds.
func _gate_wait_note() -> String:
	return "" if _pending_gate == 0 else " (it comes out of the gate once the vortex has opened, a few seconds; `traffic status` counts it then)"


static func _rest_arg() -> ConsoleArg:
	var arg := ConsoleArg.string_optional(&"arg", "")
	arg.rest = true
	return arg


static func _answer(why: String, done: String) -> ConsoleResult:
	return ConsoleResult.failure("traffic: %s" % why) if not why.is_empty() else ConsoleResult.line(done)
