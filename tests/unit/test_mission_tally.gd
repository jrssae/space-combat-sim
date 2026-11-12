extends GutTest
## MissionTally (M5-T09, D56): the player's bolts fired and hit, and the wingmen lost. Only the player's own bolts count.

const PLAYER: int = 1001
const RAIDER: int = 31
const ALLY: int = 2002


func _bolt_hit(shooter: int, target: int = RAIDER) -> HitInfo:
	return HitInfo.new(target, shooter, &"earth_alliance", 10.0)


func test_a_new_tally_is_empty() -> void:
	var tally := MissionTally.new(PLAYER)
	assert_eq([tally.shots_fired, tally.shots_hit, tally.wing_losses], [0, 0, 0])
	assert_eq(tally.accuracy(), 0.0, "no shots, no accuracy (and no division by zero)")


func test_every_bolt_fired_counts() -> void:
	var tally := MissionTally.new(PLAYER)
	for _i: int in 5:
		tally.note_fired()
	assert_eq(tally.shots_fired, 5)


func test_a_hit_by_the_players_bolt_counts() -> void:
	var tally := MissionTally.new(PLAYER)
	tally.note_fired()
	tally.note_hit(_bolt_hit(PLAYER))
	assert_eq(tally.shots_hit, 1)


func test_other_ships_bolts_do_not_count() -> void:
	var tally := MissionTally.new(PLAYER)
	tally.note_hit(_bolt_hit(ALLY))
	tally.note_hit(_bolt_hit(RAIDER, PLAYER))
	assert_eq(tally.shots_hit, 0)


func test_a_ram_or_the_console_is_no_bolt_hit() -> void:
	var tally := MissionTally.new(PLAYER)
	var ram := HitInfo.new(RAIDER, PLAYER, &"earth_alliance", 10.0, Vector3.ZERO, Vector3.ZERO, 0.0, HitInfo.CAUSE_RAM)
	var console := HitInfo.new(RAIDER, PLAYER, &"", 10.0, Vector3.ZERO, Vector3.ZERO, 0.0, HitInfo.CAUSE_CONSOLE)
	tally.note_hit(ram)
	tally.note_hit(console)
	assert_eq(tally.shots_hit, 0, "the debrief's hits are shots that landed")


func test_a_tally_with_no_player_counts_no_hits() -> void:
	var tally := MissionTally.new()
	tally.note_hit(_bolt_hit(0))
	assert_eq(tally.shots_hit, 0, "shooter 0 is the console, never the player")


func test_a_null_hit_is_ignored() -> void:
	var tally := MissionTally.new(PLAYER)
	tally.note_hit(null)
	assert_eq(tally.shots_hit, 0)


func test_accuracy_is_hits_over_shots() -> void:
	var tally := MissionTally.new(PLAYER)
	for _i: int in 8:
		tally.note_fired()
	for _i: int in 2:
		tally.note_hit(_bolt_hit(PLAYER))
	assert_almost_eq(tally.accuracy(), 0.25, 1e-6)


func test_wing_losses_count_up() -> void:
	var tally := MissionTally.new(PLAYER)
	tally.note_wing_loss()
	tally.note_wing_loss()
	assert_eq(tally.wing_losses, 2)


func test_stats_are_the_keys_a_result_carries() -> void:
	var tally := MissionTally.new(PLAYER)
	tally.note_fired()
	tally.note_fired()
	tally.note_hit(_bolt_hit(PLAYER))
	tally.note_wing_loss()
	assert_eq(tally.stats(), {"shots_fired": 2, "shots_hit": 1, "wing_losses": 1})
