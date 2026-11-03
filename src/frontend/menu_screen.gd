class_name MenuScreen
extends VBoxContainer
## One page of a menu (architecture §18, D57): a column of options the D-pad and left stick walk through (Godot's `ui_*`
## focus), A accepts and B (or Esc) asks to go back. Menus are UI, so they use `ui_*` and never the game's actions.
##
## A page never plays sound or changes screens itself: it asks. `sound_requested` for the move/accept sounds, `back_requested`
## for B, and `info_changed` when the frame's right panel may need new content. The `MenuFrame` that holds the page answers.

signal back_requested
signal sound_requested(sound: StringName)
signal info_changed

const SOUND_MOVE: StringName = &"ui_move"
const SOUND_ACCEPT: StringName = &"ui_accept"

## Shown above the options.
var title: String = ""
## The pause menu sets this: there Esc is the `pause` action, which `Main` hands to the menu as one edge, so the page must
## not also act on the key or one press would go back twice.
var cancel_ignores_keys: bool = false

var _last_focus: Control = null
var _silent: bool = false


## Adds a button the pad can focus. `on_accept` runs when it is pressed (A, Enter or a click).
func add_option(text: String, on_accept: Callable, enabled: bool = true, accept_sound: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		if accept_sound:
			sound_requested.emit(SOUND_ACCEPT)
		on_accept.call())
	button.focus_entered.connect(_on_option_focused.bind(button))
	add_child(button)
	return button


## The last option of a page that can be left, for the mouse (the pad has B). The frame plays the back sound.
func add_back_option() -> Button:
	return add_option("Back", func() -> void: back_requested.emit(), true, false)


## Puts the focus on the first option without a move sound (the page has only just been shown).
func focus_first() -> void:
	var first: Control = _first_focusable(self)
	if first != null:
		_grab_silently(first)


## Gives the focus back to the option that had it when the page was hidden, or the first one.
func restore_focus() -> void:
	if _last_focus != null and is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree() \
			and _last_focus.focus_mode != Control.FOCUS_NONE:
		_grab_silently(_last_focus)
	else:
		focus_first()


## The right panel's content while this page is up (`ObjectivesModel` shape), or empty for the frame's own.
func info() -> Dictionary:
	return {}


## The option that has the focus now, or null when it is elsewhere.
func focused_option() -> Control:
	var holder: Control = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return holder if holder != null and is_ancestor_of(holder) else null


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or event.is_echo():
		return
	if _is_navigation(event) and get_viewport().gui_get_focus_owner() == null:
		# Focus is nowhere (a click on empty space, a page that came back empty): the pad takes the first option.
		get_viewport().set_input_as_handled()
		focus_first()
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if cancel_ignores_keys and event is InputEventKey:
		return
	var holder: Control = get_viewport().gui_get_focus_owner()
	if holder != null and not is_ancestor_of(holder):
		return  # the console, or another page, has the keyboard
	get_viewport().set_input_as_handled()
	back_requested.emit()


func _is_navigation(event: InputEvent) -> bool:
	for action: StringName in [&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_accept"]:
		if event.is_action_pressed(action):
			return true
	return false


func _on_option_focused(option: Control) -> void:
	_last_focus = option
	if not _silent:
		sound_requested.emit(SOUND_MOVE)
	info_changed.emit()


func _grab_silently(control: Control) -> void:
	_silent = true
	control.grab_focus()
	_silent = false


func _first_focusable(node: Node) -> Control:
	for child: Node in node.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		if control.focus_mode != Control.FOCUS_NONE:
			return control
		var deeper: Control = _first_focusable(control)
		if deeper != null:
			return deeper
	return null
