extends GutTest
## The main docking bay's inner doors (M7-T25): open while a ship asks, shut once none does, at the data's pace; held open or shut
## from the console; a hull's reach along its nose read from its shapes.


func test_the_doors_open_while_a_ship_asks_and_shut_when_none_does() -> void:
	var doors := AirlockDoors.new()
	doors.open_s = 3.0
	doors.close_s = 2.0
	assert_true(doors.is_shut())
	doors.ask(7)
	doors.ask(9)
	doors.step(1.5)
	assert_almost_eq(doors.fraction, 0.5, 1e-6, "half open after half the opening time")
	assert_eq(doors.state_name(), "opening")
	doors.step(2.0)
	assert_true(doors.is_open())
	doors.release(7)
	doors.step(1.0)
	assert_true(doors.is_open(), "still open: another ship asks")
	doors.release(9)
	doors.release(9)  # letting go twice is harmless
	doors.step(1.0)
	assert_almost_eq(doors.fraction, 0.5, 1e-6, "closing at its own pace")
	assert_eq(doors.state_name(), "closing")
	doors.step(5.0)
	assert_true(doors.is_shut())
	assert_eq(doors.asking(), 0)


func test_the_console_holds_them_open_or_shut() -> void:
	var doors := AirlockDoors.new()
	doors.mode = AirlockDoors.Mode.OPEN
	doors.step(10.0)
	assert_true(doors.is_open(), "held open with nobody asking")
	doors.ask(1)
	doors.mode = AirlockDoors.Mode.SHUT
	doors.step(10.0)
	assert_true(doors.is_shut(), "held shut though a ship asks")
	doors.mode = AirlockDoors.Mode.AUTO
	doors.step(10.0)
	assert_true(doors.is_open(), "back to the asks")


func test_a_hulls_reach_along_its_nose_comes_from_its_shapes() -> void:
	var body := RigidBody3D.new()
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	(box.shape as BoxShape3D).size = Vector3(10.0, 4.0, 20.0)
	box.position = Vector3(0.0, 0.0, -5.0)  # the box reaches 15 m ahead (-Z) and 5 m behind
	body.add_child(box)
	var owner_id: int = body.create_shape_owner(body)  # a lean ship's shape owner, without a node
	var capsule := CapsuleShape3D.new()
	capsule.radius = 2.0
	capsule.height = 10.0
	body.shape_owner_add_shape(owner_id, capsule)
	body.shape_owner_set_transform(owner_id, Transform3D(Basis(Vector3.RIGHT, 0.5 * PI), Vector3(0.0, 0.0, 6.0)))  # along z, to 11 m aft
	add_child_autofree(body)
	var reach: Vector2 = StationAirlock.hull_reach(body)
	assert_almost_eq(reach.x, 15.0, 1e-4, "ahead")
	assert_almost_eq(reach.y, 11.0, 1e-4, "behind")
