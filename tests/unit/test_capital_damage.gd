extends GutTest
## `CapitalDamage` (M10-T08, D12.5, Q53; M10-T65, Q72): points by hull share, only the part a shot hits takes it (a subsystem in
## full and the hull half, else hull damage off the section and the total), a lost section takes what it holds and its hits go to
## the total, a magazine, fuel or reactor section at 0 blows (a hulk or not), the bridge at 0, the reactor at a tenth (Q78) or the
## hull below a tenth makes a hulk with no power.
## A synthetic hull of 10 000 points laid along z.

const HULL: float = 10000.0

var _changes: Array = []
var _lost_mounts: Array[String] = []
var _drive: int = 0
var _disabled: int = 0
var _blew: Array[String] = []
var _parts_lost: Array[String] = []


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
		"bays": [{"name": "bay_1", "section": "hangar", "position": [0.0, -20.0, 430.0], "exit": [0.0, -20.0, 420.0], "mouth_m": [16.0, 12.0]},
				{"name": "bay_2", "section": "hangar", "position": [0.0, 20.0, 470.0], "exit": [0.0, 20.0, 480.0], "mouth_m": [16.0, 12.0]}],
		"engines": [{"name": "eng_r", "section": "engine_r", "share": 0.5, "position": [0.0, 0.0, 699.0], "radius_m": 8.0},
				{"name": "eng_l", "section": "engine_l", "share": 0.5, "position": [0.0, 0.0, 799.0], "radius_m": 8.0}],
	}
	var m: CapitalDamage = CapitalDamage.build(sections, hardpoints, HULL)
	_changes.clear()
	_lost_mounts.clear()
	_drive = 0
	_disabled = 0
	_blew.clear()
	_parts_lost.clear()
	m.part_lost.connect(func(k: String) -> void: _parts_lost.append(k))
	m.section_changed.connect(func(s: String, state: int) -> void: _changes.append([s, state]))
	m.mount_lost.connect(func(n: String) -> void: _lost_mounts.append(n))
	m.drive_changed.connect(func() -> void: _drive += 1)
	m.disabled.connect(func() -> void: _disabled += 1)
	m.blew.connect(func(s: String) -> void: _blew.append(s))
	return m


# A point on the bow clear of its two turrets.
const BOW_CLEAR := Vector3(0.0, 0.0, 10.0)


# The centre of section `index` of `LAYOUT`.
static func _at(index: int) -> Vector3:
	return Vector3(0.0, 0.0, 100.0 * index + 50.0)


func test_sections_share_the_hull_and_parts_take_their_own_points() -> void:
	var m: CapitalDamage = _model()
	var total: float = 0.0
	for name: String in m.sections:
		total += m.sections[name].max_hp
	assert_almost_eq(total, HULL, 1e-6, "no armour: the sections hold the hull's points between them")
	assert_eq(m.hull_max, HULL)
	assert_almost_eq(m.sections["bow"].max_hp, 2000.0, 1e-6)
	assert_eq(m.mounts["plasma"].max_hp, 2000.0, "a heavy mount (Q53)")
	assert_eq(m.mounts["pulse"].max_hp, 800.0, "a medium one")
	assert_eq(m.mounts["beam"].max_hp, 2500.0, "a beam emitter")
	assert_eq(m.mounts["dome"].max_hp, 400.0, "an interceptor battery, by its hardpoint's kind with no weapon named")
	assert_eq(m.mounts["plasma"].reach_m, 24.0, "a hit within its barrel's length lands on it")
	assert_eq(m.engines["eng_r"].max_hp, 1500.0, "an engine's own points (section_damage)")
	assert_eq(m.engines["eng_r"].reach_m, 18.0, "its nozzle's radius and the mount reach")
	assert_eq(m.bays["bay_1"].position, Vector3(0.0, -20.0, 420.0), "a bay is hit at its mouth")
	assert_eq(m.bays["bay_1"].reach_m, 20.0, "half its mouth's diagonal and the mount reach")
	assert_eq(m.live_mounts().size(), 4)
	assert_eq(m.live_bays().size(), 2)
	assert_eq(m.thrust_fraction(), 1.0)
	assert_eq(m.fire_rate(), 1.0)


func test_a_hull_hit_lowers_its_section_and_the_total_only() -> void:
	var m: CapitalDamage = _model()
	assert_eq(m.hit("bow", Vector3(0.0, 0.0, 10.0), 500.0), 500.0, "all of it off the hull")
	assert_eq(m.sections["bow"].hp, 1500.0)
	assert_eq(m.hull_hp, HULL - 500.0)
	assert_eq(m.sections["bow"].state, CapitalSection.State.DAMAGED)
	assert_eq(_changes, [["bow", CapitalSection.State.DAMAGED]])
	assert_eq(m.mounts["plasma"].hp, 2000.0, "a hit out of reach leaves the mounts alone")
	assert_eq(m.mounts["pulse"].hp, 800.0)


func test_only_the_part_hit_takes_it_in_full_and_the_hull_half() -> void:
	var m: CapitalDamage = _model()
	assert_almost_eq(m.hit("bow", Vector3(0.0, -18.0, 52.0), 500.0), 250.0, 1e-6, "half off the hull")
	assert_almost_eq(m.mounts["pulse"].hp, 300.0, 1e-6, "the mount took it all")
	assert_eq(m.mounts["plasma"].hp, 2000.0, "only the part hit: its neighbour is untouched")
	assert_eq(m.sections["bow"].hp, 2000.0, "its section none: only the part hit")
	assert_almost_eq(m.hull_hp, HULL - 250.0, 1e-6)
	m.hit_mount("pulse", 300.0)
	assert_false(m.mounts["pulse"].alive, "shot off at its own points")
	assert_eq(_lost_mounts, ["pulse"] as Array[String])
	assert_true(m.mount_works("plasma"), "its neighbour still fires")
	assert_eq(m.sections["bow"].state, CapitalSection.State.INTACT, "the section untouched")


func test_an_engine_or_a_bay_is_a_part_of_its_own() -> void:
	var m: CapitalDamage = _model()
	assert_almost_eq(m.hit("engine_r", Vector3(0.0, 3.0, 702.0), 1000.0), 500.0, 1e-6, "an engine: the hull half")
	assert_almost_eq(m.engines["eng_r"].hp, 500.0, 1e-6)
	assert_eq(m.mounts["dome"].hp, 400.0, "the dome on the section is not hit")
	m.hit_part("engine:eng_r", 600.0)
	assert_eq(m.live_engines(), PackedStringArray(["eng_l"]), "shot off")
	assert_almost_eq(m.thrust_fraction(), 0.5, 1e-6, "half the thrust")
	assert_gt(_drive, 0, "the drive is refitted")
	assert_eq(m.sections["engine_r"].state, CapitalSection.State.INTACT, "its section untouched: only the part hit")
	assert_true(m.mount_works("dome"))
	m.hit("hangar", Vector3(0.0, -20.0, 421.0), 1500.0)
	assert_false(m.bay_works("bay_1"), "a bay shot off at its mouth")
	assert_true(m.bay_works("bay_2"))
	assert_eq(_parts_lost, ["engine:eng_r", "bay:bay_1"] as Array[String])


func test_a_lost_section_takes_what_it_holds() -> void:
	var m: CapitalDamage = _model()
	m.hit("engine_r", _at(6) + Vector3(0.0, 15.0, 0.0), 750.0)
	assert_eq(m.sections["engine_r"].state, CapitalSection.State.DISABLED)
	assert_eq(m.live_engines(), PackedStringArray(["eng_l"]))
	assert_eq(_lost_mounts, ["dome"] as Array[String])
	m.hit("hangar", _at(4), 1200.0)
	assert_eq(m.live_bays().size(), 0, "a hangar lost stops its bays")
	assert_false(m.is_disabled, "the ship fights on")


func test_hits_on_a_lost_section_go_to_the_hull() -> void:
	var m: CapitalDamage = _model()
	m.hit("hangar", _at(4), 1200.0)
	var fuel0: float = m.sections["fuel"].hp
	var hull0: float = m.hull_hp
	assert_eq(m.hit("hangar", Vector3(0.0, 0.0, 410.0), 100.0), 100.0, "all of it, no share passed on")
	assert_eq(m.sections["fuel"].hp, fuel0, "no section nearby takes any")
	assert_eq(m.hull_hp, hull0 - 100.0)
	assert_eq(m.hit("bow", Vector3(0.0, 0.0, 95.0), 2400.0), 2400.0, "past a section's last point: the rest to the total")
	assert_eq(m.sections["bridge"].hp, m.sections["bridge"].max_hp, "not to the section next to it")


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


func test_the_reactor_is_a_subsystem_that_cuts_power_in_a_stage_and_explodes_at_zero() -> void:
	var m: CapitalDamage = _model()
	assert_almost_eq(m.hit("reactor", _at(5), 700.0), 350.0, 1e-6, "the reactor in full, the hull half")
	assert_eq(m.sections["reactor"].hp, 800.0)
	assert_eq(m.power(), 1.0, "above half its 1 500 points")
	m.hit("reactor", _at(5), 100.0)
	assert_almost_eq(m.power(), 0.5, 1e-6, "a stage down below half")
	assert_almost_eq(m.thrust_fraction(), 0.5, 1e-6)
	assert_eq(_drive, 1, "the drive is refitted")
	m.hit("reactor", _at(5), 700.0)
	assert_true(m.is_destroyed, "from 700 to 0 in one hit it explodes, with no hulk first")
	assert_eq(m.blown, "reactor")
	assert_eq(m.sections["reactor"].state, CapitalSection.State.DESTROYED)
	assert_eq(_disabled, 0, "never a hulk on the way")


func test_the_reactor_at_a_tenth_shuts_the_ship_down_and_at_zero_still_blows_it() -> void:
	var m: CapitalDamage = _model()
	m.hit("reactor", _at(5), 1340.0)
	assert_false(m.is_disabled, "160 of 1 500 points: still above a tenth")
	assert_false(m.reactor_shut_down())
	m.hit("reactor", _at(5), 15.0)
	assert_true(m.reactor_shut_down(), "145 of 1 500: at or below a tenth (Q78)")
	assert_true(m.is_disabled, "it powers down into a hulk")
	assert_eq(_disabled, 1)
	assert_false(m.has_power())
	assert_eq(m.fire_rate(), 0.0, "no weapon fires")
	assert_eq(m.live_bays().size(), 0, "nothing launches or docks")
	assert_true(m.has_bridge(), "with its bridge standing")
	assert_false(m.is_destroyed)
	m.hit("reactor", _at(5), 100.0)
	assert_eq(_disabled, 1, "once")
	m.hit("reactor", _at(5), 45.0)
	assert_true(m.is_destroyed, "the hulk's reactor at 0 still blows it")
	assert_eq(_blew, ["reactor"] as Array[String])


func test_the_bridge_at_zero_makes_a_hulk_with_no_power() -> void:
	var m: CapitalDamage = _model()
	assert_almost_eq(m.hit("bridge", _at(1), 400.0), 200.0, 1e-6, "the bridge in full, the hull half")
	assert_false(m.is_disabled)
	m.hit("bridge", _at(1), 100.0)
	assert_false(m.has_bridge())
	assert_true(m.is_disabled, "a hulk (Q72)")
	assert_eq(_disabled, 1)
	assert_false(m.has_power())
	assert_eq(m.fire_rate(), 0.0, "no weapon fires")
	assert_eq(m.live_mounts().size(), 0)
	assert_eq(m.live_bays().size(), 0, "nothing launches or docks")
	assert_eq(m.thrust_fraction(), 0.0)
	assert_eq(m.power(), 0.0)
	assert_false(m.is_destroyed)
	m.hit("bow", BOW_CLEAR, 100.0)
	assert_almost_eq(m.hull_hp, HULL - 250.0 - 100.0, 1e-6, "a hulk still takes hits")


func test_the_hull_below_a_tenth_makes_a_hulk() -> void:
	var m: CapitalDamage = _model()
	m.hit("bow", BOW_CLEAR, 2000.0)
	m.hit("spine", _at(8), 1500.0)
	m.hit("bow", BOW_CLEAR, 5000.0)  # on the lost bow: the total alone
	assert_almost_eq(m.hull_fraction(), 0.15, 1e-6)
	assert_false(m.is_disabled)
	m.hit("bow", BOW_CLEAR, 501.0)
	assert_true(m.is_disabled, "below 10 % of its points")
	assert_true(m.has_bridge(), "with its bridge standing")
	assert_eq(_disabled, 1)
	m.hit("bow", BOW_CLEAR, 999.0)
	assert_eq(m.hull_hp, 0.0)
	assert_eq(_disabled, 1, "once")


func test_an_unknown_section_takes_the_hit_on_the_nearest() -> void:
	var m: CapitalDamage = _model()
	m.hit("", _at(8), 100.0)
	assert_almost_eq(m.sections["spine"].hp, 1400.0, 1e-6)


func test_scuttling_leaves_a_hulk_whole() -> void:
	var m: CapitalDamage = _model()
	assert_true(m.scuttle())
	assert_true(m.is_disabled)
	assert_false(m.has_power())
	assert_false(m.scuttle(), "once")


func test_restore_makes_it_whole() -> void:
	var m: CapitalDamage = _model()
	m.hit_part("engine:eng_l", 5000.0)
	m.hit("magazine", _at(2), 5000.0)
	assert_true(m.is_destroyed)
	m.restore()
	assert_false(m.is_destroyed)
	assert_eq(m.blown, "")
	assert_eq(m.hull_hp, HULL)
	for name: String in m.sections:
		assert_eq(m.sections[name].state, CapitalSection.State.INTACT)
	assert_eq(m.live_mounts().size(), 4)
	assert_eq(m.thrust_fraction(), 1.0)
