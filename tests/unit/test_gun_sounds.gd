extends GutTest
## Which shot each gun plays (M10-T87, Q82): the bolt guns share the Starfury's shot family by size, the railgun its own row;
## particle cannons, other beams, missiles and interceptors get none here (they keep their own sounds).


func test_bolt_guns_play_their_size_of_the_shot() -> void:
	assert_eq(GunSounds.of_weapon("ea_pulse_light"), &"gun_light")
	assert_eq(GunSounds.of_weapon("ea_pulse_medium"), &"gun_medium")
	assert_eq(GunSounds.of_weapon("ea_plasma_medium"), &"gun_medium", "medium plasma with the medium pulse")
	assert_eq(GunSounds.of_weapon("ea_pulse_cannon_fixed"), &"gun_medium", "a fixed gun by its bolt")
	assert_eq(GunSounds.of_weapon("ea_plasma_heavy"), &"gun_heavy")
	assert_eq(GunSounds.of_weapon("ea_railgun"), &"gun_railgun", "the railgun's own row, though a medium bolt")
	assert_eq(GunSounds.of_weapon("pulse_cannon_ef"), &"pulse_fire", "a fighter's gun is the Starfury's")


func test_beams_missiles_and_interceptors_keep_their_own() -> void:
	for weapon: String in ["ea_particle_cannon", "ea_particle_cannon_heavy", "ea_sweep_beam", "ea_missile", "ea_torpedo",
			"ea_interceptor", "no_such_weapon"]:
		assert_eq(GunSounds.of_weapon(weapon), &"", weapon)


func test_bigger_guns_play_louder() -> void:
	assert_lt(GunSounds.volume_db(&"gun_light"), GunSounds.volume_db(&"gun_medium"))
	assert_lt(GunSounds.volume_db(&"gun_medium"), GunSounds.volume_db(&"gun_heavy"))
	assert_eq(GunSounds.volume_db(&"gun_heavy"), StationGrid.SOUND_DB[StationGrid.Kind.HEAVY], "as loud as the grid's heavy")


func test_every_shot_is_within_four_percent_of_its_pitch() -> void:
	for i: int in 200:
		assert_between(GunSounds.jitter(), 0.96, 1.04)


func test_every_gun_sound_is_one_the_director_loads() -> void:
	for sound: StringName in GunSounds.BY_KIND.values() + GunSounds.BY_WEAPON.values():
		assert_true(AudioDirector.SOUND_NAMES.has(sound), String(sound))
	for kind: StationGrid.Kind in StationGrid.SOUND_NAME:
		assert_true(AudioDirector.SOUND_NAMES.has(StationGrid.SOUND_NAME[kind]), String(StationGrid.SOUND_NAME[kind]))
	assert_eq(StationGrid.SOUND_NAME[StationGrid.Kind.INTERCEPTOR], &"interceptor_fire", "the batteries keep their pulse")
