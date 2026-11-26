extends GutTest
## `EncounterPlan` (architecture §18 D58, M5-T17, AC14): the free-flight encounter schedule and its draws. Deterministic per
## seed; every draw is a hash of the seed and the event index, so asking for event 7 gives the same event whatever was
## asked before; each event due half to one and a half intervals after the last one started (M7-T56), another kind standing
## in when it cannot start; kinds by weight; a share of raids for the station; raids 2-6 raiders
## 6-12 km from their target, patrols 2/4/6 Starfuries and traffic 1-3 civilian hulls on straight routes from 26-30 km out
## (traffic passing 2-10 km from the player); a Bokmai's pods from the seed; the cap.

const SAMPLE: int = 2000


func _plan(seed_value: int = 7, interval_s: float = 120.0, weights: Dictionary = EncounterPlan.DEFAULT_WEIGHTS) -> EncounterPlan:
	return EncounterPlan.new(seed_value, interval_s, weights)


func test_the_same_seed_plans_the_same_events() -> void:
	var a: EncounterPlan = _plan(42)
	var b: EncounterPlan = _plan(42)
	for i: int in 30:
		assert_eq(a.gap_of(i), b.gap_of(i), "event %d's gap" % i)
		assert_eq(a.event(i).describe(), b.event(i).describe(), "event %d" % i)


func test_another_seed_plans_other_events() -> void:
	var a: EncounterPlan = _plan(1)
	var b: EncounterPlan = _plan(2)
	var same: int = 0
	for i: int in 30:
		same += 1 if a.event(i).describe() == b.event(i).describe() else 0
	assert_lt(same, 3, "two seeds share almost no events")


func test_a_draw_does_not_depend_on_what_was_asked_before() -> void:
	var fresh: Dictionary = _plan(9).event(7).describe()
	var walked: EncounterPlan = _plan(9)
	for i: int in 7:
		walked.event(i)
	walked.event(20)
	walked.event(3, &"raid")
	assert_eq(walked.event(7).describe(), fresh, "event 7 after other draws")
	assert_eq(_plan(9).event(7).describe(), fresh, "asked twice")


func test_each_gap_is_half_to_one_and_a_half_intervals() -> void:
	# M7-T56 (m5-056): an event every 1 to 3 minutes at the default 120 s, counted from the last start.
	var plan: EncounterPlan = _plan(3, 120.0)
	var lo: float = INF
	var hi: float = 0.0
	for i: int in 500:
		var gap: float = plan.gap_of(i)
		assert_between(gap, 60.0, 180.0, "the gap before event %d" % i)
		lo = minf(lo, gap)
		hi = maxf(hi, gap)
	assert_lt(lo, 70.0, "the short end of the band is used")
	assert_gt(hi, 170.0, "and the long end")


func test_the_interval_scales_the_gaps() -> void:
	var slow: EncounterPlan = _plan(3, 120.0)
	var fast: EncounterPlan = _plan(3, 60.0)
	for i: int in 20:
		assert_almost_eq(fast.gap_of(i), slow.gap_of(i) * 0.5, 1e-6, "event %d" % i)


func test_other_kinds_stand_in_gentlest_first() -> void:
	assert_eq(EncounterPlan.new().substitutes(&"raid"), [&"traffic", &"patrol"] as Array[StringName])
	assert_eq(EncounterPlan.new().substitutes(&"patrol"), [&"traffic", &"raid"] as Array[StringName])
	assert_eq(EncounterPlan.new().substitutes(&"traffic"), [&"patrol", &"raid"] as Array[StringName])


func test_a_share_of_raids_is_drawn_for_the_station() -> void:
	var plan: EncounterPlan = _plan(13)
	plan.station_raid_share = 0.3
	var raids: int = 0
	var at_station: int = 0
	for i: int in SAMPLE:
		var e: EncounterEvent = plan.event(i, &"raid")
		raids += 1
		at_station += 1 if e.at_station else 0
		assert_false(plan.event(i, &"patrol").at_station, "only raids go for the station")
	assert_almost_eq(float(at_station) / raids, 0.3, 0.04, "the pools file's share")
	assert_false(_plan(13).event(4, &"raid").at_station, "none without a share")


func test_kinds_are_drawn_by_weight() -> void:
	var plan: EncounterPlan = _plan(11, 120.0, {&"raid": 0.5, &"patrol": 0.2, &"traffic": 0.3})
	var counts: Dictionary = {&"raid": 0, &"patrol": 0, &"traffic": 0}
	for i: int in SAMPLE:
		counts[plan.event(i).kind] += 1
	assert_almost_eq(float(counts[&"raid"]) / SAMPLE, 0.5, 0.04, "raids")
	assert_almost_eq(float(counts[&"patrol"]) / SAMPLE, 0.2, 0.04, "patrols")
	assert_almost_eq(float(counts[&"traffic"]) / SAMPLE, 0.3, 0.04, "traffic")


func test_a_kind_weighted_zero_never_comes() -> void:
	var plan: EncounterPlan = _plan(11, 120.0, {&"raid": 0.0, &"patrol": 1.0, &"traffic": 1.0})
	for i: int in 300:
		assert_ne(plan.event(i).kind, &"raid", "event %d" % i)


func test_a_forced_kind_keeps_the_index_draws() -> void:
	var plan: EncounterPlan = _plan(13)
	for kind: StringName in EncounterPlan.KINDS:
		var e: EncounterEvent = plan.event(4, kind)
		assert_eq(e.kind, kind)
		assert_eq(e.index, 4)
		assert_eq(e.describe(), _plan(13).event(4, kind).describe(), "%s at 4, twice" % kind)


func test_raids_are_two_to_six_raiders_jumping_in_six_to_twelve_km_from_their_target() -> void:
	var plan: EncounterPlan = _plan(17)
	var sizes: Dictionary = {}
	var at_civilians: int = 0
	for i: int in 300:
		var e: EncounterEvent = plan.event(i, &"raid")
		sizes[e.count()] = true
		assert_between(e.count(), 2, 6, "raid %d size" % i)
		assert_true(e.jumps, "raiders jump in")
		assert_eq(e.anchor, EncounterEvent.ANCHOR_TARGET, "placed around their target")
		at_civilians += 1 if e.at_civilian else 0
		assert_between(e.target_pick, 0.0, 1.0)
		for k: int in e.count():
			assert_eq(e.types[k], ShipPool.DEFAULT_TYPE)
			assert_between(e.positions[k].length(), 6000.0, 12000.0, "raid %d ship %d range" % [i, k])
			assert_gt(e.velocities[k].dot(-e.positions[k].normalized()), 0.9 * e.velocities[k].length(),
					"raid %d ship %d flies at its target" % [i, k])
			assert_eq(e.routes[k].size(), 0, "a raid has no route")
	assert_eq(sizes.size(), 5, "every size from 2 to 6 comes")
	assert_between(at_civilians, 60, 240, "some raids go for a civilian, some for the player")


func test_patrols_are_two_four_or_six_starfuries_cruising_in_from_26_to_30_km() -> void:
	var plan: EncounterPlan = _plan(19)
	var sizes: Dictionary = {}
	for i: int in 300:
		var e: EncounterEvent = plan.event(i, &"patrol")
		sizes[e.count()] = true
		assert_true(e.count() in [2, 4, 6], "patrol %d size %d" % [i, e.count()])
		assert_false(e.jumps)
		assert_eq(e.anchor, EncounterEvent.ANCHOR_PLAYER)
		for k: int in e.count():
			assert_eq(e.types[k], ShipPool.ALLY_TYPE)
			_assert_route_from_afar(e, k, "patrol %d ship %d" % [i, k])
	assert_eq(sizes.size(), 3, "2, 4 and 6 all come")


func test_traffic_is_one_to_three_civilians_passing_two_to_ten_km_from_the_player() -> void:
	var plan: EncounterPlan = _plan(23)
	var types: Dictionary = {}
	var pods: Dictionary = {}
	for i: int in 400:
		var e: EncounterEvent = plan.event(i, &"traffic")
		assert_between(e.count(), 1, 3, "traffic %d size" % i)
		for k: int in e.count():
			assert_true(ShipCatalog.is_civilian(e.types[k]), "traffic %d ship %d is a civilian hull" % [i, k])
			types[e.types[k]] = true
			_assert_route_from_afar(e, k, "traffic %d ship %d" % [i, k])
			var start: Vector3 = e.positions[k]
			var end: Vector3 = e.routes[k][e.routes[k].size() - 1]
			assert_between(_closest_to_origin(start, end), 1999.0, 10001.0, "traffic %d ship %d passes 2-10 km out" % [i, k])
			if e.types[k] == &"brakiri_bokmai":
				assert_between(e.cargo_pods[k], 0, 3, "a Bokmai flies 0-3 pods")
				pods[e.cargo_pods[k]] = true
			else:
				assert_eq(e.cargo_pods[k], -1, "only a Bokmai has a pod count")
	assert_eq(types.size(), ShipCatalog.civilian_types().size(), "every civilian hull comes")
	assert_eq(pods.size(), 4, "a Bokmai comes with 0, 1, 2 and 3 pods")


func test_traffic_draws_the_hulls_it_is_given_and_the_catalogues_by_default() -> void:
	# M10 Q97: the director widens the list by the traffic-only hulls its pools list; a plan left alone draws as before.
	var plain: EncounterPlan = _plan(29)
	var wide: EncounterPlan = _plan(29)
	assert_eq(plain.civilian_types, ShipCatalog.civilian_types())
	wide.civilian_types = ShipCatalog.traffic_types({&"centauri_shuttle": 1, &"minbari_flyer": 1})
	var seen: Dictionary = {}
	for i: int in 300:
		var a: EncounterEvent = plain.event(i, &"traffic")
		var b: EncounterEvent = wide.event(i, &"traffic")
		assert_eq(a.count(), b.count(), "the same convoy either way")
		for k: int in a.count():
			assert_has(ShipCatalog.civilian_types(), a.types[k], "the plain plan never draws a traffic-only hull")
			seen[b.types[k]] = true
	assert_true(seen.has(&"centauri_shuttle") and seen.has(&"minbari_flyer"), "the wide plan draws both")
	assert_eq(seen.size(), wide.civilian_types.size(), "and every other civilian hull")


func test_a_patrol_or_traffic_route_is_straight_and_ends_as_far_out_as_it_starts() -> void:
	var plan: EncounterPlan = _plan(29)
	for kind: StringName in [&"patrol", &"traffic"]:
		for i: int in 50:
			var e: EncounterEvent = plan.event(i, kind)
			for k: int in e.count():
				var start: Vector3 = e.positions[k]
				var route: PackedVector3Array = e.routes[k]
				var heading: Vector3 = (route[route.size() - 1] - start).normalized()
				for point: Vector3 in route:
					assert_almost_eq((point - start).normalized().dot(heading), 1.0, 1e-4, "%s %d: on one line" % [kind, i])
				assert_almost_eq(route[route.size() - 1].length(), start.length(), 1.0, "%s %d: ends as far out" % [kind, i])


func test_the_cap_admits_an_event_only_when_it_fits() -> void:
	assert_eq(EncounterPlan.admit(0, 6, 24), 6, "room")
	assert_eq(EncounterPlan.admit(18, 6, 24), 6, "exactly fits")
	assert_eq(EncounterPlan.admit(19, 6, 24), 5, "held: starts with the five that fit (maintainer, 2026-11-21)")
	assert_eq(EncounterPlan.admit(21, 6, 24), EncounterPlan.MIN_PARTIAL, "three fit: the smallest it starts with")
	assert_eq(EncounterPlan.admit(22, 6, 24), 0, "two would fit: it waits, never a raid of two cut from six")
	assert_eq(EncounterPlan.admit(24, 1, 24), 0, "full")
	assert_eq(EncounterPlan.admit(0, 6, 4), 4, "bigger than the whole cap: trimmed to it once nothing else is in play")
	assert_eq(EncounterPlan.admit(1, 6, 4), 3, "three fit beside one: it starts with three")
	assert_eq(EncounterPlan.admit(2, 6, 4), 0, "and waits while fewer than three fit")


func test_an_event_can_be_trimmed() -> void:
	var e: EncounterEvent = _plan(31).event(2, &"patrol")
	var whole: int = e.count()
	e.trim(1)
	assert_eq(e.count(), 1)
	assert_eq(e.types.size(), 1)
	assert_eq(e.positions.size(), 1)
	assert_eq(e.velocities.size(), 1)
	assert_eq(e.routes.size(), 1)
	assert_eq(e.cargo_pods.size(), 1)
	assert_gt(whole, 1)


# A cruising ship: it starts 26-30 km from the player, moving along its route at its cruise speed.
func _assert_route_from_afar(e: EncounterEvent, k: int, what: String) -> void:
	var start: Vector3 = e.positions[k]
	assert_between(start.length(), 26000.0, 30000.0, "%s starts 26-30 km out" % what)
	assert_gt(e.routes[k].size(), 0, "%s has a route" % what)
	var first: Vector3 = e.routes[k][0]
	assert_almost_eq(e.velocities[k].length(), e.cruise_mps, 1e-3, "%s at cruise" % what)
	assert_gt(e.velocities[k].normalized().dot((first - start).normalized()), 0.999, "%s heads along its route" % what)


# The distance from the origin (the player) to the segment start-end.
func _closest_to_origin(start: Vector3, end: Vector3) -> float:
	var d: Vector3 = end - start
	var t: float = clampf(-start.dot(d) / d.length_squared(), 0.0, 1.0)
	return (start + d * t).length()


# --- M8-T28: the three switches ------------------------------------------------------------------------------------


func _with(raid: bool, patrol: bool, traffic: bool) -> EncounterPlan:
	var plan: EncounterPlan = _plan(21)
	plan.enabled = {&"raid": raid, &"patrol": patrol, &"traffic": traffic}
	return plan


func test_a_switched_off_kind_is_never_drawn_alone_or_in_combination() -> void:
	for combo: Array in [[true, false, false], [false, true, false], [false, false, true],
			[true, true, false], [true, false, true], [false, true, true], [true, true, true]]:
		var plan: EncounterPlan = _with(combo[0], combo[1], combo[2])
		assert_true(plan.any_on())
		for i: int in 400:
			var kind: StringName = plan.event(i).kind
			assert_true(plan.kind_on(kind), "event %d is %s with %s" % [i, kind, combo])


func test_a_lone_kind_is_drawn_even_when_the_file_weights_it_zero() -> void:
	var plan: EncounterPlan = _plan(5, 120.0, {&"raid": 1.0, &"patrol": 0.0, &"traffic": 0.0})
	plan.enabled = {&"raid": false, &"patrol": true, &"traffic": false}
	assert_eq(plan.event(3).kind, &"patrol")


func test_all_switches_off_is_an_empty_sky() -> void:
	assert_false(_with(false, false, false).any_on())


func test_substitutes_skip_switched_off_kinds() -> void:
	assert_eq(_with(true, false, false).substitutes(&"traffic"), [&"raid"] as Array[StringName])
	assert_eq(_with(false, true, true).substitutes(&"raid"), [&"traffic", &"patrol"] as Array[StringName])
