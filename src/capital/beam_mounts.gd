class_name BeamMounts
extends RefCounted
## A capital's beam emitters as the native beam rows take them (M10-T12, D12.9): each `beam` mount of its hardpoints with its
## weapon's `WeaponSpec` (`assets/weapons/<id>.tres`), its arc from the mount (else half its weapon's `arc_deg` in the
## loadouts, else a hemisphere), and its numbers packed with the hull's `damage_scale` for an anti-capital weapon (Q54). Pure.

## A mount that names no arc and whose weapon names none covers a hemisphere (half angle, degrees).
const DEFAULT_ARC_HALF_DEG: float = 90.0
## Numbers `ScsBeamRows.add_beam` takes for a weapon.
const SPEC_LEN: int = 8


## Every beam mount of `hardpoints` (a capital's `hardpoints.json`) for hull `type_id`, in the file's order: dictionaries
## `{name, weapon, section, position, forward, arc_half_deg, spec, packed}` (body frame with the rotating pieces at rest). A
## mount whose weapon has no beam spec is left out with a warning.
static func of_hardpoints(hardpoints: Dictionary, type_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var weapons: Variant = hardpoints.get("weapons", [])
	if not (weapons is Array):
		return out
	for raw: Variant in weapons:
		var entry: Dictionary = raw if raw is Dictionary else {}
		if str(entry.get("kind", "")) != "beam":
			continue
		var weapon: String = str(entry.get("weapon", ""))
		var spec: WeaponSpec = WeaponSpec.of_weapon(StringName(weapon))
		if spec == null or spec.beam_kind == WeaponSpec.BEAM_NONE:
			push_warning("BeamMounts: %s's mount %s names %s, which has no beam spec" % [type_id, entry.get("name", ""), weapon])
			continue
		out.append({
			"name": str(entry.get("name", "")),
			"weapon": weapon,
			"section": str(entry.get("section", "")),
			"position": _vec3(entry.get("position"), Vector3.ZERO),
			"forward": _vec3(entry.get("forward"), Vector3.FORWARD),
			"arc_half_deg": arc_half_deg(entry, weapon),
			"spec": spec,
			"packed": packed(spec, damage_scale(type_id, spec)),
		})
	return out


## A mount's arc, half angle in degrees: the mount's own `arc_deg` (a half angle), else half its weapon's (a full arc), else a
## hemisphere.
static func arc_half_deg(entry: Dictionary, weapon: String) -> float:
	if entry.has("arc_deg"):
		return float(entry["arc_deg"])
	var row: Dictionary = CapitalData.weapon_entry(weapon)
	return 0.5 * float(row["arc_deg"]) if row.has("arc_deg") else DEFAULT_ARC_HALF_DEG


## What hull `type_id` multiplies weapon `spec`'s damage by: its `damage_scale` for an anti-capital weapon, else 1.
static func damage_scale(type_id: StringName, spec: WeaponSpec) -> float:
	if spec.role != &"ac":
		return 1.0
	return float(CapitalData.hull_entry(String(type_id)).get("damage_scale", 1.0))


## `spec`'s numbers for the native rows, damage times `scale`: kind, a pulse's damage (every barrel), dps, time on, cycle,
## charge, range, traverse (deg/s).
static func packed(spec: WeaponSpec, scale: float) -> PackedFloat64Array:
	return PackedFloat64Array([spec.beam_kind, spec.damage * maxi(spec.burst_shots, 1) * scale, spec.beam_dps * scale,
			spec.beam_on_s, spec.shot_interval_s, spec.beam_charge_s, spec.beam_range_m, spec.turret_traverse_deg_s])


static func _vec3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Array and (raw as Array).size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback
