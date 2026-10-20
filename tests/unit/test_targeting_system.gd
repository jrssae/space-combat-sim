extends GutTest
## TargetingSystem, pure (architecture §6.3, AC8): next by range with wrap, ahead by boresight angle in the forward
## hemisphere, the readout, and clearing beyond sensor range. Expected orders are derived from the positions.

const RANGE_TOL_M: float = 1e-3
const SPEED_TOL_MPS: float = 1e-6

var system: TargetingSystem


func before_each() -> void:
	system = TargetingSystem.new()


func _info(id: int, position: Vector3, velocity: Vector3 = Vector3.ZERO, display_name: String = "") -> TargetInfo:
	var label: String = display_name if not display_name.is_empty() else "T%d" % id
	return TargetInfo.new(id, label, &"neutral", position, velocity)


## Five targets at known, distinct ranges around the origin, in shuffled order.
func _five() -> Array[TargetInfo]:
	var out: Array[TargetInfo] = [
		_info(30, Vector3(0.0, 0.0, -3000.0)),
		_info(10, Vector3(0.0, 0.0, -1000.0)),
		_info(50, Vector3(5000.0, 0.0, 0.0)),
		_info(20, Vector3(0.0, 2000.0, 0.0)),
		_info(40, Vector3(0.0, 0.0, 4000.0)),
	]
	return out


## Ids sorted by range from `ship_pos`, computed independently of the system.
func _ids_by_range(candidates: Array[TargetInfo], ship_pos: Vector3) -> Array[int]:
	var sorted: Array[TargetInfo] = candidates.duplicate()
	sorted.sort_custom(func(a: TargetInfo, b: TargetInfo) -> bool:
		return a.position.distance_to(ship_pos) < b.position.distance_to(ship_pos))
	var ids: Array[int] = []
	for info: TargetInfo in sorted:
		ids.append(info.id)
	return ids


# --- select_next -------------------------------------------------------------------------------------------------


func test_next_without_selection_picks_the_nearest() -> void:
	var candidates: Array[TargetInfo] = _five()
	system.update(candidates, Vector3.ZERO)
	assert_false(system.has_selection())
	assert_true(system.select_next(Vector3.ZERO), "selection changed")
	assert_eq(system.selected_id(), _ids_by_range(candidates, Vector3.ZERO)[0])


func test_next_cycles_by_range_and_wraps() -> void:
	var candidates: Array[TargetInfo] = _five()
	var expected: Array[int] = _ids_by_range(candidates, Vector3.ZERO)
	system.update(candidates, Vector3.ZERO)
	var seen: Array[int] = []
	for i: int in expected.size() + 2:
		system.select_next(Vector3.ZERO)
		seen.append(system.selected_id())
	var wrapped: Array[int] = expected.duplicate()
	wrapped.append(expected[0])
	wrapped.append(expected[1])
	assert_eq(seen, wrapped, "range order, then back to the nearest")


func test_next_order_follows_the_ship_not_the_list() -> void:
	var candidates: Array[TargetInfo] = _five()
	var ship := Vector3(4500.0, 0.0, 0.0)  # now id 50 is nearest
	system.update(candidates, ship)
	system.select_next(ship)
	assert_eq(system.selected_id(), 50)
	system.select_next(ship)
	assert_eq(system.selected_id(), _ids_by_range(candidates, ship)[1])


func test_next_skips_targets_beyond_sensor_range() -> void:
	var far := _info(99, Vector3(0.0, 0.0, -(TargetingSystem.SENSOR_RANGE_M + 1.0)))
	var near := _info(1, Vector3(0.0, 0.0, -100.0))
	var candidates: Array[TargetInfo] = [far, near]
	system.update(candidates, Vector3.ZERO)
	assert_eq(system.in_range(Vector3.ZERO).size(), 1)
	system.select_next(Vector3.ZERO)
	assert_eq(system.selected_id(), 1)
	assert_false(system.select_next(Vector3.ZERO), "one selectable target: next wraps to itself")
	assert_eq(system.selected_id(), 1)


func test_next_with_no_candidates_changes_nothing() -> void:
	var none: Array[TargetInfo] = []
	system.update(none, Vector3.ZERO)
	assert_false(system.select_next(Vector3.ZERO))
	assert_eq(system.selected_id(), TargetingSystem.NO_TARGET)


func test_equal_ranges_order_by_id() -> void:
	var candidates: Array[TargetInfo] = [_info(7, Vector3(100.0, 0.0, 0.0)), _info(3, Vector3(-100.0, 0.0, 0.0))]
	system.update(candidates, Vector3.ZERO)
	system.select_next(Vector3.ZERO)
	assert_eq(system.selected_id(), 3)
	system.select_next(Vector3.ZERO)
	assert_eq(system.selected_id(), 7)


# --- select_ahead ------------------------------------------------------------------------------------------------


func test_ahead_picks_the_smallest_boresight_angle() -> void:
	var candidates: Array[TargetInfo] = [
		_info(1, Vector3(0.0, 0.0, -500.0)),  # dead ahead but...
		_info(2, Vector3(300.0, 0.0, -300.0)),  # 45 deg right
		_info(3, Vector3(110.0, 0.0, -1000.0)),  # ~6.3 deg right, farther
	]
	system.update(candidates, Vector3.ZERO)
	var forward := Vector3(0.1, 0.0, -1.0).normalized()  # nose ~5.7 deg right
	var expected: int = -1
	var best: float = INF
	for info: TargetInfo in candidates:
		var angle: float = forward.angle_to(info.position)
		if angle < best:
			best = angle
			expected = info.id
	assert_eq(expected, 3, "precondition: target 3 is closest to the nose")
	assert_true(system.select_ahead(Vector3.ZERO, forward))
	assert_eq(system.selected_id(), expected)


func test_ahead_ignores_the_rear_hemisphere_and_keeps_the_selection_when_nothing_is_ahead() -> void:
	var candidates: Array[TargetInfo] = [
		_info(1, Vector3(0.0, 0.0, 500.0)),  # dead astern
		_info(2, Vector3(1000.0, 0.0, 0.0)),  # exactly 90 deg: not in the forward hemisphere
		_info(3, Vector3(-300.0, 0.0, 10.0)),  # just behind abeam
	]
	system.update(candidates, Vector3.ZERO)
	assert_false(system.select_ahead(Vector3.ZERO, Vector3.FORWARD), "nothing ahead, nothing selected")
	assert_false(system.has_selection())
	system.select_next(Vector3.ZERO)
	var before: int = system.selected_id()
	assert_false(system.select_ahead(Vector3.ZERO, Vector3.FORWARD))
	assert_eq(system.selected_id(), before, "selection unchanged")


func test_ahead_tie_goes_to_the_nearer() -> void:
	var candidates: Array[TargetInfo] = [
		_info(1, Vector3(0.0, 0.0, -2000.0)),
		_info(2, Vector3(0.0, 0.0, -800.0)),
		_info(3, Vector3(0.0, 0.0, -1500.0)),
	]
	system.update(candidates, Vector3.ZERO)
	system.select_ahead(Vector3.ZERO, Vector3.FORWARD)
	assert_eq(system.selected_id(), 2)


func test_ahead_works_from_any_ship_position_and_ignores_far_targets() -> void:
	var ship := Vector3(1000.0, -200.0, 300.0)
	var candidates: Array[TargetInfo] = [
		_info(1, ship + Vector3(0.0, 0.0, -(TargetingSystem.SENSOR_RANGE_M + 10.0))),  # dead ahead, out of range
		_info(2, ship + Vector3(0.0, 400.0, -400.0)),  # 45 deg up
	]
	system.update(candidates, ship)
	system.select_ahead(ship, Vector3.FORWARD)
	assert_eq(system.selected_id(), 2)


func test_ahead_with_a_zero_forward_changes_nothing() -> void:
	var candidates: Array[TargetInfo] = [_info(1, Vector3(0.0, 0.0, -10.0))]
	system.update(candidates, Vector3.ZERO)
	assert_false(system.select_ahead(Vector3.ZERO, Vector3.ZERO))


# --- readout -----------------------------------------------------------------------------------------------------


func test_readout_range_and_closing_speed_approaching_a_static_target() -> void:
	var ship := Vector3(10.0, 20.0, 30.0)
	var target := _info(1, ship + Vector3(300.0, -400.0, 1200.0))  # 1300 m away
	var line_of_sight: Vector3 = (target.position - ship).normalized()
	var candidates: Array[TargetInfo] = [target]
	system.update(candidates, ship)
	system.select_next(ship)
	var readout: TargetReadout = system.readout(ship, line_of_sight * 10.0, line_of_sight)
	assert_not_null(readout)
	assert_almost_eq(readout.range_m, 1300.0, RANGE_TOL_M)
	assert_almost_eq(readout.closing_mps, 10.0, 1e-4, "+10 m/s straight at a static target")
	assert_almost_eq(readout.angle_off_deg, 0.0, 1e-3)
	assert_eq(readout.id, 1)
	assert_eq(readout.display_name, "T1")
	assert_eq(readout.faction, &"neutral")
	assert_eq(readout.position, target.position)


func test_closing_speed_signs() -> void:
	var target := _info(1, Vector3(0.0, 0.0, -1000.0))
	var receding: TargetReadout = TargetingSystem.compute_readout(target, Vector3.ZERO, Vector3(0.0, 0.0, 10.0))
	assert_almost_eq(receding.closing_mps, -10.0, SPEED_TOL_MPS, "flying away: negative")
	var crossing: TargetReadout = TargetingSystem.compute_readout(target, Vector3.ZERO, Vector3(25.0, 0.0, 0.0))
	assert_almost_eq(crossing.closing_mps, 0.0, SPEED_TOL_MPS, "flying across: zero")
	var drifting := _info(2, Vector3(0.0, 0.0, -1000.0), Vector3(0.0, 0.0, 3.0))
	var incoming: TargetReadout = TargetingSystem.compute_readout(drifting, Vector3.ZERO, Vector3.ZERO)
	assert_almost_eq(incoming.closing_mps, 3.0, SPEED_TOL_MPS, "a target drifting at a static ship closes")
	var matched: TargetReadout = TargetingSystem.compute_readout(drifting, Vector3.ZERO, Vector3(0.0, 0.0, 3.0))
	assert_almost_eq(matched.closing_mps, 0.0, SPEED_TOL_MPS, "matched velocity: zero")


func test_angle_off_boresight() -> void:
	var target := _info(1, Vector3(1000.0, 0.0, -1000.0))
	assert_almost_eq(TargetingSystem.compute_readout(target, Vector3.ZERO, Vector3.ZERO).angle_off_deg, 45.0, 1e-4)
	var behind := _info(2, Vector3(0.0, 0.0, 700.0))
	assert_almost_eq(TargetingSystem.compute_readout(behind, Vector3.ZERO, Vector3.ZERO).angle_off_deg, 180.0, 1e-4)
	var nose_down: TargetReadout = TargetingSystem.compute_readout(behind, Vector3.ZERO, Vector3.ZERO, Vector3.BACK)
	assert_almost_eq(nose_down.angle_off_deg, 0.0, 1e-4, "the angle is measured from the given forward axis")


func test_readout_at_zero_range_is_finite() -> void:
	var on_top := _info(1, Vector3(5.0, 5.0, 5.0))
	var readout: TargetReadout = TargetingSystem.compute_readout(on_top, Vector3(5.0, 5.0, 5.0), Vector3.ONE)
	assert_eq(readout.range_m, 0.0)
	assert_eq(readout.closing_mps, 0.0)
	assert_eq(readout.angle_off_deg, 0.0)


func test_readout_keeps_millimetres_far_from_the_origin() -> void:
	# Near the edge of the M1 play area; the differences are taken in 64-bit, so nothing is lost on top of float32.
	var ship := Vector3(20000.0, 0.0, 0.0)
	var target := _info(1, Vector3(20000.0, 0.0, -500.25))
	assert_almost_eq(TargetingSystem.compute_readout(target, ship, Vector3.ZERO).range_m, 500.25, RANGE_TOL_M)


func test_no_selection_no_readout() -> void:
	var candidates: Array[TargetInfo] = _five()
	system.update(candidates, Vector3.ZERO)
	assert_null(system.readout(Vector3.ZERO, Vector3.ZERO))
	assert_null(system.selected())


# --- clearing ----------------------------------------------------------------------------------------------------


func test_selection_clears_beyond_sensor_range() -> void:
	var target := _info(1, Vector3(0.0, 0.0, -1000.0))
	var candidates: Array[TargetInfo] = [target]
	system.update(candidates, Vector3.ZERO)
	system.select_next(Vector3.ZERO)
	assert_eq(system.selected_id(), 1)
	var edge := Vector3(0.0, 0.0, -1000.0 + TargetingSystem.SENSOR_RANGE_M)  # exactly at sensor range: kept
	assert_false(system.update(candidates, edge))
	assert_eq(system.selected_id(), 1)
	assert_true(system.update(candidates, edge + Vector3(0.0, 0.0, 1.0)), "one metre beyond: cleared")
	assert_eq(system.selected_id(), TargetingSystem.NO_TARGET)


func test_selection_clears_when_the_target_leaves_the_list() -> void:
	var candidates: Array[TargetInfo] = _five()
	system.update(candidates, Vector3.ZERO)
	system.select_next(Vector3.ZERO)
	var selected: int = system.selected_id()
	var rest: Array[TargetInfo] = []
	for info: TargetInfo in candidates:
		if info.id != selected:
			rest.append(info)
	assert_true(system.update(rest, Vector3.ZERO))
	assert_false(system.has_selection())
	assert_false(system.update(rest, Vector3.ZERO), "nothing left to clear")


func test_selection_survives_updates_with_moved_targets() -> void:
	var candidates: Array[TargetInfo] = _five()
	system.update(candidates, Vector3.ZERO)
	system.select_next(Vector3.ZERO)
	var moved: Array[TargetInfo] = []
	for info: TargetInfo in candidates:
		moved.append(_info(info.id, info.position + Vector3(1.0, 2.0, 3.0)))
	assert_false(system.update(moved, Vector3.ZERO))
	assert_eq(system.selected().position, Vector3(1.0, 2.0, -997.0), "the readout uses this tick's positions")


# --- by id / name ------------------------------------------------------------------------------------------------


func test_select_id_and_find_by_name_respect_sensor_range() -> void:
	var near := _info(1, Vector3(0.0, 0.0, -100.0), Vector3.ZERO, "NAV ALPHA")
	var far := _info(2, Vector3(0.0, 0.0, -30000.0), Vector3.ZERO, "NAV FAR")
	var candidates: Array[TargetInfo] = [near, far]
	system.update(candidates, Vector3.ZERO)
	assert_false(system.select_id(2, Vector3.ZERO), "out of range")
	assert_true(system.select_id(1, Vector3.ZERO))
	assert_eq(system.find_by_name("nav alpha", Vector3.ZERO), near, "case-insensitive")
	assert_null(system.find_by_name("NAV FAR", Vector3.ZERO))
	assert_null(system.find_by_name("NAV BRAVO", Vector3.ZERO))
	assert_true(system.clear())
	assert_false(system.clear())
	assert_eq(system.all_candidates().size(), 2)
