class_name MissionStage
extends RefCounted
## The game side of a mission (architecture §18 D51): what `MissionApi` and the triggers need of `Main`'s nodes. It knows actors
## by name (the player, the scenario's buoys and every pooled ship the pool hands out), refreshes the `MissionWorld` snapshot for
## the names the live triggers watch, spawns from the pools, sends pilots at objectives, and carries out forced triggers.
##
## Name lookups are dictionary reads kept up to date by `ShipPool.acquired`, never scans over every ship, so a tick's cost
## follows the live triggers, not the number of ships (D52).
##
## Pools (D50): every ship a mission spawns comes from a pool its scenario declares. A spawn past a pool's size is a
## `push_error` (tests fail on it), never a new ship; `ShipPool` itself is unchanged.

## How a spawned ship arrives: in place, out of an open jump point (a stand-alone vortex sized for it, `JumpPointPool`, Q12
## revised) or out of the scene's jumpgate (M6-T14: blue vortex, once it is open); either way it comes out of the funnel's black ring
## in a flash, shrunk, and grows to its whole size by the mouth (M6-T22, `VortexTransits`).
const ARRIVALS: Array[StringName] = [&"none", &"jump", &"gate"]
## Which way a `jump` arrival comes (M6-T23, `JumpCapability`): only a jump-capable ship opens its own point (`own`, the
## default); any other comes `via` the gate or behind a carrier (`CarrierJumps`: a capital stand-in opens the point and it comes
## out with it). `arrival: "gate"` is the same as `via: "gate"`.
const VIA_OWN: StringName = &""
const VIA_GATE: StringName = &"gate"
const VIA_CARRIER: StringName = &"carrier"
const VIAS: Array[StringName] = [VIA_OWN, VIA_GATE, VIA_CARRIER]
## A ship that holds its route's end (`hold_route_end`) is sent back once it is further than this from it, m; its way back
## is planned to take about `RETURN_S`, at no less than `RETURN_MIN_MPS`.
const HOLD_END_M: float = 500.0
const RETURN_S: float = 40.0
const RETURN_MIN_MPS: float = 15.0
## Taken so much further off that its way back asks for this many times its planned speed, it is sent again.
const REPLAN_FACTOR: float = 1.5
## A ship sent out through the gate flies its run-in at this speed (the player's autopilot's run-in is 250 m/s).
const DEPART_CRUISE_MPS: float = 200.0
var world: WorldFrame = null
var ships: ShipPool = null
var wings: WingDirector = null
var player: Combatant = null
var jumps: JumpPointPool = null
## The scene's jumpgates (M6-T14); null in a stage without a `Main`.
var gates: JumpgateHost = null
## Plays the mission's cinematics (D55).
var camera_rig: CameraRig = null
## Cobra-bay launches (M7-T08); null in a stage without a `Main`.
var launches: LaunchDirector = null
var system_id: StringName = &"local"
## Mixed into spawned pilots' brain seeds (the scenario's seed: the same seed flies the same mission).
var seed_value: int = 0

## The run's counted numbers (`MissionApi.fact`, M8 D79).
var facts: MissionFacts = null
var _main: Main = null
var _actors: Dictionary = {}  # MissionWorld.key -> Combatant, NavBuoy or a raid's named carrier (CapitalStandin)
var _carrier_fates: Dictionary = {}  # a carrier's key -> true once it left play whole, false once destroyed
var _own_pilots: Dictionary = {}  # an actor's key -> the pilot it flew before `pilot` gave it another
var _routes: Callable = Callable()  # a scenario route by its name (`Main.scenario_route`)
var _holds_end: Dictionary = {}  # an actor's key -> {cruise_mps: its own route's, back: its route back or null} (`hold_route_end`)


## Wires the stage to `main`'s nodes and learns the actors already in play.
func setup(main: Main, p_jumps: JumpPointPool) -> void:
	world = main.world
	ships = main.ships
	wings = main.wings
	player = main.combatant
	jumps = p_jumps
	gates = main.gates
	_routes = main.scenario_route
	camera_rig = main.camera_rig
	launches = main.launches
	system_id = main.world.origin.system_id
	seed_value = main.scenario_seed
	_main = main
	facts = MissionFacts.new()
	facts.setup(main)
	if player != null:
		_actors["player"] = player
	for buoy: NavBuoy in main.buoys:
		_actors[MissionWorld.key(buoy.display_name)] = buoy
	if gates != null:
		for gate: Jumpgate in gates.gates:
			_actors[MissionWorld.key(gate.display_name)] = gate  # a waypoint and a place to fly to (M8 D79)
	for combatant: Combatant in ships.alive():
		register(combatant)
	if not ships.acquired.is_connected(register):
		ships.acquired.connect(register)


## Drops the links into the scene (the runner leaves the tree).
func teardown() -> void:
	if ships != null and is_instance_valid(ships) and ships.acquired.is_connected(register):
		ships.acquired.disconnect(register)
	_actors.clear()
	_carrier_fates.clear()
	_holds_end.clear()
	_own_pilots.clear()
	camera_rig = null
	_main = null


## Knows `combatant` by the name it flies under now, and keeps it out of the low-attention tier: a parked tier body would read
## as gone to the triggers (a civilian 15 km ahead of the player failed the escort).
func register(combatant: Combatant) -> void:
	if combatant != null and not combatant.display_name.is_empty():
		_actors[MissionWorld.key(combatant.display_name)] = combatant
		if combatant.ship != null:
			combatant.ship.tier_exempt = true


## Updates the snapshot for `names` (lower case): position, alive and route. One unit of work each.
func refresh(snapshot: MissionWorld, names: PackedStringArray) -> void:
	if facts != null:
		facts.refresh(snapshot)
		var capitals: int = 0
		for k: String in _actors:
			capitals += 1 if _actors[k] is CapitalStandin and _node_of(k) != null else 0
		snapshot.set_fact(&"capitals_in_play", float(capitals))
	var selected: int = _selected_id()
	for actor: String in names:
		snapshot.work += 1
		var k: String = MissionWorld.key(actor)
		var node: Node3D = _node_of(k)
		snapshot.set_targeted(k, selected != 0 and node != null and target_id(k) == selected)
		if node == null:
			# A name the stage knows was in play once (load, a pool hand-out): gone, not "not arrived yet".
			if _carrier_left(k):
				snapshot.set_left(k)
			elif _actors.has(k):
				snapshot.set_gone(k)
			else:
				snapshot.set_alive(k, false)
			continue
		snapshot.set_actor(k, world.to_universe(node.global_position))
		var combatant := _actors[k] as Combatant
		var path: BehaviourFollowPath = _path_of(combatant)
		if path != null:
			var route: Route = _route_of(combatant)
			if route != null and route.count() > 0:
				snapshot.set_route(k, route.waypoint(route.count() - 1).position, path.phase == BehaviourFollowPath.Phase.DONE)
				if _holds_end.has(k):
					_hold_route_end(k, combatant, route, node, path.phase == BehaviourFollowPath.Phase.DONE)


## A forced trigger moved `actor` to `at`: placed there, velocity and spin kept. A ship goes through `Ship.reset_to`, as D51
## says, so its tank is refilled and its assist starts afresh as well.
func place(actor: String, at: UniversePos) -> void:
	var node: Node3D = _node_of(MissionWorld.key(actor))
	if node == null:
		return
	if node == world.focus:
		world.return_home()  # the player's mission places are measured on the home rail (M7-T71)
	var local: Vector3 = world.universe_to_local(at)
	var ship := node as Ship
	if ship != null:
		var velocity: Vector3 = ship.linear_velocity
		var spin: Vector3 = ship.angular_velocity
		ship.reset_to(Transform3D(ship.global_basis, local))
		ship.linear_velocity = velocity
		ship.angular_velocity = spin
		return
	node.global_position = local
	node.reset_physics_interpolation()


## A forced `destroyed` took `actor` out of play: a pooled ship leaves its wing and goes back to its pool, a buoy is hidden; no
## explosion, no kill credit. The player is never removed this way.
func release(actor: String) -> void:
	var k: String = MissionWorld.key(actor)
	if _node_of(k) == null:
		return
	var thing: Object = _actors[k]
	if thing == player:
		push_warning("Mission: a skip cannot destroy the player")
	elif thing is Combatant:
		var led: Array[Wing] = _leave_wings(thing as Combatant)
		ships.release(thing as Combatant)
		for wing: Wing in led:
			wings.refresh(wing)  # the next member takes the lead from the parked ship
	elif thing is NavBuoy:
		(thing as NavBuoy).set_destroyed(true)
	elif thing is CapitalStandin:
		_carrier_fates[k] = true  # taken out whole: a skip earns no kill
		CarrierJumps.attach(world).dismiss(thing as CapitalStandin)


## From now on the AI ship `ship_name` goes back to the end of the route it leads whenever it has flown it and is no longer
## there (M8-T08: a civilian chased off after arriving idled where the chase ended, kilometres from its goal). False, with
## an error, when there is no such AI ship in play.
func hold_route_end(ship_name: String) -> bool:
	var k: String = MissionWorld.key(ship_name)
	var combatant := _actors.get(k) as Combatant
	if combatant == null or _node_of(k) == null or _path_of(combatant) == null:
		push_error("Mission: hold_route_end: no AI ship '%s' leading a route" % ship_name)
		return false
	var route: Route = _route_of(combatant)
	_holds_end[k] = {"cruise_mps": route.cruise_mps if route != null else Route.DEFAULT_CRUISE_MPS, "back": null}
	return true


## Sends the AI ship `ship_name` on along the scenario's route `route_name` from its first waypoint (M8-T26: the escort's
## civilian flies its last leg only once the last wave has come). One that holds its route's end holds the new one's.
## False, with an error, when there is no such ship or route.
func fly_route(ship_name: String, route_name: String) -> bool:
	var k: String = MissionWorld.key(ship_name)
	var combatant := _actors.get(k) as Combatant
	var pilot := combatant.driver.brain as AiPilot if combatant != null and _node_of(k) != null and combatant.driver != null else null
	var route := _routes.call(route_name) as Route if _routes.is_valid() else null
	if pilot == null or route == null or route.count() == 0:
		push_error("Mission: fly_route: no AI ship '%s' in play or no route '%s' in the scenario" % [ship_name, route_name])
		return false
	BehaviourFollowPath.attach(pilot, route)
	if _holds_end.has(k):
		_holds_end[k] = {"cruise_mps": route.cruise_mps, "back": null}
	return true


# One look at a ship that holds its route's end: once it has flown `route` and is off its end it is sent back, slower the
# nearer it is, so it stops inside `HOLD_END_M` instead of coasting past again; taken much further off on its way back (a
# raid chased it), it is sent again at the speed that distance asks for.
func _hold_route_end(k: String, combatant: Combatant, route: Route, node: Node3D, flown: bool) -> void:
	var hold: Dictionary = _holds_end[k]
	if not flown and route != hold["back"]:
		return  # still on its own route
	var end: UniversePos = route.waypoint(route.count() - 1).position
	var away_m: float = world.to_universe(node.global_position).distance_to(end)
	var cruise_mps: float = clampf(away_m / RETURN_S, RETURN_MIN_MPS, maxf(float(hold["cruise_mps"]), RETURN_MIN_MPS))
	if (flown and away_m <= HOLD_END_M) or (not flown and cruise_mps <= REPLAN_FACTOR * route.cruise_mps):
		return
	var back := Route.new()
	back.name = route.name
	back.pace = Route.PACE_NONE
	back.loop = false
	back.cruise_mps = cruise_mps
	back.add(end)
	hold["back"] = back
	BehaviourFollowPath.attach(combatant.driver.brain as AiPilot, back)


## A forced `arrived` finished `actor`'s route: its follow-path behaviour is told it is at the end.
func finish_route(actor: String) -> void:
	var k: String = MissionWorld.key(actor)
	var combatant := _actors.get(k) as Combatant
	var path: BehaviourFollowPath = _path_of(combatant) if combatant != null else null
	if path != null:
		path.index = maxi(path.waypoint_count() - 1, 0)
		path.phase = BehaviourFollowPath.Phase.DONE


## Takes a ship from its pool for a parsed spawn (`ScenarioLoader.parse_spawn` plus `arrival` and `invulnerable`). Null, with
## an error, when its pool is spent or its brain cannot be built.
func spawn(entry: Dictionary) -> Combatant:
	var type: StringName = entry["type"]
	if ships.free_count(type) == 0:
		push_error("Mission: spawn %s: no free %s (pool of %d, %d in play); declare enough in the scenario's pools" % [
				entry["name"], type, ships.pool_size(type), ships.alive(type).size()])
		return null
	var anchor: UniversePos = _anchor(entry)
	var at: UniversePos = anchor.plus_local(entry["offset"])
	var ship_name: String = String(entry["name"])
	if ship_name.is_empty():
		ship_name = ships.next_name(ShipPool.ALLY_NAME_PREFIX, ShipPool.ALLY_FIRST_NUMBER) if type == ShipPool.ALLY_TYPE \
				else ships.next_name()
	var made: Dictionary = BrainFactory.from_behaviour(entry["behaviour"], anchor, hash([ship_name, seed_value]))
	if not bool(made["ok"]):
		push_error("Mission: spawn %s: %s" % [ship_name, made["error"]])
		return null
	var velocity: Vector3 = entry["velocity"]
	var at_local: Vector3 = world.universe_to_local(at)
	var player_local: Vector3 = player.ship.global_position if player != null else Vector3.ZERO
	# Nose along its drift, or toward the player when it starts at rest (as a wave's raiders).
	var heading: Vector3 = velocity if velocity.length() > 1.0 else player_local - at_local
	var basis: Basis = ScenarioLoader.basis_facing(heading if heading.length() > 1e-3 else Vector3.FORWARD)
	# The data's velocity is against the place; the local frame may be moving off it (M6-T08).
	var placed: Combatant = ships.acquire(ship_name, at, basis, velocity + world.rest_velocity(), made["brain"] as PilotBrain,
			type)
	if placed == null:
		push_error("Mission: spawn %s: the %s pool refused" % [ship_name, type])
		return null
	register(placed)  # before it may dock on its carrier: a mission's ship stays out of the tier after its launch
	if StringName(entry.get("arrival", &"none")) == &"jump" and jumps != null:
		_jump_in(placed, entry, at, basis)
	placed.damageable.invulnerable = bool(entry.get("invulnerable", false))
	if not String(entry.get("wing", "")).is_empty():
		wings.join(String(entry["wing"]), placed)
	return placed


# Brings a ship just placed out of a jump point (M6-T23): behind a carrier when its spawn says `via: "carrier"`, else out of its
# own point, which only a jump-capable ship may open (any other is an error in the mission's data: it stays where it was placed).
func _jump_in(placed: Combatant, entry: Dictionary, at: UniversePos, basis: Basis) -> void:
	var transits: VortexTransits = VortexTransits.attach(world)
	if StringName(entry.get("via", VIA_OWN)) == VIA_CARRIER:
		var carriers: CarrierJumps = CarrierJumps.attach(world)
		var run: CarrierRun = carriers.run_for(jumps, at, -basis.z, placed.faction, entry.get("carrier", {}) as Dictionary) \
				if carriers != null else null
		if run != null:
			carriers.bring_through(run, placed.ship, placed.ship.linear_velocity)
			_register_carrier(run)
		return
	if not JumpCapability.can_open(placed.ship):
		push_error("Mission: spawn %s: a %s cannot open a jump point; say via \"gate\" or via \"carrier\"" % [
				placed.display_name, entry["type"]])
		return
	var point: JumpVortex = jumps.open_for(at, -basis.z, placed.ship.bounding_radius(), JumpVortex.Direction.ARRIVAL, true,
			placed.ship)
	if point != null and transits != null:
		transits.begin_arrival(placed.ship, point, placed.ship.global_position, placed.ship.linear_velocity)


## A spawn that comes out of the gate (`arrival: "gate"`, M6-T14): the blue vortex opens now and the ship is taken from its pool
## once it is fully open, at the gate's arrival point, its `offset` read in the gate's frame (x right, y up) so a group comes out
## side by side, flying out at `Jumpgate.ARRIVAL_SPEED_MPS`. Its anchor and velocity are not used. Returns the name it will fly
## under (it is not in play until it comes through), or "" with an error.
func spawn_through_gate(entry: Dictionary) -> String:
	var gate: Jumpgate = gates.gate() if gates != null else null
	if gate == null:
		push_error("Mission: spawn %s: arrival \"gate\" needs a jumpgate in the scenario's props" % entry["name"])
		return ""
	var type: StringName = entry["type"]
	if ships.free_count(type) == 0:
		push_error("Mission: spawn %s: no free %s (pool of %d, %d in play); declare enough in the scenario's pools" % [
				entry["name"], type, ships.pool_size(type), ships.alive(type).size()])
		return ""
	var ship_name: String = String(entry["name"])
	if ship_name.is_empty():
		ship_name = ships.next_name(ShipPool.ALLY_NAME_PREFIX, ShipPool.ALLY_FIRST_NUMBER) if type == ShipPool.ALLY_TYPE \
				else ships.next_name()
	var made: Dictionary = BrainFactory.from_behaviour(entry["behaviour"], world.to_universe(gate.global_position),
			hash([ship_name, seed_value]))
	if not bool(made["ok"]):
		push_error("Mission: spawn %s: %s" % [ship_name, made["error"]])
		return ""
	var offset: Vector3 = entry["offset"]
	var place: Callable = func() -> void:
		var xform: Transform3D = gate.arrival_transform(offset)
		var placed: Combatant = ships.acquire(ship_name, world.to_universe(xform.origin), xform.basis,
				gate.arrival_velocity() + world.rest_velocity(), made["brain"] as PilotBrain, type)
		if placed == null:
			push_error("Mission: spawn %s: the %s pool refused at the gate" % [ship_name, type])
			return
		placed.damageable.invulnerable = bool(entry.get("invulnerable", false))
		gate.bring_through(placed.ship)
		register(placed)
		if not String(entry.get("wing", "")).is_empty():
			wings.join(String(entry["wing"]), placed)
	gate.request_arrival(place)
	return ship_name


## Sends the AI ship `ship_name` out through the gate (M6-T14): it flies the gate's departure route, the orange vortex opens as
## it nears, and once through it leaves play as a forced `destroyed` does (back to its pool, no explosion, no kill credit). Its
## objective is dropped so it does not turn back to fight. With no gate it leaves through the nearest open departure point a
## jump-capable ship holds (M6-T23: it cannot open its own). False, with an error, when there is no such ship or no way out.
func depart(ship_name: String) -> bool:
	var gate: Jumpgate = gates.gate() if gates != null else null
	var k: String = MissionWorld.key(ship_name)
	var combatant := _actors.get(k) as Combatant
	var point: JumpVortex = _held_departure_near(combatant.ship) if gate == null and combatant != null else null
	if gate == null and point == null:
		push_error("Mission: depart %s: no jumpgate in the scenario's props and no capable ship's departure point open" % ship_name)
		return false
	if combatant == null or _node_of(k) == null or combatant == player:
		push_error("Mission: depart: no AI ship '%s' in play" % ship_name)
		return false
	var pilot := combatant.driver.brain as AiPilot if combatant.driver != null else null
	if pilot == null:
		push_error("Mission: depart: %s flies no AI pilot" % ship_name)
		return false
	pilot.context.objective_name = ""
	if gate == null:
		BehaviourFollowPath.attach(pilot, CarrierJumps.departure_route(point, world, DEPART_CRUISE_MPS))
		CarrierJumps.attach(world).send_departure(combatant.ship, point, func(_ship: Node3D) -> void: release(ship_name))
		return true
	BehaviourFollowPath.attach(pilot, gate.departure_route(world, DEPART_CRUISE_MPS))
	gate.send_departure(combatant.ship, func(_ship: Node3D) -> void: release(ship_name))
	return true


# The open departure point nearest `ship` that a jump-capable ship holds, or null.
func _held_departure_near(ship: Node3D) -> JumpVortex:
	var carriers: CarrierJumps = CarrierJumps.attach(world) if world != null else null
	if carriers == null or ship == null:
		return null
	var best: JumpVortex = null
	for point: JumpVortex in carriers.held_departures():
		if best == null or ship.global_position.distance_to(point.global_position) \
				< ship.global_position.distance_to(best.global_position):
			best = point
	return best


## Sets the pilot objective of the AI ship `ship_name` (D39): `target_name` ("none" or "" clears it). False, with an error, when
## there is no such AI ship in play.
func send(ship_name: String, target_name: String) -> bool:
	var k: String = MissionWorld.key(ship_name)
	var combatant := _actors.get(k) as Combatant
	if combatant == null or _node_of(k) == null:
		push_error("Mission: send: no ship '%s' in play" % ship_name)
		return false
	var pilot := combatant.driver.brain as AiPilot if combatant.driver != null else null
	if pilot == null:
		push_error("Mission: send: %s flies no AI pilot, so it takes no objective" % ship_name)
		return false
	var target: String = target_name.strip_edges()
	pilot.context.objective_name = "" if target.to_lower() == "none" else target
	return true


## Starts the player's launch from wing `wing`'s door `door`, wingmen on the arm's other racks (M7-T08); "" or why not.
func launch_from(wing: String, door: int) -> String:
	if launches == null or not is_instance_valid(launches):
		return "no launch director in this scene"
	return launches.launch_player(wing, door)


## Sends `count` raiders at the station, its wings scrambled when `scramble` (M7-T10); "" or why not.
func raid_station(count: int, scramble: bool) -> String:
	var traffic: StationTraffic = launches.main.traffic if launches != null and is_instance_valid(launches) and launches.main != null else null
	if traffic == null:
		return "no station traffic in this scene"
	return traffic.raid(count, scramble)


## The player is still on its rack or rail.
func launching() -> bool:
	return launches != null and is_instance_valid(launches) and launches.locks_controls()


## Starts the squadron-launch cinematic from wing `wing`'s arm, the player last from door `door` (M8-T03; empty and 0 for the
## data's); "" or why not.
func launch_squadron(wing: String = "", door: int = 0, flights: int = 0) -> String:
	if launches == null or not is_instance_valid(launches):
		return "no launch director in this scene"
	return launches.launch_squadron(wing, door, flights)


## Plays the station tour's stop `stop` ("" for the whole tour, M7-T12), with or without its caption; "" or why not.
func tour(stop: String, captions: bool = true) -> String:
	if _main == null or _main.tours == null:
		return "no tour in this scene"
	_main.tours.captions = captions
	return _main.tours.start(stop)


func touring() -> bool:
	return _main != null and _main.tours != null and _main.tours.playing


func stop_tour() -> void:
	if touring():
		_main.tours.stop()


## Keeps the station's run of civilians going between the gate and the bays, or lets it run out (M7-T56); "" or why not.
func traffic(on: bool) -> String:
	if _main == null or _main.traffic == null or not _main.traffic.lanes_ready():
		return "no station traffic in this scene"
	_main.traffic.auto_forced = true
	_main.traffic.auto = on
	return ""


## Launches `count` more Starfuries of the station's wing `wing` from its Cobra arm (the places not flown, at most); "" or why not.
func scramble(wing: String, count: int) -> String:
	if _main == null or _main.traffic == null:
		return "no station traffic in this scene"
	return _main.traffic.scramble(wing, count)


## Sends the AI ship `ship_name` along `points` (metres from the scenario's origin) at `cruise_mps`, waiting for the player when
## `paced`; a point may name a demo to show there (`Manoeuvres.NAMES`). "" or why not.
func fly(ship_name: String, points: Array, cruise_mps: float, paced: bool, demo: StringName = &"") -> String:
	var k: String = MissionWorld.key(ship_name)
	var combatant := _actors.get(k) as Combatant
	var pilot := combatant.driver.brain as AiPilot if combatant != null and combatant.driver != null and _node_of(k) != null else null
	if pilot == null:
		return "no AI ship %s in play" % ship_name
	var route := Route.new()
	route.name = ship_name
	route.cruise_mps = cruise_mps
	route.loop = false
	route.pace = Route.PACE_PLAYER if paced else Route.PACE_NONE
	if paced and player != null and player.targetable != null:
		route.pace_id = player.targetable.get_instance_id()
	for i: int in points.size():
		var p: Vector3 = points[i]
		route.add(UniversePos.new(p.x, p.y, p.z, system_id), demo if i == points.size() - 1 else &"")
	if route.count() == 0:
		route.add(world.to_universe(combatant.ship.global_position), demo)  # where it is: the demo starts at once
	BehaviourFollowPath.attach(pilot, route)
	return ""


## The place `ahead_m` out of the scene's jumpgate along the way its arrivals fly, or null with no gate.
func gate_point(ahead_m: float) -> UniversePos:
	var gate: Jumpgate = gates.gate() if gates != null else null
	if gate == null:
		return null
	return world.to_universe(gate.global_position + (gate.global_basis * gate.arrival_forward).normalized() * ahead_m)


## Gives the AI ship `ship_name` a pilot of `profile` (`AiProfile.PATHS`), or with "" its own pilot back (M8-T33: the
## tutorial's instructor flies as a fighting wingman for a drill, then instructs again). "" or why not.
func pilot(ship_name: String, profile: String) -> String:
	var k: String = MissionWorld.key(ship_name)
	var combatant := _actors.get(k) as Combatant
	if combatant == null or combatant.driver == null or _node_of(k) == null:
		return "no AI ship %s in play" % ship_name
	if profile.is_empty():
		if _own_pilots.has(k):
			combatant.driver.brain = _own_pilots[k]
			_own_pilots.erase(k)
		return ""
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": profile},
			world.to_universe(combatant.ship.global_position), hash([ship_name, seed_value, profile, _own_pilots.size()]))
	if not bool(made["ok"]):
		return String(made["error"])
	if not _own_pilots.has(k):
		_own_pilots[k] = combatant.driver.brain
	combatant.driver.brain = made["brain"]
	return ""


## Puts the AI ship `ship_name` in the player's flight (a free slot of it), or takes it out again; "" or why not.
func join_flight(ship_name: String, join: bool) -> String:
	var k: String = MissionWorld.key(ship_name)
	var combatant := _actors.get(k) as Combatant
	var flight: Wing = wings.player_wing() if wings != null else null
	if combatant == null or _node_of(k) == null:
		return "no ship %s in play" % ship_name
	if flight == null:
		return "the player leads no flight"
	if not join:
		wings.remove_member(flight, combatant)
		wings.refresh(flight)
		return ""
	if flight.slot_of(combatant) > 0:
		return ""
	return "" if wings.join(flight.name, combatant) == flight else "%s could not join %s" % [ship_name, flight.name]


## Puts the ship `ship_name` at `at`, nose along `facing`, at rest against the station's frame: a cut between scenes, for use
## as a cinematic ends or with the controls held (M8-T33: the tutorial's lessons start at rest in clear space). A shot still
## filming the player is ended, since it would follow the ship across the cut. "" or why not.
func put(ship_name: String, at: UniversePos, facing: Vector3) -> String:
	var k: String = MissionWorld.key(ship_name)
	var ship := _node_of(k) as Ship
	if ship == null:
		return "no ship %s in play" % ship_name
	if ship == world.focus:
		world.return_home()
		if camera_rig != null and camera_rig.playing_shot() != null:
			camera_rig.stop_shot()
		if launches != null and is_instance_valid(launches):
			launches.skip()  # a launch's burn would carry the ship on from where it is put
	var up: Vector3 = Vector3.UP if absf(facing.normalized().dot(Vector3.UP)) < 0.99 else Vector3.BACK
	ship.reset_to(Transform3D(Basis.looking_at(facing, up), world.universe_to_local(at)))
	return ""


## Selects the actor `actor` as the player's target (a skipped `targeted` trigger).
func select(actor: String) -> void:
	if player != null and player.ship != null and player.ship.targeting != null and _node_of(MissionWorld.key(actor)) != null:
		player.ship.targeting.select_by_name(actor.to_upper())


## The name of the player's selected target, "" for none.
func player_target() -> String:
	var targeting: TargetingController = player.ship.targeting if player != null and player.ship != null else null
	return targeting.selected_name() if targeting != null and _selected_id() != 0 else ""


func _selected_id() -> int:
	var targeting: TargetingController = player.ship.targeting if player != null and player.ship != null \
			and is_instance_valid(player.ship) else null
	return targeting.selected_id() if targeting != null else 0


## Control's docking offer is the mission's to say: the HUD line stays off (M8-T06).
func own_dock_offer() -> void:
	if _main != null and _main.docking != null:
		_main.docking.offer_line = false


## Jumps the player's launch to the hand-off (a skipped step).
func skip_launch() -> void:
	if launches != null and is_instance_valid(launches):
		launches.skip()


## Plays `shot` on the camera rig (D55): its actors are found by name every frame, its origin points from the scenario's origin.
func play_cinematic(shot: CinematicShot) -> void:
	if camera_rig != null and is_instance_valid(camera_rig):
		camera_rig.play_shot(shot, actor_pose, origin_to_local)


## `shot` is still on screen.
func cinematic_playing(shot: CinematicShot) -> bool:
	return camera_rig != null and is_instance_valid(camera_rig) and camera_rig.playing_shot() == shot


## Cuts `shot` if it is still on screen.
func stop_cinematic(shot: CinematicShot) -> void:
	if cinematic_playing(shot):
		camera_rig.stop_shot()


## The pose the renderer draws `actor` at this frame, World-local, or null when it is not in play (a shot's actor points).
func actor_pose(actor: String) -> Variant:
	var node: Node3D = _node_of(MissionWorld.key(actor))
	return node.get_global_transform_interpolated() if node != null else null


## The World-local position of a point `offset` metres (64-bit) from the scenario's origin (a shot's origin points).
func origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], system_id))


## The World-local position of the actor `actor` this frame, or null when it is not in play (the HUD's waypoint).
func local_position(actor: String) -> Variant:
	var node: Node3D = _node_of(MissionWorld.key(actor))
	return node.global_position if node != null else null


## The ship `actor`'s hull, 0..1, for the HUD's bar (M7-T54); 0 once it is lost or out of play.
func hull_fraction(actor: String) -> float:
	var k: String = MissionWorld.key(actor)
	var c := _actors.get(k) as Combatant
	if c == null or _node_of(k) == null:
		return 0.0
	return c.damageable.hull.fraction()


## The `Targetable` id of the actor `actor` (its radar contact), or 0 when it is not in play or has no marker (M5-T25).
func target_id(actor: String) -> int:
	var node: Node3D = _node_of(MissionWorld.key(actor))
	var marker := node.get_node_or_null(^"Targetable") as Targetable if node != null else null
	return marker.get_instance_id() if marker != null else 0


# A raid's carrier is an actor under the name its raid gives it (M8-T08), so an objective can ask for it destroyed.
func _register_carrier(run: CarrierRun) -> void:
	var cap: CapitalStandin = run.carrier
	var k: String = MissionWorld.key(cap.targetable.display_name) if is_instance_valid(cap) else ""
	if k.is_empty() or str(run.options.get("name", "")).is_empty() or _actors.get(k) == cap:
		return
	_actors[k] = cap
	_carrier_fates.erase(k)


# Whether the carrier `k` left play whole (it jumped out, or went through a gate) instead of being destroyed. Its fate is
# kept from the first look: its pool restores a destroyed hull for a later raid.
func _carrier_left(k: String) -> bool:
	var cap := _actors.get(k) as CapitalStandin
	if cap == null or not is_instance_valid(cap):
		return false
	if not _carrier_fates.has(k):
		_carrier_fates[k] = not cap.damageable.hull.destroyed
	return bool(_carrier_fates[k])


# The node of a live actor (the ship's body or the buoy), or null when it is unknown, parked, destroyed or flying another name.
# A fighter riding in on its carrier's cradle is live, though it is out of play until its launch (M8-T08).
func _node_of(k: String) -> Node3D:
	var thing: Object = _actors.get(k)
	if thing == null or not is_instance_valid(thing):
		return null
	if thing is CapitalStandin:
		var cap := thing as CapitalStandin
		var in_play: bool = cap.is_inside_tree() and cap.visible and cap.process_mode != Node.PROCESS_MODE_DISABLED \
				and not cap.damageable.hull.destroyed and MissionWorld.key(cap.targetable.display_name) == k
		return cap if in_play and not _carrier_fates.has(k) else null
	if thing is Combatant:
		var c := thing as Combatant
		var hidden: bool = not c.ship.visible or c.ship.process_mode == Node.PROCESS_MODE_DISABLED if c.ship != null else true
		if c.ship == null or not c.ship.is_inside_tree() or c.damageable.hull.destroyed \
				or (hidden and not c.ship.has_meta(CarrierJumps.RIDING_META)):
			return null
		if c != player and MissionWorld.key(c.targetable.display_name) != k:
			return null  # the pool gave this ship to someone else
		return c.ship
	if thing is Jumpgate:
		return thing as Jumpgate
	if thing is NavBuoy:
		var buoy := thing as NavBuoy
		return buoy if buoy.is_inside_tree() and buoy.visible and not buoy.is_destroyed() else null
	return null


# Takes a ship out of every wing slot it holds (not marked lost: it was not shot down) and returns the wings it led.
func _leave_wings(combatant: Combatant) -> Array[Wing]:
	var led: Array[Wing] = []
	if wings == null:
		return led
	for wing: Wing in wings.wings:
		if wing.slot_of(combatant) >= 1:
			wings.remove_member(wing, combatant)
		if wing.leader == combatant:
			led.append(wing)
	return led


func _path_of(combatant: Combatant) -> BehaviourFollowPath:
	if combatant == null or combatant.driver == null:
		return null
	var pilot := combatant.driver.brain as AiPilot
	return pilot.behaviour(&"follow_path") as BehaviourFollowPath if pilot != null else null


func _route_of(combatant: Combatant) -> Route:
	var pilot := combatant.driver.brain as AiPilot if combatant != null and combatant.driver != null else null
	return pilot.context.route if pilot != null else null


func _anchor(entry: Dictionary) -> UniversePos:
	if StringName(entry["anchor"]) == &"player" and player != null and player.ship.is_inside_tree():
		return world.to_universe(player.ship.global_position)
	return UniversePos.new(0.0, 0.0, 0.0, system_id)
