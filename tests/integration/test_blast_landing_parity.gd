extends GutTest
## The blasts' parity recording (M10-T76, Q70): blast landing moves from GDScript (`BlastResolver._land`, one `apply_hit` and
## one push a hull, the mines through `MineField.blast_reached`) into one native batch on the damage store. Before the move
## this file recorded, from the GDScript landing in the real main scene (free flight, Babylon 5 in play), seeded blasts on
## a fighter group with low hulls (deaths blowing in turn), on an Omega with its sections nearly spent (sections, mounts and its
## death blast), on Babylon 5's sections and grid, and an Omega dying beside a 100-mine field with fighters at its far end (the
## field going off as a chain): every blast hit (the hull, the tick, damage, points removed, point), every event, every hull's
## velocity each tick (the pushes) and the end state (`tests/fixtures/parity/blast_landing.json`). The native batch must give the
## same, bit for bit, with six threads, one thread and the `delayed` step alike; its hits are read from the batch's native hit
## log now (a hit it leaves to GDScript would still show as a `hit_taken`).

const FILE: String = "blast_landing"
const TICKS: int = 240
const OMEGA: StringName = &"ea_omega"
const SECTION_LEFT: float = 0.12
const CHUNK_TICKS: int = 20
## The ticks Omega B's death and its field's chain fall in (the cost readout).
const CHAIN_FROM: int = 130
const CHAIN_TO: int = 239

var main: Main
var _tick: int = 0
var _hits: Array = []
var _pending: Array = []  # [who, tick, HitInfo]: its points removed are read when the tick ends
var _events: Array = []
var _who: Dictionary = {}  # body id -> place in the scene
var _ships: Array[Combatant] = []
var _caps: Array[CapitalShip] = []
var _station: Station = null
var _field: MineField = null
var _settings_backup: Dictionary = {}


# The Omegas' hangars stay empty (M10-T17's switch, when the hangar has it): only the hulls placed here.
func before_all() -> void:
	(CapitalHangar as GDScript).set(&"stocked_on_spawn", false)


func after_all() -> void:
	(CapitalHangar as GDScript).set(&"stocked_on_spawn", true)


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # the player sits far from the blasts in any case
	_settings_backup = {&"perf_threads": Settings.get_value(&"perf_threads"), &"sim_step": Settings.get_value(&"sim_step")}


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	for key: StringName in _settings_backup:
		Settings.set_value(key, _settings_backup[key])


func test_blasts_and_their_outcomes_match_the_recorded_gdscript_landing() -> void:
	await _check(6, &"threaded", true)


func test_one_thread_lands_the_same_blasts() -> void:
	await _check(1, &"threaded", false)


func test_the_delayed_step_lands_the_same_blasts() -> void:
	await _check(6, &"delayed", false)


func _check(threads: int, step: StringName, may_record: bool) -> void:
	Settings.set_value(&"perf_threads", threads)
	Settings.set_value(&"sim_step", step)
	var got: Dictionary = await _run()
	gut.p("%d threads, %s: blast hits %d, events %d, blasts %d" % [threads, step, int(got["hits"]), int(got["events"]),
			int(got["blasts"])])
	assert_gt(int(got["hits"]), 40, "the blasts land (%d hits)" % int(got["hits"]))
	var expected: Variant = await ParityFixture.expected(FILE, "scene", func() -> Dictionary: return got) if may_record \
			else ParityFixture.stored(FILE, "scene")
	assert_not_null(expected, "the landing is recorded (%s.json)" % FILE)
	if expected == null:
		return
	var mine: Dictionary = ParityFixture.encode(got)
	var theirs: Dictionary = expected
	assert_eq(mine["hits"], theirs.get("hits"), "as many blast hits as recorded")
	assert_eq(mine["blasts"], theirs.get("blasts"), "as many blasts as recorded")
	var first_bad: int = -1
	var chunks: Array = mine["chunks"]
	var recorded: Array = theirs.get("chunks", [])
	for c: int in chunks.size():
		if c >= recorded.size() or chunks[c] != recorded[c]:
			first_bad = c * CHUNK_TICKS
			break
	assert_eq(first_bad, -1, "hits and velocities tick by tick as recorded (first chunk off starts at tick %d)" % first_bad)
	assert_eq(mine["events"], theirs.get("events"), "as many events as recorded")
	assert_eq(mine["event_log"], theirs.get("event_log"), "the events as recorded")
	assert_eq(mine["counts"], theirs.get("counts"), "the blasts' readouts (hulls hurt, pushed) as recorded")
	assert_eq(mine["end"], theirs.get("end"), "every hull's end state as recorded")


# The scene and its seeded blasts; returns the digests compared.
func _run() -> Dictionary:
	_tick = 0
	_hits.clear()
	_pending.clear()
	_events.clear()
	_who.clear()
	_ships.clear()
	_caps.clear()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 20
	main.ally_pool_size = 12
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)
	BlastResolver.reset_stats()
	BlastResolver.set_hit_log(true)
	_station = main.far_props.station
	var p: Vector3 = main.ship.global_position
	var fwd: Vector3 = -main.ship.global_basis.z
	var side: Vector3 = main.ship.global_basis.x
	var up: Vector3 = main.ship.global_basis.y
	var rng := RandomNumberGenerator.new()
	rng.seed = 76
	# A: a fighter group 3 km ahead, many hulls low.
	var group_a: Vector3 = p + fwd * 3000.0
	var a: Array[Combatant] = []
	for k: int in 14:
		var c: Combatant = _spawn("raider" if k < 8 else "ally")
		a.append(c)
		_place(c, group_a + Vector3(rng.randf_range(-70.0, 70.0), rng.randf_range(-70.0, 70.0), rng.randf_range(-70.0, 70.0)))
	# The Omegas: one 6 km to the right with its sections nearly spent, one 6 km to the left beside the minefield.
	var cap_a: CapitalShip = _omega(p + side * 6000.0 + fwd * 3000.0, "EAS Test A")
	var cap_b: CapitalShip = _omega(p - side * 6000.0 + fwd * 3000.0, "EAS Test B")
	if cap_a == null or cap_b == null:
		return {}
	var b: Array[Combatant] = []
	for k: int in 4:
		var c: Combatant = _spawn("raider")
		b.append(c)
		_place(c, cap_a.global_position + up * (300.0 + 40.0 * k) + side * (30.0 * k))
	# The field: 100 raider mines in a line from 2.3 km to 4.3 km left of Omega B (its reactor reaches the first few, the rest
	# go off as a chain), and a raider group at its far end.
	var field_at: Vector3 = cap_b.global_position - side * 3300.0
	_field = MineField.spawn_in(main.world, main.world.to_universe(field_at), true)
	var from: Vector3 = side * 1000.0
	var plan: MineFieldPlan = MineFieldPlan.place({"id": "t76", "faction": "raiders", "kind": "mine_prox", "pattern": "line",
			"from": [from.x, from.y, from.z], "to": [-from.x, -from.y, -from.z], "count": 100})
	var made: int = _field.build(plan.rows)
	assert_eq(made, 100, "the field is laid")
	main.director.watch_mines(_field)
	_field.detonated.connect(func(slot: int, kind: int, _at: Vector3) -> void: _events.append([_tick, "mine", slot, kind]))
	# A raider group waits just past the mine farthest from Omega B, where the chain ends.
	var far_mine: Vector3 = field_at
	for row: Dictionary in plan.rows:
		var at: Vector3 = field_at + (row["offset"] as Vector3)
		if at.distance_to(cap_b.global_position) > far_mine.distance_to(cap_b.global_position):
			far_mine = at
	var away: Vector3 = (far_mine - cap_b.global_position).normalized()
	var c_group: Array[Combatant] = []
	for k: int in 6:
		var c: Combatant = _spawn("raider")  # the mines' own side: only a blast sets their mines off
		c_group.append(c)
		_place(c, far_mine + away * (50.0 + 12.0 * k) + up * (10.0 * k))
	await _ticks(1)
	# Placed again after the first tick (the pool's spawn settles them), then watched.
	rng.seed = 76
	for k: int in a.size():
		_place(a[k], group_a + Vector3(rng.randf_range(-70.0, 70.0), rng.randf_range(-70.0, 70.0), rng.randf_range(-70.0, 70.0)))
		if k % 2 == 0:
			a[k].damageable.hull.hp = a[k].damageable.hull.max_hp * (0.05 + 0.04 * k)
	for k: int in b.size():
		_place(b[k], cap_a.global_position + up * (300.0 + 40.0 * k) + side * (30.0 * k))
	for k: int in c_group.size():
		_place(c_group[k], far_mine + away * (50.0 + 12.0 * k) + up * (10.0 * k))
	for c: Combatant in a + b + c_group:
		_watch_ship(c)
	for cap: CapitalShip in [cap_a, cap_b]:
		_watch_capital(cap)
	_watch_station()
	SimCore.for_tree(get_tree()).sync_now()
	var chunks: Array = []
	var chunk_rows: Array = []
	var hits_from: int = 0
	# The readouts (wall clock): a scripted blast's landing with the deaths it causes, and Omega B's chain: its death's landing
	# then every step of its field (the mines going off, drawn, with their blasts and the deaths they cause).
	var costs: PackedStringArray = []
	var probe: Array[int] = [0, 0, 0]  # the probes' hulls hurt, us, of which the native batch's (none before M10-T76)
	var chain: Array[int] = [0, 0, 0]  # blasts before it, us landing Omega B's death, us in its field's steps
	for t: int in TICKS:
		_tick = t
		await get_tree().physics_frame
		var spent: Array[int] = [BlastResolver.blasts, BlastResolver.total_us,
				int(BlastResolver.stats().get("native_mean_us", 0.0) * BlastResolver.blasts)]
		_script(t, a, b, cap_a, cap_b, side, up)
		if t >= 4 and t <= 7:
			probe[0] += BlastResolver.last_hurt
			probe[1] += BlastResolver.total_us - spent[1]
			probe[2] += int(BlastResolver.stats().get("native_mean_us", 0.0) * BlastResolver.blasts) - spent[2]
		if t == 14 or t == 70:
			costs.append("tick %d: %d blasts, %d us" % [t, BlastResolver.blasts - spent[0], BlastResolver.total_us - spent[1]])
		if t == CHAIN_FROM:
			chain = [spent[0], BlastResolver.total_us - spent[1], 0]
		await get_tree().process_frame
		if t >= CHAIN_FROM and t <= CHAIN_TO:
			chain[2] += int(_field.step_us)
		_take_pending()
		chunk_rows.append(_velocities())
		if (t + 1) % CHUNK_TICKS == 0:
			chunks.append(ParityFixture.digest([_hits.slice(hits_from), chunk_rows]))
			chunk_rows.clear()
			hits_from = _hits.size()
	var end: Array = []
	for c: Combatant in _ships:
		end.append([c.damageable.hull.hp, c.damageable.hull.destroyed])
	for cap: CapitalShip in _caps:
		var state: Array = [cap.damageable.hull.hp, cap.damage.hull_hp, cap.damage.is_disabled, cap.damage.is_destroyed,
				cap.damage.blown]
		for name: String in cap.damage.sections:
			state.append([cap.damage.sections[name].hp, cap.damage.sections[name].state])
		for name: String in cap.damage.mounts:
			state.append([cap.damage.mounts[name].hp, cap.damage.mounts[name].alive])
		end.append(state)
	if _station != null:
		end.append([Array(_station.sections.health), _station.hull.hp if _station.hull != null else -1.0,
				Array(_station.grid.health.health) if _station.grid != null and _station.grid.health != null else []])
	end.append([_field.alive_count(), _field.total_set_off()])
	var counts: Array = [BlastResolver.blasts, BlastResolver.hulls_hurt, BlastResolver.pushed]
	var out: Dictionary = {"hits": _hits.size(), "blasts": BlastResolver.blasts, "chunks": chunks, "events": _events.size(),
			"event_log": ParityFixture.digest(_events), "counts": counts, "end": ParityFixture.digest(end)}
	gut.p("cost: 4 probes, %d hulls hurt, %d us: %.1f us a hull (native %.1f)" % [probe[0], probe[1],
			float(probe[1]) / maxf(probe[0], 1.0), float(probe[2]) / maxf(probe[0], 1.0)])
	gut.p("cost: %d blasts, mean %.0f us, max %d us, the core's reach %.0f us; the chain (Omega B, its field's steps): %d blasts, %d us; %s" % [
			BlastResolver.blasts, float(BlastResolver.stats()["mean_us"]), BlastResolver.max_us,
			float(BlastResolver.stats()["reach_mean_us"]), BlastResolver.blasts - chain[0], chain[1] + chain[2], "; ".join(costs)])
	BlastResolver.set_hit_log(false)
	main.queue_free()
	await _ticks(2)
	return out


# The seeded blasts, tick by tick.
func _script(t: int, a: Array[Combatant], b: Array[Combatant], cap_a: CapitalShip, cap_b: CapitalShip, side: Vector3,
		up: Vector3) -> void:
	match t:
		4, 5, 6, 7:
			# A probe that hurts the whole group and kills none: the landing's own cost, a hull at a time.
			BlastResolver.set_off(BlastSpec.make(&"t76_probe", 0.5, 400.0, 200.0), _centre_of(a), Factions.NEUTRAL)
		10:
			a[1].damageable.kill()  # a raider's death in the group: its low neighbours blow in turn
		14:
			BlastResolver.set_off(BlastTable.spec(&"small_craft_death"), _centre_of(a), Factions.NEUTRAL)
		20:
			BlastResolver.set_off(BlastTable.spec(&"missile"), _alive(a).ship.global_position + side * 6.0, Factions.RAIDERS,
					_alive(a).ship.get_instance_id())
		30, 36, 42, 48, 54:
			var names: Array = cap_a.damage.sections.keys()
			var section: CapitalSection = cap_a.damage.sections[names[(t - 30) / 6 % names.size()]]
			var at: Vector3 = cap_a.global_transform * (section.box.get_center() + Vector3(0.0, section.box.size.y * 0.5 + 25.0, 0.0))
			var source: StringName = &"torpedo" if t % 12 == 6 else &"mine_energy"
			BlastResolver.set_off(BlastTable.spec(source), at, Factions.RAIDERS, b[0].ship.get_instance_id())
		70:
			if not cap_a.damageable.hull.destroyed:
				cap_a.damageable.kill()  # its death blast takes its attackers
		90, 96, 102, 108, 114:
			if _station != null:
				var i: int = ((t - 90) / 6 * 3) % _station.sections.sections.size()
				var s: Dictionary = _station.sections.sections[i]
				var box: AABB = s["aabb"]
				var at: Vector3 = _station.to_world(box.get_center() + Vector3(0.0, box.size.y * 0.5 + 30.0, 0.0), String(s["body"]))
				var source: StringName = [&"torpedo", &"mine_energy", &"civilian_death"][(t / 6) % 3]
				BlastResolver.set_off(BlastTable.spec(source), at, Factions.RAIDERS)
		130:
			cap_b.damageable.kill()  # beside the minefield: the field goes off as a chain


func _alive(list: Array[Combatant]) -> Combatant:
	for c: Combatant in list:
		if not c.damageable.hull.destroyed:
			return c
	return list[0]


func _centre_of(list: Array[Combatant]) -> Vector3:
	var sum := Vector3.ZERO
	for c: Combatant in list:
		sum += c.ship.global_position
	return sum / float(list.size())


func _spawn(kind: String) -> Combatant:
	var type: StringName = ShipPool.DEFAULT_TYPE if kind == "raider" else ShipPool.ALLY_TYPE
	var before: Array[Combatant] = main.ships.alive(type).duplicate()
	assert_true(DebugConsole.registry.execute("spawn %s idle 900" % kind)[0].ok)
	for c: Combatant in main.ships.alive(type):
		if not before.has(c):
			return c
	return null


func _place(c: Combatant, at: Vector3) -> void:
	c.ship.global_transform = Transform3D(main.ship.global_basis, at)
	c.ship.linear_velocity = main.world.rest_velocity()
	c.ship.angular_velocity = Vector3.ZERO


func _omega(at: Vector3, label: String) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(OMEGA, Factions.EARTH_ALLIANCE, label, rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	main.world.spawn(cap, main.world.to_universe(at), main.ship.global_basis)
	cap.set_course(Vector3.ZERO, rest)
	return cap


# Every blast hit on the ship as it lands, and its death.
func _watch_ship(c: Combatant) -> void:
	var who: int = _ships.size()
	_ships.append(c)
	_who[c.ship.get_instance_id()] = who
	c.damageable.hit_taken.connect(func(info: HitInfo) -> void:
		if info.cause == HitInfo.CAUSE_BLAST:
			_pending.append([who, _tick, info]))
	c.damageable.destroyed.connect(func(_info: HitInfo) -> void: _events.append([_tick, who, "destroyed"]))


func _watch_capital(cap: CapitalShip) -> void:
	_caps.append(cap)
	var who: int = -_caps.size()
	_who[cap.get_instance_id()] = who
	for rotor: CapitalRotor in cap.rotors:
		_who[rotor.get_instance_id()] = who
	for name: String in cap.damage.sections:
		if cap.damage.sections[name].kind != CapitalSection.BRIDGE:
			cap.damage.sections[name].hp = cap.damage.sections[name].max_hp * SECTION_LEFT
	cap.damageable.hit_taken.connect(func(info: HitInfo) -> void:
		if info.cause == HitInfo.CAUSE_BLAST:
			_pending.append([who, _tick, info]))
	cap.damage.section_changed.connect(func(s: String, state: int) -> void: _events.append([_tick, who, "section", s, state]))
	cap.damage.mount_lost.connect(func(n: String) -> void: _events.append([_tick, who, "mount", n]))
	cap.damage.part_lost.connect(func(k: String) -> void: _events.append([_tick, who, "part", k]))
	cap.damage.disabled.connect(func() -> void: _events.append([_tick, who, "disabled"]))
	cap.damage.blew.connect(func(s: String) -> void: _events.append([_tick, who, "blew", s]))
	cap.damageable.destroyed.connect(func(_info: HitInfo) -> void: _events.append([_tick, who, "destroyed"]))


func _watch_station() -> void:
	if _station == null:
		return
	var who: int = -100
	for hull: Damageable in [_station.frame_hull, _station.drum_hull]:
		if hull == null:
			continue
		_who[hull.body().get_instance_id()] = who
		hull.hit_taken.connect(func(info: HitInfo) -> void:
			if info.cause == HitInfo.CAUSE_BLAST:
				_pending.append([who, _tick, info]))
	_station.section_lost.connect(func(i: int, _n: String) -> void: _events.append([_tick, who, "section_lost", i]))
	_station.disabled.connect(func() -> void: _events.append([_tick, who, "disabled"]))
	_station.station_destroyed.connect(func(s: String) -> void: _events.append([_tick, who, "destroyed", s]))


# The tick's hits with the points each removed: the batch's, then any landed in GDScript.
func _take_pending() -> void:
	for info: HitInfo in BlastResolver.hit_log():
		if _who.has(info.target_id):
			_hits.append([_who[info.target_id], _tick, info.damage, info.applied, info.point])
	BlastResolver.set_hit_log(true)  # forgets what it read
	for e: Array in _pending:
		var info: HitInfo = e[2]
		_hits.append([e[0], e[1], info.damage, info.applied, info.point])
	_pending.clear()


# Every watched hull's velocity now (a tier row's from the core).
func _velocities() -> Array:
	var out: Array = []
	for c: Combatant in _ships:
		var pose: Array = TierDirector.row_pose(c.ship) if c.ship.has_meta(TierDirector.TIER_META) else []
		out.append(pose[1] if not pose.is_empty() else c.ship.linear_velocity)
	for cap: CapitalShip in _caps:
		var pose: Array = TierDirector.row_pose(cap) if cap.has_meta(TierDirector.TIER_META) else []
		out.append(pose[1] if not pose.is_empty() else cap.linear_velocity)
	return out


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
