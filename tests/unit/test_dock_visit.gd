extends GutTest
## DockVisit (M8-T06, D82): one ship's visit to the docking bay as a state, its repair clock and when it can be called off.


func test_a_visit_starts_on_its_way_in_and_can_be_called_off_outside_the_doors() -> void:
	var visit := DockVisit.new("PLAYER", true, DockVisit.WHY_HOLD)
	assert_eq(visit.state, DockVisit.State.APPROACH)
	assert_true(visit.can_cancel())
	visit.enter(DockVisit.State.LANE)
	assert_true(visit.can_cancel())
	visit.enter(DockVisit.State.INSIDE)
	assert_false(visit.can_cancel(), "through the inner doors it stays")
	assert_false(visit.is_away(), "still flying in the void")


func test_the_repair_clock_runs_down_and_reports_its_progress() -> void:
	var visit := DockVisit.new("ALPHA 2")
	visit.begin_repair(10.0, 0.4)
	assert_eq(visit.state, DockVisit.State.REPAIR)
	assert_true(visit.is_away())
	assert_almost_eq(visit.hull_before, 0.4, 1e-6)
	assert_false(visit.repair_tick(4.0))
	assert_almost_eq(visit.repair_progress(), 0.4, 1e-6)
	assert_true(visit.repair_tick(6.5), "done, never below zero")
	assert_eq(visit.repair_left_s, 0.0)
	assert_eq(visit.repair_progress(), 1.0)


func test_the_time_in_a_state_restarts_with_the_state() -> void:
	var visit := DockVisit.new("PLAYER", true)
	visit.advance(2.0)
	visit.enter(DockVisit.State.LANE)
	visit.advance(0.5)
	assert_almost_eq(visit.state_s, 0.5, 1e-6)
	assert_almost_eq(visit.total_s, 2.5, 1e-6)


func test_a_cancelled_visit_is_over_and_says_why() -> void:
	var visit := DockVisit.new("PLAYER", true)
	visit.cancel("respawn")
	assert_true(visit.is_over())
	assert_eq(visit.cancel_reason, "respawn")
	assert_eq(visit.state_name(), "cancelled")


func test_every_state_has_a_name() -> void:
	assert_eq(DockVisit.STATE_NAMES.size(), DockVisit.State.size())
	var visit := DockVisit.new("ALPHA 3")
	visit.begin_repair(12.0, 0.5)
	assert_string_contains(visit.describe(), "ALPHA 3 repair 12 s left")
