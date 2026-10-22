class_name ShipCatalog
extends RefCounted
## Scenario ship type -> `ShipSpec` (architecture §15.2). Scenarios and console commands name ships by type
## (`raider_fighter`); this is the one place that knows which resource flies it. Pure.

const PATHS: Dictionary[StringName, String] = {
	&"starfury_aurora": "res://assets/ships/starfury_aurora.tres",
	&"raider_fighter": "res://assets/ships/raider_delta_v.tres",
}


static func has_type(type: StringName) -> bool:
	return PATHS.has(type)


static func types() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(PATHS.keys())
	return out


## The spec resource for `type`, or null (with a warning) for an unknown type.
static func spec_for(type: StringName) -> ShipSpec:
	if not PATHS.has(type):
		push_warning("ShipCatalog: unknown ship type '%s'" % type)
		return null
	return load(PATHS[type]) as ShipSpec
