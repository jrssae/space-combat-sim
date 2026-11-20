extends GutTest
## The ship catalogue (M10-T61) answers what the per-type lists it replaced answered: types, specs, factions, roles, the docking,
## look-sheet, class-name and callsign lists, all in their old order (seeded picks index into them). The old answers were captured
## from the code before the catalogue (`tests/fixtures/ships/catalog_before_t61.json`).

const RECORDING: String = "res://tests/fixtures/ships/catalog_before_t61.json"

var _old: Dictionary = {}


func before_all() -> void:
	_old = JSON.parse_string(FileAccess.get_file_as_string(RECORDING))


func _names(list: Array) -> Array[String]:
	var out: Array[String] = []
	for item: Variant in list:
		out.append(str(item))
	return out


func test_the_types_in_their_order() -> void:
	assert_eq(_names(ShipCatalog.types()), _names(_old["types"]))


func test_every_type_gives_the_same_spec_faction_role_and_callsign() -> void:
	var per_type: Dictionary = _old["per_type"]
	for id: String in per_type:
		var was: Dictionary = per_type[id]
		var type := StringName(id)
		assert_eq(ShipCatalog.has_type(type), was["has_type"], "%s: listed" % id)
		assert_eq(String(ShipCatalog.faction_for(type)), was["faction"], "%s: faction" % id)
		assert_eq(ShipCatalog.is_civilian(type), was["civilian"], "%s: the civilian role" % id)
		assert_eq(EncounterDirector.civilian_callsign(type), was["callsign"], "%s: callsign" % id)
		if not bool(was["has_type"]):
			continue
		var spec: ShipSpec = ShipCatalog.spec_for(type)
		assert_eq(spec.resource_path, was["spec"], "%s: spec" % id)
		assert_eq(spec.asset_id, was["asset"], "%s: asset" % id)


func test_the_lists_in_their_order() -> void:
	assert_eq(_names(ShipCatalog.civilian_types()), _names(_old["civilian_types"]), "the civilians")
	assert_eq(_names(DockingPlan.tunnel_types()), _names(_old["tunnel_types"]), "the docking tunnel's hulls")
	assert_eq(_names(DockingPlan.freighter_types()), _names(_old["freighter_types"]), "the cargo bay's Saturns")
	assert_eq(_names(LookScene.hull_assets()), _names(_old["look_hull_assets"]), "the bare capital hulls")
	var pairs: Array = []
	var pool: Dictionary = LookScene.pool_types()
	for asset: Variant in pool:
		pairs.append([str(asset), String(pool[asset])])
	assert_eq(pairs, _old["look_pool_types"], "the look sheets' pooled types")


func test_the_class_names() -> void:
	var texts: Dictionary = _old["class_texts"]
	for asset_id: String in texts:
		assert_eq(TargetPreviewModel.class_text(asset_id), texts[asset_id], asset_id)
