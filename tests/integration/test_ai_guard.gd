extends GutTest
## AC9, guard (M3-T10, architecture §16 D34): an allied Starfury on the `ally_starfury` profile holds a post. A raider seen
## outside the 1 500 m guard radius is left alone; once it drifts inside, the guard engages it, and once it is gone the guard
## returns within 300 m of its post. A fixed post is a `UniversePos`, so the run goes through T14's `RebaseFight` with a
## rebase forced every 0.5 s of sim time. A guard on a ship's slot engages a raider outside the radius that attacks the ship it
## guards. The real main scene, Jolt and the real drivers; sim time sped up.

const SPEED_UP: float = 4.0

var main: Main
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	ContactScan.invalidate()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.waves_auto_start = false
	main.ally_pool_size = 8  # the sandbox's three wingmen (M3-T10) and room for this test's allies
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	ContactScan.invalidate()


func _from_player(offset: Vector3) -> UniversePos:
	return main.world.to_universe(main.ship.global_position).plus_local(offset)


func _guard(ship_name: String, at: UniversePos, guard: Dictionary) -> Combatant:
	var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury", "guard": guard}, at, hash(ship_name))
	assert_true(bool(made["ok"]), str(made.get("error", "")))
	return main.ships.acquire(ship_name, at, Basis.IDENTITY, Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)


func _behaviour(c: Combatant) -> StringName:
	var pilot := c.driver.brain as AiPilot
	return pilot.current.id if pilot != null and pilot.current != null else &""


func test_a_guard_engages_inside_its_radius_and_returns_to_its_post_through_rebases() -> void:
	var post: UniversePos = _from_player(Vector3(4000.0, 0.0, 0.0))  # 4 km off the player: nothing else near the post
	var guard: Combatant = _guard("ALPHA 5", post, {"post": [0, 0, 0]})
	# A raider coasting at the post from 3.2 km, nose on it: seen (inside 5 km) well before it enters the 1.5 km radius.
	var raider: Combatant = main.ships.acquire("RAIDER 7", post.plus_local(Vector3(0.0, 0.0, -3200.0)), Basis.IDENTITY,
			Vector3(0.0, 0.0, 40.0), IdleBrain.new(false), ShipPool.DEFAULT_TYPE)
	var seen: Dictionary = {"attacked_outside": false, "engaged_inside": false, "gone_at_s": -1.0}
	var raider_id: int = raider.ship.get_instance_id()
	var watch := func() -> bool:
		var raider_alive: bool = is_instance_valid(raider.ship) and raider.ship.can_process() and raider.ship.get_instance_id() == raider_id \
				and main.ships.alive(ShipPool.DEFAULT_TYPE).has(raider)
		if raider_alive:
			var d: float = main.world.to_universe(raider.ship.global_position).distance_to(post)
			if _behaviour(guard) == &"attack":
				if d > BehaviourGuard.DEFAULT_RADIUS_M + 50.0:
					seen["attacked_outside"] = true
				else:
					seen["engaged_inside"] = true
		elif float(seen["gone_at_s"]) < 0.0:
			seen["gone_at_s"] = SimClock.now()
			raider_id = 0
		if float(seen["gone_at_s"]) < 0.0:
			return false
		return main.world.to_universe(guard.ship.global_position).distance_to(post) < 300.0 and SimClock.now() - float(seen["gone_at_s"]) > 5.0
	Engine.time_scale = SPEED_UP
	var fight: RebaseFight = await RebaseFight.run(self, main, 240.0, watch, 40.0, 0.0, 0.5)
	Engine.time_scale = 1.0
	var back_m: float = main.world.to_universe(guard.ship.global_position).distance_to(post)
	gut.p("guard: %s; engaged %s, raider gone at %.0f s, back %.0f m from the post" % [fight.summary(), seen["engaged_inside"],
			seen["gone_at_s"], back_m])
	assert_false(bool(seen["attacked_outside"]), "a hostile outside the radius is left alone")
	assert_true(bool(seen["engaged_inside"]), "it engaged inside the radius")
	assert_gt(float(seen["gone_at_s"]), 0.0, "the raider went down")
	assert_lt(back_m, 300.0, "back within 300 m of the post")
	assert_eq(_behaviour(guard), &"guard")


func test_a_guard_on_a_ships_slot_engages_whoever_attacks_that_ship() -> void:
	var at: UniversePos = _from_player(Vector3(-4000.0, 0.0, 0.0))
	var made: Dictionary = BrainFactory.from_behaviour({"type": "idle", "hold": true}, at, 1)
	var guarded: Combatant = main.ships.acquire("ALPHA 6", at, Basis.IDENTITY, Vector3.ZERO, made["brain"] as PilotBrain, ShipPool.ALLY_TYPE)
	var guard: Combatant = _guard("ALPHA 7", at.plus_local(Vector3(0.0, 0.0, 200.0)),
			{"ship": "ALPHA 6", "offset": [0, 0, 200], "radius_m": 1000})
	# An attack raider 2.5 km out: outside the 1 km radius, with the guarded ship (the nearest hostile to it) selected.
	var raider: Combatant = main.ships.acquire("RAIDER 8", at.plus_local(Vector3(0.0, 0.0, -2500.0)), Basis.IDENTITY,
			Vector3.ZERO, AttackBrain.new(load(BrainFactory.DEFAULT_TACTICS_PATH) as RaiderTactics, 3), ShipPool.DEFAULT_TYPE)
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	var engaged_at_m: float = -1.0
	while SimClock.now() - t0 < 30.0:
		await get_tree().physics_frame
		if _behaviour(guard) == &"attack" and raider.ship.targeting.selected_id() == guarded.targetable.get_instance_id():
			engaged_at_m = raider.ship.global_position.distance_to(guarded.ship.global_position)
			break
	Engine.time_scale = 1.0
	gut.p("guarded ship: the guard engaged its attacker %.0f m from it" % engaged_at_m)
	assert_gt(engaged_at_m, 1000.0, "outside the radius, because it attacks the guarded ship")
	assert_eq((guard.driver.brain as AiPilot).current.target_id(), raider.targetable.get_instance_id())
