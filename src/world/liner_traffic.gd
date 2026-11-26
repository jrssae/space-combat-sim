class_name LinerTraffic
extends RefCounted
## The Asimov liners of the station's traffic (M10-T53, Q85): a liner comes out of the jumpgate, flies to a standoff spot off
## the docking sphere and holds there; its two shuttles (the bay's crew shuttle and Kestrel) leave its bay, fly into
## Babylon 5's main docking bay by the lane, queuing with the other traffic, wait inside to unload, come out and are taken
## back into the bay, then fly the same trip again to load; when its stay is over and its shuttles are home it leaves through
## the gate. `StationTraffic` owns it, steps it once a tick and gives it the console.
##
## - **The liner** is a `CapitalShip` flown by its helm's orders (`set_course`), looked at twice a second; out of the
##   low-attention tier for its visit, as the lane's ships are.
## - **The shuttles** are its hangar's own (`CapitalHangar.launch`, `recall`): let go ahead of the bay they get a civilian
##   pilot and become a docking ship of the traffic (`StationTraffic.adopt_docking`); behind the inner doors they are kept
##   inside the station, hidden by its walls, then sent out as an undocking ship and flown home.
## - **The schedule** (`LinerSchedule`) runs on the traffic's own clock while the run is on: the next visit is timed from the
##   last liner leaving its spot, and no visit starts while a liner is at the station or on its way in.
## - A liner that is disabled or destroyed ends its visit where it is; its shuttles out leave through the gate.

const TYPE: StringName = &"ea_asimov"
const CIVILIAN_AI: Dictionary = {"type": "ai", "profile": "civilian"}
## How often a liner's course and its shuttles are looked at, s.
const DECIDE_S: float = 0.5
## A liner within this of its spot turns its bow to where its shuttles fly, m.
const TURN_IN_M: float = 600.0
## It holds once it is this slow against the station, m/s.
const HOLD_MPS: float = 3.0
## A shuttle this near its liner's bow is handed to the hangar, m.
const HAND_OVER_M: float = 400.0
## A shuttle kept inside the station lies this far behind the docking bay's void, in the hull, m.
const INSIDE_DEEP_M: float = 400.0
## A launch the bay has not finished after this long is called off when the liner's stay is over, s.
const LAUNCH_LIMIT_S: float = 90.0
## The second shuttle leaves this long after the first, s.
const STAGGER_S: float = 45.0
## A liner whose departure the gate did not take (an arrival had it) is let go this far past the gate, m.
const PAST_GATE_M: float = 1500.0
## One liner at a time comes out of the gate: the next waits until the last is this far from it, m.
const GATE_CLEAR_M: float = 3000.0
## Nor do two fly out together: a liner leaves its spot once the one ahead is this far from it, m.
const OUT_GAP_M: float = 8000.0
## With no gate it is let go this far from its spot, m.
const NO_GATE_OUT_M: float = 12000.0
## Where `view` puts the player: this far from the liner on the side away from the docking sphere and this far above it,
## m, looking this far under it (the liner in the upper half of the view, the sphere beyond it).
const VIEW_BACK_M: float = 1000.0
const VIEW_UP_M: float = 300.0
const VIEW_UNDER_M: float = 250.0

var traffic: StationTraffic = null
var schedule: LinerSchedule = LinerSchedule.new()
var visits: Array[LinerVisit] = []
## Its speed on the run and the braking its approach counts on, the standoff spots (station frame), how near a spot counts
## as there, how far ahead of its bow a shuttle is handed over, where it lines up on the gate.
var cruise_mps: float = 120.0
var brake_mps2: float = 0.2
var spots: Array[Vector3] = [Vector3(2500.0, 1500.0, -6500.0), Vector3(2500.0, -1500.0, -6500.0)]
var arrive_m: float = 150.0
var home_ahead_m: float = 500.0
var line_up_m: float = 6000.0
## How long a shuttle waits inside the station, and aboard between its trips, s (least, most).
var inside_s: Vector2 = Vector2(45.0, 90.0)
var aboard_s: Vector2 = Vector2(40.0, 80.0)
## Visits the schedule started, liners that came and that left, shuttle trips flown home.
var visits_started: int = 0
var liners_come: int = 0
var liners_left: int = 0
var trips_flown: int = 0
## The traffic clock time of the next scheduled visit (-1: not drawn yet).
var next_at_s: float = -1.0
## What a tick of the liners costs: the last one and the mean, microseconds (0 with no liner in play).
var last_us: int = 0
var total_us: int = 0
var ticks: int = 0

var _data: Dictionary = {}
var _decide_s: float = 0.0
var _asked: int = 0


func _init(p_traffic: StationTraffic) -> void:
	traffic = p_traffic


## Reads traffic.json's `liner` block; absent keys keep their defaults.
func load_data(data: Dictionary) -> void:
	_data = data
	cruise_mps = maxf(float(data.get("cruise_mps", cruise_mps)), 1.0)
	brake_mps2 = maxf(float(data.get("brake_mps2", brake_mps2)), 0.01)
	arrive_m = maxf(float(data.get("arrive_m", arrive_m)), 10.0)
	home_ahead_m = maxf(float(data.get("home_ahead_m", home_ahead_m)), 100.0)
	line_up_m = maxf(float(data.get("line_up_m", line_up_m)), 1000.0)
	inside_s = LinerSchedule.span_of(data.get("inside_s"), inside_s)
	aboard_s = LinerSchedule.span_of(data.get("aboard_s"), aboard_s)
	var raw: Variant = data.get("spots")
	if raw is Array and (raw as Array).size() >= LinerSchedule.MAX_AT_ONCE:
		spots.clear()
		for spot: Variant in raw:
			spots.append(Vector3(float(spot[0]), float(spot[1]), float(spot[2])))
	schedule = LinerSchedule.from_data(data, schedule.seed_value, ShipNames.names_for(TYPE).size())


## Liners in play (asked of the gate, at the station or flying out).
func in_play() -> int:
	return visits.size()


## The liner called `liner_name`, or null.
func visit_named(liner_name: String) -> LinerVisit:
	for visit: LinerVisit in visits:
		if visit.name == liner_name:
			return visit
	return null


## Every visit in a line each, or "none".
func text() -> String:
	var parts := PackedStringArray()
	for visit: LinerVisit in visits:
		parts.append(visit.text())
	return "; ".join(parts) if not parts.is_empty() else "none"


## Seconds of the traffic's clock until the next scheduled visit (-1: none is timed, as while a liner is at the station).
func next_in_s() -> float:
	return maxf(next_at_s - traffic.elapsed_s, 0.0) if next_at_s >= 0.0 and not _visiting() else -1.0


## The mean cost of a tick with a liner in play, microseconds.
func mean_us() -> float:
	return float(total_us) / float(ticks) if ticks > 0 else 0.0


## A liner comes through the gate and calls at the station for `stay_s` (under 0: drawn from the data's range). `near` starts
## it holding at its spot instead (also the way in a scenario with no gate). Returns "" or why not.
func start(stay_s: float = -1.0, near: bool = false, name_index: int = -1) -> String:
	if not traffic.lanes_ready():
		return "the station takes no traffic now"
	if in_play() >= LinerSchedule.MAX_AT_ONCE:
		return "%d liners are here already" % LinerSchedule.MAX_AT_ONCE
	var gate: Jumpgate = _gate()
	if gate == null and not near:
		return "no jumpgate in this scenario (traffic liner near)"
	_asked += 1
	var visit := LinerVisit.new()
	visit.name = _free_name(name_index if name_index >= 0 else hash([_seed(), "liner asked", _asked]))
	visit.slot = _free_slot()
	visit.stay_s = stay_s if stay_s >= 0.0 else lerpf(schedule.stay_s.x, schedule.stay_s.y, _unit("stay asked", _asked))
	visits.append(visit)
	traffic.last_event = "liner %s" % visit.name
	if not near:
		return ""  # asked of the gate in its turn (`_ask_gate`)
	_place(visit, Transform3D(Basis.looking_at(_face(visit), Vector3.UP), _spot(visit)), Vector3.ZERO)
	if visit.ship == null:
		return "%s is not generated (scripts/gen_assets.sh, then import)" % TYPE
	visit.phase = LinerVisit.HOLDING
	return ""


## Puts the player beside and above the last liner started, the docking sphere beyond it: its shuttles leave its bow and
## come home in view. "" or why not.
func view() -> String:
	var main: Main = traffic.main
	if visits.is_empty() or visits[visits.size() - 1].ship == null:
		return "no liner at the station to look at"
	if not main.player_alive:
		return "no player to move"
	main.world.return_home()  # the station's rail first (M7-T71)
	var visit: LinerVisit = visits[visits.size() - 1]
	var station: Station = traffic.station()
	var up: Vector3 = station.global_basis.y
	var spot: Vector3 = visit.ship.global_position
	var at: Vector3 = spot - (station.global_transform * traffic.plan.mouth - spot).normalized() * VIEW_BACK_M + up * VIEW_UP_M
	main.ship.reset_to(Transform3D(Basis.looking_at((spot - up * VIEW_UNDER_M - at).normalized(), up), at))
	main.ship.linear_velocity = main.world.rest_velocity()
	main.ship.angular_velocity = Vector3.ZERO
	return ""


## Ends every visit: the liners leave the world and their shuttles go back to their pools. Returns how many liners.
func clear() -> int:
	var n: int = visits.size()
	for visit: LinerVisit in visits.duplicate():
		_remove(visit)
	return n


## One tick: the schedule, the shuttles kept inside the station, and twice a second every liner's course and shuttles.
func step(delta: float) -> void:
	_run_schedule()
	if visits.is_empty():
		last_us = 0
		return
	var t0: int = Time.get_ticks_usec()
	for visit: LinerVisit in visits:
		for s: Dictionary in visit.shuttles:
			if s["leg"] == LinerVisit.INSIDE:
				_keep_inside(s)
	_decide_s += delta
	if _decide_s >= DECIDE_S:
		for visit: LinerVisit in visits.duplicate():
			_step_visit(visit, _decide_s)
		_decide_s = 0.0
	last_us = Time.get_ticks_usec() - t0
	total_us += last_us
	ticks += 1


## A shuttle of ours is through the station's inner doors and they have shut: it waits inside, out of everyone's way.
func shuttle_inside(entry: Dictionary) -> void:
	var s: Dictionary = _shuttle_of(entry)
	if s.is_empty():
		entry.erase("liner")
		return
	var ship: Ship = (s["combatant"] as Combatant).ship
	s["kept"] = {"layer": ship.collision_layer, "mask": ship.collision_mask}
	ship.collision_layer = 0
	ship.collision_mask = 0
	ship.custom_integrator = true
	ship.clamped = true
	ship.inside_station = true
	entry["kind"] = &"shuttle"
	entry["state"] = &"inside"
	s["leg"] = LinerVisit.INSIDE
	s["wait_s"] = lerpf(inside_s.x, inside_s.y, _unit("inside " + String(s["type"]), hash([s["visit"], s["trip"]])))
	_keep_inside(s)


## A shuttle of ours is clear of the station's lane: it flies home to its liner instead of leaving. False when it has no
## liner to go to (it leaves as any civilian does).
func take_home(entry: Dictionary) -> bool:
	var s: Dictionary = _shuttle_of(entry)
	var visit: LinerVisit = visit_named(str(entry.get("liner", "")))
	if s.is_empty() or visit == null or not _liner_fit(visit):
		entry.erase("liner")
		return false
	entry["kind"] = &"shuttle"
	entry["state"] = &"home"
	s["leg"] = LinerVisit.HOME
	var c: Combatant = s["combatant"]
	var route := Route.new()
	route.name = "TO %s" % visit.name.to_upper()
	route.pace = Route.PACE_NONE
	route.lane = true
	route.cruise_mps = StationTraffic.TRANSIT_CRUISE_MPS
	route.add_lane(traffic.main.world.to_universe(c.ship.global_position))
	route.add_lane(traffic.main.world.to_universe(_home_point(visit)), 1.0e9)
	BehaviourFollowPath.attach(s["brain"] as AiPilot, route)
	return true


# --- the schedule -----------------------------------------------------------------------------------------------


# Starts the next visit when its time has come: the run on, nobody sheltering, and no liner at the station or on its way.
func _run_schedule() -> void:
	if not traffic.auto or traffic.sheltering or _gate() == null:
		return
	if schedule.seed_value != _seed():
		schedule.seed_value = _seed()
		next_at_s = -1.0
	if next_at_s < 0.0:
		next_at_s = traffic.elapsed_s + schedule.wait_s(visits_started)
	if _visiting() or traffic.elapsed_s < next_at_s or not traffic.lanes_ready():
		return
	var index: int = visits_started
	visits_started += 1
	next_at_s = INF  # timed again when its last liner leaves its spot
	for k: int in mini(schedule.liners(index), LinerSchedule.MAX_AT_ONCE - in_play()):
		var why: String = start(schedule.stay(index, k), false, schedule.name_index(index, k))
		if not why.is_empty():
			traffic.last_event = "liner (auto): %s" % why
	if not _visiting():
		next_at_s = traffic.elapsed_s + schedule.wait_s(visits_started)


func _visiting() -> bool:
	for visit: LinerVisit in visits:
		if visit.visiting():
			return true
	return false


# --- the liner --------------------------------------------------------------------------------------------------


# Builds the visit's liner at `at` (World) with `velocity` against the station, its hangar driven from here.
func _place(visit: LinerVisit, at: Transform3D, velocity: Vector3) -> void:
	var world: WorldFrame = traffic.main.world
	var liner: CapitalShip = CapitalShip.create(TYPE, ShipCatalog.data().faction(TYPE), visit.name, world.rest_velocity() + velocity)
	if liner == null:
		_remove(visit)
		return
	liner.tier_exempt = true  # flown in full for its visit, wherever the player is
	var aboard: Dictionary = liner.hangar.stock.duplicate() if liner.hangar != null else {}
	if liner.hangar != null:
		# Placed empty and stocked on its first look: a hangar placed with its craft builds them into the pool anew, and
		# every visit would leave two more ships there. A launch takes a free one, or builds it then.
		liner.hangar.empty()
	world.spawn(liner, world.to_universe(at.origin), at.basis)
	liner.set_course(-at.basis.z, world.rest_velocity() + velocity)
	visit.ship = liner
	visit.phase = LinerVisit.INBOUND
	liners_come += 1
	if liner.hangar == null:
		return
	liner.hangar.auto = false
	liner.hangar.launched.connect(_on_launched.bind(visit))
	liner.hangar.recovered.connect(_on_recovered.bind(visit))
	liner.hangar.gave_up.connect(_on_gave_up.bind(visit))
	var k: int = 0
	for type: Variant in aboard:
		for n: int in int(aboard[type]):
			visit.shuttles.append({"type": StringName(type), "leg": LinerVisit.ABOARD, "trip": 0, "wait_s": 10.0 + STAGGER_S * float(k),
					"visit": visit.name, "combatant": null, "brain": null, "entry": {}})
			k += 1


func _step_visit(visit: LinerVisit, dt: float) -> void:
	if visit.phase == LinerVisit.GATE:
		_ask_gate(visit)
		return
	if not _liner_fit(visit):
		_abandon(visit)
		return
	visit.ship.tier_exempt = true
	if not visit.stocked and visit.ship.hangar != null:
		visit.stocked = true
		visit.ship.hangar.stock_from_loadout()
	match visit.phase:
		LinerVisit.INBOUND:
			if _fly_to(visit, _spot(visit), true) < arrive_m and _speed(visit) < HOLD_MPS:
				visit.phase = LinerVisit.HOLDING
				traffic.last_event = "liner %s holds off the docking sphere" % visit.name
		LinerVisit.HOLDING:
			_fly_to(visit, _spot(visit), true)
			visit.held_s += dt
			for s: Dictionary in visit.shuttles:
				_step_shuttle(visit, s, dt)
			var over: bool = visit.held_s >= visit.stay_s
			if over and visit.shuttles_home() and not traffic.sheltering and _way_out_clear(visit):
				_leave(visit)
		LinerVisit.OUTBOUND:
			_fly_out(visit)


# Asks the gate for the visit's arrival once no other liner is waiting for the vortex, still near the gate, or flying out
# toward it (the way out and the way in share the gate's axis).
func _ask_gate(visit: LinerVisit) -> void:
	var gate: Jumpgate = _gate()
	if visit.asked or gate == null:
		return
	for other: LinerVisit in visits:
		if other == visit:
			continue
		if (other.phase == LinerVisit.GATE and other.asked) or other.phase == LinerVisit.OUTBOUND \
				or (other.phase == LinerVisit.INBOUND and is_instance_valid(other.ship)
				and other.ship.global_position.distance_to(gate.global_position) < GATE_CLEAR_M):
			return
	visit.asked = true
	gate.request_arrival(func() -> void:
		if not visit.in_play():
			return
		var at: Transform3D = gate.arrival_transform()
		_place(visit, at, -at.basis.z * cruise_mps)
		if visit.ship != null:
			gate.bring_through(visit.ship))


# Whether no liner that left before it is still near on the way out.
func _way_out_clear(visit: LinerVisit) -> bool:
	for other: LinerVisit in visits:
		if other != visit and other.phase == LinerVisit.OUTBOUND and is_instance_valid(other.ship) \
				and other.ship.global_position.distance_to(visit.ship.global_position) < OUT_GAP_M:
			return false
	return true


# Flies the liner's helm at `target` (World): at cruise, or with `stop` slowing to rest there. Returns how far it is.
func _fly_to(visit: LinerVisit, target: Vector3, stop: bool) -> float:
	var liner: CapitalShip = visit.ship
	var rest: Vector3 = traffic.main.world.rest_velocity()
	var to: Vector3 = target - liner.global_position
	var dist: float = to.length()
	var along: Vector3 = to / dist if dist > 1.0 else Vector3.ZERO
	var speed: float = cruise_mps
	if stop:
		speed = minf(cruise_mps, sqrt(2.0 * brake_mps2 * maxf(dist - 0.3 * arrive_m, 0.0)))
	liner.set_course(along if dist > TURN_IN_M or not stop else _face(visit), rest + along * speed)
	return dist


func _speed(visit: LinerVisit) -> float:
	return (visit.ship.linear_velocity - traffic.main.world.rest_velocity()).length()


# Its stay is over and its shuttles are home: back to the gate, and the next visit is timed from now.
func _leave(visit: LinerVisit) -> void:
	visit.phase = LinerVisit.OUTBOUND
	visit.out_leg = 0
	traffic.last_event = "liner %s leaves for the gate" % visit.name
	var gate: Jumpgate = _gate()
	if gate != null:
		gate.send_departure(visit.ship, func(_body: Node3D) -> void: _gone(visit))
	if not _visiting() and next_at_s == INF:
		next_at_s = traffic.elapsed_s + schedule.wait_s(visits_started)


# The way out: onto the gate's axis well ahead of it, then through; with no gate, straight on until it is far off.
func _fly_out(visit: LinerVisit) -> void:
	var gate: Jumpgate = _gate()
	if gate == null:
		var bow: Vector3 = -visit.ship.global_basis.z
		if _fly_to(visit, visit.ship.global_position + bow * 10000.0, false) > 0.0 \
				and visit.ship.global_position.distance_to(_spot(visit)) > NO_GATE_OUT_M:
			_gone(visit)
		return
	var local: Vector3 = gate.local_of(visit.ship.global_position)
	if visit.out_leg == 0 and (local.z > -line_up_m or local.distance_to(Vector3(0.0, 0.0, -line_up_m)) < 1000.0):
		visit.out_leg = 1
	var aim: Vector3 = Vector3(0.0, 0.0, -line_up_m) if visit.out_leg == 0 else Vector3(0.0, 0.0, gate.radius_m * 4.0)
	_fly_to(visit, gate.global_transform * aim, false)
	if local.z > PAST_GATE_M:
		gate.cancel_departure(visit.ship)
		_gone(visit)


# Through the gate: the liner leaves the world.
func _gone(visit: LinerVisit) -> void:
	if not visit.in_play():
		return
	liners_left += 1
	traffic.last_event = "liner %s left" % visit.name
	_remove(visit)


func _remove(visit: LinerVisit) -> void:
	visit.phase = LinerVisit.GONE
	visits.erase(visit)
	for s: Dictionary in visit.shuttles:
		_restore(s)
		traffic.forget(s["entry"])
	var liner: CapitalShip = visit.ship
	visit.ship = null
	if liner == null or not is_instance_valid(liner):
		return
	# Craft still out go back to their pools with their liner (a visit cleared midway).
	if liner.hangar != null:
		for out: Dictionary in liner.hangar.craft_out():
			var c: Combatant = out["combatant"]
			if c != null and is_instance_valid(c.ship):
				c.targetable.broadcast_range_m = 0.0
				traffic.main.ships.release(c)
	var gate: Jumpgate = _gate()
	if gate != null:
		gate.cancel_departure(liner)
	liner.leave_play()
	liner.queue_free()


# The liner is disabled or gone: its visit ends, and its shuttles still out leave as any civilian does.
func _abandon(visit: LinerVisit) -> void:
	for s: Dictionary in visit.shuttles:
		if s.get("combatant") == null or not _flies(s):
			continue
		var entry: Dictionary = s["entry"]
		entry.erase("liner")
		if s["leg"] == LinerVisit.INSIDE:
			_restore(s)
			traffic.send_out(entry)
		elif s["leg"] == LinerVisit.HOME:
			traffic.send_away(entry)
	visit.phase = LinerVisit.GONE
	visits.erase(visit)
	traffic.last_event = "liner %s is lost" % visit.name
	if not _visiting() and next_at_s == INF:
		next_at_s = traffic.elapsed_s + schedule.wait_s(visits_started)


func _liner_fit(visit: LinerVisit) -> bool:
	var liner: CapitalShip = visit.ship
	return liner != null and is_instance_valid(liner) and liner.is_inside_tree() and not liner.is_hulk() \
			and not liner.damage.is_destroyed


# --- the shuttles -----------------------------------------------------------------------------------------------


# One shuttle, twice a second: its waits run down, it is launched for its next trip, sent out of the station when the bay
# is free, and handed to the hangar once it is back at its liner's bow.
func _step_shuttle(visit: LinerVisit, s: Dictionary, dt: float) -> void:
	var leg: StringName = s["leg"]
	if leg == LinerVisit.DONE or leg == LinerVisit.LOST:
		return
	var c: Combatant = s.get("combatant")
	if c != null and not _flies(s):
		_lose(s)
		return
	s["wait_s"] = maxf(float(s["wait_s"]) - dt, 0.0)
	match leg:
		LinerVisit.ABOARD:
			# No trip starts once the stay is over, while Control shelters the civilians or the station takes nobody.
			if float(s["wait_s"]) <= 0.0 and visit.held_s < visit.stay_s and not traffic.sheltering and traffic.lanes_ready():
				traffic.main.ensure_free(s["type"], 1)
				if visit.ship.hangar.launch(s["type"], 1) > 0:
					s["leg"] = LinerVisit.LAUNCHING
					s["wait_s"] = LAUNCH_LIMIT_S
		LinerVisit.LAUNCHING:
			if not visit.ship.hangar.is_launching():
				s["leg"] = LinerVisit.ABOARD  # the bay sent nothing (no craft free in the pool): asked again
				s["wait_s"] = 10.0
			elif float(s["wait_s"]) <= 0.0 and visit.held_s >= visit.stay_s:
				# The bay never let it go (a lost bay, a jammed door) and the liner is due out: it stays aboard.
				visit.ship.hangar.empty()
				s["leg"] = LinerVisit.ABOARD
		LinerVisit.INSIDE:
			if float(s["wait_s"]) <= 0.0 and not traffic.sheltering and not traffic.lane_taken():
				_restore(s)
				s["leg"] = LinerVisit.FROM_STATION
				traffic.send_out(s["entry"])
		LinerVisit.HOME:
			if c.ship.global_position.distance_to(_home_point(visit)) < HAND_OVER_M \
					and visit.ship.hangar.recall(c.ship, s["type"]):
				c.targetable.broadcast_range_m = 0.0
				s["leg"] = LinerVisit.BERTHING


# The hangar let a craft go ahead of the bay: it gets a civilian pilot and joins the docking bay's queue.
func _on_launched(craft: Ship, visit: LinerVisit) -> void:
	if not visit.in_play() or not is_instance_valid(visit.ship):
		return
	for out: Dictionary in visit.ship.hangar.craft_out():
		if out["ship"] != craft:
			continue
		for s: Dictionary in visit.shuttles:
			if s["leg"] == LinerVisit.LAUNCHING and s["type"] == out["type"]:
				_send_to_station(visit, s, out["combatant"] as Combatant)
				return


func _send_to_station(visit: LinerVisit, s: Dictionary, c: Combatant) -> void:
	var world: WorldFrame = traffic.main.world
	var made: Dictionary = BrainFactory.from_behaviour(CIVILIAN_AI, world.to_universe(c.ship.global_position),
			hash([_seed(), "liner shuttle", visit.name, s["type"], s["trip"]]))
	if not bool(made.get("ok", false)) or c.driver == null:
		push_error("LinerTraffic: no pilot for %s: %s" % [c.display_name, made.get("error", "no driver")])
		_lose(s)
		return
	c.driver.brain = made["brain"] as PilotBrain
	c.ship.tier_exempt = true
	c.targetable.broadcast_range_m = ShipPool.CIVILIAN_BROADCAST_RANGE_M
	s["combatant"] = c
	s["brain"] = made["brain"]
	s["leg"] = LinerVisit.TO_STATION
	s["entry"] = traffic.adopt_docking(c, made["brain"] as PilotBrain, {"liner": visit.name})


# The hangar took a shuttle back into the bay: one trip flown; it waits aboard for the next, or is finished.
func _on_recovered(_craft: Ship, type: StringName, visit: LinerVisit) -> void:
	for s: Dictionary in visit.shuttles:
		if s["leg"] == LinerVisit.BERTHING and s["type"] == type:
			traffic.forget(s["entry"])
			s["combatant"] = null
			s["brain"] = null
			s["entry"] = {}
			s["trip"] = int(s["trip"]) + 1
			trips_flown += 1
			s["leg"] = LinerVisit.DONE if int(s["trip"]) >= LinerVisit.TRIPS.size() else LinerVisit.ABOARD
			s["wait_s"] = lerpf(aboard_s.x, aboard_s.y, _unit("aboard " + String(type), hash([visit.name, s["trip"]])))
			return


# The hangar could not take it in: it is asked again from the bow.
func _on_gave_up(craft: Ship, visit: LinerVisit) -> void:
	for s: Dictionary in visit.shuttles:
		var c: Combatant = s.get("combatant")
		if s["leg"] == LinerVisit.BERTHING and c != null and c.ship == craft:
			s["leg"] = LinerVisit.HOME


func _lose(s: Dictionary) -> void:
	traffic.forget(s["entry"])
	s["leg"] = LinerVisit.LOST
	s["combatant"] = null
	s["brain"] = null
	s["entry"] = {}


# Whether the shuttle's ship still flies for us (a destroyed one went back to its pool).
static func _flies(s: Dictionary) -> bool:
	var c: Combatant = s.get("combatant")
	return c != null and is_instance_valid(c.ship) and c.driver != null and c.driver.brain == s["brain"] \
			and not c.damageable.hull.destroyed


# Holds a shuttle that waits inside the station where nothing sees or meets it: in the hull, behind the bay's void.
func _keep_inside(s: Dictionary) -> void:
	var station: Station = traffic.station()
	var c: Combatant = s.get("combatant")
	if station == null or traffic.plan == null or c == null or not is_instance_valid(c.ship):
		return
	var inward: Vector3 = (traffic.plan.airlock - traffic.plan.mouth).normalized()
	c.ship.global_transform = Transform3D(station.global_basis.orthonormalized(),
			station.global_transform * (traffic.plan.airlock + inward * INSIDE_DEEP_M))
	c.ship.linear_velocity = traffic.main.world.anchored_velocity()
	c.ship.angular_velocity = Vector3.ZERO
	c.ship.inside_station = true


# A shuttle kept inside meets the world again.
func _restore(s: Dictionary) -> void:
	var kept: Dictionary = s.get("kept", {})
	var c: Combatant = s.get("combatant")
	if kept.is_empty() or c == null or not is_instance_valid(c.ship):
		return
	c.ship.collision_layer = int(kept["layer"])
	c.ship.collision_mask = int(kept["mask"])
	c.ship.custom_integrator = false
	c.ship.clamped = false
	s["kept"] = {}


func _shuttle_of(entry: Dictionary) -> Dictionary:
	var visit: LinerVisit = visit_named(str(entry.get("liner", "")))
	if visit == null:
		return {}
	for s: Dictionary in visit.shuttles:
		if is_same(s["entry"], entry):
			return s
	return {}


# --- places -----------------------------------------------------------------------------------------------------


func _gate() -> Jumpgate:
	return traffic.main.gates.gate() if traffic.main != null and traffic.main.gates != null else null


func _seed() -> int:
	return traffic.main.scenario_seed if traffic.main != null else 0


func _unit(what: String, index: int) -> float:
	return float(hash([_seed(), "liner " + what, index])) / 4294967296.0


# The visit's standoff spot, World.
func _spot(visit: LinerVisit) -> Vector3:
	return traffic.station().global_transform * spots[visit.slot % spots.size()]


# Where its bow points while it holds: at the docking bay's waiting points, where its shuttles fly.
func _face(visit: LinerVisit) -> Vector3:
	var lane: Array[Dictionary] = traffic.plan.dock_in
	var inward: Vector3 = ((lane[1]["at"] as Vector3) - (lane[0]["at"] as Vector3)).normalized()
	var entry: Vector3 = traffic.station().global_transform * ((lane[0]["at"] as Vector3) - inward * StationTraffic.ENTRY_OUT_M)
	return (entry - _spot(visit)).normalized()


# Where a shuttle coming home is handed to the hangar: ahead of the liner's bow, on its axis.
func _home_point(visit: LinerVisit) -> Vector3:
	return visit.ship.global_transform * Vector3(0.0, 0.0, -(visit.ship.half_extents().z + home_ahead_m))


# The lowest standoff spot no liner in play holds.
func _free_slot() -> int:
	var taken: Array[int] = []
	for visit: LinerVisit in visits:
		taken.append(visit.slot)
	var slot: int = 0
	while taken.has(slot):
		slot += 1
	return slot


# The name at `index` of the hull's list, or the next one no liner in play wears.
func _free_name(index: int) -> String:
	var faction: StringName = ShipCatalog.data().faction(TYPE)
	var count: int = maxi(ShipNames.names_for(TYPE).size(), 1)
	for step: int in count:
		var liner_name: String = ShipNames.pick(TYPE, faction, (absi(index) + step) % count)
		if liner_name.is_empty():
			break
		if visit_named(liner_name) == null:
			return liner_name
	return "%s %d" % [ShipCatalog.entry_text(TYPE, "name"), _asked]
