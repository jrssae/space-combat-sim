extends TestSteps
## M8-T20 (D86, AC16): the card's memory reaches `state render` and the debug overlay, read about twice a second from the
## driver's files (a fake tree here), and falls back to the game's share where the driver gives none.

const ROOT := "res://reports/tmp/test_vram_overlay"
const GB: int = 1073741824

var _root: String = ""


func before_each() -> void:
	_root = ProjectSettings.globalize_path(ROOT)
	_write("mem_info_vram_used", 4 * GB)
	_write("mem_info_vram_total", 16 * GB)


func after_all() -> void:
	var device: String = ProjectSettings.globalize_path(ROOT).path_join("card0/device")
	for file: String in DirAccess.get_files_at(device):
		DirAccess.remove_absolute(device.path_join(file))
	for dir: String in ["card0/device", "card0", ""]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT).path_join(dir))


func _write(file_name: String, bytes: int) -> void:
	var device: String = _root.path_join("card0/device")
	DirAccess.make_dir_recursive_absolute(device)
	var file: FileAccess = FileAccess.open(device.path_join(file_name), FileAccess.WRITE)
	file.store_string("%d\n" % bytes)
	file.close()


func _status(drm_root: String) -> RenderStatus:
	var status := RenderStatus.new()
	status.drm_root = drm_root
	add_child_autofree(status)
	return status


func test_the_drivers_files_are_read_twice_a_second_not_every_frame() -> void:
	var status: RenderStatus = _status(_root)
	for ms: int in range(0, 500, 16):
		status.vram(ms)
	assert_eq(status.vram_reads, 1, "half a second of frames: one read")
	_write("mem_info_vram_used", 8 * GB)
	assert_almost_eq(status.vram(499).used_gb(), 4.0, 1e-6, "the old sample until the next read is due")
	assert_almost_eq(status.vram(500).used_gb(), 8.0, 1e-6, "then the new one")
	assert_eq(status.vram_reads, 2)
	for ms: int in range(500, 2000, 16):
		status.vram(ms)
	assert_eq(status.vram_reads, 4, "two seconds: four reads")


func test_state_render_reports_the_card() -> void:
	_status(_root)
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_almost_eq(float(registry.read("render.vram_used_gb")["value"]), 4.0, 1e-6)
	assert_almost_eq(float(registry.read("render.vram_total_gb")["value"]), 16.0, 1e-6)
	assert_almost_eq(float(registry.read("render.vram_pct")["value"]), 25.0, 1e-6)


func test_state_render_says_unknown_without_a_driver_total() -> void:
	_status(_root.path_join("missing"))
	var registry: ConsoleRegistry = DebugConsole.registry
	for key: String in ["vram_used_gb", "vram_total_gb", "vram_pct"]:
		assert_eq(float(registry.read("render." + key)["value"]), -1.0, key)


func test_the_overlay_shows_the_card_and_the_fallback() -> void:
	var main: Main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.ready.connect(func() -> void: main.render_status.drm_root = _root)
	add_child_autofree(main)
	await _ticks(2)
	var shown: bool = bool(Settings.get_value(&"show_overlay"))
	Settings.set_value(&"show_overlay", true)
	main.update_overlay(1.0)
	assert_string_contains(main.overlay.get_text(), "VRAM  4.00 / 16.00 GB (25 %)   GAME ")
	var bare: RenderStatus = _status(_root.path_join("missing"))
	assert_string_contains(OverlayText.format({"vram": bare.vram()}), "VRAM  GAME 0.00 GB   total unknown")
	Settings.set_value(&"show_overlay", shown)
