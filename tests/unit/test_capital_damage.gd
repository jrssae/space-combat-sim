extends GutTest
## `CapitalDamage` (M10-T08, D12.5, Q53), per section kind: points by hull share, a lost section takes what it holds, a
## magazine or fuel section blows, a reactor shuts down and blows on its overload, a lost bridge halves the rate of fire, hits
## on a lost section pass half on, mounts take their own points. A synthetic hull of 10 000 points laid along z.

const HULL: float = 10000.0

var _changes: Array = []
var _lost_mounts: Array[String] = []
var _drive: int = 0
var _disabled: int = 0
var _blew: Array[String] = []


# Sections in a row along z, each 100 m long: [name, kind, share].
const LAYOUT: Array = [
	["bow", "structure", 0.20],
	["bridge", "bridge", 0.05],
	["magazine", "magazine", 0.10],
	["fuel", "fuel", 0.08],
	["hangar", "hangar", 0.12],
	["reactor", "reactor", 0.15],
	["engine_r", "engine", 0.075],
	["engine_l", "engine", 0.075],
	["spine", "structure", 0.15],
]


func _model() -> CapitalDamage:
	var sections := CapitalSections.new()
	for i: int in LAYOUT.size():
		var row: Array = LAYOUT[i]
		sections.by_name[row[0]] = {"name": row[0], "kind": row[1], "hull_share": row[2], "piece": "hull",
				"aabb_min": [-20.0, -20.0, 100.0 * i], "aabb_max": [20.0, 20.0, 100.0 * i + 100.0]}
	var hardpoints: Dictionary = {
		"weapons": [
			{"name": "plasma", "section": "bow", "kind": "turret", "weapon": "ea_plasma_heavy", "position": [0.0, 20.0, 50.0], "barrel_m": 24.0},
			{"name": "pulse", "section": "bow", "kind": "turret", "weapon": "ea_pulse_medium", "position": [0.0, -20.0, 50.0]},
			{"name": "beam", "section": "reactor", "kind": "beam", "weapon": "ea_sweep_beam", "position": [20.0, 0.0, 550.0]},
			{"name": "dome", "section": "engine_r", "kind": "interceptor", "position": [20.0, 0.0, 650.0]},
		],
		"bays": [{"name": "bay_1", "section": "hangar"}, {"name": "bay_2", "section": "hangar"}],
		"engines": [{"name": "eng_r", "section": "engine_r", "share": 0.5}, {"name": "eng_l", "section": "engine_l", "share": 0.5}],
	}
	var m: CapitalDamage = CapitalDamage.build(sections, hardpoints, HULL)
	_changes.clear()
	_lost_mounts.clear()
	_drive = 0
	_disabled = 0
	_blew.clear()
	m.section_changed.connect(func(s: String, state: int) -> void: _changes.append([s, state]))
	m.mount_lost.connect(func(n: String) -> void: _lost_mounts.append(n))
	m.drive_changed.connect(func() -> void: _drive += 1)
	m.disabled.connect(func() -> void: _disabled += 1)
	m.blew.connect(func(s: String) -> void: _blew.append(s))
	return m


# The centre of section `index` of `LAYOUT`.
static func _at(index: int) -> Vector3:
	return Vector3(0.0, 0.0, 100.0 * index + 50.0)


func test_sections_share_the_hull_and_mounts_take_their_kinds_points() -> void:
	var m: CapitalDamage = _model()
	var total: float = 0.0
	for name: String in m.sections:
		total += m.sections[name].max_hp
	assert_almost_eq(total, HULL, 1e-6, "no armour: the sections hold the hull's points between them")
	assert_almost_eq(m.sections["bow"].max_hp, 2000.0, 1e-6)
	assert_eq(m.mounts["plasma"].max_hp, 2000.0, "a heavy mount (Q53)")
	assert_eq(m.mounts["pulse"].max_hp, 800.0, "a medium one")
	assert_eq(m.mounts["beam"].max_hp, 2500.0, "a beam emitter")
	assert_eq(m.mounts["dome"].max_hp, 400.0, "an interceptor battery, by its hardpoint's kind with no weapon named")
	assert_eq(m.mounts["plasma"].reach_m, 24.0, "a hit within its barrel's length lands on it")
	assert_eq(m.live_mounts().size(), 4)
	assert_eq(m.live_bays().size(), 2)
	assert_eq(m.thrust_fraction(), 1.0)
	assert_eq(m.fire_rate(), 1.0)


func test_a_structure_section_is_damaged_then_lost_with_its_mounts() -> void:
	var m: CapitalDamage = _model()
	assert_eq(m.hit("bow", Vector3(0.0, 0.0, 10.0), 500.0), 500.0, "the points it removed")
	assert_eq(m.sections["bow"].state, CapitalSection.State.DAMAGED)
	assert_eq(_changes, [["bow", CapitalSection.State.DAMAGED]])
	assert_true(m.mount_works("plasma"), "a hit out of reach leaves the mounts alone")
	m.hit("bow", Vector3(0.0, 0.0, 10.0), 1500.0)
	assert_eq(m.sections["bow"].state, CapitalSection.State.DISABLED, "at 0 a structure section is lost")
	assert_eq(_lost_mounts, ["plasma", "pulse"] as Array[String], "its mounts die with it")
	assert_false(m.mount_works("pulse"))
	assert_false(m.is_disabled, "the ship fights on")
	assert_false(m.is_destroyed)


func test_a_hit_on_a_mount_counts_against_its_section_and_kills_it_at_its_points() -> void:
	var m: CapitalDamage = _model()
	m.hit("bow", Vector3(0.0, -18.0, 52.0), 500.0)
	assert_almost_eq(m.mounts["pulse"].hp, 300.0, 1e-6, "the mount took the hit")
	assert_almost_eq(m.sections["bow"].hp, 1500.0, 1e-6, "and so did its section")
	m.hit_mount("pulse", 300.0)
	assert_false(m.mounts["pulse"].alive, "shot off at its own points")
	assert_eq(_lost_mounts, ["pulse"] as Array[String])
	assert_true(m.mount_works("plasma"), "its neighbour still fires")
	assert_eq(m.sections["bow"].state, CapitalSection.State.DAMAGED, "the section stands")


func test_an_engine_lost_takes_its_thrust_share_and_its_mounts() -> void:
	var m: CapitalDamage = _model()
	m.hit("engine_r", _at(6), 750.0)
	assert_eq(m.live_engines(), PackedStringArray(["eng_l"]))
	assert_almost_eq(m.thrust_fraction(), 0.5, 1e-6, "half the thrust")
	assert_gt(_drive, 0, "the drive is refitted")
	assert_eq(_lost_mounts, ["dome"] as Array[String])
	m.hit("engine_l", _at(7), 750.0)
	assert_eq(m.thrust_fraction(), 0.0, "no engines")
	assert_false(m.is_disabled, "with power and its bridge it still fights and turns")


func test_a_hangar_lost_stops_its_bays() -> void:
	var m: CapitalDamage = _model()
	m.hit("hangar", _at(4), 1200.0)
	assert_eq(m.live_bays().size(), 0)
	assert_false(m.bay_works("bay_1"))
	assert_false(m.is_disabled)


func test_a_magazine_or_fuel_section_blows_at_zero() -> void:
	for kind: String in ["magazine", "fuel"]:
		var m: CapitalDamage = _model()
		var index: int = 2 if kind == "magazine" else 3
		m.hit(kind, _at(index), m.sections[kind].max_hp - 1.0)
		assert_false(m.is_destroyed, "%s: not yet" % kind)
		m.hit(kind, _at(index), 5.0)
		assert_true(m.is_destroyed, "%s at 0 blows" % kind)
		assert_eq(m.blown, kind)
		assert_eq(m.sections[kind].state, CapitalSection.State.DESTROYED)
		assert_eq(_blew, [kind] as Array[String], "once")
		assert_eq(m.hit("bow", _at(0), 100.0), 0.0, "a destroyed ship takes nothing more")
		assert_eq(m.thrust_fraction(), 0.0)
		assert_eq(m.fire_rate(), 0.0)


func test_a_reactor_cuts_power_in_a_stage_shuts_down_then_blows_on_its_overload() -> void:
	var m: CapitalDamage = _model()
	m.hit("reactor", _at(5), 700.0)
	assert_eq(m.power(), 1.0, "above half its 1 500 points")
	assert_eq(_drive, 0)
	m.hit("reactor", _at(5), 100.0)
	assert_almost_eq(m.power(), 0.5, 1e-6, "a stage down below half")
	assert_almost_eq(m.thrust_fraction(), 0.5, 1e-6)
	assert_eq(_drive, 1, "the drive is refitted")
	m.hit("reactor", _at(5), 700.0)
	assert_eq(m.sections["reactor"].state, CapitalSection.State.DISABLED, "at 0 it shuts down")
	assert_true(m.is_disabled, "power gone: disabled")
	assert_eq(_disabled, 1)
	assert_false(m.is_destroyed, "not blown yet")
	assert_eq(m.power(), 0.0)
	assert_eq(m.thrust_fraction(), 0.0)
	assert_false(m.mount_works("plasma"), "nothing fires without power")
	assert_false(m.bay_works("bay_1"))
	assert_eq(m.hit("reactor", _at(5), 700.0), 0.0, "its overload removes no hull points")
	assert_false(m.is_destroyed)
	m.hit("reactor", _at(5), 60.0)
	assert_true(m.is_destroyed, "it blows after another half of its points")
	assert_eq(m.blown, "reactor")
	assert_eq(m.sections["reactor"].state, CapitalSection.State.DESTROYED)


func test_a_lost_bridge_halves_the_rate_of_fire_and_disables_only_with_every_engine_gone() -> void:
	var m: CapitalDamage = _model()
	m.hit("bridge", _at(1), 500.0)
	assert_false(m.has_bridge())
	assert_almost_eq(m.fire_rate(), 0.5, 1e-6, "last orders at half the rate of fire")
	assert_false(m.is_disabled, "the engines still answer")
	m.hit("engine_r", _at(6), 750.0)
	assert_false(m.is_disabled)
	m.hit("engine_l", _at(7), 750.0)
	assert_true(m.is_disabled, "no bridge and no engines: control is gone")
	assert_eq(m.fire_rate(), 0.0)


func test_hits_on_a_lost_section_pass_half_on_to_the_nearest_live_one() -> void:
	var m: CapitalDamage = _model()
	m.hit("hangar", _at(4), 1200.0)
	var fuel0: float = m.sections["fuel"].hp
	var reactor0: float = m.sections["reactor"].hp
	var removed: float = m.hit("hangar", Vector3(0.0, 0.0, 410.0), 100.0)
	assert_almost_eq(removed, 50.0, 1e-6, "half passed on")
	assert_almost_eq(m.sections["fuel"].hp, fuel0 - 50.0, 1e-6, "to the fuel section, nearer the hit")
	assert_eq(m.sections["reactor"].hp, reactor0)


func test_damage_past_a_sections_last_point_passes_half_on() -> void:
	var m: CapitalDamage = _model()
	var removed: float = m.hit("bow", Vector3(0.0, 0.0, 95.0), 2400.0)
	assert_almost_eq(removed, 2200.0, 1e-6, "its 2 000 points and half of the 400 past them")
	assert_almost_eq(m.sections["bridge"].hp, 300.0, 1e-6, "on the bridge next to it")


func test_an_unknown_section_takes_the_hit_on_the_nearest() -> void:
	var m: CapitalDamage = _model()
	m.hit("", _at(8), 100.0)
	assert_almost_eq(m.sections["spine"].hp, 1400.0, 1e-6)


func test_restore_makes_it_whole() -> void:
	var m: CapitalDamage = _model()
	m.hit("magazine", _at(2), 5000.0)
	assert_true(m.is_destroyed)
	m.restore()
	assert_false(m.is_destroyed)
	assert_eq(m.blown, "")
	for name: String in m.sections:
		assert_eq(m.sections[name].state, CapitalSection.State.INTACT)
	assert_eq(m.live_mounts().size(), 4)
	assert_eq(m.thrust_fraction(), 1.0)
