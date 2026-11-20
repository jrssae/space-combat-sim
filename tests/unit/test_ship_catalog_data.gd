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
	var twice: String = '{"id": "a", "spec": "res://a.tres", "asset": "a", "faction": "x", "role": "fighter"}'
	assert_string_contains(_parse('{"ships": [%s, %s]}' % [twice, twice]).error, "twice")


func test_a_bad_file_is_empty() -> void:
	var data: ShipCatalogData = _parse("[1]")
	assert_eq(data.ids(), [] as Array[StringName])
	assert_false(data.has(&"a"))
