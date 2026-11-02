extends GutTest
## AudioDirector (M2-T12, AC14): the generated sounds load and play headless without errors; a hit, a shot and an explosion
## each make a sound; the 3D voice pool never exceeds 16 (the oldest voice is stolen); the hull warning repeats below 25 %;
## `sfx_volume` sets the SFX bus; the console surface works. The engine voices (M5-T19) are in test_engine_audio.gd.

var main: Main
var source: FakeInputSource
var _volume_backup: Variant


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	_volume_backup = Settings.get_value(&"sfx_volume")
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	Settings.set_value(&"sfx_volume", _volume_backup)
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


## The 3D voices now playing `sound_name`.
func _voices_playing(sound_name: StringName) -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for i: int in AudioDirector.VOICES:
		var voice := main.audio.get_node("Voice%d" % i) as AudioStreamPlayer3D
		if voice.playing and voice.stream != null and voice.stream.resource_path.get_file() == "%s.wav" % sound_name:
			out.append(voice)
	return out


func test_every_sound_loads() -> void:
	for sound_name: StringName in AudioDirector.SOUND_NAMES:
		assert_true(main.audio.has_sound(sound_name), "%s loaded (run scripts/gen_assets.sh, then import)" % sound_name)


func test_play_uses_a_voice_and_unknown_sounds_are_ignored() -> void:
	var voice: AudioStreamPlayer3D = main.audio.play(&"pulse_fire", Vector3(0.0, 0.0, -50.0))
	assert_not_null(voice)
	assert_true(voice.playing)
	assert_eq(voice.global_position, Vector3(0.0, 0.0, -50.0))
	assert_eq(voice.bus, AudioDirector.BUS)
	assert_eq(main.audio.voices_active(), 1)
	assert_null(main.audio.play(&"no_such_sound", Vector3.ZERO))


func test_a_reused_voice_is_heard_at_its_new_sound_at_once() -> void:
	# Physics interpolation is on: a voice moved to a new sound in a tick would be blended from where its last sound was (and,
	# since M3-T14, from where a rebase left it) for the frames until the next tick.
	await get_tree().physics_frame
	var voice: AudioStreamPlayer3D = main.audio.play(&"pulse_fire", Vector3(0.0, 0.0, -50.0))
	await get_tree().process_frame
	await get_tree().physics_frame  # inside a tick, as shots and hits are
	var again: AudioStreamPlayer3D = null
	for i: int in AudioDirector.VOICES:
		again = main.audio.play(&"pulse_fire", Vector3(400.0, 0.0, 0.0))
		if again == voice:
			break
	assert_eq(again, voice, "the same voice, stolen for the new sound")
	await get_tree().process_frame
	assert_almost_eq(voice.get_global_transform_interpolated().origin, Vector3(400.0, 0.0, 0.0), Vector3.ONE * 1e-3,
			"heard where the new sound is, not on the way from the old one")


func test_the_voice_pool_never_exceeds_sixteen_and_steals_the_oldest() -> void:
	var voices: Array[AudioStreamPlayer3D] = []
	for i: int in 40:
		voices.append(main.audio.play(&"main_burst", Vector3(float(i), 0.0, 0.0)))  # 4 s long: all still playing
		assert_lte(main.audio.voices_active(), AudioDirector.VOICES, "after %d plays" % (i + 1))
	assert_eq(main.audio.voices_active(), AudioDirector.VOICES)
	var distinct: Dictionary = {}
	for voice: AudioStreamPlayer3D in voices:
		distinct[voice.get_instance_id()] = true
	assert_eq(distinct.size(), AudioDirector.VOICES, "only 16 players exist")
	assert_eq(voices[-1].global_position.x, 39.0, "the newest sound is the one playing")
	assert_eq(voices[0], voices[16], "the first voice was stolen for the 17th sound")


func test_a_voice_that_finished_is_reused_before_stealing() -> void:
	var first: AudioStreamPlayer3D = main.audio.play(&"target_blip", Vector3.ZERO)
	first.stop()
	var second: AudioStreamPlayer3D = main.audio.play(&"target_blip", Vector3.ZERO)
	assert_eq(first, second, "the idle voice is taken first")


func test_a_players_shot_makes_a_pulse_sound_and_a_raiders_shot_a_raider_sound() -> void:
	var before: int = main.audio.times_played(&"pulse_fire")
	main.cannon.step(SimClock.now() + 1.0)
	var cmd := CombatCommand.new()
	cmd.fire = true
	main.cannon.set_combat_command(cmd)
	main.cannon.step(SimClock.now() + 2.0)
	assert_eq(main.audio.times_played(&"pulse_fire"), before + 1)
	for voice: AudioStreamPlayer3D in _voices_playing(&"pulse_fire"):
		assert_eq(voice.volume_db, AudioDirector.SHOT_DB[&"pulse_fire"], "a shot plays at its gun's gain")
	assert_false(_voices_playing(&"pulse_fire").is_empty())
	DebugConsole.registry.execute("spawn raider 400")
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	var raider_before: int = main.audio.times_played(&"raider_fire")
	raider.cannon.set_combat_command(cmd)
	raider.cannon.step(SimClock.now() + 3.0)
	assert_eq(main.audio.times_played(&"raider_fire"), raider_before + 1)


func test_hits_and_explosions_are_heard_where_they_happen() -> void:
	DebugConsole.registry.execute("spawn raider 300")
	var raider: Combatant = main.ships.alive(ShipPool.DEFAULT_TYPE)[0]
	var hits: int = main.audio.times_played(&"hit_hull")
	var resolver: HitResolver = main.get_node("Combat/HitResolver") as HitResolver
	resolver.hit_resolved.emit(HitInfo.new(1, 2, Factions.EARTH_ALLIANCE, 10.0, Vector3(5.0, 0.0, -20.0)))
	assert_eq(main.audio.times_played(&"hit_hull"), hits + 1)
	var booms: int = main.audio.times_played(&"explosion")
	raider.damageable.kill()
	assert_eq(main.audio.times_played(&"explosion"), booms + 1)


func test_a_new_selection_blips_and_clearing_it_does_not() -> void:
	main.ship.targeting.refresh()
	var blips: int = main.audio.times_played(&"target_blip")
	main.ship.targeting.select_by_name("NAV ALPHA")
	assert_eq(main.audio.times_played(&"target_blip"), blips + 1)
	main.ship.targeting.clear_selection()
	assert_eq(main.audio.times_played(&"target_blip"), blips + 1)


func test_the_hull_warning_repeats_below_a_quarter_and_stops_above() -> void:
	var hull: HullHealth = main.combatant.damageable.hull
	var beeps: int = main.audio.times_played(&"warning_beep")
	await get_tree().process_frame
	assert_eq(main.audio.times_played(&"warning_beep"), beeps, "no warning at full hull")
	hull.apply(hull.max_hp * 0.8)  # 20 % left
	await get_tree().process_frame
	assert_eq(main.audio.times_played(&"warning_beep"), beeps + 1, "the first beep at once")
	main.audio._update_warning(AudioDirector.WARNING_INTERVAL_S + 0.1)
	assert_eq(main.audio.times_played(&"warning_beep"), beeps + 2, "and again after the interval")
	hull.restore()
	main.audio._update_warning(5.0)
	assert_eq(main.audio.times_played(&"warning_beep"), beeps + 2, "silent once repaired")


func test_sfx_volume_sets_the_bus_gain() -> void:
	var bus: int = AudioServer.get_bus_index(AudioDirector.BUS)
	assert_gte(bus, 0, "the SFX bus exists")
	Settings.set_value(&"sfx_volume", 1.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), 0.0, 1e-3)
	Settings.set_value(&"sfx_volume", 0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5), 1e-3)
	Settings.set_value(&"sfx_volume", 0.0)
	assert_lte(AudioServer.get_bus_volume_db(bus), -60.0, "silent")


func test_the_console_surface() -> void:
	var registry: ConsoleRegistry = DebugConsole.registry
	assert_true(registry.has_provider(&"audio"))
	assert_true(registry.execute("sfx explosion")[0].ok)
	assert_eq(registry.format_path("audio.voices_active"), "audio.voices_active = 1")
	assert_true(registry.execute("set audio.volume 0.25")[0].ok)
	assert_eq(Settings.get_value(&"sfx_volume"), 0.25)
	assert_false(registry.execute("sfx nonsense")[0].ok)
	assert_eq(registry.format_path("audio.sounds").count("pulse_fire"), 1)


func test_sfx_volume_is_a_schema_entry() -> void:
	assert_true(SettingsSchema.new().keys().has(&"sfx_volume"))
	assert_eq(float(Settings.get_value(&"sfx_volume")), float(_volume_backup))
