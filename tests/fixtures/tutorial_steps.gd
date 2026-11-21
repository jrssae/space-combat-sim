class_name TutorialSteps
extends TestSteps
## Test fixture for the tutorial mission's test files (M8 D79): the real Main flying `data/scenarios/tutorial.json` as the flow
## starts a mission, the game's flow and career put aside for the test, and the helpers that drive and read the mission.

const SCENARIO_ID: StringName = &"tutorial"
const MISSION_PATH: String = "res://data/scenarios/tutorial.json"
const CAREER_PATH: String = "user://test_tutorial_career.json"
const FrontEndScene: PackedScene = preload("res://src/frontend/front_end.tscn")
const Script_: GDScript = preload("res://data/missions/tutorial.gd")
const BEAT_S: float = 0.25

var main: Main
var holder: Node
var source: FakeInputSource
var _saved: Dictionary = {}


func before_each() -> void:
	get_tree().paused = false
	source = FakeInputSource.new()
	_saved = {"flow": Game.flow, "parent": Game.scene_parent, "main_path": Game.main_scene_path, "career": Game.career,
			"career_path": Game.career_path}
	Game.flow = GameFlow.new()
	Game.career = Career.new()
	Game.career_path = CAREER_PATH
	DirAccess.remove_absolute(CAREER_PATH)
	holder = Node.new()
	add_child_autofree(holder)
	Game.scene_parent = holder


func after_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = false
	Game.flow = _saved["flow"]
	Game.scene_parent = _saved["parent"]
	Game.main_scene_path = _saved["main_path"]
	Game.career = _saved["career"]
	Game.career_path = _saved["career_path"]
	DirAccess.remove_absolute(CAREER_PATH)


# --- helpers -----------------------------------------------------------------------------------------------------------


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _wait_for(what: String, reached: Callable, max_ticks: int = 1500) -> void:
	var waited: int = 0
	while not bool(reached.call()) and waited < max_ticks:
		await _ticks(1)
		waited += 1
	assert_true(bool(reached.call()), "waited %d ticks for: %s" % [waited, what])


# The tutorial in the real Main, started as the flow starts a mission; `checkpoint` as a debrief's restart hands it over.
func _fly(seed_value: int = 5, checkpoint: Dictionary = {}) -> void:
	Game.flow.enter_directly(GameFlow.make_request(&"mission", SCENARIO_ID, false, seed_value))
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.scenario_path = MISSION_PATH
	main.scenario_seed = seed_value
	main.mission_checkpoint = checkpoint
	holder.add_child(main)
	await _ticks(2)
	main.mission.debrief_delay_s = BEAT_S


func _api() -> MissionApi:
	return main.mission.api


func _goto(step: StringName) -> void:
	assert_true(_run("mission goto %s" % step).ok, "mission goto %s" % step)
	await _wait_for("step %s" % step, func() -> bool: return _api().step_name() == step and not _api().is_skipping(), 600)


func _ship(ship_name: String) -> Combatant:
	return main.mission.stage._actors.get(MissionWorld.key(ship_name)) as Combatant


func _grading() -> TutorialRules:
	return TutorialRules.load_file()["rules"]


# The names of the AI Starfuries in play, sorted.
func _starfuries() -> Array:
	var names: Array = main.ships.alive(ShipPool.ALLY_TYPE).map(func(c: Combatant) -> String: return c.display_name)
	names.sort()
	return names


func _check_open(id: StringName) -> bool:
	return _api().checks.is_active() and _api().checks.current != null and _api().checks.current.id == id


# Waits until check `id` is open and has taken its first look: an order given in its first tick would be its baseline.
func _await_check(id: StringName, max_ticks: int) -> void:
	await _wait_for("the %s check" % id, func() -> bool: return _check_open(id), max_ticks)
	await _ticks(5)


func _debrief() -> DebriefScreen:
	return holder.get_child(0) as DebriefScreen if holder.get_child_count() == 1 else null


func _local(at: Vector3) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(at.x, at.y, at.z, main.world.origin.system_id))


func _put_player(at: Vector3) -> void:
	main.mission.stage.place("player", UniversePos.new(at.x, at.y, at.z, main.world.origin.system_id))


func _journal_has(prefix: String) -> bool:
	for entry: String in _api().journal:
		if entry.begins_with(prefix):
			return true
	return false


# The line the comms panel shows now, &"" for none.
func _line() -> StringName:
	return _api().dialog.current.id if _api().dialog.current != null else &""


# Whether the script has said `line_id` (the journal's `say` entries; a check's own hint is not one of them).
func _said(line_id: StringName) -> bool:
	return Array(_api().journal).has("say %s" % line_id)


# The player's speed against the station's rest, m/s.
func _speed() -> float:
	return (main.ship.linear_velocity - main.world.rest_velocity()).length()


# One press of `action` on the stand-in pad, as the pilot's thumb would give it.
func _press(action: StringName) -> void:
	source.hold(action, 1.0, true)
	await _ticks(2)
	source.release(action)
	await _ticks(2)


# Where the scenario's point `at` (metres from its origin) is in the scene now.
func _distance_to(at: Vector3) -> float:
	return main.ship.global_position.distance_to(_local(at))
