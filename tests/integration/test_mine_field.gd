extends TestSteps
## Mines and minefields in the real main scene (M10-T15, Q20, D12.9, AC9's mine clause): a hostile inside a mine's trigger sets
## it off and a friend does not; its blast falls off with the gap to each hull's nearest hit volume (T09's curve); a chain goes
## off through the blasts, a ship's death blast sets off the mines it reaches; a capital touches a mine with its hull and not its
## sphere; the battle's layers send energy mines at a hostile capital (interceptors shoot them down, one that arrives goes off
## on it) and drop guided mines astern; the radar shows an enemy's mine only inside 1 km; scenario and mission data lay fields;
## the console lists, lays and clears them. The 1-vs-6-thread identity is `test_mine_field_threads`.

const CRUISER: StringName = &"capital_test_cruiser"
const OMEGA: StringName = &"ea_omega"
const EA: StringName = Factions.EARTH_ALLIANCE
## The layers' side in the capital tests: the G'Quan's, at war with the Earth Alliance.
const LAYER_SIDE: StringName = &"drakh"

var main: Main


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true  # the player sits near the test mines
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.ally_pool_size = 8
	add_child_autofree(main)
	await _ticks(2)
	BlastResolver.reset_stats()


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	Factions.reset()


func _spawn(kind: String, distance_m: float) -> Combatant:
	var type: StringName = ShipPool.DEFAULT_TYPE if kind == "raider" else ShipPool.ALLY_TYPE
	var before: Array[Combatant] = main.ships.alive(type).duplicate()
	assert_true(DebugConsole.registry.execute("spawn %s idle %s" % [kind, distance_m])[0].ok)
	for c: Combatant in main.ships.alive(type):
		if not before.has(c):
			return c
	return null


func _place(c: Combatant, at: Vector3) -> void:
	c.ship.global_transform = Transform3D(main.ship.global_basis, at)
	c.ship.linear_velocity = main.world.rest_velocity()
	c.ship.angular_velocity = Vector3.ZERO


# A point `ahead_m` along the player's nose.
func _ahead(ahead_m: float) -> Vector3:
	return main.ship.global_position - main.ship.global_basis.z * ahead_m


func _field(rows: Array[Dictionary], at: Vector3 = Vector3.ZERO) -> MineField:
	var field: MineField = MineField.spawn_in(main.world, main.world.to_universe(at), true)
	assert_gt(field.build(rows), 0, "the mines are laid")
	return field


static func _row(at: Vector3, faction: StringName = EA, kind: StringName = &"mine_prox") -> Dictionary:
	return {"offset": at, "faction": faction, "kind": kind}


static func _gap(c: Combatant, at: Vector3) -> float:
	var local: Vector3 = c.ship.global_transform.affine_inverse() * at
	var best: float = INF
	for shape: HitShape in c.damageable.shapes:
		best = minf(best, shape.nearest_point(local).distance_to(local))
	return best


static func _blast_hits(damageable: Damageable) -> Array[HitInfo]:
	return BlastHits.of(damageable)  # the native batch's summaries (M10-T76)


func _sync() -> void:
	SimCore.for_tree(get_tree()).sync_now()


func test_a_hostile_inside_the_trigger_sets_a_mine_off_a_friend_does_not_and_the_blast_falls_off() -> void:
	var raider: Combatant = _spawn("raider", 900.0)
	var friend: Combatant = _spawn("ally", 950.0)
	var centre: Vector3 = _ahead(600.0)
	var side: Vector3 = main.ship.global_basis.x
	var field: MineField = _field([_row(centre)])
	raider.damageable.hull.max_hp = 1.0e6  # tough enough to live through the blast, so its death blast is not in the count
	raider.damageable.hull.hp = 1.0e6
	friend.damageable.hull.max_hp = 1.0e6
	friend.damageable.hull.hp = 1.0e6
	_place(friend, centre + side * 35.0)
	_place(raider, centre + side * 400.0)
	await _ticks(2 * MineKinds.CHECK_TICKS)
	assert_eq(field.alive_count(), 1, "a friend inside the trigger sets nothing off")
	_place(friend, centre + side * 35.0)
	_place(raider, centre - side * 45.0)
	_sync()
	var raider_hits: Array[HitInfo] = _blast_hits(raider.damageable)
	var friend_hits: Array[HitInfo] = _blast_hits(friend.damageable)
	var raider_gap: float = _gap(raider, centre)
	var friend_gap: float = _gap(friend, centre)
	await _ticks(MineKinds.CHECK_TICKS + 1)
	assert_eq(field.alive_count(), 0, "a hostile within 60 m of its surface set it off")
	assert_eq(field.by_trigger, 1, "by its trigger")
	var spec: BlastSpec = MineKinds.blast(MineKinds.PROX)
	assert_eq(raider_hits.size(), 1)
	assert_eq(friend_hits.size(), 1, "the blast hurts friend and foe alike")
	assert_almost_eq(raider_hits[0].damage, spec.damage_at(raider_gap), 0.5, "by the falloff to its nearest hit volume")
	assert_almost_eq(friend_hits[0].damage, spec.damage_at(friend_gap), 0.5)
	assert_gt(friend_hits[0].damage, raider_hits[0].damage, "the nearer takes more")
	assert_eq(BlastResolver.last_source, &"mine_prox", "the table's row")


func test_a_chain_goes_off_through_the_blasts_and_a_ships_death_sets_off_the_mine_it_reaches() -> void:
	var centre: Vector3 = _ahead(600.0)
	var x := Vector3.RIGHT
	var field: MineField = _field([_row(centre), _row(centre + x * 100.0), _row(centre + x * 200.0), _row(centre + x * 450.0)])
	assert_true(field.strike(0), "a shot hits the first")
	await _ticks(2)
	assert_eq([field.is_alive(0), field.is_alive(1), field.is_alive(2), field.is_alive(3)], [false, false, false, true],
			"100 m apart is inside the 120 m blast: the first three, not the one 250 m on")
	assert_eq([field.by_shot, field.by_blast], [1, 2])
	var raider: Combatant = _spawn("raider", 900.0)
	var lone: Vector3 = _ahead(1500.0)
	var second: MineField = _field([_row(lone, Factions.RAIDERS)])  # its own side's: only the blast sets it off
	_place(raider, lone + Vector3.UP * 50.0)
	await _ticks(1)
	_place(raider, lone + Vector3.UP * 50.0)
	_sync()
	assert_true(raider.damageable.kill())
	await _ticks(2)
	assert_eq(second.alive_count(), 0, "the raider's death blast (80 m) reached the mine's body")
	assert_eq(second.by_blast, 1)


func test_a_capital_touches_a_mine_with_its_hull_not_its_sphere() -> void:
	var cap: CapitalShip = CapitalShip.create(CRUISER, EA, "TEST CRUISER", main.world.rest_velocity())
	assert_not_null(cap, "the test cruiser is generated (scripts/gen_assets.sh)")
	if cap == null:
		return
	var at: Vector3 = _ahead(3000.0)
	main.world.spawn(cap, main.world.to_universe(at), main.ship.global_basis)
	cap.set_course(-main.ship.global_basis.z, main.world.rest_velocity())
	await _ticks(2)
	_sync()
	var core: ScsSimCore = SimCore.for_tree(get_tree()).core
	# The hull's nearest point to a spot far off its flank, and mines 2 m and 100 m out from it along the same line.
	var probe: Vector3 = at + main.ship.global_basis.x * 90.0
	var found: Array = core.blast_reach(probe, 400.0)
	var ids: PackedInt64Array = found[0]
	assert_gt(ids.size(), 0, "the cruiser is in the core's rows")
	var nearest: Vector3 = (found[3] as PackedVector3Array)[0]
	var out: Vector3 = (probe - nearest).normalized()
	var field: MineField = _field([_row(nearest + out * 2.0), _row(nearest + out * 150.0)])
	await _ticks(MineKinds.CHECK_TICKS + 1)
	assert_false(field.is_alive(0), "2 m off its flank: the hull touches the body")
	assert_eq(field.by_touch, 1)
	assert_true(field.is_alive(1), "150 m off: inside its sphere, clear of its hull and of the first blast")


func _cruiser_and_omega(apart_m: float, interceptors_held: bool) -> Array[CapitalShip]:
	var rest: Vector3 = main.world.rest_velocity()
	Factions.table().set_relation(LAYER_SIDE, EA, Factions.Relation.HOSTILE)  # a side at war with the Omega's, not a renegade (Q55)
	var cruiser: CapitalShip = CapitalShip.create(CRUISER, LAYER_SIDE, "LAYER", rest)
	var omega: CapitalShip = CapitalShip.create(OMEGA, EA, "TARGET", rest)
	assert_not_null(cruiser, "the test cruiser is generated")
	assert_not_null(omega, "the Omega is generated")
	# The Omega near the player, the cruiser `apart_m` off its right flank (its batteries cover the hemispheres to its sides), its
	# bow, where the launcher is, turned toward the Omega.
	var basis: Basis = main.ship.global_basis
	var turned: Basis = basis.rotated(basis.y, 0.5 * PI)
	var at: Vector3 = _ahead(300.0) + basis.x * 600.0
	main.world.spawn(omega, main.world.to_universe(at), basis)
	main.world.spawn(cruiser, main.world.to_universe(at + basis.x * apart_m), turned)
	omega.set_course(-basis.z, rest)
	cruiser.set_course(-turned.z, rest)
	for cap: CapitalShip in [cruiser, omega]:
		CapitalBeams.of(main.world).hold(cap, true)
		CapitalGuns.of(main.world).hold(cap, true)
		cap.damageable.invulnerable = true
	CapitalGuns.of(main.world).hold_interceptors(cruiser, true)
	CapitalGuns.of(main.world).hold_interceptors(omega, interceptors_held)
	var out: Array[CapitalShip] = [cruiser, omega]
	return out


# One energy-mine launcher on the cruiser's bow, as the G'Quan's (the layers' own numbers).
func _launcher(cruiser: CapitalShip) -> MineField:
	var field: MineField = MineField.battle(main.world)
	assert_gte(field.add_layer(cruiser.get_instance_id(), Vector3(0.0, 0.0, -100.0), Vector3(0.0, 0.0, -1.0), MineKinds.ENERGY,
			MineKinds.laying(MineKinds.ENERGY)), 0, "the layer is taken")
	return field


func test_an_energy_mine_sent_at_a_capital_arrives_and_goes_off_on_it() -> void:
	var ships: Array[CapitalShip] = _cruiser_and_omega(6300.0, true)
	var omega_hits: Array[HitInfo] = _blast_hits(ships[1].damageable)
	var field: MineField = _launcher(ships[0])
	var laid_at: Array[float] = []
	field.laid.connect(func(_slot: int) -> void: laid_at.append(SimClock.now()))
	await _fly(14.0, func() -> bool: return field.total_set_off() > 0)
	assert_gt(field.mines_laid, 0, "a mine was laid at the hostile capital 6.4 km on")
	assert_gt(field.total_set_off(), 0, "it arrived, armed and went off")
	assert_gt(field.by_trigger + field.by_fuse + field.by_flight, 0)
	assert_gt(omega_hits.size(), 0, "its 300 m blast reached the Omega")
	assert_eq(field.shot_down_count, 0, "(its interceptors were held)")


func test_the_interceptors_of_a_capital_shoot_an_energy_mine_down_in_flight() -> void:
	var ships: Array[CapitalShip] = _cruiser_and_omega(6300.0, false)
	var field: MineField = _launcher(ships[0])
	await _fly(14.0, func() -> bool: return field.shot_down_count > 0)
	assert_gt(field.mines_laid, 0, "a mine was laid")
	assert_gt(field.shot_down_count, 0, "an interceptor shot one down (three pulses: its toughness, Q81)")


func test_hostile_shots_from_guns_stop_a_mine_in_flight_three_for_an_energy_mine() -> void:
	var ships: Array[CapitalShip] = _cruiser_and_omega(6300.0, true)
	var field: MineField = _launcher(ships[0])
	await _ticks(40)
	assert_eq(field.alive_count(), 1, "a mine is flying")
	var sim: SimCore = SimCore.for_tree(get_tree())
	var weapon := WeaponSpec.new()
	weapon.lifetime_s = 10.0
	for k: int in 3:
		var at: Vector3 = field.global_position + (field.rows.info(0)[4] as Vector3)
		assert_eq(field.shot_down_count, 0, "still flying before shot %d" % k)
		sim.add_bolt(at + Vector3.UP * 0.5, Vector3.ZERO, EA, main.combatant.ship.get_instance_id(), weapon, SimClock.now())
		await _ticks(2)
		assert_eq(field.shots_on_flight(), k + 1, "shot %d met the mine" % k)
	assert_eq(field.shot_down_count, 1, "three hostile shots shot it down")
	assert_eq(field.alive_count(), 0)
	assert_eq(field.total_set_off(), 0, "with no blast")


func test_a_guided_layer_drops_mines_astern_while_a_hostile_is_on_its_tail_and_stops_at_its_cap() -> void:
	var rest: Vector3 = main.world.rest_velocity()
	Factions.table().set_relation(LAYER_SIDE, Factions.RAIDERS, Factions.Relation.HOSTILE)
	var cruiser: CapitalShip = CapitalShip.create(CRUISER, LAYER_SIDE, "DROPPER", rest)
	var basis: Basis = main.ship.global_basis
	main.world.spawn(cruiser, main.world.to_universe(_ahead(300.0)), basis)
	cruiser.set_course(-basis.z, rest)
	CapitalBeams.of(main.world).hold(cruiser, true)
	CapitalGuns.of(main.world).hold(cruiser, true)
	cruiser.damageable.invulnerable = true
	var raider: Combatant = _spawn("raider", 900.0)
	await _ticks(1)
	var field: MineField = MineField.battle(main.world)
	var numbers: PackedFloat64Array = MineKinds.laying(MineKinds.GUIDED)
	assert_gte(field.add_layer(cruiser.get_instance_id(), Vector3(0.0, 0.0, 120.0), Vector3(0.0, 0.0, 1.0), MineKinds.GUIDED, numbers), 0)
	_place(raider, cruiser.global_position + basis.z * 1500.0)  # on its tail
	_sync()
	await _ticks(60)
	assert_eq(field.mines_laid, 4, "four in the first drop")
	for slot: int in field.capacity:
		if field.is_alive(slot):
			var info: Array = field.rows.info(slot)
			assert_eq(info[3], cruiser.get_instance_id(), "each is the cruiser's")
			assert_eq(info[2], 0, "dormant")
	var before: int = field.mines_laid
	await _ticks(60)
	assert_eq(field.mines_laid, before, "no second drop inside its 30 s cycle")


func test_the_radar_shows_an_enemys_mine_only_inside_a_kilometre_and_its_own_always() -> void:
	var raiders: StringName = Factions.RAIDERS
	var near: Vector3 = _ahead(800.0)
	var far: Vector3 = _ahead(1500.0)
	var own: Vector3 = _ahead(3500.0)
	var field: MineField = _field([_row(near, raiders), _row(far, raiders), _row(own, EA)])
	var contacts: RadarContacts = RadarContacts.gather(get_tree(), main.ship, 5000.0)
	var mine_dots: Array[int] = []
	for k: int in contacts.size():
		if contacts.ids[k] < MineField.RADAR_ID_BASE + MineField.ID_STRIDE:
			mine_dots.append(k)
	assert_eq(mine_dots.size(), 2, "the enemy's near mine and our own far one; not the enemy's at 1.5 km")
	var places: Array[Vector3] = []
	for k: int in mine_dots:
		places.append(contacts.positions[k])
	assert_true(places.any(func(p: Vector3) -> bool: return p.distance_to(near) < 0.5), "the near enemy mine")
	assert_true(places.any(func(p: Vector3) -> bool: return p.distance_to(own) < 0.5), "our own, far")
	assert_eq(field.alive_count(), 3)


func test_scenario_data_and_a_mission_lay_minefields() -> void:
	var data: Dictionary = {"scenario_id": "t", "system_id": "local", "player": {"position": [0, 0, 0], "forward": [0, 0, -1]},
			"props": [], "minefields": [{"id": "gate", "faction": "raiders", "pattern": "sphere", "radius_m": 300, "count": 25,
			"seed": 3, "centre": [0, 0, -5000]}]}
	var parsed: Dictionary = ScenarioLoader.from_data(data, "case")
	assert_true(parsed["ok"], parsed["error"])
	var list: Array = parsed["minefields"]
	assert_eq(list.size(), 1)
	assert_eq(MineFieldPlan.place(list[0]["entry"]).rows.size(), 25)
	data["minefields"][0]["pattern"] = "cone"
	assert_string_contains(ScenarioLoader.from_data(data, "case")["error"], "minefields[0]")
	data["minefields"][0] = {"id": "x", "faction": "no_such_side", "pattern": "sphere", "radius_m": 3, "count": 1, "centre": [0, 0, 0]}
	assert_string_contains(ScenarioLoader.from_data(data, "case")["error"], "faction")
	var before: int = MineField.fields.size()
	var stage := MissionStage.new()
	stage.setup(main, null)
	assert_eq(stage.lay_minefield({"faction": "raiders", "pattern": "box", "size": [200, 200, 200], "count": 10, "seed": 1,
			"anchor": "player", "at": [0, 0, -2000]}), "")
	assert_eq(MineField.fields.size(), before + 1, "a mission's field is in play")
	assert_ne(stage.lay_minefield({"faction": "raiders", "pattern": "cone"}), "", "a field with a problem is refused")
	stage.teardown()


func test_the_console_lists_lays_and_clears_the_fields() -> void:
	assert_true(_exec("mines list").ok)
	var result: ConsoleResult = _exec("mines spawn 1200 mine_prox 30")
	assert_true(result.ok, result.text())
	assert_eq(MineField.total_in_play(), 30)
	assert_string_contains(_exec("mines list").text(), "placed")
	assert_eq(int(DebugConsole.registry.read("mines.in_play").get("value")), 30)
	assert_true(_exec("mines clear").ok)
	assert_eq(MineField.total_in_play(), 0)
	assert_false(_exec("mines spawn 100 mine_spiky 3").ok, "an unknown kind")


# Flies `seconds` of sim time sped up (`done` ends it early).
func _fly(seconds: float, done: Callable = Callable()) -> void:
	var rate: int = Engine.physics_ticks_per_second
	var scale: float = Engine.time_scale
	var steps: int = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	Engine.max_physics_steps_per_frame = maxi(steps, 4)
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = rate
	Engine.time_scale = scale
	Engine.max_physics_steps_per_frame = steps

