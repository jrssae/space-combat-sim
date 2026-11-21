extends GutTest
## `Career` and `CareerStore` (M8 D79): the rank is only ever raised, reads back from disk, and bad data gives a fresh career.
## The console's `career set` needs its rank.

const PATH: String = "user://test_career.json"


func after_each() -> void:
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(PATH + CareerStore.TMP_SUFFIX)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


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


func test_a_saved_course_that_is_no_rating_reads_as_never_flown_so_a_later_one_still_counts() -> void:
	var career: Career = Career.from_dict({"rank": "squadron_pilot", "course": "legendary"})
	assert_eq(career.course, &"", "an unknown word is dropped")
	assert_eq(career.rank, Career.SQUADRON_PILOT, "the rank beside it is kept")
	assert_eq(Career.from_dict({"course": "par"}).course, TutorialRules.PAR)
	var saved: Dictionary = {"game": Game.career, "path": Game.career_path}
	Game.career = career
	Game.career_path = PATH
	Game.earn(&"", TutorialRules.BELOW_PAR)
	var earned: StringName = Game.career.course
	Game.career = saved["game"]
	Game.career_path = saved["path"]
	assert_eq(earned, TutorialRules.BELOW_PAR, "the first real rating is taken")


func test_a_save_replaces_the_file_whole_and_leaves_no_temporary_behind() -> void:
	var first := Career.new()
	first.award(Career.SQUADRON_PILOT)
	assert_eq(CareerStore.save_file(first, PATH), "")
	assert_false(FileAccess.file_exists(PATH + CareerStore.TMP_SUFFIX))
	var second := Career.new()
	second.award(Career.SQUADRON_LEADER)
	second.course = TutorialRules.EXEMPLARY
	assert_eq(CareerStore.save_file(second, PATH), "", "over the file that is there")
	assert_false(FileAccess.file_exists(PATH + CareerStore.TMP_SUFFIX), "the temporary file became the save")
	var back: Career = CareerStore.load_file(PATH)
	assert_eq(back.rank, Career.SQUADRON_LEADER)
	assert_eq(back.course, TutorialRules.EXEMPLARY)
	assert_string_contains(CareerStore.save_file(second, "user://no_such_dir/career.json"), "cannot write")


func test_career_set_without_a_rank_fails_with_its_usage_and_changes_nothing() -> void:
	var saved: Dictionary = {"game": Game.career, "path": Game.career_path}
	Game.career = Career.new()
	Game.career.award(Career.SQUADRON_LEADER)
	Game.career_path = PATH
	var bare: ConsoleResult = DebugConsole.registry.execute("career set")[0]
	var rank_after_bare: StringName = Game.career.rank
	var named: ConsoleResult = DebugConsole.registry.execute("career set squadron_pilot")[0]
	var rank_after_named: StringName = Game.career.rank
	Game.career = saved["game"]
	Game.career_path = saved["path"]
	assert_false(bare.ok, "no rank named")
	assert_string_contains(bare.text(), "career set <unassigned|squadron_pilot|squadron_leader>")
	assert_eq(rank_after_bare, Career.SQUADRON_LEADER, "not demoted")
	assert_true(named.ok)
	assert_eq(rank_after_named, Career.SQUADRON_PILOT, "a named rank is still set, lower or not")


## A save whose move failed after the old file had gone leaves the new save in the file beside it: a load finds it there.
func test_a_load_falls_back_to_the_file_beside_the_save_when_the_save_is_missing_or_unreadable() -> void:
	var tmp: String = PATH + CareerStore.TMP_SUFFIX
	_write(tmp, JSON.stringify({"rank": "squadron_leader", "course": "exemplary"}))
	var back: Career = CareerStore.load_file(PATH)
	assert_eq(back.rank, Career.SQUADRON_LEADER, "the save is missing: the file beside it is read")
	assert_eq(back.course, TutorialRules.EXEMPLARY)
	_write(PATH, "{ not json")
	assert_eq(CareerStore.load_file(PATH).rank, Career.SQUADRON_LEADER, "the save does not read: the file beside it does")
	_write(PATH, "[1, 2]")
	assert_eq(CareerStore.load_file(PATH).rank, Career.SQUADRON_LEADER, "the save is no object")
	_write(PATH, JSON.stringify({"rank": "squadron_pilot"}))
	assert_eq(CareerStore.load_file(PATH).rank, Career.SQUADRON_PILOT, "a save that reads comes first")
	_write(tmp, "garbage")
	DirAccess.remove_absolute(PATH)
	assert_eq(CareerStore.load_file(PATH).rank, Career.UNASSIGNED, "neither reads: a fresh career")
