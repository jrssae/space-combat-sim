class_name ShipCatalog
extends RefCounted
## Scenario ship type -> `ShipSpec` (architecture §15.2) and the faction each type flies for by default. Scenarios and console
## commands name ships by type (`raider_fighter`); this is the one place that knows which resource flies it and whose side it
## is on. `starfury_ally` is the wingman: the Starfury's numbers with the LOD1 splats and no cockpit (§16 D35). Pure.

const PATHS: Dictionary[StringName, String] = {
	&"starfury_aurora": "res://assets/ships/starfury_aurora.tres",
	&"starfury_ally": "res://assets/ships/starfury_ally.tres",
	&"raider_fighter": "res://assets/ships/raider_delta_v.tres",
}

## The faction a ship of each type is built for (`ShipPool.prepare`); the player's own type is listed for completeness.
const FACTIONS: Dictionary[StringName, StringName] = {
	&"starfury_aurora": Factions.EARTH_ALLIANCE,
	&"starfury_ally": Factions.EARTH_ALLIANCE,
	&"raider_fighter": Factions.RAIDERS,
}


static func has_type(type: StringName) -> bool:
	return PATHS.has(type)


static func types() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(PATHS.keys())
	return out


## The faction ships of `type` fly for by default; `neutral` for a type the catalog does not list.
static func faction_for(type: StringName) -> StringName:
	return FACTIONS.get(type, Factions.NEUTRAL)


## The spec resource for `type`, or null (with a warning) for an unknown type.
static func spec_for(type: StringName) -> ShipSpec:
	if not PATHS.has(type):
		push_warning("ShipCatalog: unknown ship type '%s'" % type)
		return null
	return load(PATHS[type]) as ShipSpec
