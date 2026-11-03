class_name MenuFrame
extends Control
## The three-panel layout the pause menu, the front end and the settings and controls pages share (architecture §18, D57,
## Q15): the options at the top left, scrolling when long; below them the controller diagram with what each button does
## now; on the right the mission objectives (or the run, or a briefing).
##
## The frame holds a stack of `MenuScreen` pages and shows the top one. Its panels read small providers, so the frame needs
## nothing from a running mission: `bindings_source` for the diagram, `objectives_source` and `request_source` for the right
## panel. A page can put its own content on the right (`MenuScreen.info`), as the mission list does with a briefing.

const SettingsScript := preload("res://src/autoload/settings.gd")
const SOUND_BACK: StringName = &"ui_back"

## The root page asked to go back: the pause menu resumes, the front end ignores it.
signal closed

## A Callable returning the `ControlProfile` the diagram shows. Unset: the profile in the InputMap right now, so a rebind
## shows at once.
var bindings_source: Callable = Callable()
## A Callable returning the running mission's objectives, `Array[Dictionary]` (`ObjectivesModel`). Unset: none.
var objectives_source: Callable = Callable()
## A Callable returning `Game`'s request, for the right panel when no objective shows. Unset: none.
var request_source: Callable = Callable()
## Plays the menu sounds (`play_ui`). Null: silent.
var audio: AudioDirector = null

var _pages: Array[MenuScreen] = []
var _lit_actions: Array[StringName] = []

@onready var _title: Label = %Title
@onready var _host: VBoxContainer = %Host
@onready var _message: Label = %Message
@onready var _pad: PadDiagram = %PadDiagram
@onready var _objectives: ObjectivesPanel = %Objectives


func _ready() -> void:
	var profiles: Node = get_node_or_null(^"/root/ControlProfiles")
	if profiles != null:
		profiles.applied.connect(_on_profile_applied)
	refresh()


## Replaces every page with `page`, the first of the stack.
func set_root(page: MenuScreen) -> void:
	for old: MenuScreen in _pages:
		_drop(old)
	_pages.clear()
	_show_page(page)


## Puts `page` on top of the current one.
func push_screen(page: MenuScreen) -> void:
	if not _pages.is_empty():
		_pages.back().visible = false
	_show_page(page)


## Leaves the top page for the one under it, with the back sound. Returns false when the top page is the root: then
## `closed` is emitted instead.
func go_back() -> bool:
	_play(SOUND_BACK)
	if _pages.size() <= 1:
		closed.emit()
		return false
	_drop(_pages.pop_back())
	var below: MenuScreen = _pages.back()
	below.visible = true
	_title.text = below.title
	below.restore_focus()
	refresh()
	return true


func current_page() -> MenuScreen:
	return _pages.back() if not _pages.is_empty() else null


func depth() -> int:
	return _pages.size()


## Says something under the options (a start that was refused); empty clears it.
func show_message(text: String) -> void:
	_message.text = text


func message() -> String:
	return _message.text


## Lights the pad parts of these game actions (the controls page: the action in focus).
func highlight_actions(actions: Array[StringName]) -> void:
	_lit_actions = actions.duplicate()
	refresh_legend()


## Redraws the diagram and the right panel from their sources.
func refresh() -> void:
	refresh_legend()
	refresh_panel()


func refresh_legend() -> void:
	if _pad == null:
		return
	var profile: ControlProfile = null
	if bindings_source.is_valid():
		profile = bindings_source.call() as ControlProfile
	if profile == null:
		profile = ControlProfile.from_input_map("active")
	var legend: PadLegend = PadLegend.from_profile(profile)
	_pad.set_legend(legend)
	var lit: Array[StringName] = []
	for action: StringName in _lit_actions:
		for widget: StringName in legend.widgets_for(action):
			if not lit.has(widget):
				lit.append(widget)
	_pad.set_highlight(lit)


func refresh_panel() -> void:
	if _objectives != null:
		_objectives.show_content(right_content())


## What the right panel should say: the page's own content, else the mission's objectives or the run, else nothing.
func right_content() -> Dictionary:
	var page: MenuScreen = current_page()
	var own: Dictionary = page.info() if page != null else {}
	if not own.is_empty():
		return own
	var objectives: Array[Dictionary] = []
	if objectives_source.is_valid():
		objectives.assign(objectives_source.call())
	var request: Dictionary = request_source.call() if request_source.is_valid() else {}
	if objectives.is_empty() and request.is_empty():
		return {"title": "", "lines": []}
	return ObjectivesModel.content(objectives, request)


func pad_diagram() -> PadDiagram:
	return _pad


func objectives_panel() -> ObjectivesPanel:
	return _objectives


func _show_page(page: MenuScreen) -> void:
	_pages.append(page)
	page.back_requested.connect(go_back)
	page.sound_requested.connect(_play)
	page.info_changed.connect(refresh_panel)
	_host.add_child(page)
	_title.text = page.title
	_message.text = ""
	page.focus_first()
	refresh()


func _drop(page: MenuScreen) -> void:
	if is_instance_valid(page):
		_host.remove_child(page)
		page.queue_free()


func _play(sound: StringName) -> void:
	if audio != null:
		audio.play_ui(sound)


func _on_profile_applied(_profile_name: String) -> void:
	refresh_legend()
