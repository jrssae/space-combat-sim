extends GutTest
## The strike carrier's pure logic (M12-T19): the compound collision read from a manifest (`CompoundCollision`), the cradles'
## bookkeeping (`CarrierCradles`), the carrier's decisions (`CarrierTactics`) and the native docking rows (`ScsDockRows`).

const SECTION: Dictionary = {
	"budget": {"max_pieces": 64, "max_hull_points": 32},
	"pieces": [
		{"name": "core", "shapes": [
			{"name": "slab", "type": "box", "position": [0.0, 1.0, 2.0], "size": [4.0, 2.0, 6.0],
					"basis": {"x": [1.0, 0.0, 0.0], "y": [0.0, 1.0, 0.0], "z": [0.0, 0.0, 1.0]}},
			{"name": "arm", "type": "capsule", "position": [5.0, 0.0, 0.0], "radius": 0.5, "height": 4.0, "axis": "z",
					"basis": {"x": [0.0, 1.0, 0.0], "y": [0.0, 0.0, 1.0], "z": [1.0, 0.0, 0.0]}},
		]},
		{"name": "ring", "shapes": [
			{"name": "sector", "type": "hull", "position": [0.0, 10.0, 0.0],
					"points": [[-1.0, 9.0, -1.0], [1.0, 9.0, -1.0], [1.0, 11.0, -1.0], [-1.0, 11.0, -1.0], [0.0, 10.0, 1.0]],
					"box": {"position": [0.0, 10.0, 0.0], "size": [2.0, 2.0, 2.0],
							"basis": {"x": [1.0, 0.0, 0.0], "y": [0.0, 1.0, 0.0], "z": [0.0, 0.0, 1.0]}}},
			{"name": "broken", "type": "hull", "position": [0.0, 0.0, 0.0], "points": [[0.0, 0.0, 0.0]]},
		]},
	],
}

const CRADLES: Array = [
	{"name": "top", "position": [0.0, 40.0, 10.0], "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0], "approach_from": [0.0, 100.0, 10.0]},
	{"name": "side_r", "position": [40.0, 0.0, 10.0], "forward": [0.0, 0.0, -1.0], "up": [1.0, 0.0, 0.0], "approach_from": [100.0, 0.0, 10.0]},
	{"name": "no_position"},
]


# --- the compound collision -------------------------------------------------------------------------------------------


func test_solids_are_jolts_shapes_piece_by_piece() -> void:
	var solids: Array[Dictionary] = CompoundCollision.solids(SECTION)
	assert_eq(solids.size(), 3, "the malformed hull is skipped")
	assert_eq(CompoundCollision.piece_names(SECTION), PackedStringArray(["core", "ring"]))
	assert_true(solids[0]["shape"] is BoxShape3D)
	assert_eq((solids[0]["shape"] as BoxShape3D).size, Vector3(4.0, 2.0, 6.0))
	assert_eq((solids[0]["transform"] as Transform3D).origin, Vector3(0.0, 1.0, 2.0))
	assert_eq(solids[0]["piece"], "core")
	var capsule: CapsuleShape3D = solids[1]["shape"]
	assert_almost_eq(capsule.height, 4.0, 1e-6)
	# Its length (Godot's +Y) lies along the entry's local z, which the basis turns onto World +X.
	assert_almost_eq(((solids[1]["transform"] as Transform3D).basis.y - Vector3.RIGHT).length(), 0.0, 1e-5)
	assert_true(solids[2]["shape"] is ConvexPolygonShape3D, "a hull collides as itself")
	assert_eq((solids[2]["shape"] as ConvexPolygonShape3D).points.size(), 5)
	assert_eq(solids[2]["piece"], "ring")


func test_hit_volumes_are_boxes_and_capsules_only() -> void:
	var volumes: Array[Dictionary] = CompoundCollision.hit_volumes(SECTION)
	assert_eq(volumes.size(), 3)
	for volume: Dictionary in volumes:
		assert_not_null(HitShape.from_collision(volume), "%s is a hit shape" % volume["name"])
	assert_true(volumes[2]["shape"] is BoxShape3D, "a hull is hit as its bounding box")
	assert_eq(volumes[2]["name"], "sector")
	assert_eq((volumes[2]["transform"] as Transform3D).origin, Vector3(0.0, 10.0, 0.0))
	assert_eq(CompoundCollision.solids({}).size(), 0, "no section, no shapes")


# --- the cradles ------------------------------------------------------------------------------------------------------


func test_cradles_are_read_from_the_hardpoints() -> void:
	var cradles: CarrierCradles = CarrierCradles.from_hardpoints(CRADLES)
	assert_eq(cradles.count(), 2, "an entry without a position is skipped")
	assert_eq(cradles.names[1], "side_r")
	assert_almost_eq(cradles.approach_m[0], 60.0, 1e-4)
	assert_almost_eq((cradles.bases[1].y - Vector3.RIGHT).length(), 0.0, 1e-5, "the fighter's back points out")
	assert_almost_eq((cradles.bases[1].z - Vector3.BACK).length(), 0.0, 1e-5, "its nose to the carrier's bow")
	assert_almost_eq((cradles.approach_point(1) - Vector3(100.0, 0.0, 10.0)).length(), 0.0, 1e-4)
	var rest: Vector3 = CarrierCradles.rest_point(AABB(Vector3(-8.5, -0.8, -4.3), Vector3(17.0, 2.0, 7.2)), 0.05)
	assert_almost_eq((rest - Vector3(0.0, -0.85, -0.7)).length(), 0.0, 1e-5)
	var docked: Transform3D = cradles.docked_transform(0, rest)
	assert_almost_eq((docked * rest - Vector3(0.0, 40.0, 10.0)).length(), 0.0, 1e-5, "its resting point is on the pad")


func test_cradles_track_who_is_where() -> void:
	var cradles: CarrierCradles = CarrierCradles.from_hardpoints(CRADLES)
	assert_eq(cradles.count_in(CarrierCradles.State.FREE), 2)
	assert_eq(cradles.nearest_free(Vector3(500.0, 0.0, 0.0)), 1, "the cradle on its side")
	cradles.set_state(1, CarrierCradles.State.BUSY)
	assert_eq(cradles.nearest_free(Vector3(500.0, 0.0, 0.0)), 0, "the next free one")
	cradles.set_state(0, CarrierCradles.State.DOCKED)
	assert_eq(cradles.nearest_free(Vector3.ZERO), -1)
	assert_eq(cradles.first_in(CarrierCradles.State.DOCKED), 0)
	assert_eq(cradles.count_in(CarrierCradles.State.BUSY), 1)
	cradles.set_state(7, CarrierCradles.State.FREE)  # out of range: ignored
	assert_eq(cradles.count_in(CarrierCradles.State.FREE), 0)


# --- the carrier's decisions ------------------------------------------------------------------------------------------


func test_options_fill_in_and_stay_in_range() -> void:
	var o: Dictionary = CarrierTactics.options({"arrival": "docked", "retreat_hull": 7.0, "wait_s": -3.0, "class": "cruiser"})
	assert_eq(o["arrival"], "docked")
	assert_eq(o["retreat_hull"], 1.0)
	assert_eq(o["wait_s"], 0.0)
	assert_eq(o["standoff_m"], 2500.0, "the default")
	assert_eq(o["class"], "cruiser", "other keys are kept")
	assert_eq(CarrierTactics.options({"arrival": "sideways"})["arrival"], "beside", "anything else is beside")


func test_it_hangs_back_from_an_enemy_inside_its_stand_off() -> void:
	assert_eq(CarrierTactics.cruise(Vector3(0.0, 0.0, -4000.0), true, 2500.0, 30.0), Vector3.ZERO, "outside: it holds")
	assert_eq(CarrierTactics.cruise(Vector3.ZERO, false, 2500.0, 30.0), Vector3.ZERO, "no enemy: it holds")
	var away: Vector3 = CarrierTactics.cruise(Vector3(0.0, 0.0, -1500.0), true, 2500.0, 30.0)
	assert_almost_eq((away - Vector3(0.0, 0.0, 30.0)).length(), 0.0, 1e-4, "well inside: away at full speed")
	var easing: Vector3 = CarrierTactics.cruise(Vector3(0.0, 0.0, -2400.0), true, 2500.0, 30.0)
	assert_between(easing.z, 1.0, 29.0, "just inside: it eases off")


func test_it_shows_an_attacker_its_stern() -> void:
	assert_eq(CarrierTactics.heading(Vector3(0.0, 0.0, -4000.0), true, 2500.0), Vector3.ZERO, "outside its stand-off it keeps its heading")
	assert_almost_eq((CarrierTactics.heading(Vector3(1000.0, 0.0, 0.0), true, 2500.0) - Vector3.LEFT).length(), 0.0, 1e-5)
	var rate: Vector3 = CarrierTactics.turn_rate(Vector3.FORWARD, Vector3.LEFT, 0.07)
	assert_almost_eq((rate - Vector3(0.0, 0.07, 0.0)).length(), 0.0, 1e-5, "a turn to port about +Y, at its limit")
	assert_eq(CarrierTactics.turn_rate(Vector3.FORWARD, Vector3.ZERO, 0.07), Vector3.ZERO, "no heading to hold")
	assert_gt(CarrierTactics.turn_rate(Vector3.FORWARD, Vector3.BACK, 0.07).length(), 0.06, "dead astern: it still turns")
	assert_lt(CarrierTactics.turn_rate(Vector3.FORWARD, Vector3(0.01, 0.0, -1.0), 0.07).length(), 0.01, "nearly there: it eases")


func test_when_it_recalls_and_when_it_leaves() -> void:
	assert_false(CarrierTactics.should_recall(0.8, 0.5, false))
	assert_true(CarrierTactics.should_recall(0.49, 0.5, false), "hurt past its threshold")
	assert_true(CarrierTactics.should_recall(1.0, 0.5, true), "the raid is over")
	assert_false(CarrierTactics.raid_over(false, 100.0, 0.0, 4, 2), "no time limit, fighters still out")
	assert_true(CarrierTactics.raid_over(false, 100.0, 90.0, 4, 2), "past its time limit")
	assert_true(CarrierTactics.raid_over(true, 1.0, 0.0, 4, 4), "ended by its script")
	assert_true(CarrierTactics.raid_over(false, 1.0, 0.0, 4, 0), "no fighter left flying")
	assert_false(CarrierTactics.raid_over(false, 1.0, 0.0, 0, 0), "it brought none: nothing to wait out")
	assert_false(CarrierTactics.should_leave(2, 10.0, 45.0), "it waits for its fighters")
	assert_true(CarrierTactics.should_leave(0, 10.0, 45.0), "all home")
	assert_true(CarrierTactics.should_leave(2, 45.0, 45.0), "it has waited long enough")


# --- the native docking rows ------------------------------------------------------------------------------------------


func _step(rows: ScsDockRows, at: Vector3, velocity: Vector3, carrier_velocity: Vector3 = Vector3.ZERO) -> Array:
	return rows.step(1.0 / 60.0, Vector3.ZERO, Basis.IDENTITY, carrier_velocity, Vector3.ZERO, 150.0, PackedVector3Array([at]),
			PackedVector3Array([velocity]), PackedFloat32Array([20.0]))


func test_a_launch_runs_from_the_pad_to_its_release() -> void:
	var rows := ScsDockRows.new()
	var numbers: PackedFloat64Array = rows.constants()
	rows.add(7, CarrierDock.PHASE_LAUNCH, Vector3(0.0, 40.0, 10.0), Basis.IDENTITY, 60.0, Vector3(0.0, -0.8, 0.0))
	assert_eq(rows.count(), 1)
	assert_eq(rows.keys(), PackedInt64Array([7]))
	assert_eq(rows.phase_of(7), 0)
	var out: Array = _step(rows, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -30.0))
	assert_almost_eq((out[1][0] as Vector3).y, 40.8, 0.01, "it starts on its pad")
	var ticks: int = 1
	while (out[0] as PackedInt32Array)[0] == 0 and ticks < 600:
		out = _step(rows, Vector3.ZERO, Vector3.ZERO, Vector3(0.0, 0.0, -30.0))
		ticks += 1
	assert_eq((out[0] as PackedInt32Array)[0], CarrierDock.EVENT_RELEASED)
	assert_almost_eq(float(ticks) / 60.0, numbers[0], 0.05, "after the launch time")
	assert_almost_eq((out[1][0] as Vector3).y, 40.8 + numbers[2], 0.01, "at the release height")
	assert_almost_eq((out[2][0] as Vector3).z, -30.0, 1e-3, "with the carrier's velocity")
	assert_gt((out[2][0] as Vector3).y, 20.0, "and the push outward")
	assert_eq(rows.count(), 0, "a released row is gone")


func test_a_return_ends_at_the_approach_point_and_a_capture_on_the_pad() -> void:
	var rows := ScsDockRows.new()
	rows.add(3, CarrierDock.PHASE_RETURN, Vector3(0.0, 40.0, 10.0), Basis.IDENTITY, 60.0, Vector3(0.0, -0.8, 0.0))
	var far: Array = _step(rows, Vector3(0.0, 1500.0, 10.0), Vector3.ZERO)
	assert_eq((far[0] as PackedInt32Array)[0], 0)
	assert_lt((far[2][0] as Vector3).y, -100.0, "it is sent in fast from far out")
	assert_almost_eq(((far[1][0] as Vector3) - Vector3(0.0, 100.8, 10.0)).length(), 0.0, 1e-3, "to its approach point")
	var behind: Array = _step(rows, Vector3(0.0, -600.0, 10.0), Vector3.ZERO)
	assert_gt((behind[1][0] as Vector3).length(), 149.0, "from behind the carrier it is sent round, outside the hull")
	var there: Array = _step(rows, Vector3(0.5, 102.0, 10.0), Vector3(0.0, -5.0, 0.0))
	assert_eq((there[0] as PackedInt32Array)[0], CarrierDock.EVENT_AT_APPROACH)
	rows.begin_capture(3, Vector3(0.5, 102.0, 10.0), Basis.IDENTITY)
	assert_eq(rows.phase_of(3), 2)
	var out: Array = there
	var ticks: int = 0
	while rows.count() > 0 and ticks < 900:
		out = _step(rows, Vector3.ZERO, Vector3.ZERO)
		ticks += 1
	assert_eq((out[0] as PackedInt32Array)[0], CarrierDock.EVENT_DOCKED)
	assert_almost_eq(((out[1][0] as Vector3) - Vector3(0.0, 40.8, 10.0)).length(), 0.0, 1e-3, "on its pad")
	assert_almost_eq(float(ticks) / 60.0, rows.constants()[1], 0.05, "after the capture time")


func test_rows_are_kept_by_key_in_the_order_they_were_added() -> void:
	var rows := ScsDockRows.new()
	rows.add(1, CarrierDock.PHASE_RETURN, Vector3(0.0, 40.0, 0.0), Basis.IDENTITY, 60.0, Vector3.ZERO)
	rows.add(2, CarrierDock.PHASE_RETURN, Vector3(0.0, -40.0, 0.0), Basis(Vector3.RIGHT, PI), 60.0, Vector3.ZERO)
	rows.add(1, CarrierDock.PHASE_LAUNCH, Vector3(0.0, 40.0, 0.0), Basis.IDENTITY, 60.0, Vector3.ZERO)
	assert_eq(rows.keys(), PackedInt64Array([2, 1]), "a key added again is replaced, at the end")
	assert_true(rows.remove(2))
	assert_false(rows.remove(2))
	assert_eq(rows.phase_of(2), -1)
	rows.clear()
	assert_eq(rows.count(), 0)
