extends GutTest
## LoadingScreen (architecture §18, D50): leaving it mid-load ends the threaded request instead of leaving it behind, and a
## load that fails goes back to the front end. A recording stand-in for `Game` takes the hand-over.

const LoadingScene: PackedScene = preload("res://src/frontend/loading_screen.tscn")
## A light scene to load, so the request finishes within a frame or two.
const STAND_IN := "res://tests/fixtures/console_host.tscn"

var game: RecordingGame


func before_each() -> void:
	game = RecordingGame.new()
	autofree(game)
	game.main_scene_path = STAND_IN


func _screen() -> LoadingScreen:
	var screen: LoadingScreen = LoadingScene.instantiate() as LoadingScreen
	screen.game = game
	add_child(screen)
	return screen


func test_leaving_mid_load_collects_the_request() -> void:
	var screen: LoadingScreen = _screen()
	await wait_process_frames(2)  # the second drawn frame starts the request
	assert_ne(ResourceLoader.load_threaded_get_status(STAND_IN), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "a request is out")
	remove_child(screen)
	screen.free()
	assert_eq(ResourceLoader.load_threaded_get_status(STAND_IN), ResourceLoader.THREAD_LOAD_INVALID_RESOURCE,
			"nothing is left pending once the screen is gone")


func test_a_finished_load_is_handed_to_game_once() -> void:
	var screen: LoadingScreen = _screen()
	await wait_until(func() -> bool: return game.loaded.size() > 0, 5.0)
	assert_eq(game.loaded.size(), 1)
	assert_true(game.loaded[0] is PackedScene)
	remove_child(screen)
	screen.free()
	assert_eq(game.loaded.size(), 1, "leaving afterwards hands nothing over again")
