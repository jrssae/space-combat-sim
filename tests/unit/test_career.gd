extends GutTest
## `Career` and `CareerStore` (M8 D79): the rank is only ever raised, reads back from disk, and bad data gives a fresh career.

const PATH: String = "user://test_career.json"


func after_each() -> void:
	DirAccess.remove_absolute(PATH)


func test_a_new_career_is_unassigned_and_a_rank_is_only_raised() -> void:
	var career := Career.new()
	assert_eq(career.rank, Career.UNASSIGNED)
	assert_true(career.award(Career.SQUADRON_PILOT))
	assert_true(career.award(Career.SQUADRON_LEADER))
	assert_false(career.award(Career.SQUADRON_PILOT), "a worse run later takes nothing away")
	assert_eq(career.rank, Career.SQUADRON_LEADER)
	assert_false(career.award(&"admiral"), "not a rank")
	assert_eq(career.rank_name(), "Squadron leader")


func test_set_rank_sets_any_rank_and_refuses_a_word_that_is_none() -> void:
	var career := Career.new()
	career.award(Career.SQUADRON_LEADER)
	assert_true(career.set_rank(Career.UNASSIGNED), "the console may lower it")
	assert_eq(career.rank, Career.UNASSIGNED)
	assert_false(career.set_rank(&"admiral"))


func test_it_survives_a_save_and_a_load() -> void:
	var career := Career.new()
	career.award(Career.SQUADRON_LEADER)
	career.course = TutorialRules.EXEMPLARY
	assert_eq(CareerStore.save_file(career, PATH), "")
	var back: Career = CareerStore.load_file(PATH)
	assert_eq(back.rank, Career.SQUADRON_LEADER)
	assert_eq(back.course, TutorialRules.EXEMPLARY)
	assert_string_contains(back.describe(), "exemplary")


func test_no_file_or_bad_data_gives_a_fresh_career() -> void:
	assert_eq(CareerStore.load_file(PATH).rank, Career.UNASSIGNED)
	assert_eq(Career.from_dict("nonsense").rank, Career.UNASSIGNED)
	assert_eq(Career.from_dict({"rank": "admiral"}).rank, Career.UNASSIGNED)
