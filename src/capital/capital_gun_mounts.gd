class_name CapitalGunMounts
extends RefCounted
## A capital's gun turrets and missile launchers as the native gun rows take them (M10-T14, D12.9): each `turret` and
## `missile` mount of its hardpoints with its weapon's `WeaponSpec` (`assets/weapons/<id>.tres`), the cone it covers and its
## numbers packed with the hull's `damage_scale` for an anti-capital weapon (Q54). Pure.
##
## - A **turret** (traverse all round) covers a cone round its base's `up` down to its lowest elevation (the usual 200 deg: 10
##   below the base); its barrel rests on the base toward the bow.
## - A **fixed gun** (a mount whose traverse is under 90 deg: the Hyperion's bow guns, the Nova's pulse cannons, Q71) aims within
##   its gimbal round its `forward` and rests on that axis; its azimuth turns freely so only the elevation rate holds it back. It
##   holds targets in a wider cone (`FIXED_PICK_MARGIN_DEG` more) and fires when its ship's helm brings one onto its line.
## - A **launcher** covers a cone round its cells' `forward`: the mount's own `arc_deg`, else half its weapon's, else a
##   120 deg for a missile and a fore 45 deg for a torpedo.
## - An **interceptor** battery (M10-T13, `interceptors_of`) covers the hemisphere over its base's `up` (its elevation range),
##   fires its barrels in turn at what comes at its ship or a friend, and never at a ship (role `pd`).

## Numbers `ScsCapitalGuns.add_mount` takes for a weapon.
const SPEC_LEN: int = 19
## A mount whose traverse is under this is fixed to its axis, deg.
const FIXED_TRAVERSE_DEG: float = 90.0
## A fixed gun's azimuth round its axis turns this fast (it barely moves the barrel near the axis), deg/s.
const FIXED_AZIMUTH_DEG_S: float = 360.0
## How much wider than its gimbal a fixed gun holds a target, so the helm can bring it onto the line, deg.
const FIXED_PICK_MARGIN_DEG: float = 25.0
## A missile cell covers everything above its base and 30 deg below: its rounds climb out and turn onto the target, deg.
const MISSILE_ARC_HALF_DEG: float = 120.0
const TORPEDO_ARC_HALF_DEG: float = 45.0
const ROLES: Array[StringName] = [&"af", &"dual", &"ac", &"pd"]
## An interceptor battery's barrels sit this far out from its pivot when its mount names no radius, m.
const INTERCEPTOR_BARREL_M: float = 3.0
const KINDS: Array[String] = ["turret", "missile"]


## Every gun and launcher mount of `hardpoints` (a capital's `hardpoints.json`) for hull `type_id`, in the file's order:
## dictionaries `{name, weapon, section, kind, position, axis, zero, half_deg, pick_half_deg, on_axis, barrel_m, spec, packed}` (body frame
## with the rotating pieces at rest). A mount whose weapon has no spec is left out with a warning.
static func of_hardpoints(hardpoints: Dictionary, type_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weapons: Variant = hardpoints.get("weapons", [])
	if not (weapons is Array):
		return out
	for raw: Variant in weapons:
		var entry: Dictionary = raw if raw is Dictionary else {}
		var kind: String = str(entry.get("kind", ""))
		if not KINDS.has(kind):
			continue
		var weapon: String = str(entry.get("weapon", ""))
		var spec: WeaponSpec = WeaponSpec.of_weapon(StringName(weapon))
		if spec == null or spec.beam_kind != WeaponSpec.BEAM_NONE or (kind == "missile") != (spec.warhead != WeaponSpec.WARHEAD_NONE):
			push_warning("CapitalGunMounts: %s's mount %s names %s, which has no %s spec" % [type_id, entry.get("name", ""), weapon, kind])
			continue
		var forward: Vector3 = _vec3(entry.get("forward"), Vector3.FORWARD)
		var up: Vector3 = _vec3(entry.get("up"), Vector3.UP)
		var m: Dictionary = {"name": str(entry.get("name", "")), "weapon": weapon, "section": str(entry.get("section", "")),
				"kind": kind, "position": _vec3(entry.get("position"), Vector3.ZERO), "spec": spec}
		var traverse: float = spec.turret_traverse_deg_s
		if kind == "missile":
			m.merge({"axis": forward, "zero": up, "half_deg": launcher_half_deg(entry, weapon, spec), "on_axis": true,
					"barrel_m": 0.0})
		elif float(entry.get("traverse_deg", 180.0)) < FIXED_TRAVERSE_DEG:
			var elevations: Array = entry.get("elevation_deg", [-3.0, 3.0])
			var gimbal: float = maxf(float(entry.get("traverse_deg", 0.0)), maxf(absf(float(elevations[0])), absf(float(elevations[1]))))
			m.merge({"axis": forward, "zero": up, "half_deg": gimbal, "pick_half_deg": gimbal + FIXED_PICK_MARGIN_DEG, "on_axis": true,
					"barrel_m": float(entry.get("barrel_m", 0.0))})
			traverse = FIXED_AZIMUTH_DEG_S
		else:
			var lowest: float = float((entry.get("elevation_deg", [-10.0, 90.0]) as Array)[0])
			m.merge({"axis": up, "zero": forward, "half_deg": 90.0 - lowest, "on_axis": false,
					"barrel_m": float(entry.get("barrel_m", 0.0))})
		if not m.has("pick_half_deg"):
			m["pick_half_deg"] = m["half_deg"]
		m["packed"] = packed(spec, BeamMounts.damage_scale(type_id, spec), traverse)
		out.append(m)
	return out


## Every interceptor mount of `hardpoints` for hull `type_id`, in the file's order, as `of_hardpoints` gives the guns: its base's
## `up` is the axis, `forward` azimuth 0, the cone its elevation range above the base (the usual 0 to 90: a hemisphere).
static func interceptors_of(hardpoints: Dictionary, type_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weapons: Variant = hardpoints.get("weapons", [])
	if not (weapons is Array):
		return out
	for raw: Variant in weapons:
		var entry: Dictionary = raw if raw is Dictionary else {}
		if str(entry.get("kind", "")) != "interceptor":
			continue
		var weapon: String = str(entry.get("weapon", ""))
		var spec: WeaponSpec = WeaponSpec.of_weapon(StringName(weapon))
		if spec == null or spec.role != &"pd":
			push_warning("CapitalGunMounts: %s's mount %s names %s, which has no interceptor spec" % [type_id, entry.get("name", ""),
					weapon])
			continue
		var lowest: float = float((entry.get("elevation_deg", [0.0, 90.0]) as Array)[0])
		out.append({"name": str(entry.get("name", "")), "weapon": weapon, "section": str(entry.get("section", "")),
				"kind": "interceptor", "position": _vec3(entry.get("position"), Vector3.ZERO), "spec": spec,
				"axis": _vec3(entry.get("up"), Vector3.UP), "zero": _vec3(entry.get("forward"), Vector3.FORWARD),
				"half_deg": 90.0 - lowest, "pick_half_deg": 90.0 - lowest, "on_axis": false,
				"barrel_m": float(entry.get("radius_m", INTERCEPTOR_BARREL_M)),
				"packed": packed(spec, 1.0, spec.turret_traverse_deg_s)})
	return out


## A launcher's arc, half angle in degrees: the mount's own `arc_deg` (a half angle), else half its weapon's (a full arc), else a
## 120 deg for a missile (`MISSILE_ARC_HALF_DEG`) and 45 deg for a torpedo.
static func launcher_half_deg(entry: Dictionary, weapon: String, spec: WeaponSpec) -> float:
	if entry.has("arc_deg"):
		return float(entry["arc_deg"])
	var row: Dictionary = CapitalData.weapon_entry(weapon)
	if row.has("arc_deg"):
		return 0.5 * float(row["arc_deg"])
	return TORPEDO_ARC_HALF_DEG if spec.warhead == WeaponSpec.WARHEAD_TORPEDO else MISSILE_ARC_HALF_DEG


## `spec`'s numbers for the native rows, damage times `scale` and the azimuth turning at `traverse_deg_s`: launcher, role,
## damage, barrels, burst shots and spacing, cycle, speed, range, lifetime, hit radius, spread, traverse, elevation rate,
## guidance gain and turn, warhead, the bolts' look, and the interceptor pulses one of its shots takes (`toughness`, Q81).
static func packed(spec: WeaponSpec, scale: float, traverse_deg_s: float) -> PackedFloat64Array:
	return PackedFloat64Array([1.0 if spec.warhead != WeaponSpec.WARHEAD_NONE else 0.0, maxi(ROLES.find(spec.role), 0),
			spec.damage * scale, maxi(spec.barrels, 1), maxi(spec.burst_shots, 1), spec.burst_spacing_s, spec.shot_interval_s,
			spec.muzzle_speed_mps, spec.turret_range_m, spec.lifetime_s, spec.hit_radius_m, spec.turret_spread_deg,
			traverse_deg_s, spec.turret_elevation_deg_s, spec.missile_nav_gain, spec.missile_turn_rad_s, spec.warhead,
			BoltMesh.look_for(spec), maxi(spec.toughness, 1)])


static func _vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Array and (raw as Array).size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback
