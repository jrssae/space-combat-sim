extends GutTest
## `BotAlert` (M7-T11): fighting near a bot lately makes it go in, and only that.


func test_a_shot_alarms_the_bots_near_it_until_the_quiet_has_held() -> void:
	var alert := BotAlert.new()
	assert_false(alert.is_alarmed(Vector3.ZERO, 0.0), "quiet to begin with")
	alert.note(Vector3(100.0, 0.0, 0.0), 10.0)
	assert_true(alert.is_alarmed(Vector3.ZERO, 10.5), "100 m from a shot")
	assert_true(alert.is_alarmed(Vector3.ZERO, 10.0 + BotAlert.QUIET_S - 0.1))
	assert_false(alert.is_alarmed(Vector3.ZERO, 10.0 + BotAlert.QUIET_S + 0.1), "over once the quiet has held")


func test_a_shot_far_away_alarms_nobody_here() -> void:
	var alert := BotAlert.new()
	alert.note(Vector3(BotAlert.RADIUS_M + 50.0, 0.0, 0.0), 0.0)
	assert_false(alert.is_alarmed(Vector3.ZERO, 1.0))
	assert_true(alert.is_alarmed(Vector3(100.0, 0.0, 0.0), 1.0), "but a bot nearer the shot hears it")


func test_the_grid_going_weapons_free_alarms_everyone() -> void:
	var alert := BotAlert.new()
	alert.note_everywhere(5.0)
	assert_true(alert.is_alarmed(Vector3(7000.0, 0.0, 0.0), 6.0))
	assert_false(alert.is_alarmed(Vector3(7000.0, 0.0, 0.0), 5.0 + BotAlert.QUIET_S + 0.1))


func test_the_log_keeps_the_latest_events() -> void:
	var alert := BotAlert.new()
	for i: int in BotAlert.MAX_EVENTS + 5:
		alert.note(Vector3(float(i) * 10000.0, 0.0, 0.0), float(i) * 0.01)
	assert_true(alert.is_alarmed(Vector3(float(BotAlert.MAX_EVENTS + 4) * 10000.0, 0.0, 0.0), 1.0), "the newest is there")
	assert_false(alert.is_alarmed(Vector3.ZERO, 1.0), "the oldest was overwritten")


func test_clear_forgets_everything() -> void:
	var alert := BotAlert.new()
	alert.note(Vector3.ZERO, 0.0)
	alert.note_everywhere(0.0)
	alert.clear()
	assert_false(alert.is_alarmed(Vector3.ZERO, 1.0))
