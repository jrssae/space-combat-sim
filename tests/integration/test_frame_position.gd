extends GutTest
## Where round the body `frame orbit` and `frame drop` put the player (M7-T68, maintainer 2026-11-17): `day`, `night`, `dawn` and
## `dusk` against the star as the sky draws it (`scaled epoch` included), or an angle round the orbit; the day side by default;
## an altitude at or inside the atmosphere is refused with the floor named.

const SCENARIO: String = "res://data/scenarios/free_flight.json"
const PLANET: StringName = &"epsilon_iii"
## Two looks at the sky far enough apart that the star stands some 80 degrees round from the first (a 187-day year).
const EPOCHS_H: Array[float] = [0.0, 1000.0]

var main: Main
var world: WorldFrame


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = SCENARIO
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	world = main.world
	for i: int in 70:
		await get_tree().physics_frame


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


# The unit direction to the star as the scaled-space layer draws it now, from the camera beside the player.
func _to_star() -> Vector3:
	var layer: ScaledSpace = main.space_environment.scaled_space
	layer.refresh(get_viewport().get_camera_3d())
	assert_true(layer.has_sun(), "the layer draws the star")
	return layer.sun_direction()


# The player's direction from the planet's centre and its velocity against the planet (64-bit sums).
func _from_planet() -> Array:
	var planet: PackedFloat64Array = world.body_state(PLANET)
	var at: Vector3 = main.ship.global_position
	var out := Vector3(at.x - planet[0], at.y - planet[1], at.z - planet[2]).normalized()
	return [out, main.ship.linear_velocity - Vector3(planet[3], planet[4], planet[5])]


func test_each_position_stands_where_it_should_against_the_star_at_two_epochs() -> void:
	await _start()
	var days: Array[Vector3] = []
	for epoch_h: float in EPOCHS_H:
		assert_true(_run("scaled epoch %s" % epoch_h).ok)
		var system: StarSystem = world.star_system
		var old: float = wrapf(180.0 - world.sunward_deg(system, PLANET), -180.0, 180.0)
		gut.p("epoch +%s h: the sub-solar point %.1f deg round from +X, where the orbit used to start (%.1f deg from the night side's middle)" % [
				epoch_h, world.sunward_deg(system, PLANET), old])
		for word: String in ["day", "night", "dawn", "dusk", ""]:
			var result: ConsoleResult = _run(("frame orbit 400 %s" % word).strip_edges())
			assert_true(result.ok, result.error)
			var star: Vector3 = _to_star()
			var seen: Array = _from_planet()
			var out: Vector3 = seen[0]
			var travel: Vector3 = (seen[1] as Vector3).normalized()
			var facing: float = out.dot(star)
			var turn: float = out.cross(star).y
			gut.p("epoch +%s h, %s: out.star %.3f, (out x star).y %.3f, travel.star %.3f" % [epoch_h, word if word != "" else "(none)",
					facing, turn, travel.dot(star)])
			match word:
				"day", "":
					assert_gt(facing, 0.9, "%s at +%s h: the sub-solar side" % [word, epoch_h])
				"night":
					assert_lt(facing, -0.9, "night at +%s h: the far side" % epoch_h)
				"dawn":
					assert_almost_eq(facing, 0.0, 0.1, "dawn at +%s h: on the terminator" % epoch_h)
					assert_gt(turn, 0.9, "dawn: behind the sub-solar point")
					assert_gt(travel.dot(star), 0.9, "dawn: the orbit carries the player sunward, into daylight")
				"dusk":
					assert_almost_eq(facing, 0.0, 0.1, "dusk at +%s h: on the terminator" % epoch_h)
					assert_lt(turn, -0.9, "dusk: ahead of the sub-solar point")
					assert_lt(travel.dot(star), -0.9, "dusk: the orbit carries the player away from the star, into night")
			if word == "day":
				days.append(out)
	assert_lt(days[0].dot(days[1]), cos(deg_to_rad(30.0)), "the day side follows the star as the epoch moves it")
	await get_tree().physics_frame
	assert_true(main.player_alive, "no orbit destroyed the ship")


func test_an_angle_moves_the_player_round_the_orbit() -> void:
	await _start()
	assert_true(_run("frame orbit 400 0").ok)
	var start: Array = _from_planet()
	assert_true(_run("frame orbit 400 epsilon_iii 45").ok, "the body may be named before the angle")
	var later: Vector3 = _from_planet()[0]
	assert_almost_eq(rad_to_deg((start[0] as Vector3).angle_to(later)), 45.0, 0.01, "45 degrees round")
	assert_gt((later - start[0]).dot(start[1]), 0.0, "ahead, the way the orbit travels")
	assert_true(_run("frame orbit 400 -90").ok)
	var behind: Vector3 = _from_planet()[0]
	assert_true(_run("frame orbit 400 dawn").ok)
	assert_almost_eq(behind.dot(_from_planet()[0]), 1.0, 1e-6, "-90 degrees is dawn")
	assert_true(_run("frame drop 400 night").ok, "a drop takes a position too")
	assert_lt(_from_planet()[0].dot(_to_star()), -0.9, "and stands on the night side")


func test_an_altitude_inside_the_atmosphere_is_refused() -> void:
	await _start()
	for line: String in ["frame orbit 100", "frame orbit 40 night", "frame drop 100", "frame drop 0"]:
		var result: ConsoleResult = _run(line)
		assert_false(result.ok, "%s: refused" % line)
		assert_string_contains(result.error, "Epsilon III's atmosphere (100 km): pick more than 100 km")
	assert_eq(world.impact.destroyed, 0, "nothing hit the planet")
	assert_true(_run("frame orbit 101").ok, "just above the atmosphere is taken")
	for i: int in 120:
		await get_tree().physics_frame
	assert_true(main.player_alive, "and the ship lives on it")
	assert_eq(world.impact.destroyed, 0)


func test_words_that_are_not_a_position_or_misplaced_are_refused() -> void:
	await _start()
	assert_false(_run("frame orbit 400 noon").ok, "an unknown word")
	assert_false(_run("frame orbit 400 epsilon_iii noon").ok, "an unknown word after the body")
	assert_false(_run("frame orbit 400 day epsilon_iii").ok, "the body comes before the position")
	assert_false(_run("frame drop 1000000 epsilon day").ok, "the star has no day side")
	assert_true(_run("frame drop 1000000 epsilon 30").ok, "round the star an angle is fine")
