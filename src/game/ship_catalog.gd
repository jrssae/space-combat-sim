class_name ShipCatalog
extends RefCounted
## Scenario ship type -> `ShipSpec` (architecture §15.2) and the faction each type flies for by default. Scenarios and console
## commands name ships by type (`raider_fighter`); this is the one place that knows which resource flies it and whose side it
## is on. `starfury_ally` is the wingman: the Starfury's numbers and hull with no cockpit (§16 D35). The nine civilian hulls
## (M5-T16, D59) fly for their own people's faction with the `civilian` role (Q24): the role, not the faction, says what they
## are. Pure.

## The type the player flies (`Main` builds it, and every Starfury breaks up into its asset's chunks).
const PLAYER_TYPE: StringName = &"starfury_aurora"

const PATHS: Dictionary[StringName, String] = {
	PLAYER_TYPE: "res://assets/ships/starfury_aurora.tres",
	&"starfury_ally": "res://assets/ships/starfury_ally.tres",
	&"raider_fighter": "res://assets/ships/raider_delta_v.tres",
	&"saturn_3_freighter": "res://assets/ships/saturn_3_freighter.tres",
	&"saturn_4_transport": "res://assets/ships/saturn_4_transport.tres",
	&"saturn_4_tanker": "res://assets/ships/saturn_4_tanker.tres",
	&"saturn_8_transport": "res://assets/ships/saturn_8_transport.tres",
	&"saturn_8_tanker": "res://assets/ships/saturn_8_tanker.tres",
	&"skylark_transport": "res://assets/ships/skylark_transport.tres",
	&"narn_transport": "res://assets/ships/narn_transport.tres",
	&"centauri_brezebel": "res://assets/ships/centauri_brezebel.tres",
	&"brakiri_bokmai": "res://assets/ships/brakiri_bokmai.tres",
}

## The faction a ship of each type is built for (`ShipPool.prepare`); the player's own type is listed for completeness.
const FACTIONS: Dictionary[StringName, StringName] = {
	PLAYER_TYPE: Factions.EARTH_ALLIANCE,
	&"starfury_ally": Factions.EARTH_ALLIANCE,
	&"raider_fighter": Factions.RAIDERS,
	&"saturn_3_freighter": Factions.EARTH_ALLIANCE,
	&"saturn_4_transport": Factions.EARTH_ALLIANCE,
	&"saturn_4_tanker": Factions.EARTH_ALLIANCE,
	&"saturn_8_transport": Factions.EARTH_ALLIANCE,
	&"saturn_8_tanker": Factions.EARTH_ALLIANCE,
	&"skylark_transport": Factions.EARTH_ALLIANCE,
	&"narn_transport": &"narn",
	&"centauri_brezebel": &"centauri",
	&"brakiri_bokmai": &"brakiri",
}

## The civilian hulls (M5-T16, Q24): built with the `civilian` role, flown by the `civilian` AI profile by default.
const CIVILIAN_TYPES: Array[StringName] = [&"saturn_3_freighter", &"saturn_4_transport", &"saturn_4_tanker",
		&"saturn_8_transport", &"saturn_8_tanker", &"skylark_transport", &"narn_transport", &"centauri_brezebel",
		&"brakiri_bokmai"]


static func has_type(type: StringName) -> bool:
	return PATHS.has(type)


## Whether ships of `type` carry the `civilian` role (Q24).
static func is_civilian(type: StringName) -> bool:
	return CIVILIAN_TYPES.has(type)


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
