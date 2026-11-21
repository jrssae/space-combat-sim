extends GutTest
## `CapitalSubsystems` (M10-T18, Q17), pure: what a pilot can pick on a capital, in group order with its state and health; the
## cycle through them and back to the whole ship; and the target menu's subsystem rings built on it.

const HULL: float = 10000.0
const LAYOUT: Array = [
	["bow", "structure", 0.20], ["bridge", "bridge", 0.05], ["hangar", "hangar", 0.12], ["reactor", "reactor", 0.15],
	["engine_r", "engine", 0.075], ["engine_l", "engine", 0.075], ["spine", "structure", 0.15],
]


func _damage() -> CapitalDamage:
	var sections := CapitalSections.new()
	for i: int in LAYOUT.size():
		var row: Array = LAYOUT[i]
		sections.by_name[row[0]] = {"name": row[0], "kind": row[1], "hull_share": row[2], "piece": "hull",
				"aabb_min": [-20.0, -20.0, 100.0 * i], "aabb_max": [20.0, 20.0, 100.0 * i + 100.0]}
	var weapons: Array = []
	for i: int in 10:  # ten turrets: more than a ring holds
		weapons.append({"name": "turret_%d" % i, "section": "bow", "kind": "turret", "weapon": "ea_plasma_heavy",
				"position": [0.0, 20.0, 10.0 * i]})
	weapons.append({"name": "beam_1", "section": "reactor", "kind": "beam", "weapon": "ea_sweep_beam", "position": [20.0, 0.0, 350.0]})
	weapons.append({"name": "dome", "section": "engine_r", "kind": "interceptor", "position": [20.0, 0.0, 450.0]})
	weapons.append({"name": "mine_1", "section": "spine", "kind": "mine", "position": [0.0, 0.0, 650.0]})
	var hardpoints: Dictionary = {
		"weapons": weapons,
		"bays": [{"name": "bay_1", "section": "hangar"}, {"name": "bay_2", "section": "hangar"}],
		"engines": [{"name": "eng_r", "section": "engine_r", "share": 0.5}, {"name": "eng_l", "section": "engine_l", "share": 0.5}],
	}
	return CapitalDamage.build(sections, hardpoints, HULL)


func _groups(entries: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in entries:
		if not out.has(e["group"]):
			out.append(e["group"])
	return out


func test_every_kind_the_pilot_can_pick_is_listed_in_group_order() -> void:
	var entries: Array[Dictionary] = CapitalSubsystems.list(_damage())
	assert_eq(_groups(entries), ["bridge", "reactor", "engines", "bays", "turrets", "beams"] as Array[String],
			"no missiles aboard: no group; the mine is not a target")
	assert_eq(CapitalSubsystems.members(entries, "turrets").size(), 11, "ten turrets and the interceptor dome")
	assert_true(CapitalSubsystems.find(entries, "mount:mine_1").is_empty())
	assert_eq(CapitalSubsystems.find(entries, "bridge:bridge")["point"], Vector3(0.0, 0.0, 150.0), "a section sits at its box's centre")
	assert_eq(CapitalSubsystems.find(entries, "mount:beam_1")["point"], Vector3(20.0, 0.0, 350.0), "a mount where it is mounted")


func test_mounts_nearest_the_pilot_come_first() -> void:
	var entries: Array[Dictionary] = CapitalSubsystems.list(_damage(), Vector3(0.0, 20.0, 95.0))
	var turrets: Array[Dictionary] = CapitalSubsystems.members(entries, "turrets")
	assert_eq(turrets[0]["key"], "mount:turret_9")
	assert_eq(turrets[1]["key"], "mount:turret_8")


func test_states_and_health_follow_the_damage_model() -> void:
	var d: CapitalDamage = _damage()
	assert_eq(CapitalSubsystems.find(CapitalSubsystems.list(d), "bridge:bridge")["state"], "intact")
	d.hit("bridge", Vector3(0.0, 0.0, 150.0), 250.0)  # half of the bridge's 500 points
	var bridge: Dictionary = CapitalSubsystems.find(CapitalSubsystems.list(d), "bridge:bridge")
	assert_eq(bridge["state"], "damaged")
	assert_almost_eq(float(bridge["fraction"]), 0.5, 1e-6)
	assert_eq(CapitalSubsystems.state_text(bridge), "DAMAGED 50%")
	d.hit_mount("turret_3", 1.0e6)
	var turret: Dictionary = CapitalSubsystems.find(CapitalSubsystems.list(d), "mount:turret_3")
	assert_eq(turret["state"], "destroyed")
	assert_false(turret["works"])
	d.hit("engine_r", Vector3(0.0, 0.0, 450.0), 1.0e6)  # engine_r lost: its engine and the dome on it
	var entries: Array[Dictionary] = CapitalSubsystems.list(d)
	assert_eq(CapitalSubsystems.find(entries, "engine:eng_r")["state"], "disabled")
	assert_false(CapitalSubsystems.find(entries, "engine:eng_r")["works"])
	assert_true(CapitalSubsystems.find(entries, "engine:eng_l")["works"])
	assert_false(CapitalSubsystems.find(entries, "mount:dome")["works"], "a mount with its section lost does not work")


func test_cycling_runs_through_every_subsystem_and_the_whole_ship() -> void:
	var entries: Array[Dictionary] = CapitalSubsystems.list(_damage())
	var key: String = ""
	var seen: Array[String] = []
	for i: int in entries.size():
		key = CapitalSubsystems.cycled(entries, key)
		seen.append(key)
	assert_eq(seen.size(), entries.size())
	assert_false(seen.has(""), "every subsystem comes up before the whole ship")
	assert_eq(CapitalSubsystems.cycled(entries, key), "", "after the last: the whole ship")
	assert_eq(CapitalSubsystems.cycled(entries, "", -1), key, "backwards from the whole ship: the last")
	assert_eq(CapitalSubsystems.cycled(entries, "mount:gone"), entries[0]["key"], "a subsystem that is gone counts as the whole ship")


func test_without_a_damage_model_there_is_nothing_to_pick() -> void:
	assert_true(CapitalSubsystems.list(null).is_empty())
	assert_eq(CapitalSubsystems.cycled([] as Array[Dictionary], ""), "")


# --- the target menu's rings ---------------------------------------------------------------------------------------


func _menu(with_subsystems: bool = true) -> TargetMenu:
	var menu := TargetMenu.new()
	if with_subsystems:
		var entries: Array[Dictionary] = CapitalSubsystems.list(_damage())
		menu.subsystems_of = func(id: int) -> Array[Dictionary]: return entries if id == 7 else ([] as Array[Dictionary])
	var big := TargetInfo.new(7, "EAS Agamemnon", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -9000.0))
	big.broadcast_range_m = 1.0e5
	var small := TargetInfo.new(8, "Raider", Factions.RAIDERS, Vector3(0.0, 0.0, -3000.0))
	menu.open([big, small], Vector3.ZERO, Factions.RAIDERS)
	return menu


# Opens the ring of `category` and highlights the entry labelled `label` (the pilot here is a raider: the Earth hull is an enemy).
func _highlight_target(menu: TargetMenu, category: TargetCategories.Category, label: String) -> void:
	for slice: int in menu.radial.slice_count():
		if int(menu.radial.slots()[slice]["payload"]) == category:
			menu.radial.set_highlight(slice)
	menu.select()
	for slice: int in menu.radial.slice_count():
		if str(menu.radial.slots()[slice]["label"]) == label:
			menu.radial.set_highlight(slice)
			return
	fail_test("no entry %s" % label)


func test_picking_a_capital_opens_its_subsystem_ring_with_the_whole_ship_first() -> void:
	var menu: TargetMenu = _menu()
	_highlight_target(menu, TargetCategories.Category.ENEMIES, "EAS AGAMEMNON")
	assert_eq(menu.select(), {}, "a capital is not targeted yet: its subsystems come first")
	assert_true(menu.is_open())
	assert_eq(menu.subsystem_level(), 1)
	assert_eq(menu.page_name(), "subsystems")
	var labels: Array[String] = []
	for slot: Dictionary in menu.radial.slots():
		labels.append(str(slot["label"]))
	assert_eq(labels, ["WHOLE SHIP", "BRIDGE", "REACTOR", "ENGINES", "LAUNCH BAYS", "TURRETS", "BEAM EMITTERS"] as Array[String])
	assert_eq(menu.radial.slice_count(), 7, "one slice per entry")
	menu.radial.set_highlight(0)
	var pick: Dictionary = menu.select()
	assert_eq(pick["action"], TargetMenu.ACTION_TARGET)
	assert_eq(pick["id"], 7)
	assert_eq(pick["subsystem"], "", "the whole ship")
	assert_false(menu.is_open())


func test_a_group_of_one_is_picked_at_once_and_a_group_of_many_opens_its_members() -> void:
	var menu: TargetMenu = _menu()
	_highlight_target(menu, TargetCategories.Category.ENEMIES, "EAS AGAMEMNON")
	menu.select()
	menu.radial.set_highlight(1)  # BRIDGE
	var pick: Dictionary = menu.select()
	assert_eq(pick["subsystem"], "bridge:bridge")
	menu = _menu()
	_highlight_target(menu, TargetCategories.Category.ENEMIES, "EAS AGAMEMNON")
	menu.select()
	menu.radial.set_highlight(5)  # TURRETS
	assert_eq(menu.select(), {})
	assert_eq(menu.subsystem_level(), 2)
	assert_eq(menu.page_name(), "members")
	assert_eq(menu.radial.slice_count(), TargetCategories.RING_SIZE, "eleven turrets: the first eight")
	menu.radial.set_highlight(2)
	var turret: Dictionary = menu.select()
	assert_true(String(turret["subsystem"]).begins_with("mount:"))
	assert_eq(turret["id"], 7)


func test_back_walks_out_one_ring_at_a_time() -> void:
	var menu: TargetMenu = _menu()
	_highlight_target(menu, TargetCategories.Category.ENEMIES, "EAS AGAMEMNON")
	menu.select()
	menu.radial.set_highlight(5)
	menu.select()
	assert_eq(menu.subsystem_level(), 2)
	assert_true(menu.back())
	assert_eq(menu.subsystem_level(), 1)
	assert_true(menu.back())
	assert_eq(menu.subsystem_level(), 0)
	assert_eq(menu.page_name(), "enemies", "back from the subsystems lands on the ship ring, not the categories")
	assert_true(menu.back())
	assert_eq(menu.category, -1)


func test_a_ship_without_subsystems_is_targeted_at_once() -> void:
	var menu: TargetMenu = _menu()
	_highlight_target(menu, TargetCategories.Category.ALLIES, "RAIDER")
	var pick: Dictionary = menu.select()
	assert_eq(pick["action"], TargetMenu.ACTION_TARGET)
	assert_eq(pick["id"], 8)
	assert_false(menu.is_open())
	menu = _menu(false)
	_highlight_target(menu, TargetCategories.Category.ENEMIES, "EAS AGAMEMNON")
	assert_eq(menu.select()["id"], 7, "no source for subsystems: the plain pick")
