class_name SettingsMenuModel
extends RefCounted
## What the settings screen lists and how a press changes it (architecture §18, D57). Everything comes from `SettingsSchema`:
## the entries grouped by category with the console-only ones left out, a control kind for each type, the step a D-pad press
## moves a value and the text a value reads as. The screen only draws it. Pure.

const KIND_TOGGLE: StringName = &"toggle"
const KIND_SLIDER: StringName = &"slider"
const KIND_CHOICE: StringName = &"choice"
const CATEGORY_TITLES: Dictionary[StringName, String] = {
	&"flight": "Flight", &"controls": "Controls", &"camera": "Camera", &"hud": "HUD",
	&"graphics": "Graphics", &"audio": "Audio", &"game": "Game"}

var schema: SettingsSchema
## The categories this model lists, in the order given; empty lists every category in `SettingsSchema.CATEGORIES` order.
## A settings group page passes its group's categories (`SettingsSchema.GROUPS`).
var only: Array[StringName] = []


func _init(p_schema: SettingsSchema = null, p_only: Array[StringName] = []) -> void:
	schema = p_schema if p_schema != null else SettingsSchema.new()
	only = p_only


## The categories that have a menu entry: `{category, title, rows}` in the model's order.
func sections() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for category: StringName in (only if not only.is_empty() else SettingsSchema.CATEGORIES):
		var rows: Array[Dictionary] = []
		for key: StringName in schema.menu_keys(category):
			rows.append(row(key))
		if not rows.is_empty():
			out.append({"category": category, "title": CATEGORY_TITLES.get(category, String(category).capitalize()), "rows": rows})
	return out


## Every key the menu lists, in the order it lists them.
func visible_keys() -> Array[StringName]:
	var out: Array[StringName] = []
	for section: Dictionary in sections():
		for entry: Dictionary in section["rows"]:
			out.append(entry["key"])
	return out


## One row: its key, label, control kind, default, doc, and the range, step and choices that apply to its kind.
func row(key: StringName) -> Dictionary:
	var entry: Dictionary = schema.get_entry(key)
	var out: Dictionary = {"key": key, "label": schema.label_of(key), "kind": kind_of(key),
			"default": schema.get_default(key), "doc": String(entry.get("doc", "")), "percent": bool(entry.get("percent", false))}
	match out["kind"]:
		KIND_SLIDER:
			out["min"] = entry["min"]
			out["max"] = entry["max"]
			out["step"] = schema.step_of(key)
		KIND_CHOICE:
			out["choices"] = schema.get_choices(key)
	return out


## The control a setting gets: a switch for a bool, a slider for a number, an option list for a choice. Text has none.
func kind_of(key: StringName) -> StringName:
	match schema.get_type(key):
		TYPE_BOOL:
			return KIND_TOGGLE
		TYPE_FLOAT, TYPE_INT:
			return KIND_SLIDER
		SettingsSchema.TYPE_ENUM:
			return KIND_CHOICE
	return &""


## The value after one D-pad press, `direction` -1 (left) or +1 (right): a switch goes off or on, a number moves one step and
## stops at its ends, a choice goes to the next or previous and wraps.
func next_value(key: StringName, current: Variant, direction: int) -> Variant:
	var sign: int = 1 if direction > 0 else -1
	match kind_of(key):
		KIND_TOGGLE:
			return sign > 0
		KIND_SLIDER:
			return _stepped(key, float(current), sign)
		KIND_CHOICE:
			var choices: Array = schema.get_choices(key)
			var at: int = choices.find(StringName(current))
			return choices[posmod(at + sign, choices.size())]
	return current


## A switch's opposite, for A.
func flipped(_key: StringName, current: Variant) -> bool:
	return not bool(current)


## How a value reads on its row: On and Off, a capitalised choice, a percentage or a plain number.
func format_value(key: StringName, value: Variant) -> String:
	match kind_of(key):
		KIND_TOGGLE:
			return "On" if bool(value) else "Off"
		KIND_CHOICE:
			return String(value).capitalize()
	var entry: Dictionary = schema.get_entry(key)
	if bool(entry.get("percent", false)):
		return "%d%%" % roundi(float(value) * 100.0)
	if schema.get_type(key) == TYPE_INT:
		return _grouped(int(value))
	return _plain(float(value))


## What the right panel says about a setting: its doc without task ids, then its default and range.
func help_text(key: StringName) -> String:
	var lines: PackedStringArray = [_without_task_ids(String(schema.get_entry(key).get("doc", "")))]
	lines.append("Default: %s" % format_value(key, schema.get_default(key)))
	if kind_of(key) == KIND_SLIDER:
		var entry: Dictionary = schema.get_entry(key)
		lines.append("Range: %s to %s" % [format_value(key, entry["min"]), format_value(key, entry["max"])])
	return "\n".join(lines)


# One step from `current` on the grid that starts at the range's minimum, so repeated presses never drift and a value set
# off the grid (the console) lands on it. Ints stay ints.
func _stepped(key: StringName, current: float, sign: int) -> Variant:
	var entry: Dictionary = schema.get_entry(key)
	var low: float = float(entry["min"])
	var high: float = float(entry["max"])
	var step: float = schema.step_of(key)
	var position: float = (current - low) / step
	if absf(position - roundf(position)) < 1e-6:
		position = roundf(position)
	var target: float = (floorf(position) + 1.0) if sign > 0 else (ceilf(position) - 1.0)
	var value: float = clampf(snappedf(low + target * step, 1e-9), low, high)
	if schema.get_type(key) == TYPE_INT:
		return roundi(value)
	return value


static func _plain(value: float) -> String:
	var text: String = "%.3f" % value
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text


static func _grouped(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


# The docs are written for the console and cite the task that added the setting; the player has no use for that.
static func _without_task_ids(text: String) -> String:
	# A task id alone in brackets goes with its brackets; one sharing them with other words ("(M4-T30a, live)") goes alone.
	var alone := RegEx.create_from_string(" ?\\(M\\d+-T\\d+[a-z]?\\)")
	var leading := RegEx.create_from_string("M\\d+-T\\d+[a-z]?[,;:] ")
	var trailing := RegEx.create_from_string("[,;] M\\d+-T\\d+[a-z]?")
	return trailing.sub(leading.sub(alone.sub(text, "", true), "", true), "", true)
