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

const NODE_NAME: StringName = &"CarrierJumps"
## What a carrier does once its fighters are out.
const THEN_DEPART: StringName = &"depart"
const THEN_STAY: StringName = &"stay"
const THENS: Array[StringName] = [THEN_DEPART, THEN_STAY]
const DEFAULT_CLASS: StringName = &"cruiser"
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
var departures_watched: int = 0
## Runs refused because every carrier was out.
var refused: int = 0

var _runs: Array[CarrierRun] = []
var _departures: Array[Dictionary] = []  # {body, point, on_through, z}
var _all: Array[CapitalStandin] = []
var _parked: Array[CapitalStandin] = []
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


## Carriers built, and free now.
func size() -> int:
	return _all.size()


func free_count() -> int:
	return _parked.size()


## The carrier run a fighter of `faction` coming out at universe `at`, flying along `forward`, comes in with: one started close by
## in the last second, else a new one: a free carrier (of `options.class` when one is free, a cruiser by default) opening a point
## from `pool` at `at` and coming out of it. `options.then` is `depart` (the default) or `stay`. Null when it cannot (every carrier
## out, no point).
func run_for(pool: JumpPointPool, at: UniversePos, forward: Vector3, faction: StringName, options: Dictionary = {}) -> CarrierRun:
	if _world == null or pool == null:
		return null
	var local: Vector3 = _world.universe_to_local(at)
	var now: float = SimClock.now()
	for run: CarrierRun in _runs:
		if run.pool == pool and run.faction == faction and run.state == CarrierRun.State.ARRIVING \
				and now - run.started_s < SHARE_S and run.first_place.distance_to(local) < SHARE_M:
			return run
	var cap: CapitalStandin = _take(StringName(str(options.get("class", DEFAULT_CLASS))))
	if cap == null:
		refused += 1
		push_warning("CarrierJumps: no free carrier (%d built); prepare more at load" % _all.size())
		return null
	var ahead: Vector3 = forward.normalized() if forward.length() > 1e-3 else Vector3.FORWARD
	var up: Vector3 = Vector3.UP if absf(ahead.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	var velocity: Vector3 = _rest() + ahead * CARRIER_SPEED_MPS
	_unpark(cap, faction, Transform3D(Basis.looking_at(ahead, up), local), velocity)
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
	run.first_place = local
	run.started_s = now
	run.state_at_s = now
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
	var xform: Transform3D = ride_transform(run.arrival, run.fighters.size(), body)
	var exit_at: Vector3 = xform.origin
	if body is Ship:
		(body as Ship).reset_to(xform)
	else:
		body.global_transform = xform
	body.linear_velocity = exit_velocity
	run.fighters.append(body)
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
			if run.then == THEN_STAY:
				run.state = CarrierRun.State.STAYING  # it stays in play, drifting on its course, until the scene ends
				_runs.erase(run)
				return
			if now - run.state_at_s >= DEPART_AFTER_S:
				_leave(run)
		CarrierRun.State.LEAVING:
			if now - run.state_at_s > LEAVE_LIMIT_S:
				_gone(run, cap)


# The carrier lets its arrival point close and opens a departure point ahead of its bow, then flies into it.
func _leave(run: CarrierRun) -> void:
	var cap: CapitalStandin = run.carrier
	if is_instance_valid(run.arrival) and run.arrival.opener == cap:
		run.arrival.held = false  # nothing more comes through: it closes by its timing
		run.arrival.close()
	var fwd: Vector3 = -cap.global_basis.z
	var mouth: Vector3 = cap.global_position + fwd * (cap.length_m() * 0.5 + CARRIER_SPEED_MPS * DEPART_LEAD_S)
	var r: float = maxf(VortexFit.POINT_RADII_PER_SHIP * cap.cross_radius_m(), VortexFit.MIN_POINT_RADIUS_M)
	var up: Vector3 = cap.global_basis.y
	var xform := Transform3D(Basis.looking_at(-fwd, up), mouth)  # its way out faces the carrier: it flies in along +Z
	run.departure = run.pool.open_with(xform, VortexFit.new(r, r * VortexFit.POINT_DEPTH_RATIO), JumpVortex.Direction.DEPARTURE,
			VortexTiming.DEFAULT_HOLD_S, cap)
	run.state = CarrierRun.State.LEAVING
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
	run.state = CarrierRun.State.DONE
	_runs.erase(run)


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
				"doc": "The newest carrier's state: arriving, holding or leaving (none with no carrier at work)"},
	}), self)
