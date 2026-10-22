extends GutTest
## AttackBrain (M2-T07, architecture §15.8): the approach / break / extend state machine on synthetic perceptions, with the
## default `RaiderTactics`. Pure: no ship, no physics.

const DT: float = 1.0 / 60.0

var tactics: RaiderTactics
var brain: AttackBrain


func before_each() -> void:
	tactics = load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics
	brain = AttackBrain.new(tactics, 99)


func _capability() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.a_main = 25.0
	cap.a_retro = 7.5
	cap.a_rcs = Vector2(8.0, 8.0)
	cap.rate_max_rad = Vector3(1.0, 0.8, 1.5)
	return cap


## A perception with the raider at the origin facing -Z and a hostile target `range_m` ahead.
func _p(range_m: float, own_velocity: Vector3 = Vector3.ZERO, target_velocity: Vector3 = Vector3.ZERO, basis: Basis = Basis.IDENTITY) -> Perception:
	var p := Perception.new()
	p.basis = basis
	p.velocity = own_velocity
	p.capability = _capability()
	p.target = TargetInfo.new(5, "DRONE", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -range_m), target_velocity)
	p.target_hostile = true
	return p


func _run(p: Perception, seconds: float) -> PilotCommand:
	var cmd: PilotCommand = null
	for i: int in roundi(seconds / DT):
		cmd = brain.think(p, DT)
	return cmd


func test_it_starts_in_approach() -> void:
	assert_eq(brain.state, AttackBrain.State.APPROACH)
	assert_eq(brain.describe()["behaviour"], "attack")
	assert_eq(brain.describe()["state"], "approach")


func test_without_a_hostile_target_it_commands_nothing() -> void:
	var p := Perception.new()
	var cmd: PilotCommand = brain.think(p, DT)
	assert_eq(cmd.flight.main_left, 0.0)
	assert_false(cmd.combat.fire)
	assert_false(cmd.flight.brake)
	p.target = TargetInfo.new(1, "BUOY", Factions.NEUTRAL, Vector3(0.0, 0.0, -500.0))
	p.target_hostile = false
	assert_false(brain.think(p, DT).combat.fire, "a neutral buoy is not an enemy")


func test_far_away_it_accelerates_toward_the_target_at_the_far_closing_speed() -> void:
	var cmd: PilotCommand = brain.think(_p(3000.0), DT)
	assert_gt(cmd.flight.main_left, 0.0, "mains on")
	assert_eq(cmd.flight.main_left, cmd.flight.main_right)
	assert_false(cmd.flight.brake)
	assert_false(cmd.combat.fire, "out of range")
	# At the far closing speed already: nothing left to do.
	var cruise: PilotCommand = brain.think(_p(3000.0, Vector3(0.0, 0.0, -tactics.closing_far_mps)), DT)
	assert_eq(cruise.flight.main_left, 0.0)
	assert_eq(cruise.flight.retro_left, 0.0)


func test_inside_the_near_range_it_slows_to_the_near_closing_speed() -> void:
	var cmd: PilotCommand = brain.think(_p(1400.0, Vector3(0.0, 0.0, -tactics.closing_far_mps)), DT)
	assert_gt(cmd.flight.retro_left, 0.0, "120 m/s is too fast inside 1 500 m: retros")
	assert_eq(cmd.flight.main_left, 0.0)


func test_it_turns_its_nose_toward_the_target() -> void:
	# The target is 30 degrees to the right: it yaws right (positive) and the nose is not on the lead yet.
	var p := _p(2000.0, Vector3(0.0, 0.0, -tactics.closing_far_mps))
	p.target = TargetInfo.new(5, "DRONE", Factions.EARTH_ALLIANCE, Vector3(1000.0, 0.0, -1732.0))
	var cmd: PilotCommand = brain.think(p, DT)
	assert_gt(cmd.flight.rot.y, 0.0, "yaw right")
	assert_false(cmd.combat.fire)


func test_it_fires_when_in_range_and_on_the_lead_and_not_before() -> void:
	var p := _p(1000.0, Vector3(0.0, 0.0, -tactics.closing_near_mps))
	assert_true(brain.think(p, DT).combat.fire, "a stationary target dead ahead: the lead is dead ahead")
	assert_true(brain.firing)
	assert_lt(brain.lead_error_deg, 0.01)
	assert_false(brain.think(_p(1300.0, Vector3(0.0, 0.0, -tactics.closing_near_mps)), DT).combat.fire, "beyond the fire range")
	var off := _p(1000.0, Vector3(0.0, 0.0, -tactics.closing_near_mps), Vector3.ZERO, Basis(Vector3.UP, deg_to_rad(5.0)))
	assert_false(brain.think(off, DT).combat.fire, "5 degrees off the lead")


func test_the_cone_tightens_with_range() -> void:
	# At 301 m the miss gate is atan(3 / 301) = 0.57 degrees: 0.4 degrees (2.1 m) fires, 0.7 degrees (3.7 m) does not.
	var close := _p(301.0, Vector3(0.0, 0.0, -tactics.closing_near_mps), Vector3.ZERO, Basis(Vector3.UP, deg_to_rad(0.4)))
	assert_true(brain.think(close, DT).combat.fire)
	brain.reset()
	var wide := _p(301.0, Vector3(0.0, 0.0, -tactics.closing_near_mps), Vector3.ZERO, Basis(Vector3.UP, deg_to_rad(0.7)))
	assert_false(brain.think(wide, DT).combat.fire)
	brain.reset()
	var far := _p(1100.0, Vector3(0.0, 0.0, -tactics.closing_near_mps), Vector3.ZERO, Basis(Vector3.UP, deg_to_rad(0.5)))
	assert_false(brain.think(far, DT).combat.fire, "0.5 degrees at 1 100 m misses by 9 m: the miss gate says no")


func test_it_breaks_off_inside_the_break_range() -> void:
	brain.think(_p(tactics.break_range_m - 10.0, Vector3(0.0, 0.0, -tactics.closing_near_mps)), DT)
	assert_eq(brain.state, AttackBrain.State.BREAK)


func test_it_breaks_off_after_eight_seconds_on_target() -> void:
	var p := _p(1100.0, Vector3(0.0, 0.0, -tactics.closing_near_mps))
	_run(p, tactics.max_time_on_target_s - 0.5)
	assert_eq(brain.state, AttackBrain.State.APPROACH)
	_run(p, 1.0)
	assert_eq(brain.state, AttackBrain.State.BREAK)


func test_time_on_target_only_counts_inside_the_fire_range() -> void:
	var p := _p(tactics.fire_range_m + 100.0, Vector3(0.0, 0.0, -tactics.closing_near_mps))
	_run(p, 20.0)
	assert_eq(brain.state, AttackBrain.State.APPROACH)


func test_the_break_flies_across_the_line_of_sight_and_does_not_fire() -> void:
	brain.think(_p(250.0, Vector3(0.0, 0.0, -60.0)), DT)
	assert_eq(brain.state, AttackBrain.State.BREAK)
	var cmd: PilotCommand = brain.think(_p(250.0, Vector3(0.0, 0.0, -60.0)), DT)
	assert_false(cmd.combat.fire)
	assert_ne(cmd.flight.rot, Vector3.ZERO, "turning away")
	assert_true(absf(cmd.flight.rot.y) > 0.0, "across the line of sight: yaw")


func test_the_break_ends_after_its_duration_and_the_extension_after_range_and_time() -> void:
	var p := _p(250.0, Vector3(0.0, 0.0, -60.0))
	brain.think(p, DT)
	assert_eq(brain.state, AttackBrain.State.BREAK)
	_run(p, tactics.break_duration_s + 0.1)
	assert_eq(brain.state, AttackBrain.State.EXTEND)
	# Long enough but still too close: stays extended.
	_run(_p(500.0), tactics.extend_min_s + 1.0)
	assert_eq(brain.state, AttackBrain.State.EXTEND)
	# Far enough but just started: another brain run in a fresh extension.
	brain.state = AttackBrain.State.EXTEND
	brain.state_time_s = 0.0
	_run(_p(tactics.extend_range_m + 100.0), tactics.extend_min_s - 0.5)
	assert_eq(brain.state, AttackBrain.State.EXTEND)
	_run(_p(tactics.extend_range_m + 100.0), 1.0)
	assert_eq(brain.state, AttackBrain.State.APPROACH, "far enough and long enough: back to the attack")
	assert_eq(brain.on_target_s, 0.0, "the new approach starts its clock afresh")


func test_extend_flies_away_from_the_target() -> void:
	brain.state = AttackBrain.State.EXTEND
	var cmd: PilotCommand = brain.think(_p(500.0, Vector3(0.0, 0.0, -50.0)), DT)
	assert_gt(cmd.flight.retro_left, 0.0, "moving toward it: reverse first")
	assert_false(cmd.combat.fire)


func test_it_never_brakes() -> void:
	for state: AttackBrain.State in [AttackBrain.State.APPROACH, AttackBrain.State.BREAK, AttackBrain.State.EXTEND]:
		brain.state = state
		for range_m: float in [100.0, 500.0, 1000.0, 3000.0]:
			assert_false(brain.think(_p(range_m, Vector3(0.0, 0.0, -80.0)), DT).flight.brake)


func test_the_same_seed_breaks_to_the_same_side_and_another_may_not() -> void:
	var sides: Array[float] = []
	for seed_value: int in [1, 2, 3, 4, 5, 6, 7, 8]:
		var b := AttackBrain.new(tactics, seed_value)
		b._enter(AttackBrain.State.BREAK)
		sides.append(b._side)
	assert_true(sides.has(1.0) and sides.has(-1.0), "both sides occur across seeds")
	var a := AttackBrain.new(tactics, 4)
	var b := AttackBrain.new(tactics, 4)
	a._enter(AttackBrain.State.BREAK)
	b._enter(AttackBrain.State.BREAK)
	assert_eq(a._side, b._side)


func test_reset_returns_to_the_start() -> void:
	brain.think(_p(100.0), DT)
	assert_eq(brain.state, AttackBrain.State.BREAK)
	brain.reset()
	assert_eq(brain.state, AttackBrain.State.APPROACH)
	assert_eq(brain.state_time_s, 0.0)
	assert_false(brain.firing)


func test_describe_reports_state_range_and_firing() -> void:
	brain.think(_p(1000.0, Vector3(0.0, 0.0, -60.0)), DT)
	var d: Dictionary = brain.describe()
	assert_eq(d["state"], "approach")
	assert_eq(d["range_m"], 1000.0)
	assert_true(d["firing"])


# --- patrol and aggro, the small ones -------------------------------------------------------------------------------


func test_patrol_takes_the_next_waypoint_within_150_m_and_loops() -> void:
	var points: Array[UniversePos] = [UniversePos.new(0.0, 0.0, -1000.0), UniversePos.new(500.0, 0.0, -1000.0)]
	var patrol := PatrolBrain.new(points, 80.0)
	var p := Perception.new()
	p.capability = _capability()
	p.position = Vector3(0.0, 0.0, -900.0)  # 100 m from the first
	patrol.think(p, DT)
	assert_eq(patrol.index, 1)
	assert_eq(patrol.reached, 1)
	p.position = Vector3(450.0, 0.0, -1000.0)
	patrol.think(p, DT)
	assert_eq(patrol.index, 0, "wrapped")
	assert_eq(patrol.reached, 2)


func test_patrol_slows_for_the_arrival_and_turns_toward_the_waypoint() -> void:
	var points: Array[UniversePos] = [UniversePos.new(0.0, 0.0, -1000.0), UniversePos.new(0.0, 0.0, -2000.0)]
	var patrol := PatrolBrain.new(points, 80.0)
	var p := Perception.new()
	p.capability = _capability()
	p.velocity = Vector3(0.0, 0.0, -80.0)
	p.position = Vector3(0.0, 0.0, -300.0)  # 700 m out: still at cruise
	assert_eq(patrol.think(p, DT).flight.retro_left, 0.0)
	p.position = Vector3(0.0, 0.0, -880.0)  # 120 m out is inside the arrival radius -> next waypoint; use 200 m out
	patrol.reset()
	p.position = Vector3(0.0, 0.0, -800.0)
	assert_gt(patrol.think(p, DT).flight.retro_left, 0.0, "200 m out at 80 m/s: the retros come on")
	var to_side := Perception.new()
	to_side.capability = _capability()
	patrol.reset()
	to_side.position = Vector3(-1000.0, 0.0, -1000.0)  # the waypoint is to the east, the nose points north
	assert_gt(patrol.think(to_side, DT).flight.rot.y, 0.0, "yaw right toward it")


func test_aggro_patrols_until_a_hostile_is_close_or_the_hull_is_hurt() -> void:
	var points: Array[UniversePos] = [UniversePos.new(0.0, 0.0, -1000.0), UniversePos.new(0.0, 0.0, -2000.0)]
	var aggro := AggroBrain.new(PatrolBrain.new(points, 80.0), AttackBrain.new(tactics, 1), 1500.0)
	var p := _p(2500.0)
	aggro.think(p, DT)
	assert_false(aggro.aggroed)
	assert_eq(aggro.describe()["state"], "patrol: waypoint 1 of 2")
	aggro.think(_p(1400.0), DT)
	assert_true(aggro.aggroed, "a hostile inside the aggro range")
	assert_string_contains(String(aggro.describe()["state"]), "attack")
	aggro.reset()
	var hurt := _p(2500.0)
	hurt.hull_fraction = 0.9
	aggro.think(hurt, DT)
	assert_true(aggro.aggroed, "hurt")
	aggro.think(_p(5000.0), DT)
	assert_true(aggro.aggroed, "and it stays angry")
