extends GutTest
## The roll-up bay doors' pure rules (M10-T22, Q58): the shutter's frame, its slats as it winds up into the housing, and how
## fast it rolls.

const DOOR: Dictionary = {"name": "bay_fury_1_r_door", "position": [10.0, 5.0, 2.0], "forward": [1.0, 0.0, 0.0],
		"up": [0.0, 1.0, 0.0], "size_m": [18.0, 10.0, 0.2], "slats": 10}


func test_the_bay_comes_from_the_doors_name() -> void:
	assert_eq(BayDoors.bay_of("bay_fury_1_r_door"), "bay_fury_1_r")


func test_the_shutter_faces_out_of_the_bay_and_rolls_up() -> void:
	var f: Transform3D = BayDoors.frame(DOOR)
	assert_eq(f.origin, Vector3(10.0, 5.0, 2.0))
	assert_almost_eq(f.basis.z.dot(Vector3.RIGHT), 1.0, 1e-5, "its face looks out of the mouth")
	assert_almost_eq(f.basis.y.dot(Vector3.UP), 1.0, 1e-5, "it rolls up")


func test_a_shut_door_covers_the_mouth_with_every_slat() -> void:
	var shut: Array[Vector2] = BayDoors.slats(DOOR, 0.0)
	assert_eq(shut.size(), 10)
	assert_almost_eq(shut[0].x - 0.5 * shut[0].y, -5.0, 1e-4, "the bottom slat sits on the sill")
	assert_almost_eq(shut[9].y, 0.9, 1e-4, "a slat less its groove")


func test_opening_winds_the_slats_up_into_the_housing() -> void:
	var half: Array[Vector2] = BayDoors.slats(DOOR, 0.5)
	assert_eq(half.size(), 5, "half the slats are in the housing")
	assert_almost_eq(half[0].x - 0.5 * half[0].y, 0.0, 1e-4, "the bottom slat halfway up")
	for s: Vector2 in half:
		assert_true(s.x + 0.5 * s.y <= 5.0 + 1e-4, "nothing above the housing's lip")
	var cut: Array[Vector2] = BayDoors.slats(DOOR, 0.05)
	assert_almost_eq(cut[-1].y, 0.5, 1e-4, "the top slat is cut where it enters the housing")
	assert_true(BayDoors.slats(DOOR, 1.0).is_empty(), "open, the whole shutter is rolled up")


func test_a_dark_plate_backs_the_slats_so_no_light_shows_through() -> void:
	var shut: Vector2 = BayDoors.backing(DOOR, 0.0)
	assert_almost_eq(shut, Vector2(0.0, 10.0), Vector2.ONE * 1e-4, "shut, it backs the whole shutter")
	var half: Vector2 = BayDoors.backing(DOOR, 0.5)
	assert_almost_eq(half.x - 0.5 * half.y, 0.0, 1e-4, "half open, from the bottom slat")
	assert_almost_eq(half.x + 0.5 * half.y, 5.0, 1e-4, "to the housing's lip")
	assert_eq(BayDoors.backing(DOOR, 1.0).y, 0.0, "open, nothing")


func test_the_roll_takes_its_time_and_stops_at_the_target() -> void:
	assert_almost_eq(BayDoors.advance(0.0, 1.0, BayDoors.ROLL_SECONDS * 0.5), 0.5, 1e-5)
	assert_eq(BayDoors.advance(0.9, 1.0, 5.0), 1.0)
	assert_eq(BayDoors.advance(0.1, 0.0, 5.0), 0.0)


func test_a_hull_without_doors_lists_none() -> void:
	assert_true(BayDoors.doors_of({}).is_empty())
	assert_eq(BayDoors.doors_of({"doors": [DOOR]}).size(), 1)


func test_the_bays_light_is_found_by_its_name_and_sits_in_the_doors_frame() -> void:
	var light: Dictionary = {"name": "bay_fury_1_r_light", "position": [4.0, 5.0, 2.0], "role": "bay"}
	var hp: Dictionary = {"lights": [{"name": "bay_fury_2_r_light"}, light]}
	assert_eq(BayDoors.light_of(hp, "bay_fury_1_r"), light)
	assert_true(BayDoors.light_of(hp, "bay_shuttle").is_empty(), "a bay with no light")
	assert_true(BayDoors.light_of({}, "bay_fury_1_r").is_empty())
	var at: Vector3 = BayDoors.light_offset(DOOR, light)
	assert_almost_eq(at.z, -6.0, 1e-4, "behind the shutter, in the hall")
	assert_almost_eq(BayDoors.frame(DOOR) * at, Vector3(4.0, 5.0, 2.0), Vector3.ONE * 1e-4)


func test_a_shut_door_keeps_its_bay_dark_and_the_light_grows_as_it_opens() -> void:
	assert_eq(BayDoors.light_energy(0.0), 0.0, "shut: no light leaks onto the hull")
	assert_almost_eq(BayDoors.light_energy(0.5), 0.5 * BayDoors.LIGHT_ENERGY, 1e-6)
	assert_eq(BayDoors.light_energy(1.0), BayDoors.LIGHT_ENERGY)
	assert_eq(BayDoors.light_energy(2.0), BayDoors.LIGHT_ENERGY)


func test_a_door_node_lights_its_hall_only_while_open() -> void:
	var light: Dictionary = {"name": "bay_fury_1_r_light", "position": [4.0, 5.0, 2.0], "colour": [0.75, 0.02, 0.01], "range_m": 68.0}
	var node: BayDoorNode = BayDoorNode.create(DOOR, light)
	assert_not_null(node.emitter)
	assert_eq(node.emitter.energy, 0.0, "shut by default")
	assert_eq(node.emitter.omni_range, 68.0)
	node.snap(true)
	assert_eq(node.emitter.energy, BayDoors.LIGHT_ENERGY, "open, the hall is lit red")
	node.snap(false)
	assert_eq(node.emitter.energy, 0.0)
	node.free()
	var dark: BayDoorNode = BayDoorNode.create(DOOR)
	assert_null(dark.emitter, "no light in the hardpoints, no emitter")
	dark.free()


func test_a_door_rolled_open_in_fixed_frames_is_fully_open() -> void:
	# M10-T53: 60 frames a second left it a rounding short of 1, and the hangar, which waits for 1, launched nothing.
	for fps: float in [60.0, 120.0, 144.0, 480.0]:
		var node: BayDoorNode = BayDoorNode.create(DOOR)
		node.set_open(true)
		var frames: int = 0
		while node.is_processing() and frames < 10000:
			node._process(1.0 / fps)
			frames += 1
		assert_eq(node.amount, 1.0, "fully open at %d frames a second" % int(fps))
		node.set_open(false)
		while node.is_processing() and frames < 20000:
			node._process(1.0 / fps)
			frames += 1
		assert_eq(node.amount, 0.0, "and fully shut")
		node.free()
