extends GutTest
## FireLane (M3-T05, the AI half of AC3, architecture §16 D31): a friendly within its radius plus 5 m of the bolt path,
## short of the target, closes the lane; with friendly fire on, so does any other ship that is not hostile. The target
## itself, hostiles, contacts behind the shooter or beyond the target, and props never do. `AttackBrain` holds the trigger
## only with a clear lane, in both settings.

const DT: float = 1.0 / 60.0
const RANGE_M: float = 800.0
const TARGET_ID: int = 42


func _contact(position: Vector3, relation: Factions.Relation, radius: float = 10.0, is_ship: bool = true, id: int = 7) -> Contact:
	var c := Contact.new()
	c.id = id
	c.position = position
	c.relation = relation
	c.bounding_radius = radius
	c.is_ship = is_ship
	return c


func _clear(contacts: Array[Contact], friendly_fire: bool = false) -> bool:
	return FireLane.clear(Vector3.ZERO, Vector3.FORWARD, RANGE_M, contacts, TARGET_ID, friendly_fire)


func test_an_empty_lane_is_clear() -> void:
	var none: Array[Contact] = []
	assert_true(_clear(none))
	assert_true(_clear(none, true))


func test_a_friendly_in_the_lane_short_of_the_target_closes_it_in_both_settings() -> void:
	var lane: Array[Contact] = [_contact(Vector3(3.0, 0.0, -400.0), Factions.Relation.FRIENDLY)]
	assert_false(_clear(lane), "friendly fire off")
	assert_false(_clear(lane, true), "friendly fire on")


func test_the_lane_is_the_friendlys_radius_plus_5_m_wide() -> void:
	var radius: float = 10.0
	var inside: Array[Contact] = [_contact(Vector3(radius + FireLane.CLEARANCE_M - 0.1, 0.0, -400.0), Factions.Relation.FRIENDLY, radius)]
	var outside: Array[Contact] = [_contact(Vector3(0.0, radius + FireLane.CLEARANCE_M + 0.1, -400.0), Factions.Relation.FRIENDLY, radius)]
	assert_false(_clear(inside), "just inside")
	assert_true(_clear(outside), "just outside")


func test_only_contacts_between_the_shooter_and_the_target_count() -> void:
	var behind: Array[Contact] = [_contact(Vector3(0.0, 0.0, 50.0), Factions.Relation.FRIENDLY)]
	var beyond: Array[Contact] = [_contact(Vector3(0.0, 0.0, -RANGE_M - 50.0), Factions.Relation.FRIENDLY)]
	assert_true(_clear(behind), "behind the shooter")
	assert_true(_clear(beyond), "beyond the target")


func test_the_target_and_hostiles_never_close_the_lane() -> void:
	var target: Array[Contact] = [_contact(Vector3(0.0, 0.0, -RANGE_M + 1.0), Factions.Relation.FRIENDLY, 10.0, true, TARGET_ID)]
	var hostile: Array[Contact] = [_contact(Vector3(0.0, 0.0, -300.0), Factions.Relation.HOSTILE)]
	for ff: bool in [false, true]:
		assert_true(_clear(target, ff), "the target itself (friendly fire %s)" % ff)
		assert_true(_clear(hostile, ff), "a hostile in the way is fair game (friendly fire %s)" % ff)


func test_a_neutral_ship_closes_the_lane_only_with_friendly_fire_on() -> void:
	var lane: Array[Contact] = [_contact(Vector3(0.0, 0.0, -400.0), Factions.Relation.NEUTRAL)]
	assert_true(_clear(lane), "off: the bolt passes through it")
	assert_false(_clear(lane, true), "on: the bolt would hit it")


func test_a_prop_never_closes_the_lane() -> void:
	var buoy: Array[Contact] = [_contact(Vector3(0.0, 0.0, -400.0), Factions.Relation.NEUTRAL, 2.0, false)]
	assert_true(_clear(buoy))
	assert_true(_clear(buoy, true))


func test_a_zero_aim_direction_or_range_does_not_fail() -> void:
	var lane: Array[Contact] = [_contact(Vector3(0.0, 0.0, -400.0), Factions.Relation.FRIENDLY)]
	assert_true(FireLane.clear(Vector3.ZERO, Vector3.ZERO, RANGE_M, lane, TARGET_ID), "no aim, no lane")
	assert_true(FireLane.clear(Vector3.ZERO, Vector3.FORWARD, 0.0, lane, TARGET_ID), "no range, no lane")


# --- AttackBrain ----------------------------------------------------------------------------------------------------


func _capability() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 25.0
	cap.a_retro = 7.5
	cap.a_rcs = Vector2(8.0, 8.0)
	cap.rate_max_rad = Vector3(1.0, 0.8, 1.5)
	return cap


## A raider at the origin, nose on a stationary hostile 800 m dead ahead at the near closing speed: it fires (M2).
func _perception(contacts: Array[Contact], friendly_fire: bool) -> Perception:
	var tactics := load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	var p := Perception.new()
	p.velocity = Vector3(0.0, 0.0, -tactics.closing_near_mps)
	p.capability = _capability()
	p.target = TargetInfo.new(TARGET_ID, "DRONE", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -RANGE_M))
	p.target_hostile = true
	p.contacts = contacts
	p.friendly_fire = friendly_fire
	return p


func test_the_attack_brain_holds_fire_while_a_friendly_is_in_its_lane_in_both_settings() -> void:
	var tactics := load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	var target := _contact(Vector3(0.0, 0.0, -RANGE_M), Factions.Relation.HOSTILE, 3.0, true, TARGET_ID)
	var clear_lane: Array[Contact] = [target]
	var blocked_lane: Array[Contact] = [target, _contact(Vector3(2.0, 0.0, -300.0), Factions.Relation.FRIENDLY)]
	for ff: bool in [false, true]:
		var brain := AttackBrain.new(tactics, 5)
		assert_true(brain.think(_perception(clear_lane, ff), DT).combat.fire, "a clear lane: it fires (friendly fire %s)" % ff)
		var held := AttackBrain.new(tactics, 5)
		var cmd: PilotCommand = held.think(_perception(blocked_lane, ff), DT)
		assert_false(cmd.combat.fire, "a friendly in the lane: no fire (friendly fire %s)" % ff)
		assert_false(held.firing)
		assert_almost_eq(held.lead_error_deg, 0.0, 1e-3, "even with the nose on the lead")
