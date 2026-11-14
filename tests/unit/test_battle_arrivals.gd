extends GutTest
## How the battle's ships come in (M6-T20, AC13): every ship out of a jump point, a group of one side and one fight sharing its
## point (within 600 m of the first), a capital its own; waves of at most a hundred points, the player's fight first, never
## more than a hundred open at once; a battle small enough for one wave is all in at the start. M6-T23: only capitals open
## points; a fighter group comes through a capital's point of its side in its wave close by, or through the jumpgate.

var _big: Array[Dictionary] = []
var _arrivals: BattleArrivals = null


func before_all() -> void:
	_big = BenchLayout.plan(BenchLayout.BATTLE, 1000, 1)
	_arrivals = BattleArrivals.plan(_big)


func test_every_ship_comes_out_of_exactly_one_point() -> void:
	var seen := PackedInt32Array()
	seen.resize(_big.size())
	for p: int in _arrivals.points.size():
		for member: int in _arrivals.points[p]["members"] as PackedInt32Array:
			seen[member] += 1
			assert_eq(_arrivals.entry_point[member], p)
	for i: int in _big.size():
		assert_eq(seen[i], 1, "%s %d arrives once" % [_big[i]["kind"], i])


func test_a_group_is_one_side_of_one_fight_close_to_its_first_ship() -> void:
	for point: Dictionary in _arrivals.points:
		var members: PackedInt32Array = point["members"]
		var first: Dictionary = _big[members[0]]
		if bool(point["capital"]):
			assert_eq(members.size(), 1, "a capital opens its own point")
			assert_eq(StringName(first["kind"]), BenchLayout.KIND_CAPITAL)
			continue
		for member: int in members:
			var e: Dictionary = _big[member]
			assert_eq(StringName(e["kind"]), BenchLayout.KIND_FIGHTER)
			assert_eq(int(e["side"]), int(first["side"]), "one side")
			assert_eq(int(e["group"]), int(first["group"]), "one fight")
			assert_lt((e["offset"] as Vector3).distance_to(first["offset"] as Vector3), BattleArrivals.SHARE_M)
	assert_lt(_arrivals.points.size(), _big.size() / 2, "groups share their points (%d points for %d ships)" % [
			_arrivals.points.size(), _big.size()])


func test_waves_of_a_hundred_points_never_more_open_at_once() -> void:
	assert_gt(_arrivals.waves, 1, "1 000 ships need more than one wave (%d points)" % _arrivals.points.size())
	assert_eq(_arrivals.waves, ceili(_arrivals.points.size() / float(JumpPointPool.MAX_POINTS)))
	var per_wave: Dictionary = {}
	for point: Dictionary in _arrivals.points:
		per_wave[int(point["wave"])] = int(per_wave.get(int(point["wave"]), 0)) + 1
	assert_eq(int(per_wave[0]), JumpPointPool.MAX_POINTS, "the first wave brings a hundred units at once")
	var capitals: Dictionary = {}
	for point: Dictionary in _arrivals.points:
		if StringName(point["via"]) == BattleArrivals.VIA_OWN:
			capitals[int(point["wave"])] = int(capitals.get(int(point["wave"]), 0)) + 1
	var most: int = 0
	for wave: int in per_wave:
		assert_lte(int(per_wave[wave]), JumpPointPool.MAX_POINTS)
		most = maxi(most, int(capitals.get(wave, 0)))
	assert_eq(_arrivals.max_open(), most, "only the capitals open points: the most in one wave are open at once")
	assert_lte(_arrivals.max_open(), JumpPointPool.MAX_POINTS, "at most a hundred open at any time")


func test_fighter_groups_ride_a_near_capital_of_their_side_in_their_wave_or_take_the_gate() -> void:
	var brought: Dictionary = {}
	for point: Dictionary in _arrivals.points:
		var via: StringName = point["via"]
		var first: Dictionary = _big[(point["members"] as PackedInt32Array)[0]]
		if bool(point["capital"]):
			assert_eq(via, BattleArrivals.VIA_OWN, "a capital opens its own point")
			assert_eq(int(point["rides"]), -1)
			continue
		assert_ne(via, BattleArrivals.VIA_OWN, "a fighter group never opens a point")
		if via == BattleArrivals.VIA_GATE:
			assert_eq(int(point["rides"]), -1)
			continue
		var cap: Dictionary = _arrivals.points[int(point["rides"])]
		var cap_entry: Dictionary = _big[(cap["members"] as PackedInt32Array)[0]]
		assert_eq(StringName(cap["via"]), BattleArrivals.VIA_OWN, "it rides a capital's point")
		assert_eq(int(cap_entry["side"]), int(first["side"]), "of its own side")
		assert_eq(int(cap["wave"]), int(point["wave"]), "in its wave")
		assert_eq(float(cap["at_s"]), float(point["at_s"]), "and comes in when that capital does")
		assert_lte((cap_entry["offset"] as Vector3).distance_to(first["offset"] as Vector3), BattleArrivals.CAPITAL_NEAR_M)
		brought[int(point["rides"])] = int(brought.get(int(point["rides"]), 0)) + 1
	for cap: int in brought:
		assert_lte(int(brought[cap]), BattleArrivals.GROUPS_PER_CAPITAL)
	var via_capital: int = _arrivals.ships_via(BattleArrivals.VIA_CAPITAL)
	var via_gate: int = _arrivals.ships_via(BattleArrivals.VIA_GATE)
	assert_gt(via_capital, 0, "a mix: some groups through their side's capital points")
	assert_gt(via_gate, 0, "and some through the gate (%d and %d fighters)" % [via_capital, via_gate])
	assert_eq(via_capital + via_gate + _arrivals.ships_via(BattleArrivals.VIA_OWN), _big.size())


func test_the_first_wave_opens_at_the_start_and_later_ones_spread_out_in_turn() -> void:
	var last: float = 0.0
	for point: Dictionary in _arrivals.points:
		var wave: int = point["wave"]
		var at: float = point["at_s"]
		assert_gte(at, last, "in the order they open")
		last = at
		if wave == 0:
			assert_eq(at, 0.0, "the first wave at the start")
		else:
			assert_between(at, wave * _arrivals.period_s, wave * _arrivals.period_s + BattleArrivals.SPREAD_S)
	assert_gte(_arrivals.period_s, _arrivals.life_s + BattleArrivals.SPREAD_S, "a wave's points all close before the next opens")
	assert_almost_eq(_arrivals.life_s, VortexTiming.for_point().done_at_s(), 1e-4)


func test_a_later_waves_capitals_open_two_to_a_tick_evenly_over_the_spread() -> void:
	# After M6-T23: a capital's arrival costs mostly once a tick, so they come in pairs, each pair a tick of its own, and the
	# bench brings their riders in the ticks between.
	var slots: Dictionary = {}  # wave -> {at_s: capitals}
	var counts: Dictionary = {}
	for point: Dictionary in _arrivals.points:
		var wave: int = point["wave"]
		if wave == 0 or StringName(point["via"]) != BattleArrivals.VIA_OWN:
			continue
		if not slots.has(wave):
			slots[wave] = {}
		var at: float = point["at_s"]
		slots[wave][at] = int((slots[wave] as Dictionary).get(at, 0)) + 1
		counts[wave] = int(counts.get(wave, 0)) + 1
	assert_gt(slots.size(), 1, "later waves bring capitals")
	for wave: int in slots:
		var times: Array = (slots[wave] as Dictionary).keys()
		times.sort()
		assert_eq(times.size(), ceili(int(counts[wave]) / float(BattleArrivals.CAPITALS_PER_SLOT)), "wave %d: pairs" % wave)
		for at: float in times:
			assert_lte(int(slots[wave][at]), BattleArrivals.CAPITALS_PER_SLOT)
		var gap: float = BattleArrivals.SPREAD_S / float(times.size())
		assert_gt(gap, 1.0 / 60.0, "each pair a tick of its own")
		for k: int in range(1, times.size()):
			assert_almost_eq(float(times[k]) - float(times[k - 1]), gap, 1e-4, "evenly over the spread")
		assert_lt(float(times[-1]), wave * _arrivals.period_s + BattleArrivals.SPREAD_S, "within the second")


func test_whole_fights_come_in_the_players_first() -> void:
	var last_fight: int = 0
	for point: Dictionary in _arrivals.points:
		assert_gte(int(point["fight"]), last_fight, "fights in order")
		last_fight = int(point["fight"])
	assert_eq(int(_arrivals.points[0]["fight"]), 0, "the player's fight first")


func test_the_same_plan_gives_the_same_arrivals() -> void:
	var again: BattleArrivals = BattleArrivals.plan(BenchLayout.plan(BenchLayout.BATTLE, 1000, 1))
	assert_eq(again.entry_point, _arrivals.entry_point)
	assert_eq(again.last_at_s(), _arrivals.last_at_s())


func test_a_small_battle_comes_in_all_at_the_start() -> void:
	var plan: Array[Dictionary] = BenchLayout.plan(BenchLayout.BATTLE, 100, 1)
	var small: BattleArrivals = BattleArrivals.plan(plan)
	assert_eq(small.waves, 1, "%d points fit one wave" % small.points.size())
	assert_eq(small.first_wave_entries().size(), plan.size(), "every ship from the start, as the weapon battle's recording has it")
	assert_eq(small.last_at_s(), 0.0)
	var tight: BattleArrivals = BattleArrivals.plan(plan, 10)
	assert_eq(tight.waves, ceili(small.points.size() / 10.0), "a smaller pool: more waves")
	assert_lte(tight.max_open(), 10)


func test_the_fps_test_splits_the_frames_into_forming_open_and_the_window() -> void:
	var frames: Array[PackedFloat64Array] = []
	for k: int in 1200:  # 20 s at 60 frames a second
		var t: float = k / 60.0
		var forming: bool = t < VortexTiming.point_forming_s()
		frames.append(PackedFloat64Array([t, 2.0 if forming else 1.0, 16.7, 300.0 if forming else 200.0, 900.0, 100.0 if t < 8.5 else 0.0]))
	var parts: Dictionary = BenchRunner.render_phases(frames, 12.0)
	assert_eq(parts.keys(), ["forming", "open", "window"])
	assert_eq(int(parts["forming"]["frames"]), ceili(VortexTiming.point_forming_s() * 60.0), "the star, the flash and the growth")
	assert_eq(float(parts["forming"]["gpu_ms_median"]), 2.0)
	assert_eq(float(parts["forming"]["draw_calls_max"]), 300.0)
	assert_eq(int(parts["forming"]["points_open_max"]), 100)
	assert_eq(float(parts["open"]["gpu_ms_median"]), 1.0, "then open until the close")
	assert_eq(int(parts["window"]["frames"]), 480, "the measured window from 12 s")
	assert_eq(int(parts["window"]["points_open_max"]), 0)
	assert_almost_eq(float(parts["window"]["fps"]), 1000.0 / 16.7, 0.01)
	assert_eq(BenchRunner.render_phases([] as Array[PackedFloat64Array], 0.0), {}, "headless: nothing drawn")
