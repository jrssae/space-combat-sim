extends GutTest
## TargetPreviewModel, pure (architecture §18.20, M5-T43): the preview panel's title, class line and rows for each kind of
## entry the target menu lists.

const EA: StringName = Factions.EARTH_ALLIANCE
const OWN := Vector3.ZERO
const OWN_VELOCITY := Vector3(0, 0, -50)


func after_each() -> void:
	Factions.reset()


func _info(name: String, faction: StringName, at: Vector3, velocity: Vector3 = Vector3.ZERO, hull: float = 1.0,
		role: Targetable.Role = Targetable.Role.SHIP, broadcast_m: float = 0.0) -> TargetInfo:
	var info := TargetInfo.new(7, name, faction, at, velocity, hull, 10.0)
	info.role = role
	info.broadcast_range_m = broadcast_m
	return info


func _fields(model: TargetPreviewModel) -> Array:
	return model.rows.map(func(entry: Dictionary) -> StringName: return entry["field"])


func test_a_fighter_shows_its_name_class_faction_hull_range_and_closing_speed() -> void:
	var raider: TargetInfo = _info("Raider 2", Factions.RAIDERS, Vector3(0, 0, -1900), Vector3(0, 0, 90), 0.61)
	var model: TargetPreviewModel = TargetPreviewModel.contact(raider, OWN, OWN_VELOCITY, EA, {"asset_id": "raider_fighter"})
	assert_eq(model.kind, TargetPreviewModel.Kind.SHIP)
	assert_eq(model.target_id, 7)
	assert_eq(model.title, "RAIDER 2")
	assert_eq(model.title_color, Factions.HOSTILE_COLOR, "the name is in the IFF colour")
	assert_eq(model.subtitle, "Delta-V raider · Raiders")
	assert_eq(model.hull_id, "raider_fighter")
	assert_eq(model.flag, "")
	assert_eq(_fields(model), [&"hull", &"range", &"closing"], "no weapons, speed or heading; no pods on a hull without mounts")
	assert_eq(model.row(&"hull")["value"], "61 %")
	assert_almost_eq(float(model.row(&"hull")["bar"]), 0.61, 1e-6)
	assert_eq(model.row(&"hull")["color"], HudLayout.hull_color(0.61))
	assert_eq(model.row(&"range")["value"], "1.9 km")
	assert_eq(model.row(&"closing")["value"], "+140 m/s", "the two ships fly at each other")


func test_the_closing_speed_is_signed_and_the_range_reads_as_the_ring_does() -> void:
	assert_eq(TargetPreviewModel.closing_text(120.4), "+120 m/s")
	assert_eq(TargetPreviewModel.closing_text(-40.0), "-40 m/s")
	assert_eq(TargetPreviewModel.closing_text(-0.2), "+0 m/s", "no minus zero")
	var opening: TargetInfo = _info("Raider 1", Factions.RAIDERS, Vector3(0, 0, -850), Vector3(0, 0, -90))
	var model: TargetPreviewModel = TargetPreviewModel.contact(opening, OWN, OWN_VELOCITY, EA, {"asset_id": "raider_fighter"})
	assert_eq(model.row(&"closing")["value"], "-40 m/s")
	assert_eq(model.row(&"range")["value"], "850 m")


func test_the_attacker_flag_is_for_an_identified_ship_only() -> void:
	var near: TargetInfo = _info("Raider 2", Factions.RAIDERS, Vector3(0, 0, -900))
	var far: TargetInfo = _info("Raider 3", Factions.RAIDERS, Vector3(0, 0, -9000))
	var facts: Dictionary = {"asset_id": "raider_fighter", "attacking_you": true}
	assert_eq(TargetPreviewModel.contact(near, OWN, OWN_VELOCITY, EA, facts).flag, TargetPreviewModel.FLAG_ATTACKING)
	assert_eq(TargetPreviewModel.contact(far, OWN, OWN_VELOCITY, EA, facts).flag, "")


func test_only_a_pilot_on_the_attack_counts_as_attacking() -> void:
	assert_true(TargetPreviewModel.is_attacking("attack", "pursue"))
	assert_true(TargetPreviewModel.is_attacking("ram"))
	assert_true(TargetPreviewModel.is_attacking("aggro", "attack: pursue"))
	assert_false(TargetPreviewModel.is_attacking("aggro", "patrol: waypoint 1 of 3"))
	for other: String in ["idle", "evade", "retreat", "formation", "patrol", "none", ""]:
		assert_false(TargetPreviewModel.is_attacking(other), other)


func test_an_ally_is_blue_and_a_damaged_hull_turns_the_bar() -> void:
	var ally: TargetInfo = _info("Alpha 3", EA, Vector3(200, 0, 0), Vector3.ZERO, 0.2, Targetable.Role.SHIP, 100000.0)
	var model: TargetPreviewModel = TargetPreviewModel.contact(ally, OWN, OWN_VELOCITY, EA, {"asset_id": "starfury_aurora"})
	assert_eq(model.title_color, Factions.FRIENDLY_COLOR)
	assert_eq(model.subtitle, "Aurora Starfury · Earth Alliance")
	assert_eq(model.row(&"hull")["value"], "20 %")
	assert_eq(model.row(&"hull")["color"], HudLayout.hull_color(0.2))


func test_a_civilian_with_pod_mounts_adds_its_cargo_pods() -> void:
	var bokmai: TargetInfo = _info("Bokmai 1", &"brakiri", Vector3(0, 0, -12000), Vector3.ZERO, 1.0, Targetable.Role.CIVILIAN, 15000.0)
	var model: TargetPreviewModel = TargetPreviewModel.contact(bokmai, OWN, OWN_VELOCITY, EA,
			{"asset_id": "brakiri_bokmai", "cargo_pods": 2, "cargo_mounts": 3})
	assert_eq(model.kind, TargetPreviewModel.Kind.SHIP, "its transponder identifies it beyond 5 km")
	assert_eq(model.subtitle, "Bokmai hauler · Brakiri Syndicracy")
	assert_eq(model.title_color, Factions.NEUTRAL_COLOR)
	assert_eq(_fields(model), [&"hull", &"range", &"closing", &"cargo"])
	assert_eq(model.row(&"cargo")["value"], "2 of 3")
	var tanker: TargetInfo = _info("Tanker 1", EA, Vector3(0, 0, -3000), Vector3.ZERO, 1.0, Targetable.Role.CIVILIAN, 15000.0)
	model = TargetPreviewModel.contact(tanker, OWN, OWN_VELOCITY, EA, {"asset_id": "saturn_8_tanker"})
	assert_null(model.row(&"cargo"), "a hull without pod mounts has no cargo line")
	assert_eq(model.subtitle, "Saturn 8 tanker · Earth Alliance")


func test_a_buoy_shows_its_kind_and_no_hull_bar() -> void:
	var buoy: TargetInfo = _info("NAV ALPHA", Factions.NEUTRAL, Vector3(0, 0, -42000), Vector3.ZERO, -1.0, Targetable.Role.BEACON, 1.0e6)
	var model: TargetPreviewModel = TargetPreviewModel.contact(buoy, OWN, OWN_VELOCITY, EA, {"asset_id": "nav_buoy"})
	assert_eq(model.kind, TargetPreviewModel.Kind.BEACON)
	assert_eq(model.title, "NAV ALPHA")
	assert_eq(model.subtitle, "Nav buoy · Neutral")
	assert_eq(model.hull_id, "nav_buoy")
	assert_eq(_fields(model), [&"range", &"closing"])
	assert_eq(model.row(&"range")["value"], "42.0 km")
	assert_eq(model.row(&"closing")["value"], "+50 m/s")


func test_an_unknown_contact_gives_away_neither_its_name_nor_its_hull() -> void:
	var far: TargetInfo = _info("Raider 9", Factions.RAIDERS, Vector3(0, 0, -7000), Vector3.ZERO, 0.4)
	var model: TargetPreviewModel = TargetPreviewModel.contact(far, OWN, OWN_VELOCITY, EA,
			{"asset_id": "raider_fighter", "attacking_you": true, "cargo_pods": 1, "cargo_mounts": 3})
	assert_eq(model.kind, TargetPreviewModel.Kind.UNKNOWN)
	assert_eq(model.title, TargetMenu.UNKNOWN_LABEL)
	assert_eq(model.title_color, Factions.UNIDENTIFIED_COLOR)
	assert_eq(model.hull_id, "", "no wireframe of a hull that is not identified")
	assert_eq(model.placeholder, TargetPreviewModel.NO_ID)
	assert_false(model.subtitle.contains("raider") or model.subtitle.contains("Raider"))
	assert_eq(model.flag, "")
	assert_eq(_fields(model), [&"range", &"closing"], "no hull bar either")


func test_an_objective_shows_its_text_instead_of_a_hull() -> void:
	var entry: Dictionary = {"text": "Escort the convoy to the jump gate", "label": "convoy_1", "target_id": 42,
			"position": Vector3(0, 0, -2500)}
	var model: TargetPreviewModel = TargetPreviewModel.objective(entry, OWN, "saturn_4_tanker")
	assert_eq(model.kind, TargetPreviewModel.Kind.OBJECTIVE)
	assert_eq(model.title, "CONVOY_1")
	assert_eq(model.title_color, TargetCategories.COLORS[TargetCategories.Category.OBJECTIVES])
	assert_eq(model.hull_id, "saturn_4_tanker", "an objective about a ship in play draws it")
	assert_eq(model.target_id, 42)
	assert_eq(_fields(model), [&"text", &"range"])
	assert_eq(model.row(&"text")["value"], "Escort the convoy to the jump gate")
	assert_eq(model.row(&"range")["value"], "2.5 km")
	assert_eq(TargetPreviewModel.objective({"text": "Reach the area", "label": "area"}, OWN).hull_id, "", "a bare place has no hull")


func test_none_shows_nothing() -> void:
	var model: TargetPreviewModel = TargetPreviewModel.none()
	assert_eq(model.kind, TargetPreviewModel.Kind.NONE)
	assert_eq(model.rows.size(), 0)
	assert_eq(model.hull_id, "")
	assert_eq(model.placeholder, "")


func test_every_kind_has_its_fields_and_a_hull_without_a_name_reads_as_its_id() -> void:
	for kind: TargetPreviewModel.Kind in TargetPreviewModel.Kind.values():
		assert_true(TargetPreviewModel.FIELDS.has(kind), "kind %d" % kind)
	assert_eq(TargetPreviewModel.class_text("capital_cruiser"), "Capital Cruiser")
	for type: StringName in ShipCatalog.types():
		var asset_id: String = ShipCatalog.spec_for(type).asset_id
		assert_true(TargetPreviewModel.CLASS_NAMES.has(asset_id), "%s has a class name" % asset_id)
