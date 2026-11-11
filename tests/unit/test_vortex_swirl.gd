extends GutTest
## Which way a jump vortex turns and travels (M6-T19 round 3): seen from in front of the mouth an arrival turns counter-clockwise
## and travels out, a departure turns clockwise and travels in; the enum matches `JumpVortex.Direction`.


func test_the_directions_match_the_vortex_enum() -> void:
	assert_eq(VortexSwirl.ARRIVAL, int(JumpVortex.Direction.ARRIVAL))
	assert_eq(VortexSwirl.DEPARTURE, int(JumpVortex.Direction.DEPARTURE))


func test_an_arrival_turns_counter_clockwise_and_travels_out() -> void:
	assert_eq(VortexSwirl.turn_from_front(VortexSwirl.ARRIVAL), 1.0, "counter-clockwise from in front")
	assert_eq(VortexSwirl.radial(VortexSwirl.ARRIVAL), 1.0, "out toward the rim")


func test_a_departure_turns_clockwise_and_travels_in() -> void:
	assert_eq(VortexSwirl.turn_from_front(VortexSwirl.DEPARTURE), -1.0, "clockwise from in front")
	assert_eq(VortexSwirl.radial(VortexSwirl.DEPARTURE), -1.0, "in toward the throat")


func test_the_mesh_angle_runs_the_other_way_to_the_front_view() -> void:
	# A camera in front looks along +Z with +Y up: its right is the funnel's -X.
	var camera := Basis.looking_at(Vector3.BACK, Vector3.UP)
	assert_almost_eq(camera.x.dot(Vector3.RIGHT), -1.0, 1e-6)
	for direction: int in [VortexSwirl.ARRIVAL, VortexSwirl.DEPARTURE]:
		assert_eq(VortexSwirl.turn_in_mesh(direction), -VortexSwirl.turn_from_front(direction))


func test_a_patch_on_screen_turns_the_way_its_direction_says() -> void:
	for direction: int in [VortexSwirl.ARRIVAL, VortexSwirl.DEPARTURE]:
		for start: float in [0.0, 1.3, 4.0]:
			var before: Vector2 = VortexSwirl.seen_from_front(start, 0.0, direction)
			var after: Vector2 = VortexSwirl.seen_from_front(start, 0.2, direction)
			# Positive with x right and y up: counter-clockwise on screen.
			var turned: float = before.angle_to(after)
			assert_almost_eq(turned, 0.2 * VortexSwirl.turn_from_front(direction), 1e-5)
