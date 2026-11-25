extends GutTest
## One voice per firing ship (M10-T87, Q82): a ship's next shot fades its last one's tail out quickly, other ships' shots and
## other sounds are left alone, and a reused voice stops being anyone's tail.


func test_a_ships_next_shot_fades_its_last_tail() -> void:
	var tails := ShotTails.new(4)
	assert_eq(tails.claim(0, 7), -1, "the first shot cuts nothing")
	assert_eq(tails.claim(1, 7), 0, "the second shot fades the first")
	assert_true(tails.is_fading(0))
	assert_false(tails.is_fading(1), "the new shot plays at full level")
	assert_eq(tails.gain_db(1), 0.0)


func test_the_fade_falls_and_ends_within_its_time() -> void:
	var tails := ShotTails.new(2)
	tails.claim(0, 7)
	tails.claim(1, 7)
	assert_almost_eq(tails.gain_db(0), 0.0, 0.01, "starts at the voice's own level")
	assert_eq(tails.step(ShotTails.FADE_S * 0.5).size(), 0)
	assert_almost_eq(tails.gain_db(0), linear_to_db(0.5), 0.01, "halfway: half the amplitude")
	var ended: PackedInt32Array = tails.step(ShotTails.FADE_S * 0.6)
	assert_eq(ended, PackedInt32Array([0]), "the faded voice is handed back to stop")
	assert_false(tails.is_fading(0))


func test_other_ships_and_sounds_keep_ringing() -> void:
	var tails := ShotTails.new(4)
	tails.claim(0, 7)
	assert_eq(tails.claim(1, 8), -1, "another ship's shot does not cut this one")
	assert_eq(tails.claim(2, 0), -1, "a hit or an explosion cuts nothing")
	assert_eq(tails.claim(3, 0), -1)
	assert_eq(tails.fading_count(), 0)


func test_a_reused_voice_is_no_longer_a_tail() -> void:
	var tails := ShotTails.new(2)
	tails.claim(0, 7)
	tails.claim(1, 7)
	tails.claim(0, 0)  # the pool steals the fading voice for an explosion
	assert_false(tails.is_fading(0), "the explosion plays at full level")
	assert_eq(tails.claim(1, 7), -1, "ship 7's only voice is the one it fires on again")


func test_rapid_fire_holds_at_most_two_voices_per_ship() -> void:
	var tails := ShotTails.new(16)
	var voice: int = 0
	for shot: int in 16:  # 8 shots a second for two seconds
		tails.claim(voice, 7)
		tails.step(0.125)
		voice = (voice + 1) % 16
		assert_lte(tails.fading_count(), 1, "shot %d" % shot)
