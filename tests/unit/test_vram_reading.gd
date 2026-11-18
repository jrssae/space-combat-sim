extends GutTest
## VramReading (M8-T20, D86): the card's memory from fake driver trees, and the overlay's line.

const ROOT := "res://reports/tmp/test_vram_reading"
const GB: int = 1073741824

var _root: String = ""


func before_each() -> void:
	_root = ProjectSettings.globalize_path(ROOT)
	_wipe(_root)
	DirAccess.make_dir_recursive_absolute(_root)


func after_all() -> void:
	_wipe(ProjectSettings.globalize_path(ROOT))


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for dir: String in DirAccess.get_directories_at(path):
		_wipe(path.path_join(dir))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


# A card as the driver shows it; an empty value leaves that file out.
func _card(card_name: String, used: String, total: String, vendor: String = "") -> void:
	var device: String = _root.path_join(card_name).path_join("device")
	DirAccess.make_dir_recursive_absolute(device)
	for entry: Array in [["mem_info_vram_used", used], ["mem_info_vram_total", total], ["vendor", vendor]]:
		if String(entry[1]).is_empty():
			continue
		var file: FileAccess = FileAccess.open(device.path_join(String(entry[0])), FileAccess.WRITE)
		file.store_string(String(entry[1]) + "\n")
		file.close()


func test_it_reads_the_cards_use_and_size() -> void:
	_card("card1", "3377774592", "17163091968", "0x1002")
	var reading: VramReading = VramReading.read(500 * 1048576, "AMD Radeon RX 6950 XT (RADV NAVI21)", _root)
	assert_true(reading.has_total())
	assert_eq(reading.card, "card1")
	assert_eq(reading.used_bytes, 3377774592)
	assert_eq(reading.total_bytes, 17163091968)
	assert_almost_eq(reading.used_gb(), 3.146, 0.001)
	assert_almost_eq(reading.total_gb(), 15.984, 0.001)
	assert_almost_eq(reading.pct(), 19.68, 0.01)
	assert_almost_eq(reading.game_gb(), 0.488, 0.001)


func test_the_line_shows_gb_the_percentage_and_the_games_share() -> void:
	var reading := VramReading.new()
	reading.used_bytes = int(2.41 * GB)
	reading.total_bytes = 16 * GB
	reading.game_bytes = int(0.48 * GB)
	assert_eq(reading.line(), "VRAM  2.41 / 16.00 GB (15 %)   GAME 0.48 GB")


func test_no_driver_tree_shows_the_games_share_and_total_unknown() -> void:
	var reading: VramReading = VramReading.read(int(0.5 * GB), "Some GPU", _root.path_join("missing"))
	assert_false(reading.has_total())
	assert_eq(reading.card, "")
	assert_eq(reading.used_gb(), -1.0)
	assert_eq(reading.total_gb(), -1.0)
	assert_eq(reading.pct(), -1.0)
	assert_eq(reading.line(), "VRAM  GAME 0.50 GB   total unknown")
	assert_false(reading.line().contains("%"), "no percentage without a total")


func test_a_card_without_both_files_is_not_a_reading() -> void:
	_card("card0", "1000", "")
	_card("card1", "", "2000")
	assert_false(VramReading.read(0, "", _root).has_total())


func test_bad_numbers_are_not_a_reading() -> void:
	_card("card0", "lots", "17163091968")
	_card("card1", "-5", "17163091968")
	_card("card2", "100", "0")
	assert_false(VramReading.read(0, "", _root).has_total())


func test_it_picks_the_card_the_adapter_names() -> void:
	_card("card0", "1000", str(GB), "0x8086")
	_card("card1", "2000", str(16 * GB), "0x1002")
	assert_eq(VramReading.read(0, "AMD Radeon RX 6950 XT (RADV NAVI21)", _root).card, "card1")
	assert_eq(VramReading.read(0, "Intel(R) Arc(tm) A770 Graphics (DG2)", _root).card, "card0")


func test_it_falls_back_to_the_first_card_with_both_files() -> void:
	_card("card0", "1000", "")
	_card("card10", "3000", str(8 * GB), "0x1002")
	_card("card2", "2000", str(16 * GB), "0x1002")
	assert_eq(VramReading.read(0, "", _root).card, "card2", "no adapter name: the lowest numbered card")
	assert_eq(VramReading.read(0, "llvmpipe (LLVM 19.1.0, 256 bits)", _root).card, "card2", "an adapter no card matches")


func test_connectors_and_other_entries_are_not_cards() -> void:
	_card("card1-DP-1", "1000", str(GB), "0x1002")
	_card("renderD128", "1000", str(GB), "0x1002")
	assert_false(VramReading.read(0, "AMD", _root).has_total())
