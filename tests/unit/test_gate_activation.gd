extends GutTest
## A jumpgate's activation (M6-T19): the fin stations' lamps (burning steadily between openings) flash in turn along every arm, from its front end to its back end,
## then the back ends glow into the vortex's centre flash; all inside the lead-in the vortex waits for.

const EPS: float = 1e-4


func test_lamps_are_ranked_by_station_from_the_front_on_every_arm_alike() -> void:
	# Two arms' lamps, inner and outer faces, five stations from 206 m behind the front ends, as the generator places them.
	var along := PackedFloat32Array()
	for arm: int in 2:
		for station: int in 5:
			for face: int in 2:
				along.append(206.34 + 209.268 * float(station) + 0.0001 * float(face))
	var ranks: PackedInt32Array = GateActivation.station_ranks(along)
	assert_eq(ranks.size(), 20)
	for i: int in along.size():
		assert_eq(ranks[i], (i / 2) % 5, "lamp %d: its station, 0 at the front" % i)


func test_the_chase_runs_station_by_station_from_front_to_back() -> void:
	var last: float = -1.0
	for rank: int in 5:
		var at: float = GateActivation.flash_at_s(rank, 5)
		assert_gt(at, last, "station %d flashes after the one in front of it" % rank)
		last = at
	assert_eq(GateActivation.flash_at_s(0, 5), 0.0, "the front end first")
	assert_almost_eq(GateActivation.flash_at_s(4, 5), GateActivation.CHASE_S, EPS, "the back end last")
	assert_lt(GateActivation.CHASE_S, GateActivation.DURATION_S, "the chase is over before the flash")


func test_a_lamp_is_dark_then_flashes_then_glows_until_the_flash_is_over() -> void:
	var start: float = GateActivation.flash_at_s(2, 5)
	assert_eq(GateActivation.lamp_level(2, 5, start - 0.01), GateActivation.STEADY_LEVEL, "its steady burn before its turn")
	assert_almost_eq(GateActivation.lamp_level(2, 5, start + GateActivation.RISE_S), 1.0, EPS, "a flash in its turn")
	var held: float = GateActivation.lamp_level(2, 5, GateActivation.DURATION_S)
	assert_between(held, GateActivation.HOLD_LEVEL - EPS, 0.5, "then a brighter glow")
	assert_eq(GateActivation.lamp_level(2, 5, GateActivation.DURATION_S + VortexTiming.FLASH_S), GateActivation.STEADY_LEVEL,
			"back to its steady burn after the flash")
	assert_gt(GateActivation.STEADY_LEVEL, 0.0, "a gate in shadow shows its lamps")
	assert_lt(GateActivation.STEADY_LEVEL, GateActivation.HOLD_LEVEL)


func test_the_back_ends_peak_as_the_vortex_flashes() -> void:
	assert_eq(GateActivation.tip_level(0.1), 0.0, "not while the chase runs")
	assert_almost_eq(GateActivation.tip_level(GateActivation.DURATION_S), 1.0, EPS, "peak at the flash")
	assert_eq(GateActivation.tip_level(GateActivation.DURATION_S + VortexTiming.FLASH_S), 0.0, "gone during the flash")
	assert_true(GateActivation.is_showing(0.5))
	assert_false(GateActivation.is_showing(GateActivation.DURATION_S + VortexTiming.FLASH_S))
