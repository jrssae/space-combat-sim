extends GutTest
## M4-T40 fix round 1: the measure tool (`scripts/measure_fight_node.gd`, behind `fullscreen_check.sh` and `render_compare.sh`) runs
## its `exec` statements after a leading `bench` straight away, so a setting passed through `FULLSCREEN_EXEC` or `RC_EXEC` is in
## effect when the measured window opens. Before, `bench` held the console and the rest never ran. `wait` stands in for `bench`
## here: both hold the console the same way (`ConsoleResult.wait_frames`).

const MEASURE := preload("res://scripts/measure_fight_node.gd")

var _backup: Variant


func before_each() -> void:
	_backup = Settings.get_value(&"anti_aliasing")


func after_each() -> void:
	Settings.set_value(&"anti_aliasing", _backup)


func test_a_setting_after_a_holding_statement_applies_at_set_up() -> void:
	Settings.set_value(&"anti_aliasing", &"smaa")
	var measure: Node = MEASURE.new()
	measure.run_exec("wait 1000000; set settings.anti_aliasing taa")
	assert_eq(Settings.get_value(&"anti_aliasing"), &"taa", "FULLSCREEN_EXEC's setting is in effect before the window opens")
	measure.free()
