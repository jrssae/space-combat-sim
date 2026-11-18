extends GutTest
## The player's wing re-forming after the player turns about at speed (M7-T76): the maintainer reversed at high speed with
## Alpha's eleven wingmen on the V and several rammed each other getting back into formation. A leader flown on a fixed
## schedule (straight on, its nose turned about at a Starfury's 60 degrees/s, and a burn on its mains back to the same speed
## the other way, after the turn or during it), with the wing on its slots under FORM ON ME: no ship may touch another while
## the wing comes round to its slots, now on the far side of the leader. Flown headless through the native core with the
## physics rate and the time scale raised.
##
## On HEAD before M7-T76 (2.5 s turns): 1 ram flipping at 100, 200 or 300 m/s and burning after; 3 rams (two between
## wingmen) turning in 1.5 s while burning; 4 (three between wingmen, at 140 m/s) turning in 2.5 s while burning.

const ALLY: StringName = &"starfury_ally"
const SPEED_UP: float = 8.0
## Alpha grown to eleven (M7-T58), the balanced V (M7-T74).
const WING_SIZE: int = 11
## Straight on before the turn, s: the wing settles on its slots.
const SETTLE_S: float = 8.0
## The nose's half turn at 60 degrees/s, s, and the burn back on the mains, m/s^2 (four pods of 360 kN on 48 t).
const FLIP_S: float = 3.5
const BURN_MPS2: float = 30.0
## How long the leader flies on after its burn while the wing re-forms, s.
const REFORM_S: float = 60.0
## Within this of its slot a wingman is formed up again, m: half the V's spacing.
const FORMED_M: float = 20.0
## The least two ships' centres may come to each other, m: two Starfury radii (10 m) and a little room.
const CLEAR_M: float = 25.0

var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()  # some 90 s of flying per case


func before_each() -> void:
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func test_alpha_reforms_after_turning_about_at_200_mps_and_burning_back() -> void:
	# Yawed about: the V's slots swing through behind the leader to the far side, mirrored, each across the leader.
	await _reverse(200.0, Vector3.UP, false)


func test_alpha_reforms_after_turning_about_at_300_mps_while_burning_back() -> void:
	# The burn starts with the turn, so the leader brakes back into the wing while the slots are still swinging.
	await _reverse(300.0, Vector3.UP, true)


func test_alpha_reforms_after_pitching_over_at_200_mps_and_burning_back() -> void:
	# Pitched over: the arms stay on their sides and only the centre slot lies across the leader.
	await _reverse(200.0, Vector3.RIGHT, false)


# Flies the turn about `axis` at `speed` (burning back during the turn when `overlap`, after it otherwise) and asserts no
# ship came near touching another and the wing re-formed.
func _reverse(speed: float, axis: Vector3, overlap: bool) -> void:
	var scene: TurretScene = TurretScene.build(self, &"threaded", 6)
	var formation := Formation.new()
	var heading := Vector3.FORWARD
	var basis := Basis.looking_at(heading, Vector3.UP)
	var leader: Combatant = scene.ship(ALLY, Factions.EARTH_ALLIANCE, "ALPHA 1", Vector3.ZERO, {}, 1, false, basis)
	var callsigns: Dictionary = {leader.ship.get_instance_id(): leader.display_name}
	var wing: Array[Combatant] = []
	var slots: Array[Vector3] = []
	var rams: Array[int] = [0]
	for k: int in range(1, WING_SIZE + 1):
		var offset: Vector3 = formation.offset(k, WING_SIZE)
		slots.append(offset)
		var c: Combatant = scene.ship(ALLY, Factions.EARTH_ALLIANCE, "ALPHA %d" % (k + 1),
				Formation.slot_point(Vector3.ZERO, heading, Vector3.UP, offset), {"type": "ai", "profile": "ally_starfury"},
				80 + k, false, basis)
		var pilot: AiPilot = c.driver.brain as AiPilot
		pilot.add_behaviour(BehaviourFormation.new(pilot.profile))  # as `WingDirector.add_member` briefs a wingman
		pilot.add_behaviour(BehaviourRally.new(pilot.profile))
		callsigns[c.ship.get_instance_id()] = c.display_name
		var callsign: String = c.display_name
		c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			if info != null and info.cause == HitInfo.CAUSE_RAM:
				rams[0] += 1
				gut.p("  ram: %s against %s, %.0f m/s" % [callsign, callsigns.get(info.shooter_id, "?"),
						info.relative_speed_mps]))
		c.ship.linear_velocity = heading * speed
		wing.append(c)
	leader.ship.linear_velocity = heading * speed
	var resolver := RamResolver.new()
	resolver.name = "RamResolver"
	resolver.world = scene.world
	scene.space.add_child(resolver)
	scene.attach()
	_brief(wing, leader, slots)
	var everyone: Array[Combatant] = [leader]
	everyone.append_array(wing)
	_speed_up()
	var nearest: float = INF
	var nearest_at: String = ""
	var formed_s: float = INF
	var total_s: float = SETTLE_S + FLIP_S + 2.0 * speed / BURN_MPS2 + REFORM_S
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < total_s:
		await get_tree().physics_frame
		var t: float = SimClock.now() - t0
		_lead(scene, leader, wing, heading, axis, speed, overlap, t)
		for a: int in everyone.size():
			for b: int in range(a + 1, everyone.size()):
				var d: float = everyone[a].ship.global_position.distance_to(everyone[b].ship.global_position)
				if d < nearest:
					nearest = d
					nearest_at = "%s and %s at %.1f s" % [everyone[a].display_name, everyone[b].display_name, t]
		if t > SETTLE_S + FLIP_S and formed_s == INF and _worst(leader, wing, slots) < FORMED_M:
			formed_s = t - SETTLE_S
	var worst: float = _worst(leader, wing, slots)
	after_each()
	gut.p("turned about at %.0f m/s: rams %d, nearest centres %.1f m (%s), re-formed %.1f s after the turn began, worst %.0f m at the end"
			% [speed, rams[0], nearest, nearest_at, formed_s, worst])
	assert_eq(rams[0], 0, "no ship touched another")
	assert_gt(nearest, CLEAR_M, "no two ships closer than %.0f m (%s)" % [CLEAR_M, nearest_at])
	assert_lt(worst, FORMED_M, "the wing re-formed")
	await scene.free_scene(get_tree())


# Puts the leader on its schedule `t` seconds in: straight along `heading` at `speed`, its nose turned about `axis` over
# `FLIP_S`, and a burn back to `speed` the other way (from the turn's start when `overlap`, else from its end); and tells
# the wing where it is, as `WingDirector.refresh` does each tick.
static func _lead(scene: TurretScene, leader: Combatant, wing: Array[Combatant], heading: Vector3, axis: Vector3,
		speed: float, overlap: bool, t: float) -> void:
	var flip: float = clampf((t - SETTLE_S) / FLIP_S, 0.0, 1.0)
	var burn: float = maxf(t - SETTLE_S - (0.0 if overlap else FLIP_S), 0.0)
	var velocity: Vector3 = heading * maxf(speed - BURN_MPS2 * burn, -speed)
	leader.ship.linear_velocity = velocity
	leader.ship.angular_velocity = Vector3.ZERO
	leader.ship.global_basis = Basis.looking_at(heading, Vector3.UP).rotated(axis, PI * flip).orthonormalized()
	var at: Vector3 = leader.ship.global_position
	for c: Combatant in wing:
		var ctx: AiContext = (c.driver.brain as AiPilot).context
		ctx.leader_link_position = scene.world.to_universe(at)
		ctx.leader_link_velocity = velocity


# How far the wingman furthest from its slot is from it, m.
static func _worst(leader: Combatant, wing: Array[Combatant], slots: Array[Vector3]) -> float:
	var worst: float = 0.0
	var lead: Ship = leader.ship
	for i: int in wing.size():
		var slot: Vector3 = Formation.slot_point(lead.global_position, -lead.global_basis.z, lead.global_basis.y, slots[i])
		worst = maxf(worst, wing[i].ship.global_position.distance_to(slot))
	return worst


# Puts the wing on the leader's slots under FORM ON ME, as `WingDirector.refresh` briefs a player's wing.
static func _brief(wing: Array[Combatant], leader: Combatant, slots: Array[Vector3]) -> void:
	var ids := PackedInt64Array([leader.targetable.get_instance_id()])
	for c: Combatant in wing:
		ids.append(c.targetable.get_instance_id())
	for i: int in wing.size():
		var own: int = wing[i].targetable.get_instance_id()
		var mates := PackedInt64Array()
		for id: int in ids:
			if id != own:
				mates.append(id)
		var ctx: AiContext = (wing[i].driver.brain as AiPilot).context
		ctx.wing_ids = mates
		ctx.order = AiContext.Order.FORM_ON_ME
		ctx.leader_id = leader.targetable.get_instance_id()
		ctx.has_slot = true
		ctx.slot_offset = slots[i]


func _speed_up() -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
