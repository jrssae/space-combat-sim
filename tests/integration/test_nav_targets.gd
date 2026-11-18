extends GutTest
## Navigation targets and the hold-X interaction in play (M7-T27), on the real main scene in free flight: Babylon 5's main docking
## bay and cargo bay and the jumpgate are navigation targets (not civilian), the cargo bay answers a 2 s hold of X with "not
## available" (the docking bay's hold docks the ship since M8-T06: `test_docking`),
## a tap still toggles auto-track, and the HUD shows the navigation look, the prompt and the bar. The selection moves from a
## bay to the other bay and to the gate by every path a pilot has (the target menu, the console, the wheel, the nose; the
## target button's tap takes an enemy); the gate's hold beyond 2 km answers "out of range". The jump itself is flown in
## `test_jumpgate_in_play`.

const DT: float = 1.0 / 60.0

var main: Main
var source: FakeInputSource
var station: Station


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _start(raiders: int = 0) -> void:
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = raiders
	main.ally_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	station = main.far_props.station


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# The player 1.5 km out from a nav point, nose on it, at rest, with it selected.
func _target(point: Targetable) -> void:
	var at: Vector3 = point.global_position + station.global_basis * Vector3(0.0, 0.0, -1500.0)
	main.ship.reset_to(Transform3D(Basis.looking_at(point.global_position - at, station.global_basis.y), at))
	await _ticks(3)
	assert_true(main.ship.targeting.select_id(point.get_instance_id()), "%s can be selected" % point.display_name)
	await _ticks(1)


func test_the_bays_and_the_gate_are_navigation_targets() -> void:
	await _start()
	assert_not_null(station, "free flight places Babylon 5")
	var gate: Jumpgate = main.gates.gate()
	assert_not_null(gate, "and the jumpgate")
	var markers: Array[Targetable] = [station.docking_bay.targetable, station.cargo_bay.targetable, gate.targetable]
	for marker: Targetable in markers:
		assert_eq(marker.role, Targetable.Role.BEACON, "%s is a navigation target" % marker.display_name)
		assert_eq(TargetCategories.category_of(marker.to_target_info(), main.ship.global_position, main.combatant.faction),
				TargetCategories.Category.NAVIGATION, "%s is listed under NAVIGATION, not CIVILIAN" % marker.display_name)
		assert_not_null(marker.interaction, "%s offers an interaction" % marker.display_name)
	assert_eq(station.docking_bay.targetable.interaction.kind, &"dock")
	assert_eq(station.cargo_bay.targetable.interaction.kind, &"cargo")
	assert_eq(gate.targetable.interaction.kind, &"jump")
	assert_eq(station.targetable.role, Targetable.Role.SHIP, "the station itself stays as it is")
	assert_lt(station.docking_bay.global_position.distance_to(station.global_transform * (station.hardpoints.main_docking_bay[
			"main_docking_bay_mouth"] as Vector3 + station.drum_origin)), 1.0, "at the docking bay's mouth")


func test_holding_x_on_the_cargo_bay_answers_not_available_and_a_tap_still_tracks() -> void:
	await _start()
	await _target(station.cargo_bay.targetable)
	var offer: TargetInteraction = main.interactions.offer()
	assert_not_null(offer, "the bay offers its interaction")
	assert_eq(main.interactions.prompt_line(), "HOLD X / SHIFT / MOUSE 4: CARGO", "pad and keyboard both named")
	var hud: HudFrame = HudLayout.compute(main._build_hud_input())
	assert_true(hud.target_nav, "the HUD draws it as a navigation target")
	assert_eq(hud.ack_line, "HOLD X / SHIFT / MOUSE 4: CARGO", "the prompt on the acknowledgement line")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(60)
	hud = HudLayout.compute(main._build_hud_input())
	assert_has(hud.items, HudSurface.INTERACT, "a second in, the bar shows")
	assert_almost_eq(hud.interact_progress, 0.5, 0.05)
	await _ticks(65)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(1)
	assert_eq(main.interactions.runs, 1, "the hold ran the bay's interaction once")
	assert_eq(main.interactions.last_result, TargetInteraction.NOT_AVAILABLE)
	assert_eq(main.interactions.prompt_line(), "BABYLON 5 CARGO BAY: NOT AVAILABLE", "the answer shows")
	assert_false(main.adapter.autotrack_on, "the hold left auto-track alone")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(5)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_true(main.adapter.autotrack_on, "a tap of X still switches auto-track on")
	assert_eq(main.interactions.runs, 1, "and runs nothing")


func test_the_console_runs_and_holds() -> void:
	await _start()
	await _target(station.cargo_bay.targetable)
	assert_eq(DebugConsole.registry.read("interact.offered")["value"], "cargo")
	var out: Array[ConsoleResult] = DebugConsole.registry.execute("interact run")
	assert_true(out[0].ok, "interact run")
	assert_eq(main.interactions.last_result, TargetInteraction.NOT_AVAILABLE)
	DebugConsole.registry.execute("interact hold 1")
	await _ticks(30)
	assert_gt(float(DebugConsole.registry.read("interact.progress")["value"]), 0.2, "the console's hold fills the bar")
	await _ticks(40)
	assert_eq(main.interactions.runs, 1, "released after 1 s, before the 2 s: nothing more ran")


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _selected() -> String:
	return main.ship.targeting.selected_name()


# A real hold of the pad's target button (B): the target menu opens.
func _hold_menu_open() -> void:
	source.hold(InputAdapter.TARGET_CYCLE)
	await _ticks(ceili(main.adapter.target_hold_s / DT) + 3)
	source.release(InputAdapter.TARGET_CYCLE)
	await _ticks(2)


# The maintainer's flight (2026-11-14): from the docking bay the target would not move to the cargo bay or the gate. The
# menu's NAVIGATION ring made every pick a waypoint (M5-T25); a navigation target that offers an interaction is now the target.
func test_the_target_menu_moves_the_selection_from_a_bay_to_the_other_bay_and_the_gate() -> void:
	await _start()
	await _target(station.docking_bay.targetable)
	for wanted: String in [Station.CARGO_BAY_NAME, "JUMPGATE", Station.DOCKING_BAY_NAME]:
		await _hold_menu_open()
		assert_true(main.target_menu.is_open(), "B held opens the target menu")
		assert_true(_run("targetmenu pick navigation").ok)
		var ring: String = "\n".join(_run("targetmenu highlight 0").lines)
		assert_string_contains(ring, wanted.to_lower(), "the NAVIGATION ring lists %s" % wanted)
		var picked: ConsoleResult = _run("targetmenu pick \"%s\"" % wanted.to_lower())
		assert_true(picked.ok, "\n".join(picked.lines))
		await _ticks(2)
		assert_false(main.target_menu.is_open())
		assert_eq(_selected(), wanted, "picking %s from NAVIGATION makes it the target" % wanted)
		if wanted == "JUMPGATE":
			# 50 km out: no button, only how close to come (maintainer's rule).
			assert_null(main.interactions.offer(), "the gate is out of reach")
			assert_string_contains(main.interactions.prompt_line(), "CLOSE TO 2.0 km TO JUMP")
		else:
			assert_not_null(main.interactions.offer(), "and X can act on it")
	# A plain nav buoy is still the waypoint, never the target (M5-T25).
	await _hold_menu_open()
	_run("targetmenu pick navigation")
	var buoy: String = main.buoys[0].get_node(^"Targetable").display_name
	if _run("targetmenu pick \"%s\"" % buoy.to_lower()).ok:
		await _ticks(2)
		assert_eq(_selected(), Station.DOCKING_BAY_NAME, "a buoy pick leaves the target alone")
		assert_eq(DebugConsole.registry.read("target_menu.waypoint")["value"], buoy.to_upper(), "and marks the waypoint")
	else:
		_run("targetmenu close")
		await _ticks(2)


func test_the_console_the_wheel_and_the_nose_move_the_selection_between_them() -> void:
	await _start()
	await _target(station.docking_bay.targetable)
	assert_true(_run("set targeting.selected \"%s\"" % Station.CARGO_BAY_NAME).ok)
	assert_eq(_selected(), Station.CARGO_BAY_NAME, "the console")
	await _ticks(2)
	assert_eq(_selected(), Station.CARGO_BAY_NAME, "and nothing forces it back")
	# The mouse wheel cycles every target by range: both bays and the gate come round.
	var seen: Dictionary = {}
	for i: int in main.ship.targeting.candidates().size() + 1:
		source.push_wheel(1)
		await _ticks(2)
		seen[_selected()] = true
	for wanted: String in [Station.DOCKING_BAY_NAME, Station.CARGO_BAY_NAME, "JUMPGATE"]:
		assert_true(seen.has(wanted), "the wheel reaches %s (%s)" % [wanted, ", ".join(seen.keys())])
	# The nose: the target nearest it.
	var cargo: Vector3 = station.cargo_bay.global_position
	main.ship.reset_to(Transform3D(Basis.looking_at(cargo - main.ship.global_position, station.global_basis.y),
			main.ship.global_position))
	await _ticks(2)
	source.hold(InputAdapter.TARGET_AHEAD)
	await _ticks(2)
	source.release(InputAdapter.TARGET_AHEAD)
	await _ticks(1)
	assert_eq(_selected(), Station.CARGO_BAY_NAME, "target ahead picks the bay on the nose")
	# The radar shows all three, the selected one marked.
	var f: HudFrame = HudLayout.compute(main._build_hud_input())
	for marker: Targetable in [station.docking_bay.targetable, station.cargo_bay.targetable, main.gates.gate().targetable]:
		assert_true(f.radar_plot.ids.has(marker.get_instance_id()), "the radar shows %s" % marker.display_name)


func test_the_target_buttons_tap_takes_an_enemy_and_x_keeps_the_bay() -> void:
	await _start(1)
	await _target(station.docking_bay.targetable)
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(5)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(2)
	assert_true(main.adapter.autotrack_on, "a tap of X tracks")
	assert_eq(_selected(), Station.DOCKING_BAY_NAME, "the selected bay: auto-track picks only when nothing is selected")
	var at: UniversePos = main.world.to_universe(main.ship.global_position).plus_local(main.ship.global_basis * Vector3(0, 0, -900))
	var raider: Combatant = main.ships.acquire("RAIDER 1", at, Basis.IDENTITY, Vector3.ZERO, IdleBrain.new())
	raider.damageable.invulnerable = true
	await _ticks(3)
	source.hold(InputAdapter.TARGET_CYCLE)
	await _ticks(3)
	source.release(InputAdapter.TARGET_CYCLE)
	await _ticks(2)
	assert_eq(_selected(), "RAIDER 1", "the target button's tap takes the nearest enemy, from a bay too")


# Holds X for `ticks` and lets go; returns the bar's peak and how many interactions ran meanwhile.
func _hold_x(ticks: int) -> Dictionary:
	var runs: int = main.interactions.runs
	var peak: float = 0.0
	source.hold(InputAdapter.AUTOTRACK)
	for i: int in ticks:
		await _ticks(1)
		peak = maxf(peak, main.adapter.last.ui.interact_progress)
		peak = maxf(peak, HudLayout.compute(main._build_hud_input()).interact_progress)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(1)
	return {"peak": peak, "runs": main.interactions.runs - runs}


# The maintainer's rules: the gate takes a request only within 2 km (M7-T28), and no button is prompted out of range. At 3 km the
# HUD says how close to come, with no button; the hold does nothing (no bar, no progress, no jump). At 1.8 km the prompt names
# the buttons and the hold jumps.
func test_the_gate_prompts_and_holds_only_within_two_km() -> void:
	await _start()
	var gate: Jumpgate = main.gates.gate()
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "3"}).ok)
	await _ticks(3)
	assert_true(main.ship.targeting.select_id(gate.targetable.get_instance_id()))
	await _ticks(2)
	assert_null(main.interactions.offer(), "not offered 3 km out")
	assert_eq(main.interactions.prompt_line(), "JUMPGATE: 3.0 km — CLOSE TO 2.0 km TO JUMP", "a status, no button")
	var far: Dictionary = await _hold_x(125)
	assert_eq(far["peak"], 0.0, "no bar and no progress out of range")
	assert_eq(far["runs"], 0)
	assert_false(main.gates.jump.is_active(), "no jump from 3 km")
	assert_true(main.gates._cmd_gate({&"action": &"approach", &"option": "1.8"}).ok)
	await _ticks(3)
	assert_true(main.ship.targeting.select_id(gate.targetable.get_instance_id()))
	await _ticks(1)
	assert_eq(main.interactions.prompt_line(), "HOLD X / SHIFT / MOUSE 4: JUMP", "within 2 km: the buttons")
	source.hold(InputAdapter.AUTOTRACK)
	await _ticks(125)
	source.release(InputAdapter.AUTOTRACK)
	await _ticks(1)
	assert_true(main.gates.jump.is_active(), "1.8 km out the hold starts the jump")
	main.gates.cancel_jump()


func test_a_bay_prompts_and_holds_only_within_its_reach() -> void:
	await _start()
	var bay: Targetable = station.docking_bay.targetable
	var at: Vector3 = bay.global_position + station.global_basis * Vector3(0.0, 0.0, -5000.0)
	main.ship.reset_to(Transform3D(Basis.looking_at(bay.global_position - at, station.global_basis.y), at))
	await _ticks(3)
	assert_true(main.ship.targeting.select_id(bay.get_instance_id()))
	await _ticks(1)
	assert_null(main.interactions.offer(), "5 km from the bay: out of reach")
	assert_eq(main.interactions.prompt_line(), "BABYLON 5 DOCKING BAY: 5.0 km — CLOSE TO 2.0 km TO DOCK")
	var far: Dictionary = await _hold_x(125)
	assert_eq(far["peak"], 0.0, "no bar")
	assert_eq(far["runs"], 0, "and nothing runs")
	await _target(bay)
	assert_eq(main.interactions.prompt_line(), "HOLD X / SHIFT / MOUSE 4: DOCK", "1.5 km: the buttons")
	var near: Dictionary = await _hold_x(125)
	assert_gt(near["peak"], 0.9, "the bar fills within reach")
	assert_eq(near["runs"], 1)
