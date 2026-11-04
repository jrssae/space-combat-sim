extends GutTest
## `MissionApi.cinematic` and `lock_controls` without a stage (architecture §18 D51, D55, M5-T08): the scenario's shots are read and
## checked, a shot lasts its length of sim time, a skipped step logs it and goes on at once, an unknown shot is an error, and the
## control lock is a flag in the journal. The game side (the camera, the HUD, the commands) is `test_cinematic_camera.gd`'s.

const DT: float = 1.0 / 60.0
const SHOTS: Dictionary = {
	"intro": {"keys": [
		{"t": 0, "position": {"actor": "player", "offset": [0, 5, 30]}, "look_at": {"actor": "player"}},
		{"t": 2, "position": {"origin": [0, 0, -500]}, "look_at": {"actor": "player"}},
	]},
}


## Plays the intro, then waits.
class Director extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"intro", &"after"]

	func step_intro(m: MissionApi) -> void:
		m.lock_controls(true)
		await m.cinematic(&"intro")
		m.lock_controls(false)
		trace.append("intro done at %.2f" % m.time_s())

	func step_after(m: MissionApi) -> void:
		trace.append("after")
		await m.wait(100.0)


## Asks for a shot the scenario lacks.
class Typo extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"oops"]

	func step_oops(m: MissionApi) -> void:
		await m.cinematic(&"no_such_shot")
		trace.append("went on")


func _api_with(script: MissionScript) -> MissionApi:
	var api := MissionApi.new()
	assert_eq(api.load_cinematics(SHOTS), "")
	assert_eq(api.begin(script), "")
	return api


func _tick(api: MissionApi, n: int) -> void:
	for _i: int in n:
		api.tick(DT, {})


func test_the_shots_are_read_from_the_scenario() -> void:
	var api := MissionApi.new()
	assert_eq(api.load_cinematics(SHOTS), "")
	assert_true(api.cinematics.has(&"intro"))
	assert_almost_eq((api.cinematics[&"intro"] as CinematicShot).duration_s, 2.0, 1e-6)


func test_a_bad_shot_is_refused_and_none_are_kept() -> void:
	var api := MissionApi.new()
	var problem: String = api.load_cinematics({"intro": SHOTS["intro"], "broken": {"keys": []}})
	assert_string_contains(problem, "cinematics.broken")
	assert_true(api.cinematics.is_empty())


func test_a_shot_lasts_its_length_of_sim_time_and_the_lock_is_kept() -> void:
	var script := Director.new()
	var api: MissionApi = _api_with(script)
	assert_true(api.controls_locked, "locked for the shot")
	_tick(api, 60)
	assert_eq(script.trace, [] as Array[String], "one second into a two-second shot")
	_tick(api, 61)
	assert_eq(script.trace[0], "intro done at 2.00")
	assert_false(api.controls_locked)
	assert_true(api.journal.has("cinematic intro"))
	assert_true(api.journal.has("lock_controls on"))
	assert_true(api.journal.has("lock_controls off"))


func test_a_skipped_step_logs_the_shot_and_goes_on_at_once() -> void:
	var script := Director.new()
	var api: MissionApi = _api_with(script)
	assert_eq(api.skip(), "")
	assert_eq(script.trace, ["intro done at 0.00", "after"] as Array[String])
	assert_true(api.journal.has("cinematic intro"))
	assert_false(api.controls_locked, "the world change after the shot still ran")


func test_an_unknown_shot_is_an_error_and_the_step_goes_on() -> void:
	var script := Typo.new()
	var api: MissionApi = _api_with(script)
	assert_push_error("no_such_shot")
	assert_eq(script.trace, ["went on"] as Array[String])
