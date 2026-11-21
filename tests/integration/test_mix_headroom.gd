extends TestSteps
## The mix never clips (M8-T12, roadmap M7-5): a scripted busy fight around the player, thrusting, turning and firing while
## explosions, hits and enemy guns go off close by, read on the buses' peak meters (the headless audio driver mixes). The
## Master limiter holds the output under its ceiling; the SFX bus's own peak is reported to show the headroom before it.

const FIGHT_TICKS: int = 120

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func test_a_busy_fight_never_clips_the_output() -> void:
	var ship: Ship = main.ship
	source.hold(InputAdapter.MAIN_LEFT)
	source.hold(InputAdapter.MAIN_RIGHT)
	source.hold(InputAdapter.YAW_LEFT)
	source.hold(InputAdapter.FIRE)
	var master_peak: float = -200.0
	var sfx_peak: float = -200.0
	for tick: int in FIGHT_TICKS:
		if tick % 6 == 0:
			var at: Vector3 = ship.global_position
			var side: Vector3 = ship.global_transform.basis.x
			main.audio.play(&"explosion", at + side * 40.0)
			main.audio.play(&"hit_hull", at + side * 8.0)
			main.audio.play_shot(&"raider_fire", at - side * 80.0)
			main.audio.play_shot(&"turret_fire", at + Vector3.UP * 150.0)
		if tick % 30 == 0:
			main.audio.play_ui(&"warning_beep")
		await _ticks(1)
		await get_tree().process_frame
		master_peak = maxf(master_peak, main.audio.bus_peak_db(&"Master"))
		sfx_peak = maxf(sfx_peak, main.audio.bus_peak_db(&"SFX"))
	source.release_all()
	gut.p("busy fight: SFX bus peak %.2f dBFS, Master peak %.2f dBFS" % [sfx_peak, master_peak])
	assert_gt(master_peak, -40.0, "the fight was heard (the meters run headless)")
	assert_lte(master_peak, SoundMix.LIMITER_CEILING_DB + 0.1, "the output never passes the limiter's ceiling")
	assert_lt(sfx_peak, 6.0, "the limiter catches a pile-up's peaks; it does not carry the mix")
	var readout: ConsoleResult = _exec("state audio")
	assert_true(readout.ok, "the console reads the audio state")
	assert_string_contains("\n".join(readout.lines), "master_peak_db")
