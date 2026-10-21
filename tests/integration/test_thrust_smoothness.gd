extends GutTest
## Full thrust must be smooth: no tick-to-tick kick in the velocity or the attitude (the play-test "jump at full thrust").

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await get_tree().physics_frame


func after_each() -> void:
	DebugConsole.flags.invulnerable = false


func test_full_mains_accelerate_smoothly_along_the_nose() -> void:
	source.hold(InputAdapter.MAIN_LEFT)
	source.hold(InputAdapter.MAIN_RIGHT)
	var prev_v: Vector3 = main.ship.linear_velocity
	var prev_basis: Basis = main.ship.global_basis
	var max_lateral_kick: float = 0.0
	var max_turn: float = 0.0
	var accel_min: float = INF
	var accel_max: float = 0.0
	for i: int in 600:
		await get_tree().physics_frame
		var v: Vector3 = main.ship.linear_velocity
		var dv: Vector3 = v - prev_v
		var forward: Vector3 = main.ship.forward()
		accel_min = minf(accel_min, dv.length()) if i > 5 else accel_min
		accel_max = maxf(accel_max, dv.length()) if i > 5 else accel_max
		max_lateral_kick = maxf(max_lateral_kick, (dv - forward * dv.dot(forward)).length())
		max_turn = maxf(max_turn, rad_to_deg((main.ship.global_basis * prev_basis.inverse()).get_rotation_quaternion().get_angle()))
		prev_v = v
		prev_basis = main.ship.global_basis
	gut.p("thrust: per-tick dv %.4f..%.4f m/s, worst lateral kick %.5f m/s, worst turn per tick %.5f deg" % [accel_min, accel_max, max_lateral_kick, max_turn])
	assert_lt(max_lateral_kick, 0.02, "no sideways kick")
	assert_lt(max_turn, 0.05, "no attitude kick")
	assert_lt(accel_max - accel_min, 0.05, "the acceleration is steady tick to tick")
