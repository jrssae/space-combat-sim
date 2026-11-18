extends GutTest
## Navigation targets and the hold-X interaction (M7-T27), the pure parts: a placeholder answers "not available", navigation
## targets fall in NAVIGATION (never CIVILIAN) and get the HUD's navigation look, the bar across the top, and X's tap and hold
## through the `InputAdapter`.

const DT: float = 1.0 / 60.0
const VIEW := Vector2(1920.0, 1080.0)


# --- the interaction ----------------------------------------------------------------------------------------------------


func test_a_placeholder_answers_not_available() -> void:
	var dock := TargetInteraction.new(&"dock", "DOCK")
	assert_true(dock.is_offered(), "offered whenever its target is selected")
	assert_false(dock.is_available())
	assert_eq(dock.run(), TargetInteraction.NOT_AVAILABLE)
	assert_eq(InteractionHost.notice_text(Station.DOCKING_BAY_NAME, dock.run()), "BABYLON 5 DOCKING BAY: NOT AVAILABLE")


func test_an_action_runs_and_its_offer_is_asked() -> void:
	var calls: Array[int] = [0]
	var open: Array[bool] = [false]
	var jump := TargetInteraction.new(&"jump", GateJumpPrompt.LABEL, func() -> String:
		calls[0] += 1
		return "", func() -> bool: return open[0])
	assert_false(jump.is_offered())
	open[0] = true
	assert_true(jump.is_offered())
	assert_true(jump.is_available())
	assert_eq(jump.run(), "")
	assert_eq(calls[0], 1)
	assert_eq(InteractionHost.prompt_text(jump), GateJumpPrompt.TEXT, "the pad's wording: HOLD X: JUMP")
	assert_eq(InteractionHost.prompt_text(jump, "X / SHIFT"), "HOLD X / SHIFT: JUMP", "with the keyboard's key")


func test_an_interaction_is_held_for_only_within_its_reach() -> void:
	var jump := TargetInteraction.new(&"jump", GateJumpPrompt.LABEL, Callable(), Callable(), 2000.0)
	assert_true(jump.in_reach(1999.0))
	assert_true(jump.in_reach(2000.0), "2 km is within 2 km")
	assert_false(jump.in_reach(2001.0))
	assert_true(TargetInteraction.new(&"x", "X").in_reach(1.0e9), "no reach given: anywhere")
	assert_eq(InteractionHost.status_text("JUMPGATE", 3400.0, jump), "JUMPGATE: 3.4 km — CLOSE TO 2.0 km TO JUMP",
			"out of reach: a status with no button in it")
	assert_false(InteractionHost.status_text("JUMPGATE", 3400.0, jump).contains("HOLD"))
	assert_eq(InteractionHost.range_text(850.0), "850 m")


# --- navigation targets ---------------------------------------------------------------------------------------------------


func _info(role: Targetable.Role, faction: StringName, broadcast: float = 1.0e6) -> TargetInfo:
	var info := TargetInfo.new(11, "X", faction, Vector3(0.0, 0.0, -20000.0))
	info.role = role
	info.broadcast_range_m = broadcast
	return info


func test_navigation_targets_are_navigation_not_civilian() -> void:
	var nav: TargetCategories.Category = TargetCategories.Category.NAVIGATION
	assert_eq(TargetCategories.category_of(_info(Targetable.Role.BEACON, &"neutral"), Vector3.ZERO, Factions.EARTH_ALLIANCE), nav,
			"a neutral gate or bay")
	assert_eq(TargetCategories.category_of(_info(Targetable.Role.BEACON, Factions.EARTH_ALLIANCE), Vector3.ZERO,
			Factions.EARTH_ALLIANCE), nav, "even of the player's own side")
	assert_eq(TargetCategories.category_of(_info(Targetable.Role.SHIP, &"neutral"), Vector3.ZERO, Factions.EARTH_ALLIANCE),
			TargetCategories.Category.CIVILIAN, "what the gate was before: a neutral ship-like target")


func test_the_readout_carries_the_role() -> void:
	var info: TargetInfo = _info(Targetable.Role.BEACON, &"neutral")
	assert_eq(TargetingSystem.compute_readout(info, Vector3.ZERO, Vector3.ZERO).role, Targetable.Role.BEACON)


func _hud_input() -> HudInput:
	var input := HudInput.new()
	input.camera_transform = Transform3D.IDENTITY
	input.projection = Projection.create_perspective(75.0, VIEW.x / VIEW.y, 0.05, 100000.0)
	input.viewport_size = VIEW
	return input


func _readout(role: Targetable.Role, faction: StringName = &"neutral") -> TargetReadout:
	var t := TargetReadout.new()
	t.id = 5
	t.display_name = Station.DOCKING_BAY_NAME
	t.faction = faction
	t.position = Vector3(0.0, 0.0, -3000.0)
	t.range_m = 3000.0
	t.role = role
	return t


func test_a_navigation_target_has_the_navigation_look() -> void:
	var input: HudInput = _hud_input()
	input.target = _readout(Targetable.Role.BEACON)
	var f: HudFrame = HudLayout.compute(input)
	assert_true(f.target_nav)
	assert_eq(f.target_color, TargetCategories.COLORS[TargetCategories.Category.NAVIGATION], "the navigation colour")
	assert_false(f.lead_visible, "no lead on a place")
	input.target = _readout(Targetable.Role.SHIP)
	f = HudLayout.compute(input)
	assert_false(f.target_nav, "a ship keeps its brackets")
	assert_true(f.lead_visible, "a ship ahead has its lead")
	assert_eq(f.target_color, Factions.NEUTRAL_COLOR)
	input.target = _readout(Targetable.Role.BEACON)
	input.target_unknown = true
	assert_false(HudLayout.compute(input).target_nav, "an unidentified target is grey and plain")


func test_the_bar_runs_across_the_top_only_while_a_hold_runs() -> void:
	var input: HudInput = _hud_input()
	var f: HudFrame = HudLayout.compute(input)
	assert_does_not_have(f.items, HudSurface.INTERACT, "no hold, no bar")
	input.interact_progress = 0.5
	f = HudLayout.compute(input)
	assert_has(f.items, HudSurface.INTERACT)
	assert_eq(f.interact_progress, 0.5)
	assert_almost_eq(f.interact_rect.size.x, VIEW.x * HudLayout.INTERACT_BAR_WIDTH_SHARE, 1e-3, "across the top")
	assert_almost_eq(f.interact_rect.get_center().x, VIEW.x * 0.5, 1e-3, "centred")
	assert_lt(f.interact_rect.end.y, f.status_pos.y - 12.0, "above the status line")
	input.cockpit = true
	input.screen_sizes = {&"octagon": Vector2(300.0, 300.0), &"left": Vector2(640.0, 250.0), &"right": Vector2(640.0, 250.0)}
	assert_has(HudLayout.compute(input).items, HudSurface.INTERACT, "on the window in the cockpit view too")


# --- X's tap and hold through the adapter -------------------------------------------------------------------------------


func _press(adapter: InputAdapter, source: FakeInputSource, ticks: int) -> Dictionary:
	var fired: int = 0
	var peak: float = 0.0
	source.hold(InputAdapter.AUTOTRACK)
	for i: int in ticks:
		var cmd: PilotCommand = adapter.sample(source, DT)
		fired += int(cmd.ui.interact)
		peak = maxf(peak, cmd.ui.interact_progress)
	source.release(InputAdapter.AUTOTRACK)
	var last: PilotCommand = adapter.sample(source, DT)
	fired += int(last.ui.interact)
	return {"fired": fired, "peak": peak, "release_progress": last.ui.interact_progress}


func test_a_tap_of_x_toggles_auto_track_on_an_offer() -> void:
	var adapter := InputAdapter.new()
	var source := FakeInputSource.new()
	adapter.interaction_offered = true
	var tap: Dictionary = _press(adapter, source, 5)
	assert_true(adapter.autotrack_on, "a tap switches auto-track on, on the release")
	assert_eq(tap["fired"], 0)
	assert_eq(tap["peak"], 0.0, "a tap never shows the bar")
	_press(adapter, source, 5)
	assert_false(adapter.autotrack_on, "the next tap switches it off")


func test_a_two_second_hold_runs_the_interaction_and_leaves_auto_track() -> void:
	var adapter := InputAdapter.new()
	var source := FakeInputSource.new()
	adapter.interaction_offered = true
	var held: Dictionary = _press(adapter, source, 130)
	assert_eq(held["fired"], 1, "one interaction")
	assert_false(adapter.autotrack_on, "auto-track untouched")
	assert_gt(held["peak"], 0.9, "the bar filled")


func test_releasing_early_cancels() -> void:
	var adapter := InputAdapter.new()
	var source := FakeInputSource.new()
	adapter.interaction_offered = true
	var half: Dictionary = _press(adapter, source, 60)
	assert_eq(half["fired"], 0)
	assert_false(adapter.autotrack_on, "past the tap window a release is not a tap either")
	assert_eq(half["release_progress"], 0.0, "the bar is gone on the release")


func test_hold_time_and_tap_window_come_from_the_settings() -> void:
	var adapter := InputAdapter.new()
	var source := FakeInputSource.new()
	adapter.interaction_offered = true
	adapter.interact_hold_s = 1.0
	adapter.target_hold_s = 0.2
	assert_eq(adapter.hold.tap_s, 0.2, "the tap splits where the target button's does")
	assert_eq(_press(adapter, source, 61)["fired"], 1, "1 s hold")


func test_the_console_can_hold_x() -> void:
	var adapter := InputAdapter.new()
	var source := FakeInputSource.new()
	adapter.interaction_offered = true
	adapter.console_hold_s = 2.1
	var fired: int = 0
	for i: int in 140:
		fired += int(adapter.sample(source, DT).ui.interact)
	assert_eq(fired, 1)
	assert_false(adapter.autotrack_on)
