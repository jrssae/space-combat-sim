extends GutTest
## Headless runs ignore real input devices (M7-T10): a Main started with no window and no source given flies its player on
## the idle base source, so a pad or key touched on the machine cannot steer a recorded or console-driven fight. A source
## given from outside (tests, tools) is kept.


func _main(source: InputSource) -> Main:
	var main := (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.raider_pool_size = 0
	main.waves_auto_start = false
	add_child_autofree(main)
	return main


func test_a_headless_main_gets_the_idle_source() -> void:
	if DisplayServer.get_name() != "headless":
		pending("a windowed run reads the real devices")
		return
	var main: Main = _main(null)
	await get_tree().physics_frame
	assert_not_null(main.input_source, "it has a source")
	assert_false(main.input_source is GodotInputSource, "not the one that polls pads and keys")
	assert_eq(main.input_source.get_script(), InputSource, "the idle base source")
	assert_eq(main.input_source.get_trigger(&"thrust_main_left"), 0.0)
	assert_false(main.input_source.is_pressed(&"fire_primary"))


func test_a_source_given_from_outside_is_kept() -> void:
	var fake := FakeInputSource.new()
	var main: Main = _main(fake)
	await get_tree().physics_frame
	assert_eq(main.input_source, fake)


# Every key bound to an action, pressed or released in the engine's own key state, and every action pressed or released.
func _hold_everything(down: bool) -> void:
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("ui_"):
			continue
		if down:
			Input.action_press(action)
		else:
			Input.action_release(action)
		for event: InputEvent in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key == null:
				continue
			var press := InputEventKey.new()
			press.physical_keycode = key.physical_keycode
			press.keycode = key.keycode
			press.pressed = down
			Input.parse_input_event(press)
	Input.flush_buffered_events()


func test_keys_and_actions_held_on_the_machine_do_not_reach_a_headless_players_command() -> void:
	if DisplayServer.get_name() != "headless":
		pending("a windowed run reads the real devices")
		return
	var main: Main = _main(null)
	await get_tree().physics_frame
	var before: Vector3 = main.ship.linear_velocity
	_hold_everything(true)
	# The test has teeth: the source a window would get reads these keys as held.
	var real := GodotInputSource.new()
	real.poll(1.0 / 60.0)
	var read: int = 0
	for action: StringName in InputMap.get_actions():
		read += 1 if not String(action).begins_with("ui_") and real.is_pressed(action) else 0
	assert_gt(read, 0, "the real source reads the held keys (%d actions)" % read)
	var worst: float = 0.0
	var fired: bool = false
	for i: int in 30:
		await get_tree().physics_frame
		var f: FlightCommand = main.adapter.last.flight
		worst = maxf(worst, maxf(maxf(f.main_left, f.main_right), maxf(f.retro_left, f.retro_right)))
		worst = maxf(worst, maxf(f.strafe.length(), f.rot.length()))
		fired = fired or main.adapter.last.combat.fire or f.brake
	_hold_everything(false)
	assert_eq(worst, 0.0, "no thrust, strafe or turn was commanded")
	assert_false(fired, "no trigger, no brake")
	assert_almost_eq(main.ship.linear_velocity, before, Vector3.ONE * 1e-3, "the player's ship flew on untouched")
	assert_false(get_tree().paused, "and nothing paused the game")
