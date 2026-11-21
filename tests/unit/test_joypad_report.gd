extends GutTest
## JoypadReport (M8-T22, D88): the pads connected now, the connect and disconnect history, and the wording of the log, the
## toast, the front end's notice and the `joypads` command.

const NOVA_GUID: String = "03008665373500004010000000010000"  # the maintainer's pad in its working mode

var report: JoypadReport


func before_each() -> void:
	report = JoypadReport.new()


func test_a_new_report_has_no_pads_and_says_so() -> void:
	assert_eq(report.count(), 0)
	assert_eq(report.none_notice(), JoypadReport.NONE_NOTICE)
	assert_string_contains(report.none_notice(), "keyboard and mouse work")
	assert_true(report.last_event().is_empty())
	assert_eq(report.start_lines().size(), 1)
	assert_string_contains(report.start_lines()[0], "none at start")
	assert_string_contains(report.start_lines()[0], "Gamepad not detected", "the log points at the troubleshooting section")
	var lines: PackedStringArray = report.summary_lines()
	assert_eq(lines[0], "joypads: none connected")
	assert_eq(lines[lines.size() - 1], "last events: none")


func test_a_pad_present_at_launch_is_a_start_event_without_a_toast() -> void:
	var event: Dictionary = report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 0.0)
	assert_eq(event["kind"], JoypadReport.START)
	assert_eq(JoypadReport.toast_text(event), "", "a pad that was there all along is not announced")
	assert_eq(report.count(), 1)
	assert_eq(report.none_notice(), "", "the notice goes once a pad is seen")
	assert_eq(report.start_lines()[0], "1 at start")
	assert_eq(report.start_lines()[1], "  0: Generic X-Box pad  guid %s  mapping known" % NOVA_GUID)


func test_godot_repeating_a_start_up_pad_adds_nothing() -> void:
	report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 0.0)
	var again: Dictionary = report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 0.02)
	assert_true(again.is_empty())
	assert_eq(report.events_seen(), 1)


func test_a_hotplug_is_a_connected_event_with_a_toast() -> void:
	var event: Dictionary = report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 42.0)
	assert_eq(event["kind"], JoypadReport.CONNECTED)
	assert_eq(JoypadReport.toast_text(event), "Gamepad connected: Generic X-Box pad")
	assert_eq(JoypadReport.event_line(event), "42.0 s  connected  0: Generic X-Box pad  guid %s  mapping known" % NOVA_GUID)


func test_a_pad_without_a_mapping_is_flagged() -> void:
	var event: Dictionary = report.note_connected(1, "Odd Stick", "0300aaaa", false, 5.0)
	assert_eq(report.unmapped_count(), 1)
	assert_string_contains(JoypadReport.toast_text(event), "no known button mapping")
	assert_string_contains(JoypadReport.pad_line(event), "mapping unknown")


func test_a_disconnect_keeps_the_name_godot_has_forgotten() -> void:
	report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 0.0)
	var event: Dictionary = report.note_disconnected(0, 600.0)
	assert_eq(event["kind"], JoypadReport.DISCONNECTED)
	assert_eq(event["name"], "Generic X-Box pad")
	assert_eq(event["guid"], NOVA_GUID)
	assert_eq(JoypadReport.toast_text(event), "Gamepad disconnected: Generic X-Box pad")
	assert_eq(report.count(), 0)
	assert_eq(report.none_notice(), JoypadReport.NONE_NOTICE, "the notice is back when the last pad goes")


func test_a_disconnect_of_an_unknown_pad_is_ignored() -> void:
	assert_true(report.note_disconnected(3, 1.0).is_empty())
	assert_eq(report.events_seen(), 0)


func test_a_different_pad_on_the_same_id_is_a_new_event() -> void:
	report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 0.0)
	var event: Dictionary = report.note_connected(0, "Xbox 360 Controller", "030081b85e0400008e02000014010000", true, 30.0)
	assert_eq(event["kind"], JoypadReport.CONNECTED)
	assert_eq(report.count(), 1)
	assert_eq(report.pads()[0]["name"], "Xbox 360 Controller")


func test_an_unnamed_pad_still_reads() -> void:
	var event: Dictionary = report.note_connected(2, "", "", false, 9.0)
	assert_eq(event["name"], "unnamed pad")


func test_pads_list_by_device_id() -> void:
	report.note_connected(4, "Second", "g4", true, 0.0)
	report.note_connected(1, "First", "g1", true, 0.0)
	var pads: Array[Dictionary] = report.pads()
	assert_eq(pads[0]["id"], 1)
	assert_eq(pads[1]["id"], 4)


func test_the_history_keeps_only_the_last_events() -> void:
	for i: int in JoypadReport.MAX_EVENTS + 5:
		if i % 2 == 0:
			report.note_connected(0, "Pad", "g", true, 10.0 + i)
		else:
			report.note_disconnected(0, 10.0 + i)
	assert_eq(report.events().size(), JoypadReport.MAX_EVENTS)
	assert_eq(report.events_seen(), JoypadReport.MAX_EVENTS + 5)
	assert_eq(float(report.last_event()["time_s"]), 10.0 + JoypadReport.MAX_EVENTS + 4)
	assert_eq(float(report.events()[0]["time_s"]), 15.0, "the oldest five were dropped")


func test_the_summary_lists_pads_then_events() -> void:
	report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 0.0)
	report.note_disconnected(0, 600.0)
	report.note_connected(0, "Generic X-Box pad", NOVA_GUID, true, 640.5)
	var lines: PackedStringArray = report.summary_lines()
	assert_eq(lines[0], "joypads: 1 connected")
	assert_eq(lines[1], "  0: Generic X-Box pad  guid %s  mapping known" % NOVA_GUID)
	assert_eq(lines[2], "last events: 3 of 3")
	assert_string_contains(lines[3], "0.0 s  start")
	assert_string_contains(lines[4], "600.0 s  disconnected")
	assert_string_contains(lines[5], "640.5 s  connected")


func test_the_event_line_of_no_event() -> void:
	assert_eq(JoypadReport.event_line({}), "none")
	assert_eq(JoypadReport.toast_text({}), "")
