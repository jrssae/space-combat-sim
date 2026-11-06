class_name BattleMix
extends RefCounted
## The load a battle puts on the tick, per entity type (M4-T07, Q19 and Q21; the milestone's "What the battle is"). Pure: a
## profile is a Dictionary of parameters and `counts` turns it and a ship count into the numbers every layout, summary and
## per-entity counter uses. Two profiles: `typical`, most missions (under 10 capitals and about 50 fighters on two sides), and
## `grand`, the multi-side battle that is the headline (15 % capitals, four sides). The 1 000 stretch is `grand` at 1 000, or
## with `capital_share` 0.2 for its upper edge. Missiles, beams and mines are counted here; their stand-ins are M4-T12's.

const TYPICAL: StringName = &"typical"
const GRAND: StringName = &"grand"
const CLASS_NAMES: Array[String] = ["carrier", "destroyer", "cruiser"]

# Every number a parameter. Capitals are `round(capital_share * n)`; carriers `floor(carrier_share * capitals)`, destroyers
# `round(destroyer_share * capitals)`, cruisers the rest. The area grows with the square root of N past `area_ref_n`.
const _PROFILES: Dictionary = {
	TYPICAL: {
		"capital_share": 1.0 / 7.0,
		"carrier_share": 0.25,
		"destroyer_share": 0.375,
		"turrets_per_class": {"carrier": 12, "destroyer": 10, "cruiser": 8},
		"beams_per_capital": 2,
		"interceptors_per_capital": 4,
		"missiles_per_fighter": 0.4,
		"mines_per_ship": 1.0,
		"mines_min": 100,
		"asteroids": 1000,
		"gravity_sources": 1,
		"sides": 2,
		"area_m": Vector3(20000.0, 10000.0, 20000.0),
		"area_ref_n": 58,
	},
	GRAND: {
		"capital_share": 0.15,
		"carrier_share": 0.2,
		"destroyer_share": 1.0 / 3.0,
		"turrets_per_class": {"carrier": 12, "destroyer": 10, "cruiser": 8},
		"beams_per_capital": 2,
		"interceptors_per_capital": 4,
		"missiles_per_fighter": 0.4,
		"mines_per_ship": 1.0,
		"mines_min": 100,
		"asteroids": 1000,
		"gravity_sources": 1,
		"sides": 4,
		"area_m": Vector3(60000.0, 20000.0, 60000.0),
		"area_ref_n": 500,
	},
}


## A copy of the named profile to read or change; empty for an unknown name.
static func profile(profile_name: StringName) -> Dictionary:
	return (_PROFILES.get(profile_name, {}) as Dictionary).duplicate(true)


## What `profile` puts in a battle of `n` ships (fighters and capitals): every entity count, the sides and the area.
## Empty for an empty profile.
static func counts(p: Dictionary, n: int) -> Dictionary:
	if p.is_empty():
		return {}
	var ships: int = maxi(n, 0)
	var capitals: int = mini(roundi(float(p["capital_share"]) * ships), ships)
	var carriers: int = floori(float(p["carrier_share"]) * capitals + 1e-9)  # 0.2 * 15 must give 3, not 2.999...
	var destroyers: int = mini(roundi(float(p["destroyer_share"]) * capitals), capitals - carriers)
	var cruisers: int = capitals - carriers - destroyers
	var per_class: Dictionary = p["turrets_per_class"]
	var fighters: int = ships - capitals
	var area: Vector3 = p["area_m"]
	var grow: float = sqrt(float(maxi(ships, int(p["area_ref_n"]))) / float(p["area_ref_n"]))
	var any: bool = ships > 0
	return {
		"ships": ships,
		"fighters": fighters,
		"capitals": capitals,
		"carriers": carriers,
		"destroyers": destroyers,
		"cruisers": cruisers,
		"turrets": carriers * int(per_class["carrier"]) + destroyers * int(per_class["destroyer"]) + cruisers * int(per_class["cruiser"]),
		"beams": capitals * int(p["beams_per_capital"]),
		"interceptors": capitals * int(p["interceptors_per_capital"]),
		"missiles": roundi(float(p["missiles_per_fighter"]) * fighters),
		"mines": maxi(int(p["mines_min"]), roundi(float(p["mines_per_ship"]) * ships)) if any else 0,
		"asteroids": int(p["asteroids"]) if any else 0,
		"gravity_sources": int(p["gravity_sources"]) if any else 0,
		"sides": int(p["sides"]),
		"area_m": Vector3(area.x * grow, area.y, area.z * grow),
	}


## The capital classes of `c` (a `counts` result) in placement order: carriers, then destroyers, then cruisers.
static func class_order(c: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for class_name_text: String in CLASS_NAMES:
		for i: int in int(c.get(class_name_text + "s", 0)):
			out.append(StringName(class_name_text))
	return out


## One line for a run's log and summary page.
static func describe(c: Dictionary) -> String:
	if c.is_empty():
		return "no mix"
	var area: Vector3 = c["area_m"]
	return "%d fighters, %d capitals (%d carriers, %d destroyers, %d cruisers), %d turrets, %d interceptors, %d beams, %d missiles, %d mines, %d asteroids, %d sides, %.0f x %.0f x %.0f km" % [
			int(c["fighters"]), int(c["capitals"]), int(c["carriers"]), int(c["destroyers"]), int(c["cruisers"]), int(c["turrets"]),
			int(c["interceptors"]), int(c["beams"]), int(c["missiles"]), int(c["mines"]), int(c["asteroids"]), int(c["sides"]),
			area.x * 1e-3, area.z * 1e-3, area.y * 1e-3]
