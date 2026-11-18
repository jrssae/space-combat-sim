class_name DockRepair
extends RefCounted
## How long the station takes to turn a docked fighter round (M8-T06, D82): a fixed handling time plus time for the hull, the
## guns' charge and the reaction mass it lacks. Pure; the numbers are `data/station/docking.json`'s `repair`.

## Seconds every visit takes, however whole the ship.
var base_s: float = 6.0
## Seconds to rebuild a hull from nothing, to charge empty guns and to fill an empty tank; each scales with what is missing.
var hull_s: float = 30.0
var rearm_s: float = 4.0
var refuel_s: float = 4.0
## The longest a visit takes.
var max_s: float = 45.0


static func from_dict(raw: Variant) -> DockRepair:
	var out := DockRepair.new()
	if not (raw is Dictionary):
		return out
	var d: Dictionary = raw
	out.base_s = maxf(float(d.get("base_s", out.base_s)), 0.0)
	out.hull_s = maxf(float(d.get("hull_s", out.hull_s)), 0.0)
	out.rearm_s = maxf(float(d.get("rearm_s", out.rearm_s)), 0.0)
	out.refuel_s = maxf(float(d.get("refuel_s", out.refuel_s)), 0.0)
	out.max_s = maxf(float(d.get("max_s", out.max_s)), out.base_s)
	return out


## Seconds in the bay for a ship with this much hull, gun charge and reaction mass left (each 0..1).
func time_s(hull_fraction: float, charge_fraction: float = 1.0, fuel_fraction: float = 1.0) -> float:
	var missing_hull: float = 1.0 - clampf(hull_fraction, 0.0, 1.0)
	var missing_charge: float = 1.0 - clampf(charge_fraction, 0.0, 1.0)
	var missing_fuel: float = 1.0 - clampf(fuel_fraction, 0.0, 1.0)
	return minf(base_s + hull_s * missing_hull + rearm_s * missing_charge + refuel_s * missing_fuel, max_s)
