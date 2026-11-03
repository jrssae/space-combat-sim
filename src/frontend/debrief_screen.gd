class_name DebriefScreen
extends Control
## The debrief (architecture §18, D56, AC9): the sky behind a `MenuFrame` (the menu kit of D57) whose page offers Retry (the same
## scenario and seed, through the loading screen) and Front end, with the result, the objectives, the time, the kills and
## assists, the wing losses and the shots and hits on the right. `Game.show_debrief` puts it up after a mission; it is pad-first
## like every menu.
##
## B does nothing here: the debrief is not something to skip by accident.

const GameScript := preload("res://src/autoload/game.gd")

## A is fire in flight, so a tap as the screen opens (the fight that just ended may still be under the thumb) must not pick
## Retry; presses this soon after the screen appears are ignored.
const INPUT_GUARD_S: float = 0.7

var game: GameScript = null  ## null: /root/Game
## The mission's result. Empty: the flow's `last_result`.
var result: Dictionary = {}
var input_guard_s: float = INPUT_GUARD_S
var model: DebriefModel = null

var _age_s: float = 0.0

@onready var _frame: MenuFrame = %Frame
@onready var _camera: Camera3D = %Camera
@onready var _audio: AudioDirector = %Audio


func _ready() -> void:
	if game == null:
		game = get_node_or_null(^"/root/Game") as GameScript
	if result.is_empty() and game != null:
		result = game.flow.last_result
	model = DebriefModel.from_result(result)
	_frame.audio = _audio
	_camera.basis = FrontEnd.drift_basis(0.0)
	if model == null:
		# A debrief with no mission must not happen: say so and go back.
		push_error("DebriefScreen: no mission result to show; back to the front end")
		if game != null:
			game.show_front_end()
		return
	_frame.set_root(_page())


func _process(delta: float) -> void:
	_age_s += delta
	_camera.basis = FrontEnd.drift_basis(_age_s)


func frame() -> MenuFrame:
	return _frame


func _page() -> MenuScreen:
	var entries: Array[Dictionary] = [{"id": &"retry", "text": "Retry"}, {"id": &"front_end", "text": "Front end"}]
	var page := DebriefPage.new()
	page.setup(model.headline(), entries)
	page.panel = model.panel()
	page.chosen.connect(_on_chosen)
	return page


func _on_chosen(id: StringName) -> void:
	if _age_s < input_guard_s or game == null:
		return
	match id:
		&"retry":
			var problem: String = game.retry()
			if not problem.is_empty():
				_frame.show_message(problem)
		&"front_end":
			game.show_front_end()
