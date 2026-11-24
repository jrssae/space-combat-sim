extends GutTest
## The capital guns and launchers as data (M10-T14, D12.9): every capital bolt, missile and torpedo weapon in
## `data/capitals/loadouts.json` has its `WeaponSpec` with the loadouts' numbers, no weapon keeps the dropped `push` trait and the
## Brakiri carry only pulse lasers and interceptors (Q56), and `CapitalGunMounts` reads the built hulls' mounts: the Omega's
## turrets and launchers, the Nova's fixed forward and aft guns (Q71), the Hyperion's fixed heavies and torpedoes with its damage
## scale (Q54).

const LOADOUTS: String = "res://data/capitals/loadouts.json"
const GUN_KINDS: Array[String] = ["bolt_light", "bolt_medium", "bolt_heavy", "bolt_fixed", "missile", "torpedo"]


func _loadouts() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(LOADOUTS)) as Dictionary


func _hardpoints(type_id: String) -> Dictionary:
	var path: String = "res://assets/generated/%s/hardpoints.json" % type_id
	if not FileAccess.file_exists(path):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary


func test_every_capital_gun_and_launcher_in_the_loadouts_has_a_spec_with_its_numbers() -> void:
	var count: int = 0
	var weapons: Dictionary = _loadouts()["weapons"]
	for id: String in weapons:
		var row: Dictionary = weapons[id]
		var kind: String = str(row["kind"])
		if not GUN_KINDS.has(kind):
			continue
		count += 1
		var spec: WeaponSpec = WeaponSpec.of_weapon(StringName(id))
		assert_not_null(spec, "%s has assets/weapons/%s.tres" % [id, id])
		if spec == null:
			continue
		assert_eq(spec.weapon_id, StringName(id), id)
		assert_eq(spec.beam_kind, WeaponSpec.BEAM_NONE, id)
		assert_eq(spec.role, StringName(str(row["role"])), id)
		assert_eq(spec.damage, float(row["damage"]), id)
		assert_eq(spec.shot_interval_s, float(row["cycle_s"]), id)
		assert_eq(spec.muzzle_speed_mps, float(row["speed_mps"]), id)
		assert_eq(spec.turret_range_m, float(row["range_m"]), id)
		assert_eq(spec.barrels, int(row.get("barrels", 1)), id)
		assert_eq(spec.burst_shots, int(row.get("burst", 1)), id)
		assert_eq(spec.weapon_trait, StringName(str(row.get("trait", ""))), id)
		var warhead: int = {"missile": WeaponSpec.WARHEAD_MISSILE, "torpedo": WeaponSpec.WARHEAD_TORPEDO}.get(kind, WeaponSpec.WARHEAD_NONE)
		assert_eq(spec.warhead, warhead, "%s's warhead" % id)
		if warhead != WeaponSpec.WARHEAD_NONE:
			assert_eq(spec.toughness, int(row.get("toughness", 1)), id)
	assert_eq(count, 29, "every capital gun and launcher kind of every faction")


func test_no_push_trait_and_the_brakiri_carry_pulse_lasers_and_interceptors_only() -> void:
	var data: Dictionary = _loadouts()
	assert_false((data["traits"] as Array).has("push"), "Q56 dropped the push trait")
	var weapons: Dictionary = data["weapons"]
	for id: String in weapons:
		assert_ne(str((weapons[id] as Dictionary).get("trait", "")), "push", id)
		if str((weapons[id] as Dictionary)["faction"]) == "brakiri":
			assert_true(["bolt_heavy", "bolt_medium", "interceptor", "mine_prox", "fighter_gun"].has(str(weapons[id]["kind"])),
					"%s is a pulse laser, an interceptor, a mine or the Falkosi's gun" % id)
	var avioki: Dictionary = data["hulls"]["brakiri_avioki"]
	assert_eq(avioki["weapons"], {"brakiri_pulse_laser_heavy": 4.0, "brakiri_pulse_laser": 6.0})
	assert_eq(avioki["interceptors"], {"brakiri_interceptor": 4.0})
	assert_eq(Factions.table().weapons(&"brakiri").has(&"brakiri_graviton_beam"), false)


func test_the_omegas_turrets_and_launchers() -> void:
	var hp: Dictionary = _hardpoints("ea_omega")
	if hp.is_empty():
		pending("the Omega is not generated (scripts/gen_assets.sh)")
		return
	var mounts: Array[Dictionary] = CapitalGunMounts.of_hardpoints(hp, &"ea_omega")
	var by_weapon: Dictionary = {}
	for m: Dictionary in mounts:
		by_weapon[m["weapon"]] = int(by_weapon.get(m["weapon"], 0)) + 1
	assert_eq(by_weapon, {"ea_plasma_heavy": 4, "ea_pulse_medium": 12, "ea_missile": 2}, "T03's loadout, beams and interceptors left out")
	for m: Dictionary in mounts:
		var packed: PackedFloat64Array = m["packed"]
		assert_eq(packed.size(), CapitalGunMounts.SPEC_LEN, m["name"])
		if m["kind"] == "missile":
			assert_true(m["on_axis"], "a launcher rests on its cells' axis")
			assert_eq(m["half_deg"], CapitalGunMounts.MISSILE_ARC_HALF_DEG, "its rounds climb out and turn")
			assert_eq(packed[0], 1.0, "a launcher")
		else:
			assert_false(m["on_axis"], "a turret lies on its base")
			assert_eq(m["half_deg"], 100.0, "%s covers 10 deg below its base" % m["name"])
			assert_eq(m["pick_half_deg"], m["half_deg"])
			assert_gt(float(m["barrel_m"]), 0.0)


func test_the_novas_twelve_fixed_pulse_cannons_fire_eight_ahead_and_four_astern_and_two_swivel() -> void:
	var hp: Dictionary = _hardpoints("ea_nova")
	if hp.is_empty():
		pending("the Nova is not generated (scripts/gen_assets.sh)")
		return
	var mounts: Array[Dictionary] = CapitalGunMounts.of_hardpoints(hp, &"ea_nova")
	assert_eq(mounts.size(), 14, "the 4 interceptor pods are not guns (T13)")
	var ahead: int = 0
	var astern: int = 0
	var swivels: Array[String] = []
	for m: Dictionary in mounts:
		if m["weapon"] == "ea_pulse_cannon_swivel":
			# M10-T14 review: the hangar block's pods turn through the half sphere over its flank, as the interceptor pods do.
			swivels.append(str(m["name"]))
			assert_false(m["on_axis"], "a turret")
			assert_eq(m["half_deg"], 90.0, "the half sphere over the flank")
			assert_almost_eq(absf((m["axis"] as Vector3).x), 1.0, 1e-5, "its base faces out from the block")
			assert_gt(float(m["barrel_m"]), 80.0, "its bolts leave from the muzzles")
			assert_eq((m["packed"] as PackedFloat64Array)[2], 0.75 * WeaponSpec.of_weapon(&"ea_pulse_cannon_fixed").damage, "75 % power")
			continue
		assert_eq(m["weapon"], "ea_pulse_cannon_fixed")
		assert_true(m["on_axis"], "fixed to the hull's axis")
		assert_eq(m["half_deg"], 0.0, "no traverse (Q71)")
		assert_eq(m["pick_half_deg"], CapitalGunMounts.FIXED_PICK_MARGIN_DEG, "it holds a target the helm is turning onto")
		var axis: Vector3 = m["axis"]
		if axis.is_equal_approx(Vector3.FORWARD):
			ahead += 1
		elif axis.is_equal_approx(Vector3.BACK):
			astern += 1
		assert_eq((m["packed"] as PackedFloat64Array)[3], 2.0, "twin barrels")
	assert_eq([ahead, astern], [8, 4])
	swivels.sort()
	assert_eq(swivels, ["pulse_hangar_l", "pulse_hangar_r"])


func test_the_hyperions_heavies_are_fixed_and_its_damage_scale_takes_its_anti_capital_weapons() -> void:
	var hp: Dictionary = _hardpoints("ea_hyperion")
	if hp.is_empty():
		pending("the Hyperion is not generated (scripts/gen_assets.sh)")
		return
	var scale: float = float(CapitalData.hull_entry("ea_hyperion")["damage_scale"])
	for m: Dictionary in CapitalGunMounts.of_hardpoints(hp, &"ea_hyperion"):
		var spec: WeaponSpec = m["spec"]
		var packed: PackedFloat64Array = m["packed"]
		match str(m["weapon"]):
			"ea_plasma_heavy":
				assert_true(m["on_axis"], "the bow heavies are fixed")
				assert_eq(m["half_deg"], 3.0, "within their 3 deg gimbal")
				assert_almost_eq(packed[2], spec.damage * scale, 1e-9, "Q54's scale on an anti-capital gun")
			"ea_torpedo":
				assert_eq(m["half_deg"], CapitalGunMounts.TORPEDO_ARC_HALF_DEG)
				assert_eq(int(packed[16]), WeaponSpec.WARHEAD_TORPEDO)
				assert_almost_eq(packed[2], spec.damage * scale, 1e-9)
			_:
				assert_eq(packed[2], spec.damage, "%s is not anti-capital: unscaled" % m["weapon"])


func test_a_mount_naming_no_gun_spec_is_left_out() -> void:
	var hp: Dictionary = {"weapons": [{"name": "x", "kind": "turret", "weapon": "no_such_gun", "position": [0, 0, 0]},
			{"name": "y", "kind": "missile", "weapon": "ea_pulse_medium", "position": [0, 0, 0]}]}
	assert_eq(CapitalGunMounts.of_hardpoints(hp, &"capital_test_cruiser").size(), 0, "an unknown weapon, and a gun named as a launcher")
