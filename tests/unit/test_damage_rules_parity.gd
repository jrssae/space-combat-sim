extends GutTest
## The damage rules' parity recording (M10-T75, Q70, Q85): every hull's, section's and part's points move from the GDScript
## ledgers (`HullHealth`, `CapitalDamage`, `StationSections`, `GridMountHealth`, `StationDamage`) into the native damage store.
## Before the move this file recorded what the GDScript rules gave for seeded runs of hits, aimed hits, repairs, heals, scuttles,
## restores and direct writes on synthetic hulls (`tests/fixtures/parity/damage_rules.json`); the store must give the same
## points, states and signals, op for op, bit for bit.

const FILE: String = "damage_rules"
const SEED: int = 75
const OPS: int = 400
## Ops per digest, so a mismatch is found near where it happened.
const CHUNK: int = 25

# Capital layouts: [name, kind, share, piece], laid in a row along z, 100 m each.
const SHIP_A: Array = [
	["bow", "structure", 0.20, "hull"], ["bridge", "bridge", 0.05, "hull"], ["magazine", "magazine", 0.10, "hull"],
	["fuel", "fuel", 0.08, "hull"], ["hangar", "hangar", 0.12, "hull"], ["reactor", "reactor", 0.15, "hull"],
	["engine_r", "engine", 0.075, "hull"], ["engine_l", "engine", 0.075, "hull"], ["drum", "structure", 0.15, "drum"],
]
const SHIP_B: Array = [
	["bow", "structure", 0.30, "hull"], ["mid", "structure", 0.30, "hull"], ["reactor_a", "reactor", 0.10, "hull"],
	["reactor_b", "reactor", 0.10, "hull"], ["stern", "engine", 0.20, "hull"],
]
const SHIP_C: Array = [["fore", "structure", 0.5, "hull"], ["aft", "structure", 0.5, "hull"]]


func _hardpoints_a() -> Dictionary:
	return {
		"weapons": [
			{"name": "plasma", "section": "bow", "kind": "turret", "weapon": "ea_plasma_heavy", "position": [0.0, 20.0, 50.0], "barrel_m": 24.0},
			{"name": "pulse", "section": "bow", "kind": "turret", "weapon": "ea_pulse_medium", "position": [0.0, -20.0, 50.0]},
			{"name": "beam", "section": "reactor", "kind": "beam", "weapon": "ea_sweep_beam", "position": [20.0, 0.0, 550.0]},
			{"name": "dome", "section": "engine_r", "kind": "interceptor", "position": [20.0, 0.0, 650.0]},
			{"name": "lost_one", "section": "nowhere", "kind": "turret", "weapon": "ea_pulse_medium", "position": [0.0, 0.0, 120.0]},
			{"name": "spinner", "section": "drum", "kind": "missile", "position": [0.0, 15.0, 850.0]},
		],
		"bays": [{"name": "bay_1", "section": "hangar", "position": [0.0, -20.0, 430.0], "exit": [0.0, -20.0, 420.0], "mouth_m": [16.0, 12.0]},
				{"name": "bay_2", "section": "hangar", "position": [0.0, 20.0, 470.0], "exit": [0.0, 20.0, 480.0], "mouth_m": [16.0, 12.0]},
				{"name": "bay_far", "section": "hangar"}],
		"engines": [{"name": "eng_r", "section": "engine_r", "share": 0.5, "position": [0.0, 0.0, 699.0], "radius_m": 8.0},
				{"name": "eng_l", "section": "engine_l", "share": 0.5, "position": [0.0, 0.0, 799.0], "radius_m": 8.0}],
	}


func _hardpoints_b() -> Dictionary:
	return {
		"weapons": [
			{"name": "a", "section": "bow", "kind": "turret", "weapon": "ea_pulse_medium", "position": [5.0, 18.0, 30.0]},
			{"name": "b", "section": "bow", "kind": "turret", "weapon": "ea_pulse_medium", "position": [-5.0, 18.0, 36.0]},
			{"name": "c", "section": "reactor_a", "kind": "beam", "weapon": "ea_sweep_beam", "position": [0.0, 20.0, 250.0]},
		],
		"engines": [{"name": "main", "section": "stern", "share": 1.0, "position": [0.0, 0.0, 495.0], "radius_m": 20.0}],
	}


func _capital(layout: Array, hardpoints: Dictionary, hull: float) -> CapitalDamage:
	var entries: Dictionary = {}
	for i: int in layout.size():
		var row: Array = layout[i]
		entries[row[0]] = {"name": row[0], "kind": row[1], "hull_share": row[2], "piece": row[3],
				"aabb_min": [-20.0, -20.0, 100.0 * i], "aabb_max": [20.0, 20.0, 100.0 * i + 100.0]}
	return CapitalDamage.from_entries(entries, hardpoints, hull)


func _station() -> StationDamage:
	var sections := StationSections.new()
	var rows: Array = [["command", "frame"], ["cargo", "frame"], ["reactor", "frame"], ["ring_a", "drum"], ["ring_b", "drum"]]
	for i: int in rows.size():
		sections.sections.append({"name": rows[i][0], "body": rows[i][1],
				"aabb": AABB(Vector3(100.0 * (i % 3), -20.0, -20.0 + 60.0 * (i / 3)), Vector3(100.0, 40.0, 40.0))})
		sections.max_health.append(1000.0 + 250.0 * i)
	sections.health = sections.max_health.duplicate()
	var mounts: GridMountHealth = GridMountHealth.from_mounts([
		{"name": "L1", "kind": "light_pulse", "body": "frame", "position": Vector3(150.0, 20.0, 0.0)},
		{"name": "L2", "kind": "light_pulse", "body": "frame", "position": Vector3(170.0, 20.0, 5.0)},
		{"name": "H1", "kind": "heavy", "body": "frame", "position": Vector3(40.0, -20.0, 0.0)},
		{"name": "I1", "kind": "interceptor", "body": "drum", "position": Vector3(50.0, 20.0, 60.0)},
	] as Array[Dictionary], func(k: String) -> int: return {"light_pulse": 1, "heavy": 2, "interceptor": 3}.get(k, 1))
	return StationDamage.make(sections, mounts, {"command": "bridge", "reactor": "reactor"})


func _snapshot_capital(m: CapitalDamage) -> Array:
	var out: Array = []
	for name: String in m.sections:
		out.append([m.sections[name].hp, m.sections[name].state])
	for list: Dictionary in [m.mounts, m.engines, m.bays]:
		for name: String in list:
			out.append([list[name].hp, list[name].alive])
	out.append([m.hull_hp, m.is_disabled, m.is_destroyed, m.blown, m.power(), m.thrust_fraction(), m.has_bridge(),
			m.reactor_shut_down(), m.live_mounts(), m.live_engines(), m.live_bays()])
	return out


func _snapshot_station(d: StationDamage) -> Array:
	return [d.sections.health, d.mounts.health, d.mounts.out_count(), d.hull_hp, d.is_disabled, d.is_destroyed, d.blown,
			d.has_power(), d.hull_fraction()]


# A point near `centre`: within `spread` m on each axis.
func _near(rng: RandomNumberGenerator, centre: Vector3, spread: float) -> Vector3:
	return centre + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), rng.randf_range(-spread, spread))


func _damage(rng: RandomNumberGenerator) -> float:
	var roll: float = rng.randf()
	if roll < 0.04:
		return 0.0
	if roll < 0.07:
		return -5.0
	if roll < 0.1:
		return rng.randf_range(2000.0, 6000.0)
	return rng.randf_range(0.5, 450.0)


func _record_digests(ops: Array) -> Dictionary:
	var digests: Array = []
	for start: int in range(0, ops.size(), CHUNK):
		digests.append(ParityFixture.digest(ops.slice(start, start + CHUNK)))
	return {"ops": ops.size(), "chunks": digests, "final": ops.back() if not ops.is_empty() else []}


# Seeded ops on capital `m`: hits by section and point (some on unknown sections, near parts, out of reach), aimed hits on
# parts and sections, direct writes of a mount's points, scuttles and restores. Each op: [op, its return, its signals, the
# state after].
func _run_capital(m: CapitalDamage, seed_offset: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + seed_offset
	var events: Array = []
	m.section_changed.connect(func(s: String, state: int) -> void: events.append(["section", s, state]))
	m.mount_lost.connect(func(n: String) -> void: events.append(["mount", n]))
	m.part_lost.connect(func(k: String) -> void: events.append(["part", k]))
	m.drive_changed.connect(func() -> void: events.append(["drive"]))
	m.disabled.connect(func() -> void: events.append(["disabled"]))
	m.blew.connect(func(s: String) -> void: events.append(["blew", s]))
	var names: Array = m.sections.keys()
	var keys: Array = []
	for name: String in m.mounts:
		keys.append("mount:" + name)
	for name: String in m.engines:
		keys.append("engine:" + name)
	for name: String in m.bays:
		keys.append("bay:" + name)
	var spots: Array[Vector3] = []
	for list: Dictionary in [m.mounts, m.engines, m.bays]:
		for name: String in list:
			spots.append(list[name].position)
	var ops: Array = []
	for i: int in OPS:
		events.clear()
		var roll: float = rng.randf()
		var op: Array = []
		var ret: Variant = null
		if roll < 0.72:
			var section: String = "nowhere" if rng.randf() < 0.08 else str(names[rng.randi_range(0, names.size() - 1)])
			var point: Vector3
			if rng.randf() < 0.35 and not spots.is_empty():
				point = _near(rng, spots[rng.randi_range(0, spots.size() - 1)], 22.0)
			else:
				var s: CapitalSection = m.sections.get(section, m.sections[names[0]])
				point = _near(rng, s.box.get_center(), 30.0)
			var dmg: float = _damage(rng)
			op = ["hit", section, point, dmg]
			ret = m.hit(section, point, dmg)
		elif roll < 0.88:
			var key: String = "bay:nope" if rng.randf() < 0.05 else (str(keys[rng.randi_range(0, keys.size() - 1)]) \
					if rng.randf() < 0.7 and not keys.is_empty() else str(names[rng.randi_range(0, names.size() - 1)]))
			var dmg: float = _damage(rng)
			op = ["hit_part", key, dmg]
			ret = m.hit_part(key, dmg)
		elif roll < 0.92:
			var mount: String = str(m.mounts.keys()[rng.randi_range(0, m.mounts.size() - 1)]) if not m.mounts.is_empty() else ""
			op = ["mount_hp", mount]
			if not mount.is_empty():
				m.mounts[mount].hp = 1.0
		elif roll < 0.95:
			op = ["scuttle"]
			ret = m.scuttle()
		else:
			op = ["restore"]
			m.restore()
		ops.append([op, ret, events.duplicate(true), _snapshot_capital(m)])
	return ops


func _run_station(d: StationDamage) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 100
	var events: Array = []
	d.disabled.connect(func() -> void: events.append(["disabled"]))
	d.destroyed.connect(func(s: String) -> void: events.append(["destroyed", s]))
	d.sections.lost.connect(func(i: int) -> void: events.append(["lost", i]))
	var ops: Array = []
	for i: int in OPS:
		events.clear()
		var roll: float = rng.randf()
		var op: Array = []
		var ret: Variant = null
		if roll < 0.7:
			var body: String = "frame" if rng.randf() < 0.65 else "drum"
			var point: Vector3
			if rng.randf() < 0.4:
				point = _near(rng, d.mounts.positions[rng.randi_range(0, d.mounts.count() - 1)], 40.0)
			else:
				point = Vector3(rng.randf_range(-60.0, 360.0), rng.randf_range(-80.0, 80.0), rng.randf_range(-80.0, 120.0))
			var dmg: float = _damage(rng)
			op = ["hit", body, point, dmg]
			ret = d.hit(body, point, dmg)
		elif roll < 0.8:
			var index: int = rng.randi_range(-1, d.sections.count())
			var dmg: float = _damage(rng)
			op = ["hit_section", index, dmg]
			ret = d.hit_section(index, dmg)
		elif roll < 0.86:
			var index: int = rng.randi_range(0, d.sections.count() - 1)
			var amount: float = rng.randf_range(10.0, 900.0)
			op = ["repair", index, amount]
			ret = d.sections.repair(index, amount)
		elif roll < 0.91:
			var index: int = rng.randi_range(0, d.mounts.count() - 1)
			var amount: float = rng.randf_range(10.0, 900.0)
			op = ["heal", index, amount]
			ret = d.mounts.heal(index, amount)
		elif roll < 0.94:
			var index: int = rng.randi_range(0, d.mounts.count() - 1)
			op = ["mount_repair", index]
			ret = d.mounts.repair(index)
		elif roll < 0.97:
			var index: int = rng.randi_range(0, d.mounts.count() - 1)
			var amount: float = rng.randf_range(10.0, 900.0)
			op = ["wear", index, amount]
			ret = d.mounts.wear(index, amount)
		else:
			op = ["restore"]
			d.restore()
		ops.append([op, ret, events.duplicate(true), _snapshot_station(d)])
	return ops


func _run_hulls() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 200
	var hulls: Array[HullHealth] = [HullHealth.new(300.0), HullHealth.new(0.0), HullHealth.new(5.0e4)]
	var ops: Array = []
	for i: int in OPS:
		var h: HullHealth = hulls[rng.randi_range(0, hulls.size() - 1)]
		var roll: float = rng.randf()
		var op: Array = []
		var ret: Variant = null
		if roll < 0.85:
			var amount: float = NAN if rng.randf() < 0.02 else _damage(rng) * 0.3
			op = ["apply", amount if not is_nan(amount) else "nan"]
			ret = h.apply(amount)
		elif roll < 0.92:
			op = ["restore"]
			h.restore()
		else:
			var hp: float = rng.randf_range(-10.0, 400.0)
			op = ["set_hp", hp]
			h.hp = hp
		ops.append([op, ret, [h.hp, h.max_hp, h.destroyed, h.destroyed_now, h.fraction()]])
	return ops


func _cases() -> Dictionary:
	return {
		"capital_a": _record_digests(_run_capital(_capital(SHIP_A, _hardpoints_a(), 10000.0), 0)),
		"capital_b": _record_digests(_run_capital(_capital(SHIP_B, _hardpoints_b(), 4000.0), 1)),
		"capital_c": _record_digests(_run_capital(_capital(SHIP_C, {}, 2500.0), 2)),
		"station": _record_digests(_run_station(_station())),
		"hulls": _record_digests(_run_hulls()),
	}


func test_the_damage_rules_match_the_recorded_gdscript_rules_op_for_op() -> void:
	var got: Dictionary = _cases()
	var expected: Variant = await ParityFixture.expected(FILE, "cases", func() -> Dictionary: return _cases())
	assert_not_null(expected, "the rules are recorded (%s.json)" % FILE)
	if expected == null:
		return
	var stored: Dictionary = expected
	for case: String in got:
		var mine: Dictionary = ParityFixture.encode(got[case])
		var theirs: Dictionary = stored.get(case, {})
		assert_eq(mine.get("ops"), theirs.get("ops"), "%s: as many ops as recorded" % case)
		var first_bad: int = -1
		var chunks: Array = mine.get("chunks", [])
		var recorded: Array = theirs.get("chunks", [])
		for c: int in chunks.size():
			if c >= recorded.size() or chunks[c] != recorded[c]:
				first_bad = c * CHUNK
				break
		assert_eq(first_bad, -1, "%s: every op as recorded (first chunk off starts at op %d)" % [case, first_bad])
		assert_eq(mine.get("final"), theirs.get("final"), "%s: the last op and state as recorded" % case)
