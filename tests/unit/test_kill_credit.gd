extends GutTest
## KillCredit (M3-T16, Q18, AC24): a death is the player's kill when the killing shooter is the player's ship, an assist when
## someone else killed a ship the player fired at while it was selected, never both; marks are per target and start over.

const PLAYER: int = 1001
const ALLY: int = 2002
const RAIDER_A: int = 31
const RAIDER_B: int = 32


func test_the_players_killing_shot_is_a_kill() -> void:
	var credit := KillCredit.new(PLAYER)
	assert_eq(credit.credit(RAIDER_A, PLAYER), KillCredit.KILL, "no selection needed: the bolt or ram was the player's")
	assert_eq([credit.player_kills, credit.player_assists], [1, 0])


func test_a_kill_on_a_ship_the_player_fired_at_is_not_also_an_assist() -> void:
	var credit := KillCredit.new(PLAYER)
	credit.note_shot(RAIDER_A)
	assert_eq(credit.credit(RAIDER_A, PLAYER), KillCredit.KILL)
	assert_eq([credit.player_kills, credit.player_assists], [1, 0])
	assert_false(credit.fired_at(RAIDER_A), "the death clears the mark")


func test_someone_elses_kill_after_the_player_fired_is_an_assist() -> void:
	var credit := KillCredit.new(PLAYER)
	credit.note_shot(RAIDER_A)
	credit.note_shot(RAIDER_A)  # many shots, one assist
	assert_eq(credit.credit(RAIDER_A, ALLY), KillCredit.ASSIST)
	assert_eq(credit.credit(RAIDER_A, ALLY), KillCredit.NONE, "the mark went with the first death")
	assert_eq([credit.player_kills, credit.player_assists], [0, 1])


func test_the_console_kill_of_a_marked_ship_is_an_assist() -> void:
	var credit := KillCredit.new(PLAYER)
	credit.note_shot(RAIDER_B)
	assert_eq(credit.credit(RAIDER_B, 0), KillCredit.ASSIST)


func test_shots_at_another_target_earn_nothing() -> void:
	var credit := KillCredit.new(PLAYER)
	credit.note_shot(RAIDER_B)
	credit.note_shot(0)  # fired with nothing selected
	assert_eq(credit.credit(RAIDER_A, ALLY), KillCredit.NONE)
	assert_true(credit.fired_at(RAIDER_B), "the other mark stays")
	assert_false(credit.fired_at(0))
	assert_eq([credit.player_kills, credit.player_assists], [0, 0])


func test_a_reused_pool_ship_starts_clean() -> void:
	var credit := KillCredit.new(PLAYER)
	credit.note_shot(RAIDER_A)
	credit.forget(RAIDER_A)  # released, then handed out again as somebody new
	assert_eq(credit.credit(RAIDER_A, ALLY), KillCredit.NONE)


func test_without_a_player_nobody_is_credited() -> void:
	var credit := KillCredit.new()
	assert_eq(credit.credit(RAIDER_A, 0), KillCredit.NONE, "a console kill is never the player's kill")
	assert_eq(credit.player_kills, 0)
