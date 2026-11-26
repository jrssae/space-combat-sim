extends GutTest
## A capital's staged break-up in the real main scene (M10-T11, D12.8, AC8's break-up clause): an Omega whose magazine blows
## plays its plan, the magazine first, the other sections walking outward and the reactor last, each a blast through the native
## batch that hurts what is near; its sections come apart as chunks with collision on their own motion and stay as wreckage;
## a death in the low-attention tier plays its blasts with no bodies; a Vorlon ship explodes in one blast; a Hyperion breaks up
## too; the console lists and clears the wrecks.

const SPEED_UP: float = 4.0

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8
var _radius_backup: float = 10000.0


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # the capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	_radius_backup = float(Settings.get_value(&"tier_radius_m"))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	main.waves_auto_start = false
	main.raider_pool_size = 6
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	Settings.set_value(&"tier_radius_m", _radius_backup)
	DebugConsole.flags.invulnerable = false
	BlastResolver.set_hit_log(false)


# A capital of `type` for `faction` `ahead_m` along the player's nose, bow with the player's, at rest.
func _spawn(type: StringName, display_name: String, ahead_m: float, faction: StringName = Factions.EARTH_ALLIANCE) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(type, faction, display_name, rest)
	assert_not_null(cap, "%s is generated (scripts/gen_assets.sh)" % type)
	if cap == null:
		return null
	var basis: Basis = main.ship.global_basis
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - basis.z * ahead_m), basis)
	cap.set_course(-basis.z, rest)
	return cap


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func _blow(cap: CapitalShip, section: String) -> void:
	assert_true(_run("capital focus %s" % String(cap.name)).ok)
	assert_true(_run("capital damage %s %.0f" % [section, cap.damage.sections[section].max_hp * 2.0]).ok)


func _wrecks() -> CapitalWrecks:
	return CapitalWrecks.of(main.world)


func _playing_of(label: String) -> CapitalBreakup:
	for b: CapitalBreakup in _wrecks().playing():
		if b.label == label:
			return b
	return null


func _raider_at(at: Vector3) -> Combatant:
	var before: Array[Combatant] = main.ships.alive(ShipPool.DEFAULT_TYPE).duplicate()
	assert_true(DebugConsole.registry.execute("spawn raider idle 900")[0].ok)
	for c: Combatant in main.ships.alive(ShipPool.DEFAULT_TYPE):
		if not before.has(c):
			c.ship.global_transform = Transform3D(main.ship.global_basis, at)
			c.ship.linear_velocity = main.world.rest_velocity()
			c.ship.angular_velocity = Vector3.ZERO
			return c
	return null


func test_a_magazine_blowing_plays_the_plan_outward_with_the_reactor_last() -> void:
	var cap: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", 6000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	var deaths: Array[HitInfo] = []
	main.director.capital_destroyed.connect(func(_c: CapitalBody, info: HitInfo) -> void: deaths.append(info))
	var started: int = BlastResolver.blasts
	_blow(cap, "magazine")
	assert_eq(deaths.size(), 1, "destroyed")
	assert_not_null(_wrecks(), "the world's wrecks")
	var b: CapitalBreakup = _playing_of("EAS Agamemnon")
	assert_not_null(b, "its break-up plays")
	if b == null:
		return
	var sources: Array[String] = []
	_wrecks().blast_set_off.connect(func(_at: Vector3, spec: BlastSpec) -> void: sources.append(String(spec.source)))
	assert_eq(b.names[b.plan.order[0]], "magazine", "the magazine went first")
	assert_eq(b.blasts, 1, "its blast at once")
	assert_eq(BlastResolver.blasts - started, 1, "landed in the death's tick")
	assert_almost_eq(deaths[0].blast_energy_j, b.first_spec.energy_j(), 1.0, "the death carries the magazine's blast")
	assert_eq(b.names[b.plan.order[b.plan.order.size() - 1]], "reactor", "the reactor goes last")
	var bodies: Array = _wrecks().bodies_of(b)
	assert_eq(bodies.size(), b.names.size(), "a chunk a section")
	var held: int = 0
	for chunk: Variant in bodies:
		if chunk != null and (chunk as CapitalChunk).is_held():
			held += 1
	assert_eq(held, b.names.size() - 1, "the rest still held")
	var t0: float = SimClock.now()
	await _fly(b.plan.span_s() + 1.0, func() -> bool: return b.wreck.finished())
	assert_true(b.wreck.finished(), "every section let go")
	assert_almost_eq(SimClock.now() - t0, b.plan.span_s(), 0.1, "on the plan's time")
	var expected: int = 0
	for kind: String in b.plan.blast_kind:
		expected += 1 if kind != "" else 0
	assert_eq(b.blasts, expected, "a blast a section")
	assert_eq(sources.size(), expected - 1, "the secondary blasts, one by one")
	assert_true(sources[sources.size() - 1].contains("reactor"), "the reactor's blast last (%s)" % sources[sources.size() - 1])


func test_its_secondary_blasts_hurt_what_is_near_later() -> void:
	var cap: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", 6000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	# A raider 1.2 km off the stern: past the magazine's reach, inside the reactor's.
	var stern: Vector3 = cap.global_transform * Vector3(0.0, 0.0, cap.half_extents().z + 1200.0)
	var raider: Combatant = _raider_at(stern)
	await wait_physics_frames(2)
	_blow(cap, "magazine")
	await wait_physics_frames(2)
	assert_false(raider.damageable.hull.destroyed, "the magazine's blast does not reach it")
	var b: CapitalBreakup = _playing_of("EAS Agamemnon")
	await _fly(b.plan.span_s() + 1.0, func() -> bool: return b.wreck.finished())
	assert_true(raider.damageable.hull.destroyed or raider.damageable.hull.fraction() < 1.0, "a later blast reaches it")


func test_the_chunks_fly_apart_on_their_own_motion_with_collision_and_stay() -> void:
	var cap: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", 6000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	_blow(cap, "fuel")
	var b: CapitalBreakup = _playing_of("EAS Agamemnon")
	var bodies: Array = _wrecks().bodies_of(b)
	var chunks: Array[CapitalChunk] = []
	for chunk: Variant in bodies:
		if chunk != null:
			chunks.append(chunk as CapitalChunk)
	assert_gt(chunks.size(), 6)
	var start: Array[float] = []
	for chunk: CapitalChunk in chunks:
		assert_gt(chunk.get_child_count(), 1, "%s: its mesh and its section's collision" % chunk.section)
		assert_eq(chunk.collision_layer, CollisionLayers.layer_of(&"capital"))
		assert_eq(chunk.linear_damp, 0.0, "no damping")
		start.append(chunk.global_position.distance_to(chunks[0].global_position))
		for other: CapitalChunk in chunks:
			if other != chunk:
				assert_true(chunk.get_collision_exceptions().has(other), "sisters never collide")
	await _fly(b.plan.span_s() + 3.0)
	for i: int in chunks.size():
		assert_true(is_instance_valid(chunks[i]), "it stays as wreckage")
		assert_false(chunks[i].is_held(), "loose")
		assert_false(chunks[i].freeze, "on its own motion")
	var apart: int = 0
	for i: int in range(1, chunks.size()):
		apart += 1 if chunks[i].global_position.distance_to(chunks[0].global_position) > start[i] + 1.0 else 0
	assert_gt(apart, chunks.size() / 2, "they drift apart")


func test_a_death_in_the_tier_plays_its_blasts_with_no_bodies() -> void:
	Settings.set_value(&"tier_radius_m", 10000.0)
	var cap: CapitalShip = _spawn(&"ea_omega", "EAS Achilles", 15000.0)
	if cap == null:
		return
	await _fly(1.0, func() -> bool: return cap.is_tier_parked())
	assert_true(cap.is_tier_parked(), "(15 km: a tier row)")
	assert_true(cap.damageable.kill())
	var b: CapitalBreakup = _playing_of("EAS Achilles")
	assert_not_null(b)
	if b == null:
		return
	assert_true(_wrecks().bodies_of(b).is_empty(), "no bodies far away")
	assert_eq(b.names[b.plan.order[0]], "reactor", "a console kill blows from the reactor, as M10-T09's death does")
	await _fly(b.plan.span_s() + 1.0, func() -> bool: return b.wreck.finished())
	assert_gt(b.blasts, 5, "its blasts still land")


func test_a_vorlon_ship_explodes_in_one_blast() -> void:
	var cap: CapitalShip = _spawn(&"ea_omega", "Vorlon test", 6000.0, &"vorlons")
	if cap == null:
		return
	await wait_physics_frames(3)
	assert_true(cap.scuttle())
	await wait_physics_frames(3)
	var b: CapitalBreakup = _playing_of("Vorlon test")
	assert_not_null(b, "it blew")
	if b == null:
		return
	await _fly(b.plan.span_s() + 0.5, func() -> bool: return b.wreck.finished())
	assert_eq(b.blasts, 1, "one blast, the ancients' row")
	assert_true(String(b.first_spec.source).begins_with("ancients"), b.first_spec.source)


func test_a_hyperion_breaks_up_too() -> void:
	var cap: CapitalShip = _spawn(&"ea_hyperion", "EAS Hyperion", 6000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	_blow(cap, "magazine")
	var b: CapitalBreakup = _playing_of("EAS Hyperion")
	assert_not_null(b)
	if b == null:
		return
	assert_eq(_wrecks().bodies_of(b).size(), b.names.size())
	await _fly(b.plan.span_s() + 1.0, func() -> bool: return b.wreck.finished())
	assert_eq(b.names[b.plan.order[b.plan.order.size() - 1]], "reactor")
	assert_gt(b.blasts, 5)


func test_the_console_lists_and_clears_the_wrecks() -> void:
	var cap: CapitalShip = _spawn(&"ea_omega", "EAS Agamemnon", 6000.0)
	if cap == null:
		return
	await wait_physics_frames(3)
	_blow(cap, "magazine")
	var listed: ConsoleResult = _run("wrecks")
	assert_true(listed.ok)
	assert_string_contains("\n".join(listed.lines), "EAS Agamemnon")
	assert_gt(int(str(DebugConsole.registry.read("breakups.chunks").get("value"))), 6)
	assert_true(_run("wrecks clear").ok)
	assert_eq(_wrecks().chunk_count(), 0)
	assert_eq(str(DebugConsole.registry.read("breakups.playing").get("value")), "1", "the plan plays on with no bodies")
