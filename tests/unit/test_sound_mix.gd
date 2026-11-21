extends GutTest
## The mix table (M8-T12): every sound the game plays has a level against the one loudness reference, and the table keeps
## the order the mix was set by (explosions over the guns over the jets, the squelches under the menu sounds).


func test_every_sound_played_has_a_level() -> void:
	var names: Array[StringName] = []
	names.append_array(AudioDirector.SOUND_NAMES)
	names.append_array(AudioDirector.UI_SOUND_NAMES)
	names.append(&"jump_in")
	for sound: StringName in names:
		assert_true(SoundMix.LEVEL_DB.has(sound), "%s has a mix level" % sound)


func test_levels_stay_within_a_sane_window() -> void:
	for sound: StringName in SoundMix.LEVEL_DB:
		assert_between(SoundMix.LEVEL_DB[sound], -10.0, 10.0, String(sound))


func test_the_mix_keeps_its_order() -> void:
	var at := SoundMix.level_db
	assert_gt(at.call(&"explosion"), at.call(&"main_burst"))
	assert_gt(at.call(&"main_burst"), at.call(&"pulse_fire"))
	assert_gt(at.call(&"pulse_fire"), at.call(&"rcs_burst"))
	assert_gt(at.call(&"ui_accept"), at.call(&"radio_open"))
	assert_eq(at.call(&"no_such_sound"), 0.0, "an unlisted sound plays at the reference")


func test_every_3d_kind_has_a_unit_size() -> void:
	for kind: StringName in [&"shot", &"pod", &"rcs", &"jump_in"]:
		assert_gt(SoundMix.UNIT_SIZE_M.get(kind, 0.0), 0.0, String(kind))
