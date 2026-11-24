extends GutTest
## The beam weapons as data (M10-T12, D12.9): every capital beam in `data/capitals/loadouts.json` has its `WeaponSpec` with the
## loadouts' numbers, and `BeamMounts` reads a capital's beam mounts with their arcs and the hull's damage scale (Q54).

const LOADOUTS: String = "res://data/capitals/loadouts.json"


func _loadouts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LOADOUTS)) as Dictionary


func test_every_capital_beam_in_the_loadouts_has_a_spec_with_its_numbers() -> void:
	var count: int = 0
	var weapons: Dictionary = _loadouts()["weapons"]
	for id: String in weapons:
		var row: Dictionary = weapons[id]
		var kind: String = str(row["kind"])
		if not kind.begins_with("beam_") or str(row.get("role", "")) == "fighter":
			continue
		count += 1
		var spec: WeaponSpec = WeaponSpec.of_weapon(StringName(id))
		assert_not_null(spec, "%s has assets/weapons/%s.tres" % [id, id])
		if spec == null:
			continue
		var sustained: bool = kind == "beam_sustained"
		assert_eq(spec.beam_kind, WeaponSpec.BEAM_SUSTAINED if sustained else WeaponSpec.BEAM_PULSED, id)
		assert_eq(spec.weapon_id, StringName(id), id)
		assert_eq(spec.role, StringName(str(row["role"])), id)
		assert_eq(spec.damage, float(row["damage"]), id)
		assert_eq(spec.shot_interval_s, float(row["cycle_s"]), id)
		assert_eq(spec.beam_range_m, float(row["range_m"]), id)
		assert_eq(spec.beam_dps, float(row.get("beam_dps", 0.0)), id)
		assert_eq(spec.beam_on_s, float(row.get("beam_on_s", 0.0)), id)
		assert_eq(spec.burst_shots, int(row.get("barrels", 1)), id)
		assert_eq(spec.weapon_trait, StringName(str(row.get("trait", ""))), id)
		assert_eq(spec.turret_traverse_deg_s, 3.0 if sustained else 4.0, "%s turns at its kind's rate" % id)
		assert_gt(spec.beam_charge_s, 0.0, id)
	assert_eq(count, 18, "every capital beam kind of every faction (the Nova has none, Q71; the Brakiri none, Q56)")


func test_beam_specs_warm_no_impact_flash() -> void:
	var beam: WeaponSpec = WeaponSpec.of_weapon(&"ea_sweep_beam")
	assert_false(WeaponSpec.known_bolt_colors().has(beam.bolt_color), "a beam's colour is not a bolt's")


func test_the_omegas_mounts_are_six_sustained_beams_with_hemisphere_arcs() -> void:
	var hardpoints: Dictionary = {"weapons": [
		{"name": "plasma_top_1", "kind": "turret", "weapon": "ea_plasma_heavy", "position": [0, 84, -450]},
		{"name": "beam_fore_r", "kind": "beam", "weapon": "ea_sweep_beam", "section": "bow", "arc_deg": 90.0,
				"position": [90.72, 8.27, -619.76], "forward": [0.0, 0.0, -1.0]},
		{"name": "beam_aft_top_r", "kind": "beam", "weapon": "ea_sweep_beam", "section": "reactor", "arc_deg": 90.0,
				"position": [69.1, 95.2, 572.5], "forward": [0.0, 0.0, 1.0]},
	]}
	var mounts: Array[Dictionary] = BeamMounts.of_hardpoints(hardpoints, &"ea_omega")
	assert_eq(mounts.size(), 2, "the turret is not a beam")
	assert_eq(mounts[0]["name"], "beam_fore_r")
	assert_eq(mounts[0]["section"], "bow")
	assert_eq(mounts[0]["arc_half_deg"], 90.0)
	assert_eq(mounts[0]["forward"], Vector3(0.0, 0.0, -1.0))
	assert_eq(mounts[1]["position"], Vector3(69.1, 95.2, 572.5))
	var packed: PackedFloat64Array = mounts[0]["packed"]
	assert_eq(packed.size(), BeamMounts.SPEC_LEN)
	assert_eq(packed[0], float(WeaponSpec.BEAM_SUSTAINED))
	assert_eq(packed[2], 40.0, "the Omega's damage scale is 1")
	assert_eq(packed[3], 3.0)
	assert_eq(packed[4], 12.0)
	assert_eq(packed[6], 7000.0)
	assert_eq(packed[7], 3.0)


func test_the_hulls_damage_scale_multiplies_an_anti_capital_beam() -> void:
	var spec: WeaponSpec = WeaponSpec.of_weapon(&"ea_particle_cannon")
	assert_almost_eq(BeamMounts.damage_scale(&"ea_hyperion", spec), 0.71, 1e-9, "Q54: the Hyperion's scale")
	var packed: PackedFloat64Array = BeamMounts.packed(spec, BeamMounts.damage_scale(&"ea_hyperion", spec))
	assert_almost_eq(packed[1], 71.0, 1e-9, "100 a pulse times 0.71")
	var array: WeaponSpec = WeaponSpec.of_weapon(&"ea_particle_array")
	assert_eq(BeamMounts.packed(array, 1.0)[1], 100.0, "both barrels of the twin array land as one pulse")


func test_a_mount_without_its_own_arc_takes_half_its_weapons_or_a_hemisphere() -> void:
	assert_eq(BeamMounts.arc_half_deg({"arc_deg": 30.0}, "ea_sweep_beam"), 30.0, "the mount's own half angle")
	assert_eq(BeamMounts.arc_half_deg({}, "ea_particle_cannon_heavy"), 10.0, "bow +/-10 deg from the weapon's 20")
	assert_eq(BeamMounts.arc_half_deg({}, "ea_sweep_beam"), BeamMounts.DEFAULT_ARC_HALF_DEG)


func test_a_mount_naming_no_beam_spec_is_left_out() -> void:
	var mounts: Array[Dictionary] = BeamMounts.of_hardpoints({"weapons": [{"name": "x", "kind": "beam", "weapon": "nope"}]}, &"x")
	assert_eq(mounts.size(), 0, "warned and skipped")
