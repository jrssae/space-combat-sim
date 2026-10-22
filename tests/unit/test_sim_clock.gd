extends GutTest

const SimClockScript := preload("res://src/autoload/sim_clock.gd")

var clock: Node


func before_each() -> void:
	clock = SimClockScript.new()
	add_child_autofree(clock)
	clock.set_physics_process(false)  # drive it by hand
	clock.reset()


func test_advances_by_delta() -> void:
	for i: int in 60:
		clock.advance(1.0 / 60.0)
	assert_almost_eq(clock.now(), 1.0, 1e-9)


func test_time_is_64_bit() -> void:
	# A year of sim time in seconds plus one physics tick must still resolve the tick.
	clock.reset(3.15e7)
	clock.advance(1.0 / 120.0)
	assert_almost_eq(clock.now() - 3.15e7, 1.0 / 120.0, 1e-9)


func test_warp_is_fixed_at_one_in_m1() -> void:
	clock.warp = 4.0
	assert_eq(clock.warp, 1.0)
	clock.advance(0.5)
	assert_almost_eq(clock.now(), 0.5, 1e-12)


func test_autoload_is_registered() -> void:
	assert_not_null(get_tree().root.get_node_or_null("SimClock"))
	assert_not_null(get_tree().root.get_node_or_null("Settings"))
