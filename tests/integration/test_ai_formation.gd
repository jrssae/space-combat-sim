extends GutTest
## AC9, formation (M3-T07, architecture §16 D34, D36): three allied Starfuries on the `ally_starfury` profile in a
## finger-four on a leading Starfury, the real ships in Jolt, the real drivers (avoidance included) and the real
## `WingDirector`. The leader is flown like the player's ship (commands straight to `Combatant.apply_commands`, no AI
## driver, no avoidance): 100 m/s straight on, then a 90 degree turn at 100 m/s (its heading swings at a steady rate, the
## nose along it, the velocity following on the RCS), then straight on again.
##
## Two formations fly at once in one world, 10 km apart (beyond sensor range): a left turn at `GENTLE_DPS` (a Starfury's
## RCS turns its velocity at up to about 5.7 degrees/s at 100 m/s, so this one keeps the nose on the flight path) and a right
## turn at `HARD_DPS`, just past that limit (the leader's own velocity lags its nose, and the members on the outside, whose
## noses follow the leader's, cannot pull more than their RCS gives either). Faster turns slide: the nose leaves the flight
## path, and since the slots are in the leader's body frame they swing round the leader by up to 160 m (#4 is 113 m out).
##
## The members start 200 m behind their slots and 60 m out to the side, at the leader's velocity, and join. Measured from
## the true slot (the leader's position plus its attitude times the slot offset, no lead): within `STRAIGHT_TOL_M` through
## the straight leg, within `TURN_TOL_M` from the start of the turn until `AFTER_TURN_S` after it, and no two ships ever
## closer than `MIN_CLEARANCE_M` between their bounding spheres (the avoidance margin).

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
## `Engine.time_scale`: 2 makes each 60 Hz tick 1/30 s of sim time (the 60 Hz step gave the same numbers within 0.1 m).
const SPEED_UP: float = 2.0
const SPEED_MPS: float = 100.0
const JOIN_S: float = 15.0
const STRAIGHT_S: float = 15.0
const GENTLE_DPS: float = 5.0
const HARD_DPS: float = 6.0
const AFTER_TURN_S: float = 10.0
const STRAIGHT_TOL_M: float = 25.0
const TURN_TOL_M: float = 80.0
const MIN_CLEARANCE_M: float = 15.0
const APART_M: float = 10000.0

var _scale_backup: float = 1.0


## Flies the leader like a pilot would: the heading swings at `turn_dps` (left for `turn_sign` +1, right for -1) from
## `turn_from_s` until it has turned 90 degrees; the nose faces the heading and the thrust seeks `SPEED_MPS` along it.
class LeaderPilot extends Node:
	var combatant: Combatant = null
	var turn_from_s: float = 0.0
	var turn_dps: float = 5.0
	var turn_sign: float = 1.0
	var time_s: float = 0.0
	var _capability: ShipCapability = null

	func _init() -> void:
		process_physics_priority = -5  # like Main: after the AI drivers, before the ships

	func turn_ends_s() -> float:
		return turn_from_s + 90.0 / turn_dps

	func _physics_process(delta: float) -> void:
		var ship: Ship = combatant.ship
		if _capability == null:
			_capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
		time_s += delta
		var angle: float = deg_to_rad(clampf((time_s - turn_from_s) * turn_dps, 0.0, 90.0)) * turn_sign
		var heading: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, angle)
		var flight := FlightCommand.new()
		flight.rot = PilotSteering.face(ship.global_basis, heading, _capability.rate_max_rad)
		PilotSteering.apply_seek(flight, PilotSteering.seek(ship.linear_velocity, heading * SPEED_MPS, ship.global_basis,
				_capability))
		combatant.apply_commands(flight, CombatCommand.new())


func before_each() -> void:
	_scale_backup = Engine.time_scale
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	ContactScan.invalidate()


func _starfury(world: WorldFrame, projectiles: Node3D, callsign: String, at: Vector3, ai: bool) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(STARFURY_SPEC) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: callsign,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: ai,
	})
	world.spawn(c.ship, world.to_universe(at))
	c.ship.linear_velocity = Vector3(0.0, 0.0, -SPEED_MPS)
	return c


## A leader at `origin` turning at `turn_dps` (`turn_sign` +1 left, -1 right) and its wing of three, 200 m behind and 60 m out.
func _setup(world: WorldFrame, projectiles: Node3D, director: WingDirector, origin: Vector3, turn_dps: float,
		turn_sign: float, tag: String) -> Dictionary:
	var leader: Combatant = _starfury(world, projectiles, "LEAD %s" % tag, origin, false)
	var pilot := LeaderPilot.new()
	pilot.combatant = leader
	pilot.turn_from_s = JOIN_S + STRAIGHT_S
	pilot.turn_dps = turn_dps
	pilot.turn_sign = turn_sign
	add_child_autofree(pilot)
	var wing: Wing = director.create_wing("WING %s" % tag, leader)
	var members: Array[Combatant] = []
	for slot: int in range(1, 4):
		var offset: Vector3 = wing.slot_offset(slot)
		var start: Vector3 = origin + offset + Vector3(signf(offset.x) * 60.0, 0.0, 200.0)
		var member: Combatant = _starfury(world, projectiles, "%s %d" % [tag, slot + 1], start, true)
		member.driver.brain = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, UniversePos.new(),
				slot)["brain"] as AiPilot
		assert_eq(director.add_member(wing, member), slot)
		members.append(member)
	var ships: Array[Combatant] = [leader]
	ships.append_array(members)
	return {"tag": tag, "leader": leader, "pilot": pilot, "wing": wing, "members": members, "ships": ships,
			"straight_max": [0.0, 0.0, 0.0], "turn_max": [0.0, 0.0, 0.0], "joined_s": [INF, INF, INF],
			"min_clearance": INF, "min_centres": INF, "behaviours": {}, "avoiding_ticks": 0, "avoiding_straight": 0}


func _record(run: Dictionary) -> void:
	var pilot: LeaderPilot = run["pilot"]
	var t: float = pilot.time_s
	var lead_ship: Ship = (run["leader"] as Combatant).ship
	var wing: Wing = run["wing"]
	var members: Array[Combatant] = run["members"]
	for i: int in members.size():
		var m: Combatant = members[i]
		var slot_at: Vector3 = lead_ship.global_position + lead_ship.global_basis * wing.slot_offset(i + 1)
		var error: float = m.ship.global_position.distance_to(slot_at)
		if error < STRAIGHT_TOL_M and run["joined_s"][i] == INF:
			run["joined_s"][i] = t
		if t >= JOIN_S and t < pilot.turn_from_s:
			run["straight_max"][i] = maxf(run["straight_max"][i], error)
		elif t >= pilot.turn_from_s and t <= pilot.turn_ends_s() + AFTER_TURN_S:
			run["turn_max"][i] = maxf(run["turn_max"][i], error)
		var current: AiBehaviour = (m.driver.brain as AiPilot).current
		if current != null:
			(run["behaviours"] as Dictionary)[String(current.id)] = true
		if m.driver.avoiding:
			run["avoiding_ticks"] = int(run["avoiding_ticks"]) + 1
			if t >= JOIN_S and t < pilot.turn_from_s:
				run["avoiding_straight"] = int(run["avoiding_straight"]) + 1
	var ships: Array[Combatant] = run["ships"]
	for a: int in ships.size():
		for b: int in range(a + 1, ships.size()):
			var d: float = ships[a].ship.global_position.distance_to(ships[b].ship.global_position)
			run["min_centres"] = minf(run["min_centres"], d)
			run["min_clearance"] = minf(run["min_clearance"], d - ships[a].damageable.bounding_radius
					- ships[b].damageable.bounding_radius)


func _check(run: Dictionary) -> void:
	var pilot: LeaderPilot = run["pilot"]
	var lead_ship: Ship = (run["leader"] as Combatant).ship
	var velocity: Vector3 = lead_ship.linear_velocity
	var turned_deg: float = rad_to_deg(Vector3.FORWARD.signed_angle_to(velocity, Vector3.UP))
	gut.p("formation %s: turn %.0f deg/s (%.1f s) %s; joined (within %.0f m) at %s s; straight max %s m; turn max %s m; closest centres %.1f m, clearance %.1f m; behaviours %s; avoiding %d member-ticks (%d in the straight leg); leader ends at %.1f m/s, velocity turned %.1f deg" % [
			run["tag"], pilot.turn_dps, 90.0 / pilot.turn_dps, "left" if pilot.turn_sign > 0.0 else "right", STRAIGHT_TOL_M,
			str(run["joined_s"]), str(run["straight_max"]), str(run["turn_max"]), run["min_centres"], run["min_clearance"],
			str((run["behaviours"] as Dictionary).keys()), run["avoiding_ticks"], run["avoiding_straight"], velocity.length(),
			turned_deg])
	var tag: String = run["tag"]
	assert_almost_eq(turned_deg, 90.0 * pilot.turn_sign, 5.0, "%s: the leader's velocity turned 90 degrees" % tag)
	assert_almost_eq(velocity.length(), SPEED_MPS, 5.0, "%s: at 100 m/s" % tag)
	assert_eq((run["behaviours"] as Dictionary).keys(), ["formation"], "%s: nothing but formation" % tag)
	assert_eq(int(run["avoiding_straight"]), 0, "%s: station keeping never trips the avoidance" % tag)
	var members: Array[Combatant] = run["members"]
	for i: int in members.size():
		var callsign: String = members[i].display_name
		assert_lt(float(run["joined_s"][i]), JOIN_S, "%s joined before the straight leg" % callsign)
		assert_lt(float(run["straight_max"][i]), STRAIGHT_TOL_M, "%s within 25 m of its slot in straight flight" % callsign)
		assert_lt(float(run["turn_max"][i]), TURN_TOL_M, "%s within 80 m of its slot through the turn" % callsign)
	assert_gte(float(run["min_clearance"]), MIN_CLEARANCE_M, "%s: never closer than 15 m to anyone" % tag)


func test_a_finger_four_holds_its_slots_straight_and_through_a_90_degree_turn() -> void:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var director := WingDirector.new()
	director.setup(world)
	add_child_autofree(director)
	var gentle: Dictionary = _setup(world, projectiles, director, Vector3(-APART_M / 2.0, 0.0, 0.0), GENTLE_DPS, 1.0, "A")
	var hard: Dictionary = _setup(world, projectiles, director, Vector3(APART_M / 2.0, 0.0, 0.0), HARD_DPS, -1.0, "B")
	var ticker := PhysicsTicker.new()
	ticker.on_tick = func() -> void:
		_record(gentle)
		_record(hard)
	add_child_autofree(ticker)

	Engine.time_scale = SPEED_UP
	var run_s: float = maxf((gentle["pilot"] as LeaderPilot).turn_ends_s(), (hard["pilot"] as LeaderPilot).turn_ends_s()) \
			+ AFTER_TURN_S
	var ticks: int = roundi(run_s * float(Engine.physics_ticks_per_second) / SPEED_UP)
	while ticker.ticks < ticks:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	_check(gentle)
	_check(hard)
