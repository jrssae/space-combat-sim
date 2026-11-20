extends GutTest
## The maintainer's play-test (M8-T17, 2026-11-20): free flight, Alpha wing launched, FORM ON ME, then gate jumps back to back.
## Every jump carries the wingmen in range through and out with the player; no ship dies, to a vortex or a ram.

var main: Main
var deaths: Array[String] = []


func before_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func after_each() -> void:
	get_tree().paused = false
	ContactScan.invalidate()


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _note_death(c: Combatant, label: String) -> void:
	c.damageable.destroyed.connect(func(info: HitInfo) -> void: deaths.append("%s by %s" % [label, info.cause]))


func test_alpha_wing_follows_three_jumps_in_a_row_and_nobody_dies() -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(3)
	main.combatant.damageable.invulnerable = false
	assert_true(DebugConsole.registry.execute("launch wing alpha")[0].ok)
	await _ticks(60 * 25)
	var wing: Wing = main.wings.player_wing()
	assert_gt(wing.members().size(), 6, "Alpha is out")
	assert_true(DebugConsole.registry.execute("wing order form")[0].ok)
	for c: Combatant in wing.members():
		_note_death(c, c.display_name)
	_note_death(main.combatant, "the player")
	assert_true(DebugConsole.registry.execute("goto jumpgate")[0].ok, "to the gate, the wing along in formation")
	await _ticks(60 * 3)
	var g: Jumpgate = main.gates.gate()
	for jump: int in 3:
		var why: String = main.gates.start_jump(g)
		var guard: int = 0
		while not why.is_empty() and guard < 60 * 60:  # closing on the gate until a jump may be asked
			await _ticks(1)
			guard += 1
			if guard % 30 == 0:
				main.ship.linear_velocity = main.world.rest_velocity() + (g.global_position - main.ship.global_position).normalized() * 300.0
			why = main.gates.start_jump(g)
		assert_eq(why, "", "jump %d asked" % (jump + 1))
		var carried_before: int = main.gates.wing_jump.carried
		var sent: int = 0
		while main.gates.jump.is_active():
			await _ticks(1)
			sent = maxi(sent, main.gates.wing_jump.sent.size())
		assert_eq(main.gates.jump.completed, jump + 1, "jump %d out and back (%s)" % [jump + 1, main.gates.jump.ended_why])
		assert_gt(sent, 0, "jump %d: wingmen followed" % (jump + 1))
		assert_eq(main.gates.wing_jump.carried - carried_before, sent, "jump %d: every one that followed came back out" % (jump + 1))
		assert_eq(main.gates.wing_jump.called_off, 0, "jump %d: the hold was never called off" % (jump + 1))
	assert_eq(deaths, [] as Array[String], "nobody died")
	assert_true(main.player_alive)
	assert_eq(g.vortex.form_kills + g.vortex.close_kills, 0, "no vortex killed anyone")
