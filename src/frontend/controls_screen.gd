class_name ControlsScreen
extends MenuScreen
## The Controls page (architecture §18, D57, Q15; M5-T04), in the options panel of a `MenuFrame`: pick a profile, list every game
## action with its bindings, add, replace or unbind one by pressing a button or key, and save the layout under a new name.
## `ControlProfiles` does the validating and the applying; a refusal is shown with its reason, never swallowed. The diagram in
## the frame follows at once, because every change comes back through `ControlProfiles.applied`.
##
## The page has four views of its own (the list, the profile picker, one action, save as), so B steps back inside the page
## (`back_step`) before the frame leaves it.
##
## While it waits for a press (`BindingCapture`) the page swallows every pad, key and mouse-button event in `_input`, ahead of
## the GUI and of the pages' `_unhandled_input`, so the press cannot navigate or accept. In flight the same press is also the
## `pause` action, which `Main` hands to the menu a tick later through `go_back`: `back_step` refuses it for `GRACE_S` after
## the wait ends. Only the `InputAdapter.ACTIONS` are listed or changed, so the `ui_*` actions the menus use are never touched.

const ControlProfilesScript := preload("res://src/autoload/control_profiles.gd")

## After a press ended the wait, the frame is still held in place this long (see above).
const GRACE_S: float = 0.35
const ERROR_COLOR: Color = Color(1.0, 0.55, 0.4)
const NAME_MAX_LENGTH: int = 32  # ControlProfile.NAME_PATTERN
const KEY_PROFILE: StringName = &"@profile"
const KEY_SAVE: StringName = &"@save"
const KEY_SETTINGS: StringName = &"@settings"

enum View { LIST, PROFILES, ACTION, SAVE_AS }

var profiles: ControlProfilesScript = null  ## null: /root/ControlProfiles
## Keep the profile in use for the next start after choosing or saving one (writes the settings file).
var persist: bool = true

var _view: View = View.LIST
var _action: StringName = &""
var _replacing: String = ""  # the binding a capture will replace, "" when it adds one
var _capture := BindingCapture.new()
var _prompt: String = ""
var _shown_hint: String = ""
var _grace_s: float = 0.0
var _applying: bool = false  # our own change is going through: the `applied` signal is not news
var _rows: Dictionary = {}  # Button -> the action it concerns, or KEY_PROFILE / KEY_SAVE
var _name_edit: LineEdit = null

@onready var _heading: Label = %Heading
@onready var _status: Label = %Status


func _init() -> void:
	title = "Controls"


func _ready() -> void:
	set_process(false)
	set_process_input(false)
	if profiles == null:
		profiles = get_node_or_null(^"/root/ControlProfiles") as ControlProfilesScript
	if profiles == null:
		push_error("ControlsScreen: no ControlProfiles autoload; nothing can be changed")
		_say("The controls cannot be changed: no ControlProfiles.", true)
		add_back_option()
		return
	profiles.applied.connect(_on_applied)
	_show_list()


func _exit_tree() -> void:
	_capture.cancel()
	if profiles != null and profiles.applied.is_connected(_on_applied):
		profiles.applied.disconnect(_on_applied)


# --- State for the frame and the tests ---------------------------------------------------------------------------


func current_view() -> View:
	return _view


## True while the page waits for a press to bind.
func is_capturing() -> bool:
	return _capture.is_waiting()


func status() -> String:
	return _status.text


func name_edit() -> LineEdit:
	return _name_edit


## The right panel shows the bindings of the action in focus; elsewhere the frame's own content (the objectives) stays.
func info() -> Dictionary:
	var key: StringName = _focused_key()
	if profiles == null or not InputAdapter.ACTIONS.has(key):
		return {}
	return ControlsModel.action_panel(_live(), key)


## Time for the wait: a held B or Esc cancels it and silence ends it. Called every frame by `_process`.
func advance(delta: float) -> void:
	if _capture.is_waiting():
		_capture.advance(delta)
		if not _capture.is_waiting():
			_finish_capture()
	elif _grace_s > 0.0:
		_grace_s -= delta
	if not _capture.is_waiting() and _grace_s <= 0.0:
		set_process(false)


## B, or the pause action in flight: step back inside the page, or let the frame leave it. Never while a press is awaited.
func back_step() -> bool:
	if _capture.is_waiting() or _grace_s > 0.0:
		return true
	if _view == View.LIST:
		return false
	sound_requested.emit(MenuFrame.SOUND_BACK)
	_say("")
	_show_list(_action if _view == View.ACTION else (KEY_SAVE if _view == View.SAVE_AS else KEY_PROFILE))
	return true


func _process(delta: float) -> void:
	advance(delta)


func _input(event: InputEvent) -> void:
	if not _capture.is_waiting():
		return
	if _capture.feed(event):
		get_viewport().set_input_as_handled()
	if not _capture.is_waiting():
		_finish_capture()
	elif _capture.hint != _shown_hint:
		_shown_hint = _capture.hint
		_say("%s\n%s" % [_prompt, _shown_hint])


# --- Views ---------------------------------------------------------------------------------------------------------


func _begin_view(view: View, heading: String) -> void:
	_view = view
	for child: Node in get_children():
		if child != _heading and child != _status:
			remove_child(child)
			child.queue_free()
	_rows.clear()
	_name_edit = null
	_heading.text = heading
	_heading.visible = not heading.is_empty()


# A row the pad can focus; `key` is the action it concerns (the diagram lights its buttons while the row has the focus).
func _row(text: String, on_accept: Callable, key: StringName = &"") -> Button:
	var button: Button = add_option(text, on_accept)
	_rows[button] = key
	button.focus_entered.connect(func() -> void:
		var lit: Array[StringName] = []
		if InputAdapter.ACTIONS.has(key):
			lit.append(key)
		highlight_requested.emit(lit))
	return button


func _show_list(focus_key: StringName = &"") -> void:
	_begin_view(View.LIST, "")
	var live: ControlProfile = _live()
	_row(ControlsModel.profile_row_text(profiles.active_name, profiles.is_unsaved()), _show_profiles, KEY_PROFILE)
	for action: StringName in InputAdapter.ACTIONS:
		_row(ControlsModel.row_text(live, action), _open_action.bind(action), action)
	_row("Save as a new profile...", _show_save_as, KEY_SAVE)
	_row("Sensitivity and deadzones...", _open_settings, KEY_SETTINGS)
	add_back_option()
	_focus_key(focus_key)


# The `controls` settings (invert pitch, deadzones, hold time, mouse speeds) open over this page (M5-T45).
func _open_settings() -> void:
	push_requested.emit(MenuScreens.settings_screen(&"controls"))


func _show_profiles() -> void:
	_say("")
	_begin_view(View.PROFILES, "Choose a profile")
	for entry: Dictionary in profiles.store.entries():
		var profile_name: String = entry["name"]
		var text: String = "%s%s" % ["* " if profile_name == profiles.active_name else "", profile_name]
		var errors: PackedStringArray = entry["errors"]
		var detail: String = String(entry["description"]) if entry["valid"] else "INVALID: %s" % errors[0]
		if not detail.is_empty():
			text += " - " + detail
		_row(text, _pick_profile.bind(profile_name), StringName("@" + profile_name))
	add_back_option()
	_focus_key(StringName("@" + profiles.active_name))


func _open_action(action: StringName) -> void:
	_say("")
	_show_action(action)


func _show_action(action: StringName) -> void:
	_action = action
	_begin_view(View.ACTION, ControlsModel.action_title(action))
	_row("Add a binding: press a button or key", _begin_capture.bind(""), action)
	for descriptor: String in _live().descriptors_for(action):
		var named: String = ControlsModel.binding_text(descriptor)
		_row("Replace %s" % named, _begin_capture.bind(descriptor), action)
		_row("Unbind %s" % named, _unbind.bind(descriptor), action)
	add_back_option()
	focus_first()


func _show_save_as() -> void:
	_say("")
	_begin_view(View.SAVE_AS, "Save as a new profile")
	_name_edit = LineEdit.new()
	_name_edit.max_length = NAME_MAX_LENGTH
	_name_edit.placeholder_text = "profile name"
	_name_edit.text = ControlsModel.suggested_name(profiles.active_name, profiles.store.builtin_names(), profiles.store.names())
	_name_edit.text_submitted.connect(func(_text: String) -> void: _save())
	add_child(_name_edit)
	_row("Save", _save, KEY_SAVE)
	add_back_option()
	_focus_key(KEY_SAVE)  # the pad's A saves under the suggested name; the keyboard can edit it first


# --- Changes -------------------------------------------------------------------------------------------------------


func _pick_profile(profile_name: String) -> void:
	_applying = true
	var outcome: Dictionary = profiles.use(profile_name)
	_applying = false
	if not outcome["ok"]:
		_say(ControlsModel.refusal_text(outcome["errors"]), true)
		return
	var text: String = "Using %s." % profile_name
	if outcome["discarded"]:
		text += " Your unsaved changes were dropped."
	if not profiles.last_notice.is_empty():
		text += "\n" + profiles.last_notice
	var problem: String = _keep_choice()
	_show_list(KEY_PROFILE)
	_say(text if problem.is_empty() else text + "\n" + problem, not problem.is_empty())


func _unbind(descriptor: String) -> void:
	_applying = true
	var outcome: Dictionary = profiles.unbind(_action, descriptor)
	_applying = false
	if not outcome["ok"]:
		_say(ControlsModel.refusal_text(outcome["errors"]), true)
		return
	_show_action(_action)
	_say(("Unbound %s from %s. %s" % [ControlsModel.binding_text(descriptor), ControlsModel.action_title(_action),
			_unsaved_note()]).strip_edges())


func _begin_capture(replacing: String) -> void:
	_replacing = replacing
	_capture.start()
	_shown_hint = ""
	_prompt = "Press a button or key for %s.\nHold B or Esc to cancel; it gives up after %d seconds." % [
			ControlsModel.action_title(_action), int(BindingCapture.TIMEOUT_S)]
	set_process(true)
	set_process_input(true)
	_say(_prompt)


func _finish_capture() -> void:
	set_process_input(false)
	_grace_s = GRACE_S
	var replacing: String = _replacing
	_replacing = ""
	match _capture.state:
		BindingCapture.State.CAPTURED:
			_bind_captured(_capture.descriptor, replacing)
		BindingCapture.State.TIMED_OUT:
			_say("No press: nothing changed.")
		_:
			_say("Cancelled: nothing changed.")


func _bind_captured(descriptor: String, replacing: String) -> void:
	_applying = true
	var outcome: Dictionary = profiles.bind(_action, descriptor)
	var removal: Dictionary = {"ok": true, "errors": PackedStringArray()}
	if outcome["ok"] and not replacing.is_empty() and outcome["descriptor"] != replacing:
		removal = profiles.unbind(_action, replacing)
	_applying = false
	if not outcome["ok"]:
		_say(ControlsModel.refusal_text(outcome["errors"]), true)
		return
	var named: String = ControlsModel.binding_text(outcome["descriptor"])
	var title: String = ControlsModel.action_title(_action)
	var failed: bool = not removal["ok"]
	var replaced_old: bool = not replacing.is_empty() and outcome["descriptor"] != replacing and not failed
	var lines := PackedStringArray()
	if replaced_old:
		lines.append("%s replaces %s on %s." % [named, ControlsModel.binding_text(replacing), title])
	elif not outcome["changed"]:
		lines.append("%s was already bound to %s." % [named, title])
	else:
		lines.append("%s bound to %s." % [named, title])
	if failed:
		var errors: PackedStringArray = removal["errors"]
		lines.append("%s stays: %s" % [ControlsModel.binding_text(replacing), errors[0]])
	var also: PackedStringArray = outcome["also"]
	if not also.is_empty():
		var titles := PackedStringArray()
		for other: String in also:
			titles.append(ControlsModel.action_title(StringName(other)))
		lines.append("%s is also bound to %s." % [named, ", ".join(titles)])
	if outcome["changed"] or replaced_old:
		lines.append(_unsaved_note())
	_show_action(_action)
	_say("\n".join(lines), failed)


func _save() -> void:
	var wanted: String = ControlsModel.clean_name(_name_edit.text)
	var replaced: bool = profiles.store.user_names().has(wanted)
	_applying = true
	var errors: PackedStringArray = profiles.save_as(wanted)
	_applying = false
	if not errors.is_empty():
		_say(ControlsModel.refusal_text(errors), true)
		return
	var problem: String = _keep_choice()
	_show_list(KEY_SAVE)
	var text: String = "Saved %s%s and using it." % [wanted, " (replaced the old one)" if replaced else ""]
	_say(text if problem.is_empty() else text + "\n" + problem, not problem.is_empty())


# Writes the settings file so the profile in use starts the next run; returns what went wrong, "" when nothing did.
func _keep_choice() -> String:
	if not persist or profiles.settings == null:
		return ""
	return "" if profiles.settings.save() == OK else profiles.settings.get_last_error()


# A change nobody saved is lost when another profile is chosen.
func _unsaved_note() -> String:
	return "Not saved yet: Save as keeps it." if profiles.is_unsaved() else ""


func _on_applied(_profile_name: String) -> void:
	if _applying:
		return
	match _view:
		View.LIST:
			_show_list(_focused_key())
		View.ACTION:
			_show_action(_action)
		View.PROFILES:
			_show_profiles()


# --- Helpers -------------------------------------------------------------------------------------------------------


func _live() -> ControlProfile:
	return ControlProfile.from_input_map(profiles.active_name)


func _say(text: String, refused: bool = false) -> void:
	_status.text = text
	_status.visible = not text.is_empty()
	_status.add_theme_color_override(&"font_color", ERROR_COLOR if refused else Color(0.55, 1.0, 0.65))
	info_changed.emit()


func _focused_key() -> StringName:
	return _rows.get(focused_option(), &"")


func _focus_key(key: StringName) -> void:
	for button: Button in _rows:
		if _rows[button] == key:
			_grab_silently(button)
			return
	focus_first()
