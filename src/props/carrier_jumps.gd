class_name CarrierJumps
extends Node3D
## Fighters coming in behind a jump-capable ship (M6-T23, the maintainer's rule of 2026-11-13): a fighter cannot open a jump point,
## so a mission's or an encounter's raid that says `via: "carrier"` brings a capital stand-in out of its own point first, and the
## fighters come out of that point with it. One carrier brings its whole group (fighters of one side arriving within `SHARE_M` in
## its first `SHARE_S`). Once its fighters are out it jumps back through a point it opens ahead of itself (or stays, by data), and
## leaves play at that point's black ring. One per World (at the identity under it), made on first use.
##
## The carriers are pooled (D22): `prepare` builds them at load, hidden and out of play; a run takes one and gives it back. The
## carrier holds its points (`JumpPointPool`'s rule): destroyed, or out of its hold range, its point collapses and kills the
## fighters still in the funnel. Its engines hold its course; its guns stay silent (no battle steps them). Any ship may also leave
## through a capable ship's open departure point (`send_departure`), as through a gate. Console: provider `carriers`.
##
## M12-T19: a raiders' raid comes behind the strike carrier (`CapitalStandin.STRIKE_CARRIER`) instead of the cruiser stand-in.
## Its fighters come in docked on its cradles and are launched once it is clear of its point, or out of its point beside it, by
## the raid's data (`carrier.arrival`, Q29). It then stands off from the nearest enemy with its stern to it (Q30;
## `CarrierTactics`). Console: command `carrier`.
##
## M8-T08 (D83): a carrier's drive needs its class's recharge after the jump in before it opens its point out (`JumpDrive`);
## one with no cradles holds its course until then. The strike carrier's fighters go home when few of the raid are left, or
## one by one when badly hurt; it flees when it has taken its share of damage, when its raid is over or when every surviving
## fighter has docked: through its own point once the drive has recharged, else it runs for the jumpgate (which needs no
## drive), or with no gate away from the enemy. Once it flees, fighters not docked within their time are left behind (Q27,
## Q30). The
## numbers are data (`data/capitals/capitals.json`, a raid's `carrier` options over them).
##
## The play-test rules of 2026-11-20: it never sits still (a slow weave of its own, seeded), keeps outside a hostile
## station's guns and away from fighter groups, opens the distance from whoever hits it, and on a run for the gate takes the
## way that costs least in time and danger. Cornered (hit, its drive empty) it throws every docked fighter out at once. Its
## fighters stay out of the low-attention tier while they are its own. All decided here at 2 Hz a carrier, in GDScript.

const NODE_NAME: StringName = &"CarrierJumps"
## What a carrier does once its fighters are out.
const THEN_DEPART: StringName = &"depart"
const THEN_STAY: StringName = &"stay"
const THENS: Array[StringName] = [THEN_DEPART, THEN_STAY]
const CARRIER_ACTIONS: Array[StringName] = [&"status", &"launch", &"recall", &"hurt", &"kill", &"charge"]
## A fighter riding in on a cradle, not launched yet: still to come for whoever counts a raid's ships (a mission's triggers).
const RIDING_META: StringName = &"_scs_riding_in"
const DEFAULT_CLASS: StringName = &"cruiser"
## The class each faction's raids come behind when their data names none (M12-T19).
const FACTION_CLASSES: Dictionary = {Factions.RAIDERS: CapitalStandin.STRIKE_CARRIER}
## How often a carrier standing off looks for the nearest enemy and decides, s.
const DECIDE_S: float = 0.5
## Enemies further than this many stand-offs away do not concern it.
const THREAT_REACH: float = 2.0
## Before it opens its point out it flies along its bow no faster than its cruise, within this much, m/s, and turns no
## faster than this, rad/s: the point opens ahead of the bow and must still be there when it arrives.
const LINED_UP_MPS: float = 3.0
const LINED_UP_RAD_S: float = 0.01
## A fighter this close to a run's first, within its first second, comes through the same carrier.
const SHARE_M: float = 2000.0
const SHARE_S: float = 1.0
## Fighters come out of the carrier's point this far from its axis, as a share of the mouth's radius (clear of its hull).
const RING_SHARE: float = 0.6
## The carrier leaves the mouth at its cruise along its nose, m/s, and holds it (a slow fighter still out of its funnel within
## the longest passage, 6 s, leaves it well inside a cruiser's 600 m).
const CARRIER_SPEED_MPS: float = CapitalStandin.CRUISE_MPS
## It starts to leave this long after its last fighter is out, s.
const DEPART_AFTER_S: float = 2.0
## Its departure point's mouth sits this many seconds of its speed ahead of its bow: the point is passable as its bow arrives.
const DEPART_LEAD_S: float = 1.5
## A carrier that has not gone through its departure point this long after starting to leave is taken out anyway, s.
const LEAVE_LIMIT_S: float = 60.0
## A ship watched for a departure point keeps it open this much longer each tick, s.
const DEPARTURE_KEEP_S: float = 1.5

var carriers_used: int = 0
var fighters_brought: int = 0
var carriers_departed: int = 0
## Of those, the ones that left through a jumpgate, their drive still recharging (M8-T08).
var gate_departures: int = 0
var departures_watched: int = 0
## Runs refused because every carrier was out.
var refused: int = 0

## Fighters launched from cradles, aboard when their carrier left and left behind, so far (M12-T19).
var fighters_launched: int = 0
var fighters_recovered: int = 0
var fighters_left_behind: int = 0

var _runs: Array[CarrierRun] = []
var _departures: Array[Dictionary] = []  # {body, point, on_through, z}
var _all: Array[CapitalStandin] = []
var _parked: Array[CapitalStandin] = []
var _pool_names: Dictionary = {}  # each carrier's own name, given back when a raid's name for it ends
var _world: WorldFrame = null


## The carriers of `world`, made on first use.
static func attach(world: Node) -> CarrierJumps:
	if world == null or not is_instance_valid(world):
		return null
	var found := world.get_node_or_null(NodePath(NODE_NAME)) as CarrierJumps
	if found != null:
		return found
	var made := CarrierJumps.new()
	made.name = NODE_NAME
	world.add_child(made)
	return made


func _ready() -> void:
	_world = get_parent() as WorldFrame
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Builds carriers of `cls` (hidden, out of play) until there are `count` of them. Call at load: nothing is made in play (D22).
func prepare(count: int, cls: StringName = DEFAULT_CLASS) -> void:
	if _world == null:
		return
	var have: int = 0
	for cap: CapitalStandin in _all:
		have += 1 if cap.ship_class == cls else 0
	for i: int in range(have, count):
		var cap: CapitalStandin = CapitalStandin.create(cls, Factions.NEUTRAL, "%s CARRIER %d" % [String(cls).to_upper(),
				_all.size() + 1], Vector3.ZERO)
		cap.world = _world
		cap.tier_exempt = true
		_world.spawn(cap, _world.to_universe(global_position), Basis.IDENTITY, self)
		_park(cap)
		_all.append(cap)
		_parked.append(cap)
		_pool_names[cap] = cap.targetable.display_name
		if cap.dock != null:
			cap.dock.launched.connect(_on_launched)
			cap.damageable.damaged.connect(_on_carrier_hit.bind(cap))
			cap.damageable.hits_landed.connect(_on_carrier_beamed.bind(cap))


## The class `faction`'s raids come behind: the strike carrier for the raiders, a cruiser otherwise.
static func class_for(faction: StringName) -> StringName:
	return FACTION_CLASSES.get(faction, DEFAULT_CLASS)


## Makes sure a carrier of `cls` is free, building one when none is (a hitch: for the console and tests, never in play).
func ensure_free(cls: StringName) -> void:
	for cap: CapitalStandin in _parked:
		if is_instance_valid(cap) and cap.ship_class == cls:
			return
	var have: int = 0
	for cap: CapitalStandin in _all:
		have += 1 if cap.ship_class == cls else 0
	prepare(have + 1, cls)


## Carriers built, and free now.
func size() -> int:
	return _all.size()


func free_count() -> int:
	return _parked.size()


## The carrier run a fighter of `faction` coming out at universe `at`, flying along `forward`, comes in with: one started close by
## in the last second, else a new one: a free carrier (of `options.class` when one is free, a cruiser by default) opening a point
## from `pool` at `at` and coming out of it. `options.then` is `depart` (the default) or `stay`; `options.name` is what it is
## called while the raid lasts. Null when it cannot (every carrier out, no point).
func run_for(pool: JumpPointPool, at: UniversePos, forward: Vector3, faction: StringName, options: Dictionary = {}) -> CarrierRun:
	if _world == null or pool == null:
		return null
	var local: Vector3 = _world.universe_to_local(at)
	var now: float = SimClock.now()
	for run: CarrierRun in _runs:
		if run.pool == pool and run.faction == faction and run.state == CarrierRun.State.ARRIVING \
				and now - run.started_s < SHARE_S and run.first_place.distance_to(local) < SHARE_M:
			return run
	var cap: CapitalStandin = _take(StringName(str(options.get("class", class_for(faction)))))
	if cap == null:
		refused += 1
		push_warning("CarrierJumps: no free carrier (%d built); prepare more at load" % _all.size())
		return null
	var ahead: Vector3 = forward.normalized() if forward.length() > 1e-3 else Vector3.FORWARD
	var up: Vector3 = Vector3.UP if absf(ahead.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var velocity: Vector3 = _rest() + ahead * CARRIER_SPEED_MPS
	_unpark(cap, faction, Transform3D(Basis.looking_at(ahead, up), local), velocity)
	if not str(options.get("name", "")).strip_edges().is_empty():
		cap.targetable.display_name = str(options["name"]).strip_edges()
	var point: JumpVortex = pool.open_for(at, ahead, cap.cross_radius_m(), JumpVortex.Direction.ARRIVAL, false, cap)
	if point == null:
		_give_back(cap)
		return null
	carriers_used += 1
	var run := CarrierRun.new()
	run.carrier = cap
	run.pool = pool
	run.arrival = point
	run.faction = faction
	run.then = StringName(str(options.get("then", THEN_DEPART)))
	if not THENS.has(run.then):
		run.then = THEN_DEPART
	run.options = CarrierTactics.options(options, CapitalData.doctrine(faction))
	run.first_place = local
	run.started_s = now
	run.state_at_s = now
	run.weave_seed = hash([String(cap.name), carriers_used])  # its own weave, the same every time this raid is flown
	run.exit_velocity = velocity
	_runs.append(run)
	var transits: VortexTransits = VortexTransits.attach(_world)
	if transits != null:
		transits.begin_arrival(cap, point, cap.global_position, velocity)
	set_physics_process(true)
	return run


## Brings `body` (a fighter just taken from its pool) out of `run`'s point: it is moved to its own place round the point's axis,
## facing the carrier's way, and comes out of the ring there, leaving the mouth at `exit_velocity` (World frame).
func bring_through(run: CarrierRun, body: RigidBody3D, exit_velocity: Vector3) -> void:
	if run == null or body == null or not is_instance_valid(run.arrival):
		return
	# Docked on a cradle when the raid says so and one is free (M12-T19, Q29): it rides the carrier out and is launched after.
	# The carrier's fighters stay out of the low-attention tier while they are its own: parked there they read as lost,
	# and a carrier far from the player called the rest home at once (the maintainer's play-test, 2026-11-20).
	if body is Ship:
		run.tier_was[body] = (body as Ship).tier_exempt
	var dock: CarrierDock = run.carrier.dock if is_instance_valid(run.carrier) else null
	if dock != null and body is Ship and String(run.options["arrival"]) == String(CarrierTactics.ARRIVAL_DOCKED) \
			and dock.dock_now(body as Ship):
		body.set_meta(RIDING_META, true)
		run.arrival.spare(body)
		run.fighters.append(body)
		run.brought += 1
		fighters_brought += 1
		return
	var xform: Transform3D = ride_transform(run.arrival, run.fighters.size(), body)
	var exit_at: Vector3 = xform.origin
	if body is Ship:
		(body as Ship).reset_to(xform)
		(body as Ship).tier_exempt = true
	else:
		body.global_transform = xform
	body.linear_velocity = exit_velocity
	run.fighters.append(body)
	run.brought += 1
	fighters_brought += 1
	var transits: VortexTransits = VortexTransits.attach(_world)
	if transits != null:
		transits.begin_arrival(body, run.arrival, exit_at, exit_velocity)


## Where the `k`-th ship riding another's point comes out of it, World-local: its own spot round the axis, clear of the opener's
## hull, just in front of the mouth, facing the way out.
static func ride_transform(point: JumpVortex, k: int, body: Node) -> Transform3D:
	var frame: Transform3D = point.true_frame()
	var angle: float = float(k) * 2.39996323  # the golden angle: each ship its own spot
	var r: float = RING_SHARE * point.fit.mouth_radius_m
	var damageable: Damageable = Damageable.of(body)
	var ahead_m: float = damageable.bounding_radius if damageable != null and damageable.bounding_radius > 0.0 else 10.0
	return Transform3D(Basis.looking_at(-frame.basis.z, frame.basis.y), frame * Vector3(cos(angle) * r, sin(angle) * r, -ahead_m))


## Watches `body` (any ship) flying in to `point`, a departure point a capable ship holds: once it crosses the mouth it goes on down
## the funnel (`VortexTransits`) and `on_through(body)` runs at the ring. The point is kept open while it comes.
func send_departure(body: RigidBody3D, point: JumpVortex, on_through: Callable) -> void:
	cancel_departure(body)
	if body == null or point == null:
		return
	_departures.append({"body": body, "point": point, "on_through": on_through,
			"z": (point.true_frame().affine_inverse() * body.global_position).z})
	departures_watched += 1
	set_physics_process(true)


## Stops watching `body` for a departure point.
func cancel_departure(body: Node) -> void:
	for i: int in range(_departures.size() - 1, -1, -1):
		if _departures[i]["body"] == body:
			_departures.remove_at(i)


## The open departure points a capable ship holds now (where a ship with no gate in reach can leave).
func held_departures() -> Array[JumpVortex]:
	var out: Array[JumpVortex] = []
	for run: CarrierRun in _runs:
		if run.departure != null and is_instance_valid(run.departure) and run.departure.held \
				and run.departure.open_in_s(JumpVortex.Direction.DEPARTURE) < INF:
			out.append(run.departure)
	return out


## The way into `point` for a departing AI ship, in universe positions: in front of the mouth, its centre, then down the axis.
static func departure_route(point: JumpVortex, world: WorldFrame, cruise_mps: float) -> Route:
	var frame: Transform3D = point.true_frame()
	var route := Route.new()
	route.name = "JUMP POINT DEPARTURE"
	route.pace = Route.PACE_NONE
	route.loop = false
	route.cruise_mps = cruise_mps
	for z: float in [-2.0 * point.fit.mouth_radius_m, 0.0, point.fit.depth_m]:
		route.add(world.to_universe(frame * Vector3(0.0, 0.0, z)))
	return route


func runs() -> Array[CarrierRun]:
	return _runs


## Ends `run`'s raid (its script, the console): a carrier standing off calls its fighters home and flees.
func end_raid(run: CarrierRun) -> void:
	if run != null:
		run.raid_ended = true


## Takes `carrier` out of play now, its docked fighters with it, with no point and no explosion (a mission's skip).
func dismiss(carrier: CapitalStandin) -> void:
	var run: CarrierRun = run_of(carrier)
	if run == null:
		return
	cancel_departure(carrier)
	_finish(run)
	_give_back(carrier)


## The run `carrier` flies now, or null.
func run_of(carrier: Node) -> CarrierRun:
	for run: CarrierRun in _runs:
		if run.carrier == carrier:
			return run
	return null


func _physics_process(delta: float) -> void:
	for i: int in range(_runs.size() - 1, -1, -1):
		if i < _runs.size():
			_step_run(_runs[i], delta)
	_step_departures()
	set_physics_process(not _runs.is_empty() or not _departures.is_empty())


# One tick of one run: the carrier's engines, then waiting for its fighters, holding, and leaving.
func _step_run(run: CarrierRun, delta: float) -> void:
	var cap: CapitalStandin = run.carrier
	if cap == null or not is_instance_valid(cap) or not cap.is_inside_tree() or JumpCapability.is_destroyed(cap):
		_finish(run)  # its pool collapses its points
		_give_back(cap)
		return
	var transits: VortexTransits = VortexTransits.of(_world)
	if transits == null or not transits.is_passing(cap) or run.state == CarrierRun.State.LEAVING:
		cap.step_engines(delta)  # it holds its course (its arrival's passage flies it out)
	var now: float = SimClock.now()
	match run.state:
		CarrierRun.State.ARRIVING:
			if now - run.started_s < SHARE_S or _any_passing(run):
				return
			run.state = CarrierRun.State.HOLDING
			run.state_at_s = now
		CarrierRun.State.HOLDING:
			if cap.dock != null:
				if _launching(run, cap, now):
					return
				if run.then != THEN_STAY:
					run.state = CarrierRun.State.STANDOFF
					run.state_at_s = now
					return
			if run.then == THEN_STAY:
				run.state = CarrierRun.State.STAYING  # it stays in play, drifting on its course, until the scene ends
				_clear_riding(run)
				_runs.erase(run)
				return
			if now - run.state_at_s < DEPART_AFTER_S:
				return
			_close_arrival(run)
			if JumpCapability.drive_ready(cap, now):  # it holds its course until its drive has recharged (M8-T08)
				_leave(run)
		CarrierRun.State.STANDOFF:
			_stand_off(run, cap, now)
		CarrierRun.State.FLEEING:
			if transits != null and transits.is_passing(cap):
				_abandon(run, cap)  # in the gate's funnel: whoever is not aboard stays behind
				return
			_flee_step(run, cap, now)
		CarrierRun.State.LEAVING:
			if now - run.state_at_s > LEAVE_LIMIT_S:
				_gone(run, cap)


# A carrier with cradles, clear of its point (M12-T19): it launches the fighters it brought in docked, whatever it does next.
# True while it still is.
func _launching(run: CarrierRun, cap: CapitalStandin, now: float) -> bool:
	_close_arrival(run)
	if _scramble_if_cornered(run, cap, now):
		return cap.dock.busy_count() > 0  # hit before it could launch: everyone out at once
	if cap.dock.docked_count() > 0 and now - run.state_at_s < DEPART_AFTER_S:
		return true  # a moment clear of the mouth first
	if cap.dock.docked_count() > 0:
		fighters_launched += cap.dock.launch_all()
		return true
	return cap.dock.busy_count() > 0  # the last launches are still leaving their cradles


# One decision of a carrier standing off (Q30, D83; the play-test rules of 2026-11-20), every `DECIDE_S`: it weaves, keeps
# outside a hostile station's guns and away from fighter groups, backs away from the nearest enemy with its stern to it
# (faster from one that hit it), sends a badly hurt fighter home, calls them all home when few are left, and flees when it
# is hurt itself, its raid is over or every survivor has docked. Cornered (under attack, its drive empty) it throws every
# docked fighter out and calls nobody home.
func _stand_off(run: CarrierRun, cap: CapitalStandin, now: float) -> void:
	if now - run.decided_s < DECIDE_S:
		return
	run.decided_s = now
	var cornered: bool = _scramble_if_cornered(run, cap, now)
	var standoff_m: float = float(run.options["standoff_m"])
	var attacked: bool = _under_attack(run, now)
	var threat: Variant = _threat(run, cap, THREAT_REACH * standoff_m, now)
	var to_threat: Vector3 = (threat as Vector3) - cap.global_position if threat != null else Vector3.ZERO
	var away: Vector3 = CarrierTactics.cruise(to_threat, threat != null, standoff_m, CARRIER_SPEED_MPS)
	var heading: Vector3 = CarrierTactics.heading(to_threat, threat != null, standoff_m)
	if attacked and threat != null and to_threat.length() > 1e-3:
		heading = -to_threat.normalized()  # it turns away from whoever hit it and opens the distance
		away = heading * float(run.options["flee_mps"])
	_hold_off(run, cap, away, now)
	if heading != Vector3.ZERO:
		cap.heading = heading
	if not cornered:
		for ship: Ship in _fighting(run):
			var hull: Damageable = Damageable.of(ship)
			if hull != null and CarrierTactics.fighter_goes_home(hull.hull.fraction(), float(run.options["fighter_return_hull"])):
				cap.dock.recall(ship)  # with no free cradle it fights on
		if run.recalled_at_s < 0.0 and CarrierTactics.recall_all(run.brought, _fighting(run).size(), int(run.options["recall_left"])):
			_recall_all(run, cap, now)  # it stands off until they are aboard: their time limit starts when it flees
	var over: bool = CarrierTactics.raid_over(run.raid_ended, now - run.started_s, float(run.options["raid_s"]))
	var why: StringName = CarrierTactics.flee_reason(cap.damageable.hull.fraction(), float(run.options["retreat_hull"]), over,
			run.brought, _fighting(run).size(), cap.dock.returning_count())
	if why == CarrierTactics.STAYS:
		return
	run.flee_reason = why
	run.state = CarrierRun.State.FLEEING
	run.state_at_s = now
	run.decided_s = -INF
	_flee_step(run, cap, now)


# One decision of a fleeing carrier (D83), every `DECIDE_S`: once it is not cornered it calls its fighters home, and those
# not aboard `wait_s` later are left behind; with its drive recharged it waits for them, weaving, then jumps; until then it
# runs for the nearest gate by the least dangerous way, or with no gate from the enemy.
func _flee_step(run: CarrierRun, cap: CapitalStandin, now: float) -> void:
	if now - run.decided_s < DECIDE_S:
		return
	run.decided_s = now
	var cornered: bool = _scramble_if_cornered(run, cap, now)
	if not cornered and run.recalled_at_s < 0.0:
		_recall_all(run, cap, now)
		run.state_at_s = now  # their time to get home starts with the call
	var waited_s: float = now - run.state_at_s
	var wait_s: float = float(run.options["wait_s"])
	if waited_s >= wait_s and not cornered:
		_abandon(run, cap)
	var gate: Jumpgate = _nearest_gate(cap)
	run.move = CarrierTactics.flee_move(JumpCapability.drive_ready(cap, now), gate != null, cap.dock.returning_count(), waited_s,
			wait_s)
	if run.move != CarrierTactics.MOVE_GATE:
		_drop_gate(run, cap)
	var bow: Vector3 = -cap.global_basis.z
	match run.move:
		CarrierTactics.MOVE_WAIT:
			_hold_off(run, cap, Vector3.ZERO, now)  # it waits for its fighters, never sitting still
		CarrierTactics.MOVE_JUMP:
			var along: float = (cap.linear_velocity - _rest()).dot(bow)
			cap.heading = Vector3.ZERO
			cap.cruise_velocity = _rest() + bow * clampf(along, 0.0, CARRIER_SPEED_MPS)
			if (cap.linear_velocity - cap.cruise_velocity).length() < LINED_UP_MPS and cap.angular_velocity.length() < LINED_UP_RAD_S:
				_count_aboard(run, cap)
				_leave(run)
		CarrierTactics.MOVE_GATE:
			var aim: Vector3 = gate.global_transform * CarrierTactics.gate_run_target(gate.local_of(cap.global_position),
					gate.departure_point.z, gate.radius_m)
			var zones: Array = _keep_outs(run, cap)
			var via: Vector3 = CarrierTactics.route_via(cap.global_position, aim, zones[0], zones[1],
					float(run.options["flee_mps"]), float(run.options["danger_weight"]))
			_run_along(run, cap, via - cap.global_position)
			if run.gate != gate:
				_drop_gate(run, cap)
				run.gate = gate
				gate.send_departure(cap, func(_body: Node3D) -> void: _through_gate(run, cap))
		CarrierTactics.MOVE_RUN:
			var threat: Variant = _threat(run, cap, THREAT_REACH * float(run.options["standoff_m"]), now)
			var zones: Array = _keep_outs(run, cap)
			var way: Vector3 = (cap.global_position - (threat as Vector3)).normalized() if threat != null else bow
			_run_along(run, cap, way + CarrierTactics.keep_out(cap.global_position, zones[0], zones[1]))
			cap.cruise_velocity += _weave(run, now)


# The carrier runs along `way` (World) at its fleeing speed, its bow coming round to it.
func _run_along(run: CarrierRun, cap: CapitalStandin, way: Vector3) -> void:
	var dir: Vector3 = way.normalized() if way.length() > 1e-3 else -cap.global_basis.z
	cap.heading = dir
	cap.cruise_velocity = _rest() + dir * float(run.options["flee_mps"])


# The carrier hangs back (the play-test rules of 2026-11-20): `away` (its move off an enemy, zero for none) plus its way out
# of whatever it keeps clear of, plus its weave, so it is never still; its bow follows where it goes.
func _hold_off(run: CarrierRun, cap: CapitalStandin, away: Vector3, now: float) -> void:
	# With fighters coming aboard and nobody to move off, it holds one straight leg of its weave: a steady course to
	# dock on, and still under way. (Weaving and turning under them, they rammed the hull.)
	if cap.dock != null and cap.dock.returning_count() > 0 and away == Vector3.ZERO:
		if run.recovery_course == Vector3.ZERO:
			run.recovery_course = _weave(run, now)
		cap.cruise_velocity = _rest() + run.recovery_course
		cap.heading = Vector3.ZERO
		return
	run.recovery_course = Vector3.ZERO
	var zones: Array = _keep_outs(run, cap)
	var out: Vector3 = CarrierTactics.keep_out(cap.global_position, zones[0], zones[1]) * CARRIER_SPEED_MPS
	var move: Vector3 = (away + out).limit_length(maxf(away.length(), CARRIER_SPEED_MPS)) + _weave(run, now)
	cap.cruise_velocity = _rest() + move
	cap.heading = move.normalized()


func _weave(run: CarrierRun, now: float) -> Vector3:
	return CarrierTactics.weave(run.weave_seed, now - run.started_s, float(run.options["weave_mps"]),
			float(run.options["weave_period_s"]))


# Whether the carrier was hit lately.
func _under_attack(run: CarrierRun, now: float) -> bool:
	return now - run.attacked_at_s < float(run.options["attack_memory_s"])


# A hit on a carrier at work: when, and by whom. Only an enemy's counts (or the console's): one of its own fighters
# scraping the hull on its way home is no attack.
func _on_carrier_hit(info: HitInfo, _applied: float, cap: CapitalStandin) -> void:
	var run: CarrierRun = run_of(cap)
	if run == null or info == null:
		return
	if info.cause != HitInfo.CAUSE_CONSOLE and not Factions.is_hostile(run.faction, info.faction):
		return
	run.attacked_at_s = SimClock.now()
	run.attacker_id = info.shooter_id


# A tick's beam hits on a carrier at work (M10-T75): an attack when an enemy's took points, the attacker the last hit's
# shooter when it is an enemy, else the last enemy to hit it.
func _on_carrier_beamed(summary: HitSummary, cap: CapitalStandin) -> void:
	var run: CarrierRun = run_of(cap)
	if run == null or not (summary.applied > 0.0):
		return
	if summary.cause == HitInfo.CAUSE_BLAST:
		_on_carrier_blasted(summary, run)
		return
	var attacker: int = 0
	var last: int = summary.last_shooter
	if Factions.is_hostile(run.faction, summary.faction_of(last)):
		attacker = last
	else:
		var ids: PackedInt64Array = summary.attackers
		var sides: Array[StringName] = summary.factions
		for k: int in range(ids.size() - 1, -1, -1):
			if Factions.is_hostile(run.faction, sides[k]):
				attacker = ids[k]
				break
	if attacker == 0:
		return
	run.attacked_at_s = SimClock.now()
	run.attacker_id = attacker


# A batch's blast hits on a carrier at work (M10-T76): an attack when an enemy's blast took points, as each hit's `damaged` was,
# the attacker the last enemy blast's shooter (none for a death's).
func _on_carrier_blasted(summary: HitSummary, run: CarrierRun) -> void:
	var ids: PackedInt64Array = summary.attackers
	var sides: Array[StringName] = summary.factions
	for k: int in range(ids.size() - 1, -1, -1):
		if Factions.is_hostile(run.faction, sides[k]):
			run.attacked_at_s = SimClock.now()
			run.attacker_id = ids[k]
			return


# Cornered (under attack with its drive empty), the carrier throws every docked fighter out at once and turns round those
# on their way home: they are its defence. True while it is cornered.
func _scramble_if_cornered(run: CarrierRun, cap: CapitalStandin, now: float) -> bool:
	if cap.dock == null or not CarrierTactics.cornered(_under_attack(run, now), JumpCapability.drive_ready(cap, now)):
		return false
	if cap.dock.returning_count() > 0:
		cap.dock.abandon()
	fighters_launched += cap.dock.scramble()
	run.recalled_at_s = -1.0
	return true


# Where the enemy the carrier moves off is (World), or null: whoever hit it lately, else the nearest within `reach_m`.
func _threat(run: CarrierRun, cap: CapitalStandin, reach_m: float, now: float) -> Variant:
	if run.attacker_id != 0 and _under_attack(run, now):
		var attacker := instance_from_id(run.attacker_id) as Node3D
		if attacker != null and attacker.is_inside_tree() and attacker != cap:
			return TierDirector.flying_position(attacker)
	return _nearest_enemy(cap, run.faction, reach_m)


# What the carrier keeps clear of now, as `[centres, radii]` (World, m): every hostile station's guns and their margin, and
# each group of hostile fighters it sees. Asked once a decision; the fighters come from the shared contact scan.
func _keep_outs(run: CarrierRun, cap: CapitalStandin) -> Array:
	var centres := PackedVector3Array()
	var radii := PackedFloat32Array()
	for node: Node in get_tree().get_nodes_in_group(Station.GROUP):
		var station := node as Station
		if station == null or not station.is_inside_tree() or station.grid == null \
				or not Factions.is_hostile(run.faction, station.grid.faction):
			continue
		centres.append(station.global_position)
		radii.append(station.grid.reach_m() + float(run.options["grid_margin_m"]))
	var keepout_m: float = float(run.options["wing_keepout_m"])
	var span_m: float = float(run.options["wing_span_m"])
	var fighters := PackedVector3Array()
	var scan: ContactScan = ContactScan.shared(get_tree())
	for contact: Contact in scan.contacts_for(cap.get_instance_id(), cap.global_position, run.faction, float(run.options["watch_m"])):
		if contact.relation == Factions.Relation.HOSTILE and contact.kind == BodyKind.SHIP:
			fighters.append(contact.position)
	var first_group: int = centres.size()
	for at: Vector3 in fighters:
		var together: int = 0
		for other: Vector3 in fighters:
			together += 1 if at.distance_to(other) <= span_m else 0
		var known: bool = false
		for i: int in range(first_group, centres.size()):
			known = known or centres[i].distance_to(at) <= 0.5 * keepout_m
		if together >= int(run.options["wing_size"]) and not known:
			centres.append(at)
			radii.append(keepout_m)
	return [centres, radii]


# Every fighter still in the fight is called home (D83); one with no free cradle is left behind at once.
func _recall_all(run: CarrierRun, cap: CapitalStandin, now: float) -> void:
	run.recalled_at_s = now
	for ship: Ship in _fighting(run):
		if not cap.dock.recall(ship):
			_leave_behind(run, ship)


# The fighters still on their way home are let go: they fly on their own again and are the carrier's no longer (Q30).
func _abandon(run: CarrierRun, cap: CapitalStandin) -> void:
	if cap.dock == null or cap.dock.returning_count() == 0:
		return
	for ship: Ship in cap.dock.abandon():
		_leave_behind(run, ship)


func _leave_behind(run: CarrierRun, ship: Ship) -> void:
	ship.tier_exempt = bool(run.tier_was.get(ship, false))
	run.fighters.erase(ship)
	run.left_behind += 1
	fighters_left_behind += 1


# The carrier is leaving: whoever sits on a cradle goes with it.
func _count_aboard(run: CarrierRun, cap: CapitalStandin) -> void:
	_abandon(run, cap)
	run.recovered = cap.dock.docked_count()
	fighters_recovered += run.recovered


# The carrier reached a gate's ring (M8-T08): gone with the fighters aboard, its drive never used.
func _through_gate(run: CarrierRun, cap: CapitalStandin) -> void:
	if run.state != CarrierRun.State.FLEEING:
		return
	_count_aboard(run, cap)
	run.left_via = CarrierRun.VIA_GATE
	run.gate = null
	carriers_departed += 1
	gate_departures += 1
	_finish(run)
	_give_back(cap)


# Stops the gate the carrier ran for from watching it (it jumps instead, or its run is over).
func _drop_gate(run: CarrierRun, cap: CapitalStandin) -> void:
	if run.gate != null and is_instance_valid(run.gate):
		run.gate.cancel_departure(cap)
	run.gate = null


# The gate nearest `cap` in this World, or null.
func _nearest_gate(cap: CapitalStandin) -> Jumpgate:
	var best: Jumpgate = null
	for node: Node in get_tree().get_nodes_in_group(Jumpgate.GROUP):
		var gate := node as Jumpgate
		if gate == null or not gate.is_inside_tree() or gate.vortex == null or not _world.is_ancestor_of(gate):
			continue
		if best == null or cap.global_position.distance_squared_to(gate.global_position) \
				< cap.global_position.distance_squared_to(best.global_position):
			best = gate
	return best


# The arrival point is let go once everything is through: it closes by its timing instead of collapsing when the carrier
# moves off.
func _close_arrival(run: CarrierRun) -> void:
	if is_instance_valid(run.arrival) and run.arrival.opener == run.carrier and run.arrival.held:
		run.arrival.held = false
		run.arrival.close()


# The run's fighters in the fight: flying on their own, not on their way to a cradle.
func _fighting(run: CarrierRun) -> Array[Ship]:
	var out: Array[Ship] = []
	var dock: CarrierDock = run.carrier.dock
	for ship: Ship in _flying(run):
		if dock == null or not dock.is_handling(ship):
			out.append(ship)
	return out


# The run's fighters flying on their own or on their way back: alive, in play, not on a cradle.
func _flying(run: CarrierRun) -> Array[Ship]:
	var out: Array[Ship] = []
	var dock: CarrierDock = run.carrier.dock
	for body: RigidBody3D in run.fighters:
		if body is Ship and is_instance_valid(body) and body.is_inside_tree() and body.is_visible_in_tree() \
				and not JumpCapability.is_destroyed(body) and (dock == null or not dock.is_docked(body as Ship)):
			out.append(body as Ship)
	return out


# Where the nearest ship or capital hostile to `faction` within `reach_m` of `cap` is (World), or null. It asks the pilots'
# shared contact scan, so the search is the native field's, not a walk over every target.
func _nearest_enemy(cap: CapitalStandin, faction: StringName, reach_m: float) -> Variant:
	var best: Variant = null
	var best_d: float = reach_m * reach_m
	var scan: ContactScan = ContactScan.shared(get_tree())
	for contact: Contact in scan.contacts_for(cap.get_instance_id(), cap.global_position, faction, reach_m):
		if contact.relation != Factions.Relation.HOSTILE or (contact.kind != BodyKind.SHIP and contact.kind != BodyKind.CAPITAL):
			continue
		var d: float = contact.position.distance_squared_to(cap.global_position)
		if d < best_d:
			best = contact.position
			best_d = d
	return best


# The carrier lets its arrival point close and opens a departure point ahead of its bow, then flies into it.
func _leave(run: CarrierRun) -> void:
	var cap: CapitalStandin = run.carrier
	_close_arrival(run)
	var fwd: Vector3 = -cap.global_basis.z
	var mouth: Vector3 = cap.global_position + fwd * (cap.length_m() * 0.5 + CARRIER_SPEED_MPS * DEPART_LEAD_S)
	var r: float = maxf(VortexFit.POINT_RADII_PER_SHIP * cap.cross_radius_m(), VortexFit.MIN_POINT_RADIUS_M)
	if not cap.jump_anchor.is_empty():  # a real hull says where it opens its point (M12-T19)
		mouth = cap.global_transform * (cap.jump_anchor["position"] as Vector3)
		r = maxf(r, float(cap.jump_anchor["mouth_radius_m"]))
	cap.cruise_velocity = _rest() + fwd * CARRIER_SPEED_MPS  # under way again, into its point
	cap.heading = Vector3.ZERO
	var up: Vector3 = cap.global_basis.y
	var xform := Transform3D(Basis.looking_at(-fwd, up), mouth)  # its way out faces the carrier: it flies in along +Z
	run.departure = run.pool.open_with(xform, VortexFit.new(r, r * VortexFit.POINT_DEPTH_RATIO), JumpVortex.Direction.DEPARTURE,
			VortexTiming.DEFAULT_HOLD_S, cap)
	run.state = CarrierRun.State.LEAVING
	run.left_via = CarrierRun.VIA_POINT
	run.state_at_s = SimClock.now()
	if run.departure == null:
		_gone(run, cap)
		return
	send_departure(cap, run.departure, func(_body: Node3D) -> void: _gone(run, cap))


# The carrier went through its departure point's ring (or gave up): back to the pool.
func _gone(run: CarrierRun, cap: CapitalStandin) -> void:
	cancel_departure(cap)
	if run.state == CarrierRun.State.LEAVING:
		carriers_departed += 1
	_finish(run)
	_give_back(cap)


func _finish(run: CarrierRun) -> void:
	if is_instance_valid(run.carrier):
		_drop_gate(run, run.carrier)
	_clear_riding(run)
	for body: RigidBody3D in run.fighters:  # those still flying are the tier's again
		if is_instance_valid(body) and body is Ship and body.is_visible_in_tree():
			(body as Ship).tier_exempt = bool(run.tier_was.get(body, false))
	run.state = CarrierRun.State.DONE
	_runs.erase(run)


# A fighter left its cradle: it rides in no longer.
func _on_launched(ship: Ship) -> void:
	if is_instance_valid(ship) and ship.has_meta(RIDING_META):
		ship.remove_meta(RIDING_META)
	for run: CarrierRun in _runs:
		if is_instance_valid(ship) and run.fighters.has(ship):
			ship.tier_exempt = true


# None of the run's fighters is riding in any more (launched, or the run is over).
func _clear_riding(run: CarrierRun) -> void:
	for body: RigidBody3D in run.fighters:
		if is_instance_valid(body) and body.has_meta(RIDING_META):
			body.remove_meta(RIDING_META)


# A free carrier, of `cls` when one is free, else any; null when every one is out.
func _take(cls: StringName) -> CapitalStandin:
	var chosen: CapitalStandin = null
	for cap: CapitalStandin in _parked:
		if is_instance_valid(cap) and (chosen == null or (cap.ship_class == cls and chosen.ship_class != cls)):
			chosen = cap
	if chosen != null:
		_parked.erase(chosen)
	return chosen


# Into play for `faction` at `xform` (World-local), whole, cruising at `velocity`.
func _unpark(cap: CapitalStandin, faction: StringName, xform: Transform3D, velocity: Vector3) -> void:
	ShiftableRegistry.set_out(cap, WorldFrame.PARKED_META, false)
	cap.set_faction(faction)
	cap.damageable.restore()
	cap.process_mode = Node.PROCESS_MODE_INHERIT
	cap.visible = true
	cap.global_transform = xform
	cap.linear_velocity = velocity
	cap.angular_velocity = Vector3.ZERO
	cap.cruise_velocity = velocity
	cap.heading = Vector3.ZERO
	cap.jump_drive.charge()  # the jump in is the one that empties it
	cap.reset_physics_interpolation()
	var destruction: DestructionDirector = DestructionDirector.current()
	if destruction != null:
		destruction.watch_capital(cap)  # its death is drawn and takes it out of play (M4-T23)


# Out of play (hidden, out of Jolt and the rebase) until a run takes it again.
func _park(cap: CapitalStandin) -> void:
	cap.leave_play()
	cap.linear_velocity = Vector3.ZERO
	ShiftableRegistry.set_out(cap, WorldFrame.PARKED_META, true)


func _give_back(cap: CapitalStandin) -> void:
	if cap == null or not is_instance_valid(cap) or _parked.has(cap):
		return
	var transits: VortexTransits = VortexTransits.of(_world)
	if transits != null:
		transits.cancel(cap)
	if cap.dock != null:  # the fighters on its cradles left with it: back to their pool (M12-T19)
		var ships: ShipPool = ShipPool.for_tree(get_tree()) if is_inside_tree() else null
		for ship: Ship in cap.dock.reset():
			if ship.has_meta(RIDING_META):
				ship.remove_meta(RIDING_META)
			var combatant: Combatant = ships.combatant_of(ship) if ships != null else null
			if combatant != null:
				ships.release(combatant)
	if _pool_names.has(cap):
		cap.targetable.display_name = _pool_names[cap]
	_park(cap)
	_parked.append(cap)


# Whether the carrier or any of its fighters is still in its arrival point's funnel.
func _any_passing(run: CarrierRun) -> bool:
	var transits: VortexTransits = VortexTransits.of(_world)
	if transits == null:
		return false
	if transits.is_passing(run.carrier):
		return true
	for body: RigidBody3D in run.fighters:
		if is_instance_valid(body) and transits.is_passing(body):
			return true
	return false


# Hands each watched ship to its point's funnel once it crosses the mouth while the point lets it pass.
func _step_departures() -> void:
	var transits: VortexTransits = VortexTransits.of(_world)
	for i: int in range(_departures.size() - 1, -1, -1):
		var entry: Dictionary = _departures[i]
		var body := entry["body"] as RigidBody3D
		var point := entry["point"] as JumpVortex
		if not is_instance_valid(body) or not body.is_inside_tree() or not is_instance_valid(point) or not point.is_active() \
				or JumpCapability.is_destroyed(body):
			_departures.remove_at(i)
			continue
		var local: Vector3 = point.true_frame().affine_inverse() * body.global_position
		var was_z: float = entry["z"]
		entry["z"] = local.z
		point.extend(DEPARTURE_KEEP_S)
		var inside: bool = point.fit.contains(Vector2(local.x, local.y), 1.1)
		if was_z < 0.0 and local.z >= 0.0 and inside and point.is_passable_for(JumpVortex.Direction.DEPARTURE):
			_departures.remove_at(i)
			var on_through: Callable = entry["on_through"]
			if transits == null or not transits.begin_departure(body, point, on_through):
				on_through.call(body)


func _rest() -> Vector3:
	return _world.rest_velocity() if _world != null and is_instance_valid(_world) else Vector3.ZERO


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"carriers", ConsoleVars.new({
		&"active": {"get": func() -> int: return _runs.size(), "doc": "Carriers bringing fighters in or jumping back now (M6-T23)"},
		&"built": {"get": func() -> int: return _all.size(), "doc": "Carriers built at load (pooled), and free now below"},
		&"free": {"get": func() -> int: return _parked.size(), "doc": "Carriers out of play, ready for a raid"},
		&"used": {"get": func() -> int: return carriers_used, "doc": "Carriers brought in so far"},
		&"fighters": {"get": func() -> int: return fighters_brought, "doc": "Fighters brought through a carrier's point so far"},
		&"departed": {"get": func() -> int: return carriers_departed, "doc": "Carriers gone back through their own point so far"},
		&"state": {"get": func() -> String: return _runs[-1].state_name() if not _runs.is_empty() else "none",
				"doc": "The newest carrier's state: arriving, holding, standoff, fleeing or leaving (none with no carrier at work)"},
		&"flee": {"get": func() -> String: return String(_runs[-1].flee_reason) if not _runs.is_empty() else "",
				"doc": "Why the newest carrier flees: hurt, raid_over or all_docked (empty while it stays; M8-T08)"},
		&"move": {"get": func() -> String: return String(_runs[-1].move) if not _runs.is_empty() else "",
				"doc": "What the newest fleeing carrier does: wait for its fighters, jump, run for the gate, or run from the enemy"},
		&"drive_left_s": {"get": func() -> float: return _drive_left_s(),
				"doc": "Seconds until the newest carrier's jump drive can open a point again (0: ready)"},
		&"gate_departures": {"get": func() -> int: return gate_departures,
				"doc": "Carriers gone through a jumpgate with their drive still recharging, so far"},
		&"docked": {"get": func() -> int: return _dock_count(&"docked_count"),
				"doc": "Fighters sitting on the newest carrier's cradles (M12-T19)"},
		&"returning": {"get": func() -> int: return _dock_count(&"returning_count"),
				"doc": "Fighters called back to the newest carrier and not yet docked"},
		&"launched": {"get": func() -> int: return fighters_launched, "doc": "Fighters launched from cradles so far"},
		&"recovered": {"get": func() -> int: return fighters_recovered, "doc": "Fighters aboard when their carrier left, so far"},
		&"left_behind": {"get": func() -> int: return fighters_left_behind,
				"doc": "Fighters their carrier left without (not docked within its wait), so far"},
		&"hull": {"get": func() -> float: return _runs[-1].carrier.damageable.hull.fraction() if not _runs.is_empty() else 0.0,
				"doc": "The newest carrier's hull, 0..1"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"carrier",
			"The newest raid carrier (M12-T19, M8-T08): `status` (its state, hull, jump drive and why it flees), `launch` its docked fighters, `recall` them (ends its raid: it flees), `hurt` it to just under the hull it flees at, `kill` it, or `charge` its jump drive now",
			[ConsoleArg.enum_optional(&"action", CARRIER_ACTIONS, &"status")]), _cmd_carrier, self)


func _drive_left_s() -> float:
	return JumpCapability.recharge_left_s(_runs[-1].carrier, SimClock.now()) if not _runs.is_empty() else 0.0


func _dock_count(method: StringName) -> int:
	if _runs.is_empty() or not is_instance_valid(_runs[-1].carrier) or _runs[-1].carrier.dock == null:
		return 0
	return int(_runs[-1].carrier.dock.call(method))


func _cmd_carrier(args: Dictionary) -> ConsoleResult:
	if _runs.is_empty():
		return ConsoleResult.failure("no carrier at work (bring one in: `transit carrier point fighter`)")
	var run: CarrierRun = _runs[-1]
	var cap: CapitalStandin = run.carrier
	match StringName(args[&"action"]):
		&"launch":
			if cap.dock == null:
				return ConsoleResult.failure("this carrier has no cradles")
			var n: int = cap.dock.launch_all()
			fighters_launched += n
			return ConsoleResult.line("carrier: launching %d" % n)
		&"recall":
			end_raid(run)
			return ConsoleResult.line("carrier: its raid is over; it calls its fighters home and flees")
		&"hurt":
			var keep: float = maxf(float(run.options["retreat_hull"]) - 0.05, 0.01) * cap.damageable.hull.max_hp
			cap.damageable.apply_hit(HitInfo.new(cap.get_instance_id(), 0, &"", maxf(cap.damageable.hull.hp - keep, 0.0),
					cap.global_position, Vector3.ZERO, 0.0, HitInfo.CAUSE_CONSOLE))
			return ConsoleResult.line("carrier: hull at %.0f %%" % (100.0 * cap.damageable.hull.fraction()))
		&"kill":
			cap.damageable.kill()
			return ConsoleResult.line("carrier: destroyed")
		&"charge":
			cap.jump_drive.charge()
			return ConsoleResult.line("carrier: jump drive charged")
	var dock: CarrierDock = cap.dock
	var left_s: float = JumpCapability.recharge_left_s(cap, SimClock.now())
	var fleeing: String = "" if run.flee_reason == CarrierTactics.STAYS else ", flees (%s%s)" % [run.flee_reason,
			"" if run.move == &"" else ": " + String(run.move)]
	return ConsoleResult.line("carrier: %s, %s%s, hull %.0f %%, drive %s, docked %d, returning %d, cradles free %d" % [
			cap.targetable.display_name, run.state_name(), fleeing, 100.0 * cap.damageable.hull.fraction(),
			"ready" if left_s <= 0.0 else "recharging %.0f s" % left_s, dock.docked_count() if dock != null else 0,
			dock.returning_count() if dock != null else 0, dock.free_count() if dock != null else 0])
