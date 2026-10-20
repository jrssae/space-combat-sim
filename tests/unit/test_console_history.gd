extends GutTest
## ConsoleHistory (architecture §6.4): 100 entries, Up/Down browsing with a draft, persisted one per line.

const PATH := "user://test_console_history_unit.txt"

var history: ConsoleHistory


func before_each() -> void:
	_delete()
	history = ConsoleHistory.new(PATH)


func after_all() -> void:
	_delete()


func test_add_skips_blank_lines_and_repeats() -> void:
	history.add("help")
	history.add("   ")
	history.add("")
	history.add("help")
	history.add("  state  ")
	history.add("help")
	assert_eq(Array(history.entries()), ["help", "state", "help"], "only consecutive repeats are dropped")


func test_keeps_the_newest_hundred() -> void:
	for i: int in 150:
		history.add("cmd %d" % i)
	var entries: PackedStringArray = history.entries()
	assert_eq(entries.size(), ConsoleHistory.MAX_ENTRIES)
	assert_eq(ConsoleHistory.MAX_ENTRIES, 100)
	assert_eq(entries[0], "cmd 50")
	assert_eq(entries[99], "cmd 149")


func test_browsing_keeps_the_draft() -> void:
	history.add("one")
	history.add("two")
	history.add("three")
	assert_eq(history.older("dra"), "three")
	assert_eq(history.older("three"), "two")
	assert_eq(history.older("two"), "one")
	assert_eq(history.older("one"), "one", "stops at the oldest")
	assert_eq(history.newer("one"), "two")
	assert_eq(history.newer("two"), "three")
	assert_eq(history.newer("three"), "dra", "past the newest: the draft comes back")
	assert_eq(history.newer("dra"), "dra", "not browsing: unchanged")


func test_add_resets_browsing() -> void:
	history.add("one")
	history.add("two")
	history.older("")
	history.add("three")
	assert_eq(history.older(""), "three")


func test_empty_history_browsing_returns_current() -> void:
	assert_eq(history.older("typed"), "typed")
	assert_eq(history.newer("typed"), "typed")


func test_persists_and_reloads() -> void:
	for i: int in 120:
		history.add("line %d" % i)
	history.add("set targeting.selected \"NAV BRAVO\"")
	assert_eq(history.save_file(), OK)
	var reloaded := ConsoleHistory.new(PATH)
	assert_eq(reloaded.load_file(), OK)
	assert_eq(reloaded.size(), 100)
	assert_eq(reloaded.entries()[99], "set targeting.selected \"NAV BRAVO\"")
	assert_eq(reloaded.entries()[0], "line 21")


func test_load_caps_a_long_file() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	for i: int in 250:
		file.store_line("old %d" % i)
		file.store_line("")
	file.close()
	assert_eq(history.load_file(), OK)
	assert_eq(history.size(), 100)
	assert_eq(history.entries()[99], "old 249")


func test_missing_file_is_an_empty_history() -> void:
	history.add("x")
	assert_eq(history.load_file(), OK)
	assert_eq(history.size(), 0)


func _delete() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
