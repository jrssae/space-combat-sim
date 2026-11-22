extends GutTest
## `HulkStages` and `HulkRoster` (M10-T10, D12.7, Q19): a disabled capital loses power, then control, then thrust, then drifts
## cold; its lights die as it goes; the roster lists the hulks oldest first (no cap).

const DT: float = 1.0 / 60.0


func _stages() -> HulkStages:
	var s := HulkStages.new()
	s.control_loss_s = 2.0
	s.cold_s = 6.0
	s.lights_fade_s = 3.0
	return s


func _helm() -> FlightCommand:
	var cmd := FlightCommand.new()
	cmd.main_left = 0.8
	cmd.main_right = 0.6
	cmd.retro_left = 0.2
	cmd.strafe = Vector2(0.5, -0.5)
	cmd.rot = Vector3(0.1, -0.2, 0.0)
	return cmd


func _run(s: HulkStages, seconds: float) -> Array[int]:
	var changes: Array[int] = []
	for i: int in roundi(seconds / DT):
		if s.advance(DT):
			changes.append(s.stage)
	return changes


func test_the_file_gives_the_numbers() -> void:
	var s: HulkStages = HulkStages.from_rules(7)
	assert_eq(s.control_loss_s, CapitalData.hulk_rule("control_loss_s"))
	assert_eq(s.cold_s, CapitalData.hulk_rule("cold_s"))
	assert_eq(s.lights_fade_s, CapitalData.hulk_rule("lights_fade_s"))
	assert_gt(s.cold_s, s.control_loss_s, "control goes before the drive is cold")
	assert_eq(CapitalData.hulk_rule("cap"), 0.0, "there is no cap on hulks")


func test_a_live_hull_flies_its_helm_and_nothing_moves_on() -> void:
	var s: HulkStages = _stages()
	var helm: FlightCommand = _helm()
	assert_true(s.is_live())
	assert_eq(s.shape(helm), helm, "the helm's own command")
	assert_true(s.assist_on())
	assert_false(s.advance(10.0), "no wind-down until disabled")
	assert_eq(s.thrust_level(), 1.0)
	assert_eq(s.lights_level(), 1.0)


func test_power_then_control_then_thrust_then_cold() -> void:
	var s: HulkStages = _stages()
	s.start()
	assert_eq(s.stage, HulkStages.Stage.POWER_LOST, "power goes at once")
	assert_eq(_run(s, 7.0), [HulkStages.Stage.CONTROL_LOST, HulkStages.Stage.COLD] as Array[int], "then control, then cold")
	assert_true(s.is_cold())
	assert_false(s.advance(DT), "cold stays cold")


func test_the_drive_winds_down_evenly_and_the_helm_steers_only_while_it_has_control() -> void:
	var s: HulkStages = _stages()
	s.start()
	_run(s, 1.0)
	var helm: FlightCommand = _helm()
	var out: FlightCommand = s.shape(helm)
	var level: float = s.thrust_level()
	assert_almost_eq(level, 1.0 - 1.0 / 6.0, 0.01, "a sixth gone after a second")
	assert_eq(out.rot, helm.rot, "power lost: the helm still steers on its last orders")
	assert_almost_eq(out.main_left, 0.8 * level, 1e-6, "with what the drive has left")
	assert_almost_eq(out.retro_left, 0.2 * level, 1e-6)
	assert_almost_eq(out.strafe.x, 0.5 * level, 1e-6)
	assert_true(s.assist_on())
	_run(s, 2.0)
	assert_eq(s.stage, HulkStages.Stage.CONTROL_LOST)
	out = s.shape(null)
	assert_eq(out.rot, Vector3.ZERO, "control lost: no steering")
	assert_eq(out.strafe, Vector2.ZERO)
	assert_almost_eq(out.main_left, 0.8 * s.thrust_level(), 1e-6, "the mains wind down on the last setting the helm gave")
	assert_almost_eq(out.main_right, 0.6 * s.thrust_level(), 1e-6)
	assert_false(s.assist_on(), "the assist goes with control")
	_run(s, 4.0)
	out = s.shape(helm)
	assert_eq([out.main_left, out.main_right, out.retro_left, out.retro_right], [0.0, 0.0, 0.0, 0.0], "cold: no force")
	assert_eq(out.rot, Vector3.ZERO)
	assert_eq(s.thrust_level(), 0.0)


func test_the_lights_die_stuttering_and_stay_out() -> void:
	var s: HulkStages = _stages()
	s.start()
	var levels: Array[float] = []
	var dipped: bool = false
	var brighter: int = 0
	for i: int in roundi(3.5 / DT):
		s.advance(DT)
		var level: float = s.lights_level()
		var fade: float = maxf(1.0 - s.elapsed_s / s.lights_fade_s, 0.0)
		levels.append(level)
		if level > fade + 1e-6:
			brighter += 1
		if level < 0.5 * fade:
			dipped = true
	assert_eq(brighter, 0, "never brighter than the fade allows")
	assert_true(dipped, "a dying supply stutters")
	assert_eq(levels.back(), 0.0, "out after the fade")
	_run(s, 1.0)
	assert_false(s.lights_fading(), "nothing left to change")
	var again: HulkStages = _stages()
	again._seed = s._seed
	again.start()
	for i: int in roundi(1.0 / DT):
		again.advance(DT)
	var replay: HulkStages = _stages()
	replay._seed = s._seed
	replay.start()
	for i: int in roundi(1.0 / DT):
		replay.advance(DT)
	assert_eq(again.lights_level(), replay.lights_level(), "the same ship stutters the same way")


func test_finish_is_cold_at_once_and_reset_is_live() -> void:
	var s: HulkStages = _stages()
	s.start()
	s.finish()
	assert_true(s.is_cold())
	assert_eq(s.lights_level(), 0.0)
	assert_eq(s.shape(_helm()).main_left, 0.0)
	s.reset()
	assert_true(s.is_live())
	assert_eq(s.thrust_level(), 1.0)


func test_the_roster_keeps_every_hulk_oldest_first() -> void:
	var r := HulkRoster.new()
	for key: int in [11, 12, 13, 14]:
		r.add(key)
	r.add(12)
	assert_eq(r.size(), 4, "a hulk is noted once, and none is dropped for their number")
	r.remove(11)
	assert_eq(r.keys(), PackedInt64Array([12, 13, 14]))
	assert_true(r.has(13))


func test_the_ancients_never_become_hulks() -> void:
	assert_true(CapitalData.never_hulk(&"vorlons", &"ea_omega"))
	assert_true(CapitalData.never_hulk(&"shadows", &"ea_omega"))
	assert_false(CapitalData.never_hulk(&"earth_alliance", &"ea_omega"))


func test_the_omega_struggles_to_turn_and_the_nova_does_not_out_turn_it_in_acceleration() -> void:
	var omega: ShipSpec = load("res://assets/ships/ea_omega.tres")
	var nova: ShipSpec = load("res://assets/ships/ea_nova.tres")
	# Rates are deg/s, accelerations rad/s^2 about the pitch axis (x).
	assert_lte(omega.rate_max.x, 1.0, "the Omega turns slowly")
	assert_lt(omega.rate_max.x, nova.rate_max.x, "slower than the dreadnought, which is lighter")
	var omega_acc: float = omega.rcs_torque_max.x / omega.inertia.x
	var nova_acc: float = nova.rcs_torque_max.x / nova.inertia.x
	assert_lt(omega_acc, nova_acc * 0.6, "and it is slow to start a turn")
