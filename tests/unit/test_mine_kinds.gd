extends GutTest
## The mine kinds' numbers (M10-T15, Q20, Q53; `data/capitals/mines.json`): T03's table (docs/assets-capital.md, "Mines"), the
## blast each goes off with, what the native rows are told, the battle laying of the two kinds a hull lays, and the constants
## the native kernel mirrors.


func test_the_kinds_hold_t03s_numbers() -> void:
	assert_eq(MineKinds.NAMES, [&"mine_prox", &"mine_energy", &"mine_guided"] as Array[StringName])
	assert_eq(MineKinds.number(MineKinds.PROX, "trigger_m"), 60.0, "a proximity mine: 60 m from the hull's surface")
	assert_eq(MineKinds.number(MineKinds.ENERGY, "trigger_m"), 200.0, "an energy mine: 200 m")
	assert_eq(MineKinds.number(MineKinds.GUIDED, "trigger_m"), 30.0, "a guided mine: 30 m")
	assert_true(bool(MineKinds.row(MineKinds.ENERGY)["capitals_only"]), "an energy mine goes off on capitals only")
	assert_false(bool(MineKinds.row(MineKinds.PROX)["capitals_only"]))
	assert_eq(MineKinds.number(MineKinds.ENERGY, "speed_mps"), 900.0, "an energy mine flies at 900 m/s")
	assert_eq(MineKinds.number(MineKinds.ENERGY, "fuse_s"), 5.0, "and goes off 5 s after it arrives")
	assert_eq(MineKinds.number(MineKinds.ENERGY, "toughness"), 3.0, "an interceptor needs 3 pulses (Q81)")
	assert_eq(MineKinds.number(MineKinds.GUIDED, "dormant_s"), 60.0, "a guided mine lies dormant for 60 s")
	assert_eq(MineKinds.number(MineKinds.GUIDED, "speed_mps"), 150.0, "then homes at 150 m/s")
	assert_eq(MineKinds.number(MineKinds.GUIDED, "home_m"), 800.0, "on a hostile within 800 m")
	for k: int in MineKinds.NAMES.size():
		assert_eq(MineKinds.number(k, "radar_m"), 1000.0, "%s shows on the radar 1 km out" % MineKinds.NAMES[k])


func test_each_kind_goes_off_with_its_row_of_the_blast_table() -> void:
	var expected: Array = [[300.0, 120.0], [250.0, 300.0], [400.0, 60.0]]
	for k: int in MineKinds.NAMES.size():
		var blast: BlastSpec = MineKinds.blast(k)
		assert_not_null(blast, "%s has a blast" % MineKinds.NAMES[k])
		assert_eq([blast.d0, blast.radius_m], expected[k], "%s's blast is T03's" % MineKinds.NAMES[k])
	var spec: PackedFloat64Array = MineKinds.numbers(MineKinds.PROX)
	assert_eq(spec.size(), 12, "the numbers the rows take")
	assert_eq(spec[9], 120.0, "the blast radius is the table's, for the chain")


func test_only_the_two_battle_kinds_have_laying_numbers() -> void:
	assert_true(MineKinds.laying(MineKinds.PROX).is_empty(), "a proximity mine is laid by data, never by a hull")
	var energy: PackedFloat64Array = MineKinds.laying(MineKinds.ENERGY)
	assert_eq([energy[0], energy[1], energy[2]], [4000.0, 12000.0, 20.0], "capitals 4 to 12 km away, one every 20 s")
	var guided: PackedFloat64Array = MineKinds.laying(MineKinds.GUIDED)
	assert_eq([guided[1], guided[2], guided[3], guided[4]], [3000.0, 30.0, 4.0, 12.0], "astern within 3 km: 4 every 30 s, 12 in play")


func test_the_loadouts_name_the_hulls_that_lay_and_their_mine_weapons_exist() -> void:
	assert_eq(CapitalData.weapon_kind("narn_energy_mine"), "mine_energy")
	assert_eq(CapitalData.weapon_kind("centauri_guided_mine"), "mine_guided")
	assert_eq(CapitalData.weapon_kind("ea_mine"), "mine_prox")
	assert_eq(float(CapitalData.weapon_entry("narn_energy_mine")["toughness"]), MineKinds.number(MineKinds.ENERGY, "toughness"))
	assert_eq(float(CapitalData.weapon_entry("narn_energy_mine")["speed_mps"]), MineKinds.number(MineKinds.ENERGY, "speed_mps"))


func test_a_hulls_mine_mounts_become_layers_by_the_kind_of_their_weapon() -> void:
	var hardpoints: Dictionary = {"weapons": [
			{"name": "turret", "kind": "turret", "weapon": "narn_light_pulse"},
			{"name": "mine_l", "kind": "mine", "weapon": "narn_energy_mine", "section": "bow", "position": [3.0, 0.0, -20.0], "forward": [0, 0, -1]},
			{"name": "drop", "kind": "mine", "weapon": "centauri_guided_mine", "position": [0.0, -2.0, 30.0], "forward": [0, 0, 1]},
			{"name": "field_only", "kind": "mine", "weapon": "narn_mine"}]}
	var layers: Array[Dictionary] = MineLayers.of_hardpoints(hardpoints, &"test_hull")
	assert_eq(layers.size(), 2, "the energy launcher and the guided drop; a proximity mine is never laid in battle")
	assert_eq([layers[0]["name"], layers[0]["kind"]], ["mine_l", MineKinds.ENERGY])
	assert_eq([layers[1]["name"], layers[1]["kind"]], ["drop", MineKinds.GUIDED])
	assert_eq(layers[1]["forward"], Vector3(0.0, 0.0, 1.0), "the way a mine leaves")
