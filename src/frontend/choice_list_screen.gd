class_name ChoiceListScreen
extends MenuScreen
## A page that is a plain list of choices (architecture §18, D57): the front end's main menu, the pause menu, the mission and
## sandbox lists. Choosing one emits `chosen` with its id; the host decides what it means. An entry can carry the right
## panel's content (a mission's briefing), shown while that entry has the focus.

signal chosen(id: StringName)

var _info: Dictionary = {}  # id -> panel content (ObjectivesModel shape)
var _buttons: Dictionary = {}  # id -> Button


## Fills the page. Each entry is `{id: StringName, text: String}` with optional `enabled: bool` and `info: Dictionary`.
func setup(page_title: String, entries: Array[Dictionary]) -> void:
	title = page_title
	for entry: Dictionary in entries:
		var id: StringName = entry["id"]
		var button: Button = add_option(String(entry["text"]), func() -> void: chosen.emit(id), bool(entry.get("enabled", true)))
		_buttons[id] = button
		if entry.has("info"):
			_info[id] = entry["info"]


## The right panel's content for the focused entry, or empty when it has none.
func info() -> Dictionary:
	var focused: Control = focused_option()
	for id: StringName in _buttons:
		if _buttons[id] == focused:
			return _info.get(id, {})
	return {}


func option_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_buttons.keys())
	return out


func button_of(id: StringName) -> Button:
	return _buttons.get(id)
