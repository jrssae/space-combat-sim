extends GutTest
## ShipCatalogData (M10-T61): the ship catalogue file parsed and checked, and its lists in file order.

const GOOD: String = """{"ships": [
	{"id": "a_fighter", "spec": "res://a.tres", "asset": "a", "faction": "earth_alliance", "role": "fighter",
		"name": "A fighter", "look_sheet": "pool"},
	{"id": "b_hauler", "spec": "res://b.tres", "asset": "b", "faction": "narn", "role": "civilian", "ai_profile": "civilian",
		"docking": "tunnel", "callsign": "BEE"},
	{"id": "c_carrier", "spec": "res://c.tres", "asset": "c", "faction": "raiders", "role": "capital",
		"capital_class": "strike_carrier", "pooled": false, "look_sheet": "hull"},
	{"id": "d_hauler", "spec": "res://d.tres", "asset": "d", "faction": "brakiri", "role": "civilian", "docking": "tunnel"}
]}"""


func _parse(text: String) -> ShipCatalogData:
	return ShipCatalogData.parse(text, "test")


func _with(entry: String) -> String:
	return '{"ships": [%s]}' % entry


func test_a_good_file_parses_in_order() -> void:
	var data: ShipCatalogData = _parse(GOOD)
	assert_eq(data.error, "")
	assert_eq(data.ids(), [&"a_fighter", &"b_hauler", &"c_carrier", &"d_hauler"] as Array[StringName])
	assert_true(data.has(&"b_hauler"))
	assert_false(data.has(&"nothing"))


func test_pooled_ids_leave_out_hulls_built_another_way() -> void:
	var data: ShipCatalogData = _parse(GOOD)
	assert_eq(data.pooled_ids(), [&"a_fighter", &"b_hauler", &"d_hauler"] as Array[StringName])
	assert_true(data.is_pooled(&"a_fighter"))
	assert_false(data.is_pooled(&"c_carrier"))
	assert_false(data.is_pooled(&"nothing"))


func test_fields_and_their_defaults() -> void:
	var data: ShipCatalogData = _parse(GOOD)
	assert_eq(data.spec_path(&"a_fighter"), "res://a.tres")
	assert_eq(data.faction(&"b_hauler"), &"narn")
	assert_eq(data.role(&"c_carrier"), &"capital")
	assert_eq(data.text(&"c_carrier", "capital_class"), "strike_carrier")
	assert_eq(data.text(&"a_fighter", "ai_profile"), "", "an absent key reads empty")
	assert_eq(data.text(&"nothing", "faction"), "", "an unknown id reads empty")
	assert_eq(data.text(&"b_hauler", "callsign"), "BEE")


func test_ids_where_keeps_file_order_and_is_read_only() -> void:
	var data: ShipCatalogData = _parse(GOOD)
	var tunnel: Array[StringName] = data.ids_where("docking", "tunnel")
	assert_eq(tunnel, [&"b_hauler", &"d_hauler"] as Array[StringName])
	assert_true(tunnel.is_read_only(), "a shared list, like the consts it replaces")
	assert_eq(data.ids_where("role", "civilian"), tunnel)
	assert_eq(data.ids_where("docking", "nowhere"), [] as Array[StringName])


func test_a_civilian_marked_out_of_the_random_pool_is_still_a_civilian() -> void:
	var marked: String = GOOD.replace('"docking": "tunnel", "callsign": "BEE"', '"docking": "tunnel", "callsign": "BEE", "random_pool": false')
	var data: ShipCatalogData = _parse(marked)
	assert_eq(data.error, "")
	assert_eq(data.civilian_pool(), [&"d_hauler"] as Array[StringName], "random picks leave it out")
	assert_eq(data.ids_where("role", "civilian"), [&"b_hauler", &"d_hauler"] as Array[StringName], "its role stands")
	assert_false(data.in_random_pool(&"b_hauler"))
	assert_true(data.in_random_pool(&"d_hauler"), "the default")
	assert_eq(_parse(GOOD).civilian_pool(), [&"b_hauler", &"d_hauler"] as Array[StringName])


func test_a_traffic_only_civilian_joins_the_traffic_of_a_scenario_that_pools_it() -> void:
	var marked: String = GOOD.replace('"docking": "tunnel", "callsign": "BEE"', '"docking": "tunnel", "callsign": "BEE", "traffic_only": true')
	var data: ShipCatalogData = _parse(marked)
	assert_eq(data.error, "")
	assert_eq(data.civilian_pool(), [&"d_hauler"] as Array[StringName], "the missions' random civilian never draws it")
	assert_true(data.in_random_pool(&"b_hauler"), "it is still random traffic")
	assert_true(data.is_traffic_only(&"b_hauler"))
	assert_false(data.is_traffic_only(&"d_hauler"))
	assert_eq(data.traffic_pool({}), data.civilian_pool(), "a scenario that pools none draws as it always did")
	assert_eq(data.traffic_pool({&"b_hauler": 0}), data.civilian_pool(), "an empty pool is no pool")
	assert_eq(data.traffic_pool({&"b_hauler": 2}), [&"b_hauler", &"d_hauler"] as Array[StringName], "pooled: it joins, in file order")
	# M10 Q99: it docks only where it is pooled, so the older scenarios' seeded docking hulls hold.
	assert_eq(_parse(GOOD).docking_pool("tunnel", {}), [&"b_hauler", &"d_hauler"] as Array[StringName])
	assert_eq(data.docking_pool("tunnel", {}), [&"d_hauler"] as Array[StringName], "not drawn for the bay where no pool lists it")
	assert_eq(data.docking_pool("tunnel", {&"b_hauler": 1}), [&"b_hauler", &"d_hauler"] as Array[StringName], "drawn where it is pooled")
	assert_eq(data.ids_where("docking", "tunnel"), [&"b_hauler", &"d_hauler"] as Array[StringName], "it fits the bay all the same")
	assert_string_contains(_parse(marked.replace('"traffic_only": true', '"traffic_only": "yes"')).error, "traffic_only")


func test_by_asset_maps_each_asset_once_to_the_first_entry_with_a_value() -> void:
	var data: ShipCatalogData = _parse(GOOD)
	assert_eq(data.by_asset("name"), {"a": "A fighter"})
	assert_eq(data.by_asset("look_sheet", "pool"), {"a": &"a_fighter"}, "asset -> the type that shows it")
	assert_eq(data.by_asset("look_sheet", "hull"), {"c": &"c_carrier"})
	assert_true(data.by_asset("name").is_read_only(), "shared")


func test_bad_files_say_why() -> void:
	assert_string_contains(_parse("[1]").error, "JSON object")
	assert_string_contains(_parse('{"ships": {}}').error, "ships")
	assert_string_contains(_parse(_with('{"spec": "res://a.tres", "asset": "a", "faction": "x", "role": "fighter"}')).error, "id")
	assert_string_contains(_parse(_with('{"id": "a", "asset": "a", "faction": "x", "role": "fighter"}')).error, "spec")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "faction": "x", "role": "fighter"}')).error, "asset")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "role": "fighter"}')).error, "faction")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "boat"}')).error,
			"role")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "capital"}')).error,
			"capital_class")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "fighter", "docking": "moon"}')).error,
			"docking")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "fighter", "look_sheet": "x"}')).error,
			"look_sheet")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "fighter", "colour": "red"}')).error,
			"colour")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "civilian", "random_pool": "no"}')).error,
			"random_pool")
	var twice: String = '{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "fighter"}'
	assert_string_contains(_parse('{"ships": [%s, %s]}' % [twice, twice]).error, "twice")


func test_a_bad_file_is_empty() -> void:
	var data: ShipCatalogData = _parse("[1]")
	assert_eq(data.ids(), [] as Array[StringName])
	assert_false(data.has(&"a"))


func test_finalized_hulls_are_listed_for_the_line_up() -> void:
	var marked: String = GOOD.replace('"docking": "tunnel", "callsign": "BEE"', '"docking": "tunnel", "callsign": "BEE", "finalized": true')
	var data: ShipCatalogData = _parse(marked)
	assert_eq(data.error, "")
	assert_eq(data.finalized_ids(), [&"b_hauler"] as Array[StringName])
	assert_eq(_parse(GOOD).finalized_ids(), [] as Array[StringName], "default: not finalized")
	assert_string_contains(_parse(_with('{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "civilian", "finalized": "yes"}')).error,
			"finalized must be true or false")
