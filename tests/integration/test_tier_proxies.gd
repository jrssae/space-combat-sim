extends TestSteps
## Far proxies for the low-attention tier (M4-T23, architecture §17.14): every tier row is drawn (a fighter as a far dot, a
## capital as an instance of its class's mesh, one multimesh per mesh) and shows on the radar; a promoted ship's proxy goes in
## the tick its body shows (no double, no gap); the player can select a tier ship, read it from its row, and keep the
## selection through promotion and demotion; candidates and broadcasts include tier ships; a row promoted inside a rock comes
## back clear of it. Real pooled ships and capitals, the threaded step, real physics frames.

const POOL: int = 8
const RADIUS_M: float = 10000.0
const SETTINGS: Array[StringName] = [&"tier_radius_m", &"tier_hz", &"ai_think_rate"]

var world: WorldFrame
var projectiles: Node3D
var pool: ShipPool
var player: Combatant
var standins: StandinDirector
var sim: SimCore
var tier: TierDirector
var _saved: Dictionary = {}


func before_each() -> void:
	for key: StringName in SETTINGS:
		_saved[key] = Settings.get_value(key)
	Settings.set_value(&"tier_radius_m", RADIUS_M)
	Factions.reset()
	ContactScan.invalidate()
	ContactScan.clear_statics()
	_build()


func after_each() -> void:
	for key: StringName in SETTINGS:
		Settings.set_value(key, _saved[key])
	ContactScan.clear_statics()
	Factions.reset()
	ContactScan.invalidate()


func _build() -> void:
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	pool = ShipPool.new()
	pool.name = "Ships"
	world.add_child(pool)
	pool.world = world
	pool.projectiles = projectiles
	player = ShipAssembly.build(load("res://assets/ships/starfury_aurora.tres") as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
		ShipAssembly.OPT_DISPLAY_NAME: "PLAYER",
		ShipAssembly.OPT_CONSOLE_OWNER: true,
	})
	world.spawn(player.ship, world.to_universe(Vector3.ZERO))
	player.damageable.invulnerable = true
	pool.player = player.ship
	pool.prepare(ShipPool.DEFAULT_TYPE, POOL)
	pool.prepare(ShipPool.ALLY_TYPE, 2)
	standins = StandinDirector.new()
	standins.name = "Standins"
	standins.world = world
	standins.projectiles = projectiles
	standins.ships = pool
	standins.player = player.ship
	world.add_child(standins)
	FlightBatch.attach(world)
	sim = SimCore.attach(world)
	tier = TierDirector.attach(world, pool, standins)


func _raider(display_name: String, at: Vector3, velocity: Vector3 = Vector3.ZERO) -> Combatant:
	var c: Combatant = pool.acquire(display_name, world.to_universe(at), Basis.IDENTITY, velocity, IdleBrain.new())
	c.damageable.invulnerable = true
	return c


func _row_at(body: Node3D) -> Vector3:
	var p: Vector4 = sim.core.tier_position(body.get_instance_id())
	assert_eq(p.w, 1.0, "%s has a tier row" % body.name)
	return Vector3(p.x, p.y, p.z)


# Whether far dot `k`'s position is `at` (World-local), within a metre.
func _dot_near(dots: FarDots, at: Vector3) -> bool:
	for k: int in dots.dot_count():
		if dots.dot_position(k).distance_to(world.to_global(at)) < 1.0:
			return true
	return false


func test_every_tier_row_has_a_dot_or_a_hull_instance_and_a_radar_blip() -> void:
	var raiders: Array[Combatant] = []
	for i: int in 5:
		raiders.append(_raider("RAIDER %d" % i, Vector3(float(i) * 300.0, 0.0, -15000.0 - float(i) * 1000.0)))
	var cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER", world.to_universe(Vector3(2000.0, 0.0, -16000.0)),
			Basis.IDENTITY, Vector3(0.0, 0.0, -30.0))
	cap.damageable.invulnerable = true
	standins.active = true
	await _ticks(4)
	for c: Combatant in raiders:
		assert_true(c.ship.is_tier_parked(), "%s is a tier row" % c.display_name)
	assert_true(cap.is_tier_parked(), "the cruiser is a tier row")
	var dots: FarDots = FarDots.of(world)
	assert_not_null(dots, "the far dots were made when the first fighter went into the tier")
	dots.refresh()
	assert_eq(dots.tier_shown, raiders.size(), "one dot a tier fighter, none for the capital")
	for c: Combatant in raiders:
		assert_true(_dot_near(dots, _row_at(c.ship)), "%s is drawn where its row flies" % c.display_name)
	var hulls: FarHulls = FarHulls.of(world)
	assert_not_null(hulls, "the far hulls were made when the capital went into the tier")
	hulls.refresh()
	assert_eq(hulls.class_count(), 1)
	assert_eq(hulls.class_mesh(0), cap.drawn_mesh(), "the cruiser's proxy is the mesh its body draws")
	assert_eq(hulls.instance_count(0), 1)
	var drawn: Transform3D = hulls.instance_transform(0, 0)
	assert_lt(drawn.origin.distance_to(_row_at(cap)), 0.01, "at its row's pose")
	var contacts: RadarContacts = RadarContacts.gather(get_tree(), player.ship, RadarModel.MAX_RANGE_M)
	for c: Combatant in raiders:
		var k: int = contacts.ids.find(c.targetable.get_instance_id())
		assert_gt(k, -1, "%s is on the radar, by its marker" % c.display_name)
		if k >= 0:
			assert_lt(contacts.positions[k].distance_to(_row_at(c.ship)), 0.01, "where its row is")
	assert_gt(contacts.ids.find(cap.targetable.get_instance_id()), -1, "the cruiser is on the radar")


func test_capitals_of_a_class_share_one_multimesh_and_another_class_has_its_own() -> void:
	for i: int in 2:
		standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER %d" % i, world.to_universe(Vector3(float(i) * 2000.0, 0.0, -18000.0)),
				Basis.IDENTITY, Vector3.ZERO)
	standins.add_capital(&"destroyer", Factions.RAIDERS, "DESTROYER", world.to_universe(Vector3(-3000.0, 0.0, -19000.0)),
			Basis.IDENTITY, Vector3.ZERO)
	standins.active = true
	await _ticks(4)
	var hulls: FarHulls = FarHulls.of(world)
	hulls.refresh()
	assert_eq(hulls.class_count(), 2, "one class per mesh")
	var counts: Array[int] = [hulls.instance_count(0), hulls.instance_count(1)]
	counts.sort()
	assert_eq(counts, [1, 2] as Array[int], "two cruisers in one multimesh, the destroyer in the other")
	assert_eq(hulls.shown, 3)


func test_a_promoted_ships_proxy_goes_the_tick_its_body_shows_and_comes_back_when_it_is_demoted() -> void:
	var c: Combatant = _raider("RAIDER 1", Vector3(0.0, 0.0, -15000.0), Vector3(0.0, 0.0, -40.0))
	await _ticks(4)
	assert_true(c.ship.is_tier_parked())
	var dots: FarDots = FarDots.of(world)
	dots.refresh()
	assert_eq(dots.tier_shown, 1, "in the tier: drawn from its row")
	Settings.set_value(&"tier_radius_m", 30000.0)
	await _ticks(1)
	assert_false(c.ship.is_tier_parked(), "promoted this tick")
	assert_true(c.ship.visible, "its body shows")
	dots.refresh()
	assert_eq(dots.tier_shown, 0, "and its row's dot went in the same tick: no double")
	assert_eq(dots.dot_count(), 1 if c.ship.is_far_dot() else 0, "drawn by its body alone (its far dot or its hull): no gap")
	Settings.set_value(&"tier_radius_m", RADIUS_M)
	await _ticks(1)
	assert_true(c.ship.is_tier_parked(), "demoted this tick")
	dots.refresh()
	assert_eq(dots.tier_shown, 1, "its row draws it from the same tick")
	assert_eq(dots.dot_count(), 1, "and its parked body draws nothing")


func test_the_player_selects_a_tier_ship_reads_it_from_its_row_and_keeps_it_through_the_handovers() -> void:
	var c: Combatant = _raider("RAIDER 1", Vector3(0.0, 0.0, -15000.0), Vector3(0.0, 0.0, -100.0))
	await _ticks(4)
	assert_true(c.ship.is_tier_parked())
	await _ticks(60)  # the row flies on from where the node was parked
	var targeting: TargetingController = player.ship.targeting
	assert_true(targeting.select_by_name("RAIDER 1"), "a tier ship can be selected by name")
	var id: int = c.targetable.get_instance_id()
	assert_eq(targeting.selected_id(), id, "by its marker's id")
	var names := PackedStringArray()
	for info: TargetInfo in targeting.candidates():
		names.append(info.display_name)
	assert_has(names, "RAIDER 1", "it is a candidate")
	var readout: TargetReadout = targeting.selected_readout()
	assert_not_null(readout)
	assert_almost_eq(readout.range_m, _row_at(c.ship).length(), 1.0, "its range is its row's, not where it was parked")
	assert_gt(_row_at(c.ship).distance_to(c.ship.global_position), 50.0, "(the row did move away from the parked node)")
	Settings.set_value(&"tier_radius_m", 30000.0)
	await _ticks(3)
	assert_false(c.ship.is_tier_parked(), "promoted")
	assert_eq(targeting.selected_id(), id, "the selection survives the promotion")
	Settings.set_value(&"tier_radius_m", RADIUS_M)
	await _ticks(3)
	assert_true(c.ship.is_tier_parked(), "demoted again")
	assert_eq(targeting.selected_id(), id, "and the demotion")
	assert_eq(targeting.selected_name(), "RAIDER 1")


func test_candidates_and_broadcasts_include_tier_allies_and_enemies_in_range() -> void:
	var ally: Combatant = pool.acquire("ALPHA 7", world.to_universe(Vector3(40000.0, 0.0, 0.0)), Basis.IDENTITY, Vector3.ZERO, null,
			ShipPool.ALLY_TYPE)
	var raider: Combatant = _raider("RAIDER 1", Vector3(0.0, 20000.0, 0.0))
	var far_raider: Combatant = _raider("RAIDER 2", Vector3(0.0, 40000.0, 0.0))
	await _ticks(4)
	assert_true(ally.ship.is_tier_parked() and raider.ship.is_tier_parked() and far_raider.ship.is_tier_parked())
	var names := PackedStringArray()
	for info: TargetInfo in player.ship.targeting.candidates():
		names.append(info.display_name)
	assert_has(names, "ALPHA 7", "the 40 km ally broadcasts")
	assert_has(names, "RAIDER 1", "the 20 km raider is in sensor range")
	assert_does_not_have(names, "RAIDER 2", "the 40 km raider is not")
	ContactScan.invalidate()
	var heard: ContactScan = ContactScan.shared_broadcasts()
	var contacts: Array[Contact] = heard.broadcasts_for(player.ship.get_instance_id(), player.ship.global_position, Factions.EARTH_ALLIANCE)
	var heard_names := PackedStringArray()
	for contact: Contact in contacts:
		heard_names.append(contact.name)
	assert_has(heard_names, "ALPHA 7", "the AI hears a tier ally's broadcast from its row")


func test_a_row_promoted_inside_a_rock_comes_back_clear_of_it() -> void:
	var moving: Combatant = _raider("RAIDER 1", Vector3(0.0, 0.0, -15000.0), Vector3(0.0, 0.0, 50.0))
	var still: Combatant = _raider("RAIDER 2", Vector3(5000.0, 0.0, -15000.0))
	await _ticks(4)
	assert_true(moving.ship.is_tier_parked() and still.ship.is_tier_parked())
	var rock_r: float = 300.0
	var rocks: Array[Vector3] = [_row_at(moving.ship) + Vector3(0.0, 40.0, 0.0), _row_at(still.ship) + Vector3(0.0, 30.0, 0.0)]
	for k: int in rocks.size():
		ContactScan.register_static(9000001 + k, rocks[k], rock_r, BodyKind.STATIC, Factions.NEUTRAL, world)
	await _ticks(2)  # the core takes the rocks at its next sync
	var before_moving: Vector3 = _row_at(moving.ship)
	var cleared: int = int(sim.core.tier_cleared())
	Settings.set_value(&"tier_radius_m", 30000.0)
	await _ticks(1)
	assert_false(moving.ship.is_tier_parked() or still.ship.is_tier_parked(), "both promoted")
	assert_eq(int(sim.core.tier_cleared()) - cleared, 2, "both were moved clear first")
	var need: float = rock_r + moving.damageable.bounding_radius
	assert_gt(moving.ship.global_position.distance_to(rocks[0]), need, "the moving ship comes back outside its rock")
	# The shortest way out (fix round 1): no more than the overlap and the clearance, about 300 m here, not across the rock.
	var overlap: float = need - before_moving.distance_to(rocks[0])
	assert_lt(moving.ship.global_position.distance_to(before_moving), overlap + 10.0, "moved by the overlap, no more")
	assert_almost_eq(moving.ship.linear_velocity, Vector3(0.0, 0.0, 50.0), Vector3.ONE * 0.5, "its velocity unchanged")
	assert_gt(still.ship.global_position.distance_to(rocks[1]), rock_r + still.damageable.bounding_radius,
			"the still one is pushed straight out")


func test_a_mine_blast_is_on_the_cores_rows_and_hurts_a_tier_row_and_a_near_hull_alike() -> void:
	var c: Combatant = _raider("RAIDER 1", Vector3(0.0, 0.0, -15000.0))
	await _ticks(4)
	assert_true(c.ship.is_tier_parked())
	var near: Combatant = _raider("RAIDER 2", Vector3(0.0, 0.0, -900.0))
	var row: Vector3 = _row_at(c.ship)
	var mines: MineStandin = standins.add_mines([
			{"offset": row + Vector3(0.0, 5.0, 0.0), "faction": Factions.EARTH_ALLIANCE},
			{"offset": near.ship.global_position + Vector3(0.0, 5.0, 0.0), "faction": Factions.EARTH_ALLIANCE}],
			world.to_universe(Vector3.ZERO))
	standins.active = true
	var hit_by_mine: Dictionary = {}
	for who: Combatant in [c, near]:
		who.damageable.hit_taken.connect(func(info: HitInfo) -> void:
			if info.cause == MineStandin.CAUSE:
				hit_by_mine[who.display_name] = true)
	await _ticks(MineStandin.TRIGGER_TICKS + 2)
	assert_false(mines.is_alive(0), "the tier row set its mine off")
	assert_true(hit_by_mine.get("RAIDER 1", false), "and the blast hurt it, from its row")
	assert_false(mines.is_alive(1), "the near hull set its own off")
	assert_true(hit_by_mine.get("RAIDER 2", false), "and was hurt the same way")
	var source: String = FileAccess.get_file_as_string("res://src/perf/standins/standin_director.gd")
	assert_false(source.contains("func _gather_hulls"), "no GDScript walk of the hulls orders a blast: one path, the core's rows")


func test_a_capital_is_cleared_of_a_rock_by_its_hull_with_no_big_jump() -> void:
	Settings.set_value(&"tier_radius_m", RADIUS_M)
	var cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER", world.to_universe(Vector3(0.0, 0.0, -16000.0)),
			Basis.IDENTITY, Vector3.ZERO)
	cap.damageable.invulnerable = true
	standins.active = true
	await _ticks(4)
	assert_true(cap.is_tier_parked())
	var half: Vector3 = cap.half_extents()
	var row: Vector3 = _row_at(cap)
	var rock_r: float = 100.0
	# One rock 20 m into the hull's side; one off a corner, clear of the hull but inside its bounding sphere.
	var side: Vector3 = row + Vector3(half.x + rock_r - 20.0, 0.0, 0.0)
	var corner: Vector3 = row + Vector3(half.x + 80.0, 0.0, half.z + 80.0)
	assert_lt(corner.distance_to(row), CapitalStandin.hull_radius(&"cruiser") + rock_r + 5.0, "(the corner rock is inside the bounding sphere's reach)")
	ContactScan.register_static(9100001, side, rock_r, BodyKind.STATIC, Factions.NEUTRAL, world)
	ContactScan.register_static(9100002, corner, rock_r, BodyKind.STATIC, Factions.NEUTRAL, world)
	await _ticks(2)
	var before: Vector3 = _row_at(cap)
	var cleared: int = int(sim.core.tier_cleared())
	var promotions: int = int(sim.core.tier_promotions())
	Settings.set_value(&"tier_radius_m", 30000.0)
	await _ticks(1)
	assert_false(cap.is_tier_parked(), "promoted")
	assert_eq(int(sim.core.tier_cleared()) - cleared, 1, "moved clear once")
	assert_eq(int(sim.core.tier_promotions()) - promotions, 1)
	var jump: float = cap.global_position.distance_to(before)
	assert_between(jump, 20.0, 40.0, "by the 20 m overlap and the clearance, not its 154 m bounding radius (%.1f m)" % jump)
	var local: Vector3 = cap.global_transform.affine_inverse() * side
	var nearest := Vector3(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y), clampf(local.z, -half.z, half.z))
	assert_gte(local.distance_to(nearest), rock_r, "the hull clear of the side rock")


func test_a_release_or_a_death_in_the_tier_is_not_a_promotion() -> void:
	var c: Combatant = _raider("RAIDER 1", Vector3(0.0, 0.0, -15000.0))
	var cap: CapitalStandin = standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER", world.to_universe(Vector3(3000.0, 0.0, -16000.0)),
			Basis.IDENTITY, Vector3.ZERO)
	standins.active = true
	await _ticks(4)
	assert_true(c.ship.is_tier_parked() and cap.is_tier_parked())
	var promotions: int = int(sim.core.tier_promotions())
	pool.release(c)
	tier.forget_capital(cap)
	assert_false(sim.core.tier_has(c.ship.get_instance_id()) or sim.core.tier_has(cap.get_instance_id()), "both rows gone")
	assert_eq(int(sim.core.tier_promotions()), promotions, "and neither counted as a promotion")


func test_the_bench_counts_leave_a_dead_capital_and_its_weapons_out() -> void:
	var a: CapitalStandin = standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER 1", world.to_universe(Vector3(0.0, 0.0, -3000.0)),
			Basis.IDENTITY, Vector3.ZERO)
	standins.add_capital(&"cruiser", Factions.RAIDERS, "CRUISER 2", world.to_universe(Vector3(2000.0, 0.0, -3000.0)), Basis.IDENTITY,
			Vector3.ZERO)
	standins.active = true
	await _ticks(2)
	var guns: int = standins.turret_count()
	assert_eq(standins.capitals_in_play(), 2)
	a.damageable.kill()
	assert_eq(standins.capitals_in_play(), 1, "the dead one is not counted")
	assert_eq(standins.turret_count(), guns - a.guns().size(), "nor its guns")
