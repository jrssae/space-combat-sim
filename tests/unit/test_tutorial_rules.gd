extends GutTest
## `TutorialRules` (M8 D79): the buoy course's four ratings against the instructor's time, and the qualification rule.


func _rules() -> TutorialRules:
	var made: Dictionary = TutorialRules.from_dict({"course": {"instructor_time_s": 100.0, "exemplary_within": 0.10, "par_within": 0.40}})
	assert_true(bool(made["ok"]))
	return made["rules"]


func test_the_data_file_loads_with_the_settled_numbers() -> void:
	var made: Dictionary = TutorialRules.load_file()
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	var rules: TutorialRules = made["rules"]
	assert_almost_eq(rules.exemplary_within, 0.10, 1e-6)
	assert_almost_eq(rules.par_within, 0.40, 1e-6)
	assert_eq(rules.gate_raiders, 6)
	assert_eq(rules.carrier_raiders, 8)
	assert_eq(rules.leader_max_starfuries_lost, 1)
	assert_eq(rules.leader_max_civilians_lost, 0)


func test_a_course_time_rates_exemplary_within_10_percent_par_within_40_and_below_par_beyond() -> void:
	var rules: TutorialRules = _rules()
	assert_eq(rules.rating(95.0, false), TutorialRules.EXEMPLARY)
	assert_eq(rules.rating(110.0, false), TutorialRules.EXEMPLARY, "within 10 % of the instructor's own time")
	assert_eq(rules.rating(110.1, false), TutorialRules.PAR)
	assert_eq(rules.rating(140.0, false), TutorialRules.PAR)
	assert_eq(rules.rating(140.1, false), TutorialRules.BELOW_PAR)


func test_a_destroyed_buoy_is_the_worst_whatever_the_time() -> void:
	assert_eq(_rules().rating(60.0, true), TutorialRules.BUOY_DESTROYED)


func test_squadron_leader_needs_an_exemplary_course_one_starfury_lost_at_most_and_no_civilian() -> void:
	var rules: TutorialRules = _rules()
	assert_eq(rules.rank(TutorialRules.EXEMPLARY, 0, 0), Career.SQUADRON_LEADER)
	assert_eq(rules.rank(TutorialRules.EXEMPLARY, 1, 0), Career.SQUADRON_LEADER)
	assert_eq(rules.rank(TutorialRules.EXEMPLARY, 2, 0), Career.SQUADRON_PILOT)
	assert_eq(rules.rank(TutorialRules.EXEMPLARY, 0, 1), Career.SQUADRON_PILOT)
	assert_eq(rules.rank(TutorialRules.PAR, 0, 0), Career.SQUADRON_PILOT)
	assert_eq(rules.rank(&"", 0, 0), Career.SQUADRON_PILOT, "a course never flown")


func test_no_starfury_lost_is_a_perfect_score() -> void:
	assert_true(TutorialRules.perfect(0))
	assert_false(TutorialRules.perfect(1))


func test_bad_numbers_are_refused() -> void:
	assert_false(bool(TutorialRules.from_dict({"course": {"instructor_time_s": 0}})["ok"]))
	assert_false(bool(TutorialRules.from_dict({"course": {"exemplary_within": 0.5, "par_within": 0.2}})["ok"]))
	assert_false(bool(TutorialRules.from_dict({"raid": {"gate_raiders": 0}})["ok"]))
