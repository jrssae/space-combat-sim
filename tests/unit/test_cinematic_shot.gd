extends GutTest
## `CinematicShot` (architecture §18 D55, M5-T08, AC8): a camera shot read from a scenario's `cinematics`, its keys placed
## relative to actors or the scenario origin and interpolated (Catmull-Rom on positions, an eased look-at and field of view).
## The actors are plain transforms handed in by a lookup, so every number here is checked without a scene.

const TOL: float = 1e-3

## Actor name -> Transform3D, read by `_pose`.
var actors: Dictionary = {}
## Added to every origin point, as a rebase would (the local position of the scenario origin).
var origin_local: Vector3 = Vector3.ZERO
## The universe offsets `_origin_to_local` was asked for.
var origin_calls: Array[PackedFloat64Array] = []


func before_each() -> void:
	actors = {"player": Transform3D.IDENTITY}
	origin_local = Vector3.ZERO
	origin_calls.clear()


func _pose(actor: String) -> Variant:
	return actors.get(actor)


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	origin_calls.append(offset)
	return origin_local + Vector3(offset[0], offset[1], offset[2])


func _origin_key(t: float, at: Vector3, look: Vector3, fov: Variant = null) -> Dictionary:
	var key: Dictionary = {"t": t, "position": {"origin": [at.x, at.y, at.z]}, "look_at": {"origin": [look.x, look.y, look.z]}}
	if fov != null:
		key["fov"] = fov
	return key


func _shot(keys: Array) -> CinematicShot:
	var made: Dictionary = CinematicShot.from_dict(&"test", {"keys": keys})
	assert_true(bool(made["ok"]), "the shot parses: %s" % made.get("error", ""))
	return made["shot"] as CinematicShot


func _eval(shot: CinematicShot, t: float) -> CinematicShot.Pose:
	return shot.pose_at(t, _pose, _origin_to_local)


func _assert_parse_error(data: Variant, fragment: String) -> void:
	var made: Dictionary = CinematicShot.from_dict(&"bad", data)
	assert_false(bool(made["ok"]), "refused: %s" % JSON.stringify(data))
	assert_string_contains(String(made.get("error", "")), fragment)


# Uniform Catmull-Rom on four points, the textbook form.
func _catmull_rom(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u: float) -> Vector3:
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u * u
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u * u * u)


# --- parsing ---------------------------------------------------------------------------------------------------------------


func test_a_shot_parses_its_keys_and_lasts_until_the_last_one() -> void:
	var shot: CinematicShot = _shot([
		{"t": 0, "position": {"actor": "player", "offset": [0, 5, 30]}, "look_at": {"actor": "player"}, "fov": 55},
		{"t": 2.5, "position": {"origin": [0, 0, -1000]}, "look_at": {"actor": "NAV ALPHA", "offset": [0, 0, 0]}},
	])
	assert_eq(shot.id, &"test")
	assert_eq(shot.keys.size(), 2)
	assert_almost_eq(shot.duration_s, 2.5, TOL)
	assert_eq(shot.keys[0].position.actor, "player")
	assert_eq(shot.keys[0].position.offset, Vector3(0, 5, 30))
	assert_almost_eq(shot.keys[0].fov, 55.0, TOL)
	assert_almost_eq(shot.keys[1].fov, CinematicShot.DEFAULT_FOV_DEG, TOL, "no fov: the default")
	assert_true(shot.keys[1].position.actor.is_empty(), "an origin point names no actor")
	assert_eq(shot.keys[1].position.universe, PackedFloat64Array([0.0, 0.0, -1000.0]))
	assert_eq(shot.actors(), PackedStringArray(["player", "NAV ALPHA"]))


func test_bad_shots_are_refused_with_a_reason() -> void:
	var good_point: Dictionary = {"actor": "player"}
	_assert_parse_error([], "must be an object")
	_assert_parse_error({}, "keys")
	_assert_parse_error({"keys": []}, "at least one key")
	_assert_parse_error({"keys": [{"position": good_point, "look_at": good_point}]}, "keys[0].t")
	_assert_parse_error({"keys": [{"t": -1, "position": good_point, "look_at": good_point}]}, "keys[0].t")
	_assert_parse_error({"keys": [{"t": 1, "position": good_point, "look_at": good_point},
			{"t": 1, "position": good_point, "look_at": good_point}]}, "keys[1].t")
	_assert_parse_error({"keys": [{"t": 0, "look_at": good_point}]}, "keys[0].position")
	_assert_parse_error({"keys": [{"t": 0, "position": good_point}]}, "keys[0].look_at")
	_assert_parse_error({"keys": [{"t": 0, "position": {}, "look_at": good_point}]}, "actor or origin")
	_assert_parse_error({"keys": [{"t": 0, "position": {"actor": "player", "origin": [0, 0, 0]}, "look_at": good_point}]},
			"actor or origin")
	_assert_parse_error({"keys": [{"t": 0, "position": {"actor": ""}, "look_at": good_point}]}, "actor")
	_assert_parse_error({"keys": [{"t": 0, "position": {"actor": "player", "offset": [1, 2]}, "look_at": good_point}]},
			"offset")
	_assert_parse_error({"keys": [{"t": 0, "position": {"origin": [1, 2, "x"]}, "look_at": good_point}]}, "origin")
	_assert_parse_error({"keys": [{"t": 0, "position": {"origin": [0, 0, 0], "offset": [1, 0, 0]}, "look_at": good_point}]},
			"offset")
	_assert_parse_error({"keys": [{"t": 0, "position": good_point, "look_at": good_point, "fov": 0}]}, "fov")
	_assert_parse_error({"keys": [{"t": 0, "position": good_point, "look_at": good_point, "fov": 180}]}, "fov")


# --- positions -------------------------------------------------------------------------------------------------------------


func test_the_camera_passes_through_every_key_at_its_time() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 20, 0), Vector3(150, -10, 80), Vector3(60, 0, 200)]
	var times: Array[float] = [0.0, 1.0, 3.5, 4.0]
	var keys: Array = []
	for i: int in points.size():
		keys.append(_origin_key(times[i], points[i], Vector3(0, 0, -5000)))
	var shot: CinematicShot = _shot(keys)
	for i: int in points.size():
		assert_almost_eq(_eval(shot, times[i]).transform.origin, points[i], Vector3.ONE * TOL, "key %d" % i)


func test_two_keys_fly_a_straight_line_at_an_even_speed() -> void:
	var a := Vector3(0, 0, 0)
	var b := Vector3(400, 100, -200)
	var shot: CinematicShot = _shot([_origin_key(0.0, a, Vector3(0, 0, -5000)), _origin_key(2.0, b, Vector3(0, 0, -5000))])
	for u: float in [0.1, 0.25, 0.5, 0.8]:
		assert_almost_eq(_eval(shot, 2.0 * u).transform.origin, a.lerp(b, u), Vector3.ONE * 0.01, "u = %s" % u)


func test_evenly_spaced_keys_follow_a_catmull_rom_spline() -> void:
	var p: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(150, 80, 0), Vector3(150, 160, 60)]
	var keys: Array = []
	for i: int in p.size():
		keys.append(_origin_key(float(i), p[i], Vector3(0, 0, -5000)))
	var shot: CinematicShot = _shot(keys)
	for u: float in [0.25, 0.5, 0.75]:
		assert_almost_eq(_eval(shot, 1.0 + u).transform.origin, _catmull_rom(p[0], p[1], p[2], p[3], u),
				Vector3.ONE * 0.01, "middle segment, u = %s" % u)


func test_the_path_has_no_kink_at_a_key_even_with_uneven_times() -> void:
	var p: Array[Vector3] = [Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(150, 80, 0), Vector3(150, 160, 60)]
	var times: Array[float] = [0.0, 0.5, 2.5, 3.0]
	var keys: Array = []
	for i: int in p.size():
		keys.append(_origin_key(times[i], p[i], Vector3(0, 0, -5000)))
	var shot: CinematicShot = _shot(keys)
	var h: float = 1e-3
	for i: int in [1, 2]:
		var at: float = times[i]
		var before: Vector3 = (_eval(shot, at).transform.origin - _eval(shot, at - h).transform.origin) / h
		var after: Vector3 = (_eval(shot, at + h).transform.origin - _eval(shot, at).transform.origin) / h
		assert_lt((after - before).length(), 0.05 * maxf(before.length(), 1.0),
				"key %d: the velocity carries through (%s vs %s)" % [i, before, after])


func test_before_the_first_key_and_after_the_last_the_camera_holds() -> void:
	var shot: CinematicShot = _shot([_origin_key(0.5, Vector3(10, 0, 0), Vector3(0, 0, -5000)),
			_origin_key(1.5, Vector3(90, 0, 0), Vector3(0, 0, -5000))])
	assert_almost_eq(_eval(shot, 0.0).transform.origin, Vector3(10, 0, 0), Vector3.ONE * TOL)
	assert_almost_eq(_eval(shot, 9.0).transform.origin, Vector3(90, 0, 0), Vector3.ONE * TOL)


func test_a_single_key_is_a_still_shot() -> void:
	var shot: CinematicShot = _shot([_origin_key(0.0, Vector3(5, 6, 7), Vector3(0, 0, -5000), 40.0)])
	assert_almost_eq(shot.duration_s, 0.0, TOL)
	for t: float in [0.0, 1.0]:
		var pose: CinematicShot.Pose = _eval(shot, t)
		assert_almost_eq(pose.transform.origin, Vector3(5, 6, 7), Vector3.ONE * TOL)
		assert_almost_eq(pose.fov, 40.0, TOL)


# --- look-at and field of view ---------------------------------------------------------------------------------------------


func test_the_camera_looks_at_its_point_and_the_point_eases_between_keys() -> void:
	var l1 := Vector3(0, 0, -1000)
	var l2 := Vector3(1000, 0, -1000)
	var shot: CinematicShot = _shot([_origin_key(0.0, Vector3.ZERO, l1), _origin_key(1.0, Vector3.ZERO, l2)])
	for u: float in [0.0, 0.25, 0.5, 1.0]:
		var pose: CinematicShot.Pose = _eval(shot, u)
		var expected_point: Vector3 = l1.lerp(l2, smoothstep(0.0, 1.0, u))
		var forward: Vector3 = -pose.transform.basis.z
		assert_almost_eq(forward, expected_point.normalized(), Vector3.ONE * TOL, "u = %s: -z at the eased look point" % u)
		assert_almost_eq(pose.transform.basis.x.dot(Vector3.UP), 0.0, TOL, "u = %s: no roll" % u)
	# The look point starts and stops gently: a quarter of the way in time is well short of a quarter of the way.
	var quarter: Vector3 = -_eval(shot, 0.25).transform.basis.z
	assert_lt(quarter.angle_to(l1.normalized()), (l1.angle_to(l2)) * 0.25)


func test_looking_straight_up_or_down_still_gives_a_camera() -> void:
	var shot: CinematicShot = _shot([_origin_key(0.0, Vector3.ZERO, Vector3(0, 500, 0))])
	var pose: CinematicShot.Pose = _eval(shot, 0.0)
	assert_not_null(pose)
	assert_almost_eq(-pose.transform.basis.z, Vector3.UP, Vector3.ONE * TOL)
	assert_true(pose.transform.basis.is_conformal(), "an orthonormal basis")


func test_the_field_of_view_eases_between_keys() -> void:
	var shot: CinematicShot = _shot([_origin_key(0.0, Vector3.ZERO, Vector3(0, 0, -100), 60.0),
			_origin_key(2.0, Vector3(10, 0, 0), Vector3(0, 0, -100), 30.0)])
	assert_almost_eq(_eval(shot, 0.0).fov, 60.0, TOL)
	assert_almost_eq(_eval(shot, 1.0).fov, 45.0, TOL)
	assert_almost_eq(_eval(shot, 0.5).fov, lerpf(60.0, 30.0, smoothstep(0.0, 1.0, 0.25)), TOL)
	assert_almost_eq(_eval(shot, 2.0).fov, 30.0, TOL)


# --- frames: actors and the origin -----------------------------------------------------------------------------------------


func test_an_actor_point_is_offset_in_that_actor_frame_and_follows_it() -> void:
	actors["player"] = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1000, 0, 0))  # nose (-z) turned to -x
	var shot: CinematicShot = _shot([{"t": 0, "position": {"actor": "player", "offset": [0, 5, 30]},
			"look_at": {"actor": "player"}}])
	var pose: CinematicShot.Pose = _eval(shot, 0.0)
	assert_almost_eq(pose.transform.origin, Vector3(1030, 5, 0), Vector3.ONE * TOL, "30 m behind the turned ship")
	assert_almost_eq(-pose.transform.basis.z, (Vector3(1000, 0, 0) - Vector3(1030, 5, 0)).normalized(), Vector3.ONE * TOL)
	actors["player"] = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1200, 0, 0))
	assert_almost_eq(_eval(shot, 0.0).transform.origin, Vector3(1230, 5, 0), Vector3.ONE * TOL, "the ship moved on")


func test_an_origin_point_hands_its_offset_over_in_64_bit() -> void:
	var far: float = 20_000_000.25  # a buoy ring's radius: float32 would round the quarter metre away
	var shot: CinematicShot = _shot([{"t": 0, "position": {"origin": [far, 0, 0]}, "look_at": {"actor": "player"}}])
	origin_local = Vector3(-20_000_000.0, 0, 0)  # the local frame sits on the ring
	_eval(shot, 0.0)
	assert_eq(origin_calls[0][0], far, "the offset reaches the lookup unrounded")


func test_a_rebase_moves_the_whole_pose_by_the_offset_and_turns_nothing() -> void:
	actors["player"] = Transform3D(Basis(Vector3(0.3, 1, 0).normalized(), 0.7), Vector3(400, 30, -900))
	actors["NAV ALPHA"] = Transform3D(Basis.IDENTITY, Vector3(0, 0, -2000))
	var shot: CinematicShot = _shot([
		{"t": 0, "position": {"actor": "player", "offset": [20, 10, 40]}, "look_at": {"actor": "player"}, "fov": 60},
		{"t": 1, "position": {"origin": [300, 50, -1500]}, "look_at": {"actor": "NAV ALPHA"}},
		{"t": 2, "position": {"actor": "NAV ALPHA", "offset": [0, 40, 200]}, "look_at": {"actor": "player"}, "fov": 40},
	])
	var before: Array[CinematicShot.Pose] = []
	for t: float in [0.3, 1.0, 1.6]:
		before.append(_eval(shot, t))
	var shift := Vector3(-4000, 200, 2500)
	for name: String in actors.keys():
		actors[name] = (actors[name] as Transform3D).translated(shift)
	origin_local += shift
	var i: int = 0
	for t: float in [0.3, 1.0, 1.6]:
		var after: CinematicShot.Pose = _eval(shot, t)
		assert_almost_eq(after.transform.origin, before[i].transform.origin + shift, Vector3.ONE * 0.01, "t = %s" % t)
		assert_almost_eq(after.transform.basis.x, before[i].transform.basis.x, Vector3.ONE * TOL)
		assert_almost_eq(after.transform.basis.z, before[i].transform.basis.z, Vector3.ONE * TOL)
		assert_almost_eq(after.fov, before[i].fov, TOL)
		i += 1


func test_a_missing_actor_on_the_segment_gives_no_pose_but_a_missing_neighbour_does_not() -> void:
	var shot: CinematicShot = _shot([
		{"t": 0, "position": {"actor": "GONE"}, "look_at": {"actor": "player"}},
		{"t": 1, "position": {"origin": [0, 0, 100]}, "look_at": {"actor": "player"}},
		{"t": 2, "position": {"origin": [100, 0, 100]}, "look_at": {"actor": "player"}},
	])
	assert_null(_eval(shot, 0.5), "the segment's own key cannot be placed")
	assert_not_null(_eval(shot, 1.5), "the key before the segment only shapes the curve")
