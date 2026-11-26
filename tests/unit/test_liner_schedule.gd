extends GutTest
## The Asimov liners' schedule (M10-T53, Q85): one visit every 20 min on average, timed from the last departure; about one
## visit in ten brings a second liner and never a third; stays of 15 to 30 min; a pair never shares a name; the same seed
## gives the same visits.

const VISITS: int = 4000
const NAMES: int = 21


func _shipped(p_seed: int) -> LinerSchedule:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(StationTraffic.DATA_PATH))
	return LinerSchedule.from_data(data["liner"], p_seed, NAMES)


func test_the_shipped_gap_averages_twenty_minutes() -> void:
	var s: LinerSchedule = _shipped(11)
	assert_almost_eq(s.mean_gap_s(), 1200.0, 0.5, "the data's gap averages 20 min")
	var total: float = 0.0
	for i: int in range(1, VISITS + 1):
		var wait: float = s.wait_s(i)
		assert_between(wait, s.gap_s.x, s.gap_s.y)
		total += wait
	assert_almost_eq(total / float(VISITS), 1200.0, 30.0, "the drawn waits average 20 min from departure to arrival")


func test_the_first_visit_comes_sooner() -> void:
	var s: LinerSchedule = _shipped(3)
	assert_between(s.wait_s(0), s.first_s.x, s.first_s.y)
	assert_lt(s.first_s.y, s.gap_s.y, "a session's first liner does not wait a whole gap")


func test_about_one_visit_in_ten_brings_two_and_none_brings_more() -> void:
	var s: LinerSchedule = _shipped(7)
	var pairs: int = 0
	for i: int in VISITS:
		var n: int = s.liners(i)
		assert_between(n, 1, LinerSchedule.MAX_AT_ONCE)
		pairs += 1 if n == 2 else 0
	assert_between(float(pairs) / float(VISITS), 0.08, 0.12, "one visit in ten is a pair")
	assert_eq(LinerSchedule.MAX_AT_ONCE, 2)


func test_stays_last_fifteen_to_thirty_minutes() -> void:
	var s: LinerSchedule = _shipped(19)
	var total: float = 0.0
	for i: int in VISITS:
		for k: int in 2:
			assert_between(s.stay(i, k), 900.0, 1800.0)
		total += s.stay(i, 0)
	assert_almost_eq(total / float(VISITS), 1350.0, 30.0)


func test_a_pair_never_shares_a_name() -> void:
	for names: int in [2, 3, NAMES]:
		var s: LinerSchedule = LinerSchedule.from_data({}, 23, names)
		var seen: Dictionary = {}
		for i: int in VISITS:
			var a: int = s.name_index(i, 0)
			var b: int = s.name_index(i, 1)
			assert_between(a, 0, names - 1)
			assert_between(b, 0, names - 1)
			if a == b:
				fail_test("visit %d's two liners both drew name %d of %d" % [i, a, names])
				return
			seen[a] = true
		assert_eq(seen.size(), names, "every name is drawn")


func test_the_same_seed_gives_the_same_visits_and_another_seed_others() -> void:
	var a: LinerSchedule = _shipped(42)
	var b: LinerSchedule = _shipped(42)
	var c: LinerSchedule = _shipped(43)
	var differs: int = 0
	for i: int in 200:
		assert_eq(a.wait_s(i), b.wait_s(i))
		assert_eq(a.liners(i), b.liners(i))
		assert_eq(a.stay(i, 1), b.stay(i, 1))
		assert_eq(a.name_index(i, 1), b.name_index(i, 1))
		differs += 1 if a.wait_s(i) != c.wait_s(i) else 0
	assert_gt(differs, 190, "another session's liners keep other times")


func test_missing_or_bad_data_keeps_the_defaults() -> void:
	var s: LinerSchedule = LinerSchedule.from_data({"gap_s": "soon", "stay_s": [50.0, 10.0], "pair_share": 4.0}, 1, 0)
	assert_eq(s.gap_s, Vector2(600.0, 1800.0))
	assert_eq(s.stay_s, Vector2(50.0, 50.0), "a range is ordered")
	assert_eq(s.pair_share, 1.0)
	assert_eq(s.name_index(5, 1), 0, "one name is all there is")
