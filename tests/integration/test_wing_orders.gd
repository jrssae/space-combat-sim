extends GutTest
## AC11 without the replenish (M3-T07, architecture §16 D36): on the real main scene, keys 1-4 (as `UiCommand` edges from the
## input source, never `Input`) and `wing order <attack|form|engage|cover>` change every member's order and post one
## acknowledgement line; ATTACK MY TARGET with no hostile selected is refused with a message; `wing.members` lists callsigns,
## hull and behaviour. Three allied Starfuries on the `ally_starfury` profile join the player's wing ALPHA in their slots
## (T08 brings them from a pool; here they are built as T06's tests build them).

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"

var main: Main
var source: FakeInputSource
var allies: Array[Combatant] = []
var wing: Wing = null
var _scale_backup: float = 1.0


func before_each() -> void:
	get_tree().paused = false
	_scale_backup = Engine.time_scale
	ContactScan.invalidate()
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 1  # for a hostile to select
	add_child_autofree(main)
	await _ticks(2)
	wing = main.wings.player_wing()
	allies = []
	var spec := load(STARFURY_SPEC) as ShipSpec
	var basis: Basis = main.ship.global_basis
	for slot: int in range(1, 4):
		var ally: Combatant = ShipAssembly.build(spec, main.world, main.projectiles, {
			ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
			ShipAssembly.OPT_DISPLAY_NAME: wing.callsign(slot),
			ShipAssembly.OPT_FORCE_ASSIST: true,
			ShipAssembly.OPT_AI: true,
		})
		var at: Vector3 = Formation.slot_point(main.ship.global_position, -basis.z, basis.y, wing.slot_offset(slot))
		main.world.spawn(ally.ship, main.world.to_universe(at), basis)
		ally.driver.brain = BrainFactory.from_behaviour({"type": "ai", "profile": "ally_starfury"}, UniversePos.new(),
				slot)["brain"] as AiPilot
		assert_eq(main.wings.add_member(wing, ally), slot)
		allies.append(ally)
	watch_signals(main.wings)


func after_each() -> void:
	Engine.time_scale = _scale_backup
	get_tree().paused = false
	ContactScan.invalidate()


func test_the_player_leads_alpha_and_its_members_cover_it_in_a_finger_four() -> void:
	assert_eq(wing.name, "ALPHA")
	assert_eq(wing.leader, main.combatant)
	await _ticks(10)
	for ally: Combatant in allies:
		var pilot := ally.driver.brain as AiPilot
		assert_eq(pilot.context.order, AiContext.Order.COVER_ME, "%s: the default order" % ally.display_name)
		assert_eq(pilot.context.leader_id, main.combatant.targetable.get_instance_id())
		assert_true(pilot.context.has_slot)
		assert_eq(pilot.context.slot_offset, Formation.new().offset(wing.slot_of(ally)))
		assert_not_null(pilot.behaviour(&"formation"), "joining the wing gave it the formation behaviour")
		assert_eq(pilot.current.id, &"formation", "%s flies formation" % ally.display_name)
	assert_eq(main.wings.process_physics_priority, 290)


func test_keys_one_to_four_order_every_member_and_post_one_line_each() -> void:
	var lines: Array[String] = []
	main.wings.acknowledged.connect(func(line: String) -> void: lines.append(line))
	await _press(InputAdapter.WING_FORM)
	_assert_orders(AiContext.Order.FORM_ON_ME, "key 2")
	assert_eq(lines, ["ALPHA 2: COPY, FORMING UP"] as Array[String], "one line for the order")
	assert_eq(main.wings.ack_text(), "ALPHA 2: COPY, FORMING UP", "the HUD's line")
	await _press(InputAdapter.WING_ENGAGE)
	_assert_orders(AiContext.Order.ENGAGE_AT_WILL, "key 3")
	await _press(InputAdapter.WING_COVER)
	_assert_orders(AiContext.Order.COVER_ME, "key 4")
	assert_eq(lines.size(), 3)
	assert_eq(lines[2], "ALPHA 2: COPY, COVERING YOU")

	await _press(InputAdapter.WING_ATTACK)
	_assert_orders(AiContext.Order.COVER_ME, "key 1 with nothing selected is refused")
	assert_eq(lines.size(), 4)
	assert_eq(lines[3], "ALPHA 2: UNABLE, NO HOSTILE SELECTED", "refused with a message")

	DebugConsole.registry.execute("spawn raider idle 1500")
	await _ticks(2)
	assert_true(main.ship.targeting.select_nearest_hostile(), "the player selects the raider")
	var raider_id: int = main.ship.targeting.selected_id()
	await _press(InputAdapter.WING_ATTACK)
	_assert_orders(AiContext.Order.ATTACK_MY_TARGET, "key 1 with a hostile selected")
	assert_eq(lines.size(), 5)
	assert_eq(lines[4], "ALPHA 2: COPY, ATTACKING RAIDER 1")
	for ally: Combatant in allies:
		assert_eq((ally.driver.brain as AiPilot).context.leader_target_id, raider_id, "%s knows the target" % ally.display_name)
	await _ticks(90)
	for ally: Combatant in allies:
		assert_eq((ally.driver.brain as AiPilot).wanted_target_id, raider_id, "%s attacks it" % ally.display_name)


func test_a_buoy_is_no_hostile_to_attack() -> void:
	assert_true(main.ship.targeting.select_by_name("NAV ALPHA"))
	var result: Dictionary = main.wings.give_order(AiContext.Order.ATTACK_MY_TARGET)
	assert_false(result["ok"])
	assert_eq(result["line"], "ALPHA 2: UNABLE, NO HOSTILE SELECTED")
	_assert_orders(AiContext.Order.COVER_ME, "a neutral buoy selected")


func test_the_console_orders_the_wing_and_changes_its_formation() -> void:
	var form: ConsoleResult = _run("wing order form")
	assert_true(form.ok, form.error)
	assert_eq(form.text(), "ALPHA 2: COPY, FORMING UP")
	_assert_orders(AiContext.Order.FORM_ON_ME, "wing order form")
	assert_signal_emit_count(main.wings, "acknowledged", 1)
	assert_true(_run("wing order engage").ok)
	_assert_orders(AiContext.Order.ENGAGE_AT_WILL, "wing order engage")
	assert_true(_run("wing order COVER").ok, "any case")
	_assert_orders(AiContext.Order.COVER_ME, "wing order cover")
	assert_signal_emit_count(main.wings, "acknowledged", 3)

	var refused: ConsoleResult = _run("wing order attack")
	assert_false(refused.ok, "nothing selected")
	assert_eq(refused.error, "ALPHA 2: UNABLE, NO HOSTILE SELECTED")
	_assert_orders(AiContext.Order.COVER_ME, "the refused order changes nothing")
	assert_eq(_read("wing.last_ack"), "ALPHA 2: UNABLE, NO HOSTILE SELECTED")

	var bad: ConsoleResult = _run("wing order dance")
	assert_false(bad.ok)
	assert_string_contains(bad.error, "wing order expects one of attack|form|engage|cover, got 'dance'")
	assert_false(_run("wing dance").ok, "only order and formation")
	assert_signal_emit_count(main.wings, "acknowledged", 4, "bad words post nothing")

	assert_eq(_read("wing.formation"), "finger_four")
	var wedge: ConsoleResult = _run("wing formation wedge")
	assert_true(wedge.ok, wedge.error)
	assert_eq(wedge.text(), "ALPHA formation: finger_four -> wedge")
	assert_eq(_read("wing.formation"), "wedge")
	for ally: Combatant in allies:
		assert_eq((ally.driver.brain as AiPilot).context.slot_offset, Formation.new(Formation.Shape.WEDGE).offset(
				wing.slot_of(ally)), "%s takes its wedge slot" % ally.display_name)
	assert_false(_run("wing formation box").ok)
	assert_eq(_run("wing").text(), "ALPHA: order cover, formation wedge, members ALPHA 2, ALPHA 3, ALPHA 4")
	assert_eq(_run("wing order").text(), "ALPHA order: cover")


func test_the_roster_lists_callsigns_hull_and_behaviour() -> void:
	allies[1].damageable.hull.apply(allies[1].damageable.hull.max_hp * 0.5)
	await _ticks(5)
	assert_eq(_read("wing.name"), "ALPHA")
	assert_eq(_read("wing.order"), "cover")
	var members: PackedStringArray = _read("wing.members")
	assert_eq(members.size(), 3)
	assert_string_starts_with(members[0], "ALPHA 2 100% formation (")
	assert_string_starts_with(members[1], "ALPHA 3 50% formation (")
	assert_string_starts_with(members[2], "ALPHA 4 100% formation (")
	var rows: Array[Dictionary] = main.wings.roster()
	assert_eq(rows[1]["callsign"], "ALPHA 3")
	assert_almost_eq(float(rows[1]["hull"]), 0.5, 1e-6)
	assert_eq(rows[1]["slot"], 2)
	# The HUD gets the same rows, through Main (M3-T11).
	var input: HudInput = main._build_hud_input()
	assert_eq(input.roster.size(), 3)
	assert_eq(input.roster[1]["callsign"], "ALPHA 3")
	assert_almost_eq(float(input.roster[1]["hull"]), 0.5, 1e-6)
	main.wings.give_order(AiContext.Order.FORM_ON_ME)
	assert_eq(main._build_hud_input().ack_line, "ALPHA 2: COPY, FORMING UP", "the acknowledgement reaches the HUD")


func test_while_the_player_is_dead_the_wing_engages_at_will_and_resumes_on_respawn() -> void:
	main.wings.give_order(AiContext.Order.FORM_ON_ME)
	main.combatant.damageable.kill()
	await _ticks(2)
	_assert_orders(AiContext.Order.ENGAGE_AT_WILL, "the leader is dead")
	assert_eq(wing.order, AiContext.Order.FORM_ON_ME, "the wing keeps its order")
	for ally: Combatant in allies:
		assert_null((ally.driver.brain as AiPilot).context.leader_link_position, "no leader to fly to")
	main.respawn()
	await _ticks(2)
	_assert_orders(AiContext.Order.FORM_ON_ME, "back after the respawn")
	assert_not_null((allies[0].driver.brain as AiPilot).context.leader_link_position)


func test_a_downed_member_leaves_its_slot_and_the_next_one_answers() -> void:
	allies[0].damageable.kill()
	await _ticks(2)
	assert_eq(wing.empty_slots(), PackedInt32Array([1]), "ALPHA 2's slot is free for a replacement (M3-T08)")
	assert_eq(wing.members().size(), 2)
	assert_eq((_read("wing.members") as PackedStringArray).size(), 2)
	var result: Dictionary = main.wings.give_order(AiContext.Order.FORM_ON_ME)
	assert_eq(result["line"], "ALPHA 3: COPY, FORMING UP")
	assert_eq(main.wings.add_member(wing, allies[0]), -1, "a ship out of play cannot join")
	assert_eq(wing.empty_slots(), PackedInt32Array([1]))
	# The HUD roster keeps the slot, as DOWN, until a replacement takes it (M3-T11).
	var rows: Array[Dictionary] = main.wings.hud_roster()
	assert_eq(rows.size(), 3)
	assert_eq(rows[0]["callsign"], "ALPHA 2")
	assert_true(bool(rows[0]["down"]))
	assert_false(bool(rows[1]["down"]))
	assert_eq(rows[1]["behaviour"], "formation")


func test_the_hud_line_lasts_three_seconds_of_sim_time() -> void:
	main.wings.give_order(AiContext.Order.FORM_ON_ME)
	var posted_s: float = SimClock.now()
	# 0.1 s ticks. The scale applies from the next frame, so the wait is in sim time (the director's line ages by the same
	# physics deltas as the clock), not in ticks.
	Engine.time_scale = 6.0
	while SimClock.now() - posted_s < WingDirector.ACK_HOLD_S - 0.5:
		await get_tree().physics_frame
	assert_eq(main.wings.ack_text(), "ALPHA 2: COPY, FORMING UP", "still up at %.1f s" % (SimClock.now() - posted_s))
	while SimClock.now() - posted_s < WingDirector.ACK_HOLD_S + 0.3:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	assert_eq(main.wings.ack_text(), "", "gone after 3 s")
	assert_eq(_read("wing.last_ack"), "ALPHA 2: COPY, FORMING UP", "the provider keeps the last line")


func _assert_orders(order: AiContext.Order, why: String) -> void:
	for ally: Combatant in allies:
		assert_eq((ally.driver.brain as AiPilot).context.order, order, "%s: %s" % [ally.display_name, why])


func _press(action: StringName) -> void:
	source.hold(action, 1.0, true)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _read(path: String) -> Variant:
	var read: Dictionary = DebugConsole.registry.read(path)
	assert_true(read["ok"], "%s: %s" % [path, read["error"]])
	return read["value"]


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame
