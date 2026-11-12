class_name SettingsScreen
extends MenuScreen
## The settings page (architecture §18, D57, AC3), opened from the pause menu and the front end inside the `MenuFrame`.
## It is built from `SettingsSchema` through `SettingsMenuModel`: a heading per category, then a switch, a slider or an option
## list per entry; nothing is written here per setting. Entries the schema marks `menu: false` do not appear.
##
## The pad: D-pad up and down walk the rows, left and right change the value in the row, A flips a switch, opens an option
## list and confirms in it, and presses Apply, Revert and Defaults at the top; B goes back. A change applies at once, so a
## volume is heard while it moves, but it stays unsaved (marked `*`) until Apply writes the settings file. Revert drops the
## unsaved changes. Defaults puts every listed setting back to its default (unsaved until Apply). Leaving with B keeps unsaved
## changes for the session; the console's `save` or Apply writes them later.

const SettingsScript := preload("res://src/autoload/settings.gd")
const UNSAVED_MARK: String = " *"
const NAME_MIN_WIDTH: float = 150.0
const SLIDER_WIDTH: float = 190.0
const VALUE_WIDTH: float = 96.0
const CHOICE_WIDTH: float = 190.0
const ACTIONS: Array[Dictionary] = [
	{"id": &"apply", "text": "Apply", "help": "Write the settings to the settings file, so they are kept next time."},
	{"id": &"revert", "text": "Revert", "help": "Drop the changes made since the last Apply and go back to the saved settings."},
	{"id": &"defaults", "text": "Defaults", "help": "Put every setting on this page back to its default. Apply keeps them."},
	{"id": &"back", "text": "Back", "help": "Leave this page. Changes not yet applied stay for this session."},
]

## The settings to edit: the `Settings` autoload, unless a test hands in a scratch one before the page is shown.
var settings: SettingsScript = null
var model := SettingsMenuModel.new()
## The settings group this page edits (`SettingsSchema.GROUPS`), set before the page is shown. Empty: every setting on one page.
var group: StringName = &""

var _controls: Dictionary = {}  # key -> the Control the pad focuses (CheckButton, HSlider or OptionButton)
var _names: Dictionary = {}  # key -> its Label
var _values: Dictionary = {}  # key -> the Label that reads a slider's value
var _actions: Dictionary = {}  # action id -> Button
var _help: Dictionary = {}  # focusable Control -> right-panel content
var _status: Label = null
var _refreshing: bool = false


func _init() -> void:
	title = "Settings"


func _ready() -> void:
	show_pad = false  # the diagram has nothing to say here; the Controls page keeps it
	_apply_group()
	if settings == null:
		settings = get_node_or_null(^"/root/Settings") as SettingsScript
	if settings == null:
		push_error("SettingsScreen: no Settings to edit")
		return
	_build()
	settings.changed.connect(_on_setting_changed)
	refresh_all()


func _exit_tree() -> void:
	if settings != null and settings.changed.is_connected(_on_setting_changed):
		settings.changed.disconnect(_on_setting_changed)


# Titles the page and narrows the model to the group's categories.
func _apply_group() -> void:
	for entry: Dictionary in SettingsSchema.GROUPS:
		if entry["id"] == group:
			title = String(entry["title"])
	var categories: Array[StringName] = SettingsSchema.categories_of_group(group)
	model = SettingsMenuModel.new(null, categories)


# --- What the pad and the tests see ---------------------------------------------------------------------------------


## The keys on the page, in the order the pad walks them.
func listed_keys() -> Array[StringName]:
	return model.visible_keys()


## The control that shows `key`, or null when the page does not list it.
func control_of(key: StringName) -> Control:
	return _controls.get(key)


func action_button(id: StringName) -> Button:
	return _actions.get(id)


## The setting whose row has the focus, or "" when the focus is on one of the buttons.
func focused_key() -> StringName:
	var holder: Control = focused_option()
	for key: StringName in _controls:
		if _controls[key] == holder:
			return key
	return &""


## What the line under the buttons says.
func status() -> String:
	return _status.text if _status != null else ""


## The row's name as shown, with the mark when it is unsaved.
func row_text(key: StringName) -> String:
	return (_names[key] as Label).text if _names.has(key) else ""


## The text a slider shows next to it, or a switch or list shows on it.
func value_text(key: StringName) -> String:
	var control: Control = _controls.get(key)
	if control is HSlider:
		return (_values[key] as Label).text
	if control is OptionButton:
		return (control as OptionButton).text
	return (control as Button).text if control != null else ""


## The right panel shows what the focused setting is for, or what the focused button does.
func info() -> Dictionary:
	var holder: Control = focused_option()
	return _help.get(holder, {})


## The first setting takes the focus, so the pad's first press already acts on it; Apply is one press up.
func focus_first() -> void:
	var first: Control = _controls.get(listed_keys()[0]) if not _controls.is_empty() else null
	if first != null:
		_grab_silently(first)
	else:
		super.focus_first()


# --- Building --------------------------------------------------------------------------------------------------------


func _build() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	for entry: Dictionary in ACTIONS:
		_add_action(bar, entry)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	for section: Dictionary in model.sections():
		var heading := Label.new()
		heading.text = String(section["title"]).to_upper()
		heading.theme_type_variation = &"Heading"
		add_child(heading)
		for row: Dictionary in section["rows"]:
			_add_row(row)
	_link_focus()


func _add_action(bar: HBoxContainer, entry: Dictionary) -> void:
	var button := Button.new()
	button.text = String(entry["text"])
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id: StringName = entry["id"]
	button.pressed.connect(func() -> void:
		sound_requested.emit(SOUND_ACCEPT)
		_run_action(id))
	button.focus_entered.connect(_on_option_focused.bind(button))
	bar.add_child(button)
	_actions[id] = button
	_help[button] = _panel(String(entry["text"]), String(entry["help"]))


func _add_row(row: Dictionary) -> void:
	var key: StringName = row["key"]
	var line := HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 16)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size.x = NAME_MIN_WIDTH
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(name_label)
	_names[key] = name_label
	var control: Control
	match row["kind"]:
		SettingsMenuModel.KIND_TOGGLE:
			control = _make_toggle(key, line)
		SettingsMenuModel.KIND_SLIDER:
			control = _make_slider(key, row, line)
		_:
			control = _make_choice(key, row, line)
	control.gui_input.connect(_on_control_input.bind(key))
	control.focus_entered.connect(_on_option_focused.bind(control))
	_controls[key] = control
	_help[control] = _panel(String(row["label"]), model.help_text(key))
	add_child(line)


func _make_toggle(key: StringName, line: HBoxContainer) -> Control:
	var check := CheckButton.new()
	check.custom_minimum_size.x = CHOICE_WIDTH
	check.toggled.connect(func(on: bool) -> void:
		if not _refreshing:
			sound_requested.emit(SOUND_ACCEPT)
			_commit(key, on))
	line.add_child(check)
	return check


func _make_slider(key: StringName, row: Dictionary, line: HBoxContainer) -> Control:
	var slider := HSlider.new()
	slider.min_value = float(row["min"])
	slider.max_value = float(row["max"])
	slider.step = float(row["step"])
	slider.scrollable = false  # the wheel scrolls the list, it does not move a setting
	slider.custom_minimum_size.x = SLIDER_WIDTH
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void:
		if not _refreshing:  # the mouse; the pad steps through `_nudge`
			_commit(key, _clean(key, value)))
	line.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = VALUE_WIDTH
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(value_label)
	_values[key] = value_label
	return slider


func _make_choice(key: StringName, row: Dictionary, line: HBoxContainer) -> Control:
	var list := OptionButton.new()
	list.custom_minimum_size.x = CHOICE_WIDTH
	for choice: StringName in row["choices"]:
		list.add_item(model.format_value(key, choice))
	list.item_selected.connect(func(index: int) -> void:
		if not _refreshing:
			sound_requested.emit(SOUND_ACCEPT)
			_commit(key, (row["choices"] as Array)[index]))
	line.add_child(list)
	return list


# Up and down walk the rows in the order they are listed whatever the layout; the buttons sit one press above the first row.
func _link_focus() -> void:
	var rows: Array[Control] = []
	for key: StringName in listed_keys():
		rows.append(_controls[key])
	var bar: Array[Button] = []
	for entry: Dictionary in ACTIONS:
		bar.append(_actions[entry["id"]])
	for i: int in bar.size():
		var button: Button = bar[i]
		button.focus_neighbor_left = button.get_path_to(bar[maxi(i - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(bar[mini(i + 1, bar.size() - 1)])
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(rows[0])
	for i: int in rows.size():
		var control: Control = rows[i]
		control.focus_neighbor_top = control.get_path_to(rows[i - 1] if i > 0 else bar[0])
		control.focus_neighbor_bottom = control.get_path_to(rows[mini(i + 1, rows.size() - 1)])


# --- Changing --------------------------------------------------------------------------------------------------------


## Puts every row (and the marks) on what `Settings` holds now.
func refresh_all() -> void:
	for key: StringName in _controls:
		_refresh(key)
	_set_status("")


func _refresh(key: StringName) -> void:
	var control: Control = _controls.get(key)
	if control == null:
		return
	var value: Variant = settings.get_value(key)
	_refreshing = true
	if control is CheckButton:
		(control as CheckButton).set_pressed_no_signal(bool(value))
		(control as CheckButton).text = model.format_value(key, value)
	elif control is HSlider:
		(control as HSlider).set_value_no_signal(float(value))
		(_values[key] as Label).text = model.format_value(key, value)
	elif control is OptionButton:
		(control as OptionButton).select(settings.schema.get_choices(key).find(StringName(value)))
	_refreshing = false
	var label: String = settings.schema.label_of(key)
	(_names[key] as Label).text = label + (UNSAVED_MARK if settings.is_unsaved(key) else "")


# One D-pad press on a row.
func _nudge(key: StringName, direction: int) -> void:
	var current: Variant = settings.get_value(key)
	var next: Variant = model.next_value(key, current, direction)
	if next == current:
		return
	sound_requested.emit(SOUND_MOVE)
	_commit(key, next)


# Every change the player makes goes through here: Settings checks it, applies it and marks it unsaved.
func _commit(key: StringName, value: Variant) -> void:
	if settings.set_value(key, value) != OK:
		_set_status(settings.get_last_error())
	else:
		_set_status("")
	_refresh(key)
	info_changed.emit()


func _on_control_input(event: InputEvent, key: StringName) -> void:
	var direction: int = 0
	if event.is_action_pressed(&"ui_left", true):
		direction = -1
	elif event.is_action_pressed(&"ui_right", true):
		direction = 1
	if direction == 0:
		return
	(_controls[key] as Control).accept_event()
	_nudge(key, direction)


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	_refresh(key)
	if _status != null and _status.text.is_empty():
		_set_status("")


func _run_action(id: StringName) -> void:
	match id:
		&"apply":
			var err: Error = settings.save()
			_set_status("Saved." if err == OK else settings.get_last_error(), true)
			_refresh_marks()
		&"revert":
			settings.revert()
			refresh_all()
			_set_status("Back to the saved settings.", true)
		&"defaults":
			for key: StringName in listed_keys():
				settings.reset(key)
			refresh_all()
			_set_status("Defaults restored. Apply keeps them.", true)
		&"back":
			back_requested.emit()


func _refresh_marks() -> void:
	for key: StringName in _controls:
		_refresh(key)


# The line under the buttons: what an action just did, else a reminder while there is something unsaved.
func _set_status(text: String, keep: bool = false) -> void:
	if _status == null:
		return
	if text.is_empty() and not keep and settings != null and settings.has_unsaved():
		text = "Unsaved changes: Apply keeps them."
	_status.text = text


# A value from a slider with the float noise taken off, as a whole number for an int setting.
func _clean(key: StringName, value: float) -> Variant:
	var entry: Dictionary = settings.schema.get_entry(key)
	var clean: float = clampf(snappedf(value, 1e-9), float(entry["min"]), float(entry["max"]))
	return roundi(clean) if settings.schema.get_type(key) == TYPE_INT else clean


func _panel(heading: String, text: String) -> Dictionary:
	var content: Dictionary = ObjectivesModel.briefing(heading, text)
	content["title"] = "SETTING"
	return content
