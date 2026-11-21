extends GutTest
## Subsystems as targets on the Omega in the real main scene (M10-T18, Q17, AC12): the target menu's subsystem rings pick one, the
## pad's and keyboard's `subsystem_next` cycles them, the readout names it with its state and its point, the guns' lead and
## auto-track aim at that point, a new target clears it, and a hit on it shows in the state.

const TYPE: StringName = &"ea_omega"
const RENEGADES: StringName = &"renegades"

var main: Main
var source: FakeInputSource
var cap: CapitalShip


func before_each() -> void:
	get_tree().paused = false
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true
	cap = _spawn(1500.0)
	await wait_physics_frames(3)
	if cap != null:
		main.ship.targeting.select_id(cap.targetable.get_instance_id())


func after_each() -> void:
	get_tree().paused = false
	source.release_all()
	DebugConsole.flags.invulnerable = false


func _spawn(range_m: float) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var made: CapitalShip = CapitalShip.create(TYPE, RENEGADES, "EAS Agamemnon", rest)
	assert_not_null(made, "the Omega is generated (scripts/gen_assets.sh)")
	if made == null:
		return null
	var player: Basis = main.ship.global_basis
	var basis := Basis(player.z, player.y, -player.x)
	var target: Vector3 = main.ship.global_position - player.z * range_m
	main.world.spawn(made, main.world.to_universe(target - basis * made.rotors[0].pivot), basis)
	made.set_course(Vector3.ZERO, rest)
	return made


func _press(action: StringName) -> void:
	source.hold(action)
	await wait_physics_frames(2)
	source.release(action)
	await wait_physics_frames(2)


func test_the_pads_button_and_the_keys_cycle_through_every_subsystem_and_back_to_the_whole_ship() -> void:
	if cap == null:
		return
	var targeting: TargetingController = main.ship.targeting
	assert_eq(targeting.selected_capital(), cap, "an identified capital")
	var entries: Array[Dictionary] = targeting.subsystem_entries()
	assert_gt(entries.size(), 10, "the Omega has a bridge, reactor, engines, bays and many mounts")
	assert_eq(targeting.subsystem_key, "")
	var seen: Array[String] = []
	for i: int in entries.size():
		await _press(InputAdapter.SUBSYSTEM_NEXT)
		seen.append(targeting.subsystem_key)
	assert_eq(seen.size(), entries.size())
	assert_false(seen.has(""), "each press names a subsystem")
	assert_eq(seen.size(), Array(seen).filter(func(k: String) -> bool: return not k.is_empty()).size())
	await _press(InputAdapter.SUBSYSTEM_NEXT)
	assert_eq(targeting.subsystem_key, "", "after the last: the whole ship")


func test_the_readout_names_the_subsystem_and_the_guns_lead_it() -> void:
	if cap == null:
		return
	var targeting: TargetingController = main.ship.targeting
	var whole: TargetReadout = targeting.selected_readout()
	assert_true(whole.subsystem.is_empty())
	assert_eq(whole.aim_position(), whole.position)
	var mount: String = ""
	for entry: Dictionary in targeting.subsystem_entries():
		if entry["group"] == CapitalSubsystems.TURRETS:
			mount = entry["key"]
			break
	assert_true(targeting.select_subsystem(mount))
	var picked: TargetReadout = targeting.selected_readout()
	assert_eq(picked.subsystem["key"], mount)
	assert_eq(picked.subsystem["state"], "intact")
	var expected: Vector3 = cap.global_transform * (CapitalSubsystems.find(targeting.subsystem_entries(), mount)["point"] as Vector3)
	assert_almost_eq(picked.aim_position(), expected, Vector3.ONE * 0.01)
	assert_gt(picked.aim_offset.length(), 1.0, "a turret is not at the centre")
	# The ship's auto-track leads the subsystem: its lead offset points off the hull's centre line.
	var lead_aimed: Vector3 = main.ship.call("_lead_offset")
	targeting.select_subsystem("")
	var lead_centre: Vector3 = main.ship.call("_lead_offset")
	assert_gt((lead_aimed - lead_centre).length(), 1.0, "the lead moved with the aim point")


func test_a_hit_on_the_subsystem_shows_in_its_state_and_a_new_target_clears_it() -> void:
	if cap == null:
		return
	var targeting: TargetingController = main.ship.targeting
	assert_true(targeting.select_subsystem("bridge:bridge"))
	assert_eq(targeting.selected_readout().subsystem["state"], "intact")
	assert_true(DebugConsole.registry.execute_tokens(["capital", "damage", "bridge", "100"]).ok)
	assert_eq(targeting.selected_readout().subsystem["state"], "damaged")
	assert_lt(float(targeting.selected_readout().subsystem["fraction"]), 1.0)
	targeting.clear_selection()
	assert_eq(targeting.subsystem_key, "", "no target, no subsystem")
	targeting.select_id(cap.targetable.get_instance_id())
	assert_eq(targeting.subsystem_key, "", "a fresh selection starts on the whole ship")


func test_the_console_sets_and_lists_subsystems() -> void:
	if cap == null:
		return
	var targeting: TargetingController = main.ship.targeting
	assert_true(DebugConsole.registry.execute_tokens(["set", "targeting.subsystem", "reactor:reactor"]).ok)
	assert_eq(targeting.subsystem_key, "reactor:reactor")
	assert_false(DebugConsole.registry.execute_tokens(["set", "targeting.subsystem", "mount:nope"]).ok)
	assert_true(DebugConsole.registry.execute_tokens(["set", "targeting.subsystem", "whole"]).ok)
	assert_eq(targeting.subsystem_key, "")


func test_the_target_menu_picks_a_subsystem_through_its_rings() -> void:
	if cap == null:
		return
	var director: TargetMenuDirector = main.target_menu
	main.ship.targeting.clear_selection()
	await wait_physics_frames(2)
	assert_eq(director.open(), "")
	var found: bool = false
	for first: int in director.menu.radial.slice_count():
		director.menu.radial.set_highlight(first)
		director.select()  # a category
		for slice: int in director.menu.radial.slice_count():
			if str(director.menu.radial.slots()[slice].get("label", "")) == "EAS AGAMEMNON":
				director.menu.radial.set_highlight(slice)
				found = true
		if found:
			break
		director.back()
	assert_true(found, "the capital is on a ring")
	director.select()
	assert_true(director.is_open(), "the subsystem ring opens instead of targeting")
	assert_eq(director.menu.subsystem_level(), 1)
	assert_eq(str(director.menu.radial.slots()[0]["label"]), "WHOLE SHIP")
	var slice: int = -1
	for i: int in director.menu.radial.slice_count():
		if str(director.menu.radial.slots()[i]["label"]) == "REACTOR":
			slice = i
	assert_gte(slice, 0, "the reactor is a group of its own")
	director.menu.radial.set_highlight(slice)
	director.select()
	await wait_physics_frames(2)
	assert_false(director.is_open())
	assert_eq(main.ship.targeting.selected_id(), cap.targetable.get_instance_id())
	assert_eq(main.ship.targeting.subsystem_key, "reactor:reactor")
	assert_false(get_tree().paused)
