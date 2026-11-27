class_name ShipCatalog
extends RefCounted
## Scenario ship type -> `ShipSpec` (architecture §15.2), the faction each type flies for by default and the other per-type facts,
## read from the ship catalogue (`data/ships/catalogue.json`, M10-T61; its keys are in `ShipCatalogData`). Scenarios and console
## commands name ships by type (`raider_fighter`); adding a hull is one catalogue entry and one `.tres`. `starfury_ally` is the
## wingman: the Starfury's numbers and hull with no cockpit (§16 D35). The civilian hulls (M5-T16, D59) fly for their own people's
## faction with the `civilian` role (Q24): the role, not the faction, says what they are.
##
## `has_type`, `types`, `faction_for`, `spec_for` and `is_civilian` answer for the pooled types only (what `ShipPool` builds);
## `entry_text` and `types_where` see every entry.

## The type the player flies (`Main` builds it, and every Starfury breaks up into its asset's chunks).
const PLAYER_TYPE: StringName = &"starfury_aurora"
const FILE: String = "res://data/ships/catalogue.json"

static var _data: ShipCatalogData = null


## The catalogue in use, read on first use.
static func data() -> ShipCatalogData:
	if _data == null:
		_data = ShipCatalogData.load_file(FILE)
		if not _data.error.is_empty():
			push_error("ShipCatalog: %s" % _data.error)
	return _data


## Swaps in another catalogue file (tests registering a hull); "" on success, else why it was refused. `reset` goes back.
static func use_file(path: String) -> String:
	var other: ShipCatalogData = ShipCatalogData.load_file(path)
	if other.error.is_empty():
		_data = other
	return other.error


static func reset() -> void:
	_data = null


static func has_type(type: StringName) -> bool:
	return data().is_pooled(type)


## Whether ships of `type` carry the `civilian` role (Q24).
static func is_civilian(type: StringName) -> bool:
	return has_type(type) and data().role(type) == &"civilian"


static func types() -> Array[StringName]:
	return data().pooled_ids()


## The civilian hulls random traffic, encounters and `random_civilian` spawns draw from (M5-T16, Q24), in catalogue order: built
## with the `civilian` role, flown by the `civilian` AI profile by default. A civilian marked `random_pool: false` (the shuttles,
## M10-T57) is left out: `is_civilian` still says what it is, and a mission places it by name.
static func civilian_types() -> Array[StringName]:
	return data().civilian_pool()


## The civilian hulls the traffic and encounters of a scenario draw from: `civilian_types` and each `traffic_only` hull its
## encounter pools (`pooled`, type -> count) list (M10 Q97). A scenario that pools none of them draws as it always did.
static func traffic_types(pooled: Dictionary) -> Array[StringName]:
	return data().traffic_pool(pooled)


## The behaviour a civilian of `type` flies in traffic and encounters: its catalogue profile, the plain `civilian` without one.
static func civilian_behaviour(type: StringName) -> Dictionary:
	var profile: String = entry_text(type, "ai_profile")
	return {"type": "ai", "profile": profile if AiProfile.PATHS.has(StringName(profile)) else "civilian"}


## The hulls that dock at `value` in a scenario whose encounter pools are `pooled`: see `ShipCatalogData.docking_pool`.
static func docking_types(value: String, pooled: Dictionary) -> Array[StringName]:
	return data().docking_pool(value, pooled)


## The types whose catalogue `key` is `value`, pooled or not, in catalogue order.
static func types_where(key: String, value: String) -> Array[StringName]:
	return data().ids_where(key, value)


## A text field of `type`'s catalogue entry ("" when absent), pooled or not.
static func entry_text(type: StringName, key: String) -> String:
	return data().text(type, key)


## The faction ships of `type` fly for by default; `neutral` for a type the catalog does not list.
static func faction_for(type: StringName) -> StringName:
	return data().faction(type) if has_type(type) else Factions.NEUTRAL


## The spec resource for `type`, or null (with a warning) for an unknown type.
static func spec_for(type: StringName) -> ShipSpec:
	if not has_type(type):
		push_warning("ShipCatalog: unknown ship type '%s'" % type)
		return null
	return load(data().spec_path(type)) as ShipSpec
