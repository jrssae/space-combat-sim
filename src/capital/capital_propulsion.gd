class_name CapitalPropulsion
extends RefCounted
## How a capital hull's drive meets the flight step (M10-T07, Q51). The flight step knows four nozzle groups and the RCS; a
## capital's hardpoints give only its main `engines[]`. Pure: dictionaries and specs in, a layout and a spec out.
##
## - **Reaction** (EA, Drazi and other reaction drives): the mains, and stand-in retros at the mains' places pointing the other
##   way at the spec's `pod_retro_thrust` a nozzle. A hull with no room for retros has `pod_retro_thrust` 0: it flips and burns
##   (`CapitalHelm`).
## - **Gravitic** (Minbari, Vorlon, Shadow, ISA): the same nozzles, but backward and sideways thrust are `gravitic_fraction` of the
##   forward thrust, so it never needs to flip.

const REACTION: StringName = &"reaction"
const GRAVITIC: StringName = &"gravitic"


## The engines as the flight step's nozzles, about the hardpoints' centre of mass: each engine a main, with a stand-in retro
## at its place. An engine on the centre line (x = 0) is listed on both sides, so its thrust counts twice. Invalid (with its
## `error`) when there are no engines.
static func layout(hardpoints: Dictionary) -> ThrusterLayout:
	var pods: Array = []
	var engines: Variant = hardpoints.get("engines")
	for raw: Variant in (engines as Array) if engines is Array else []:
		if not (raw is Dictionary):
			continue
		var engine: Dictionary = raw
		var at: Array = engine.get("position", [0.0, 0.0, 0.0])
		var exhaust: Array = engine.get("exhaust", [0.0, 0.0, 1.0])
		var reverse: Array = [-float(exhaust[0]), -float(exhaust[1]), -float(exhaust[2])]
		var sides := PackedStringArray()
		if float(at[0]) >= 0.0:
			sides.append("right")
		if float(at[0]) <= 0.0:
			sides.append("left")
		for side: String in sides:
			pods.append({"name": "%s_%s" % [engine.get("name", "engine"), side], "side": side,
					"main": {"position": at, "exhaust": exhaust}, "retro": {"position": at, "exhaust": reverse}})
	var com: Variant = hardpoints.get("center_of_mass", [0.0, 0.0, 0.0])
	var centre := Vector3.ZERO
	if com is Array and (com as Array).size() == 3:
		centre = Vector3(float(com[0]), float(com[1]), float(com[2]))
	if pods.is_empty():
		var none := ThrusterLayout.new()
		none.error = "hardpoints have no engines[]"
		return none
	return ThrusterLayout.from_dict({"pods": pods}, centre)


## Whether `spec` flies a gravitic drive.
static func is_gravitic(spec: ShipSpec) -> bool:
	return spec != null and spec.propulsion == GRAVITIC


## Whether `spec` can push backward without turning: a gravitic drive, or a reaction hull with retros.
static func has_retros(spec: ShipSpec) -> bool:
	return is_gravitic(spec) or (spec != null and spec.pod_retro_thrust > 0.0)


## The spec the flight step is given: `spec` itself for a reaction hull; for a gravitic one a copy whose retros and RCS give
## `gravitic_fraction` of the forward thrust (`mains` main nozzles of `pod_main_thrust` each) along every other axis.
static func flight_spec(spec: ShipSpec, mains: int) -> ShipSpec:
	if not is_gravitic(spec):
		return spec
	var out: ShipSpec = spec.duplicate() as ShipSpec
	var fraction: float = clampf(spec.gravitic_fraction, 0.0, 1.0)
	var forward: float = spec.pod_main_thrust * float(maxi(mains, 0))
	out.pod_retro_thrust = spec.pod_main_thrust * fraction
	out.rcs_force_max = Vector3(forward * fraction, forward * fraction, 0.0)
	return out


## How many main nozzles `layout` has.
static func main_count(layout: ThrusterLayout) -> int:
	return layout.nozzles_in_group(ThrusterLayout.Group.R_MAIN).size() + layout.nozzles_in_group(ThrusterLayout.Group.L_MAIN).size()
