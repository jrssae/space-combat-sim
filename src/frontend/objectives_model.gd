class_name ObjectivesModel
extends RefCounted
## What the menu frame's right panel says (architecture §18, D57, Q15): the objectives a running mission reports (hidden ones
## left out, a mark for each state) or, with none, what is being played; or a mission's briefing in the front end. Pure.
##
## An objective is `{id: StringName, text: String, primary: bool, state: StringName}` with state `hidden`, `active`, `done`
## or `failed` (the mission core's `ObjectiveBook.snapshot()`). A panel is `{title: String, lines: Array[Dictionary]}` and a
## line is `{text, mark, state, primary, optional}`.

const MARKS: Dictionary = {&"active": "[ ]", &"done": "[x]", &"failed": "[!]"}
const TITLE_OBJECTIVES: String = "OBJECTIVES"
const TITLE_BRIEFING: String = "BRIEFING"


## The lines for the objectives that are showing, in the order given.
static func lines(objectives: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for objective: Dictionary in objectives:
		var state: StringName = StringName(objective.get("state", &"hidden"))
		if not MARKS.has(state):
			continue
		var primary: bool = bool(objective.get("primary", true))
		var text: String = String(objective.get("text", ""))
		if text.is_empty():
			text = String(objective.get("id", ""))
		out.append(_line(text if primary else "%s (optional)" % text, MARKS[state], state, primary))
	return out


## The right panel in flight: the mission's objectives, or without any showing, the run itself (free flight and whether
## encounters are on, the sandbox's name, or a mission with nothing to report yet).
static func content(objectives: Array[Dictionary], request: Dictionary) -> Dictionary:
	var shown: Array[Dictionary] = lines(objectives)
	if shown.is_empty() and not request.is_empty():
		var scenario: String = String(request.get("scenario_id", "")).replace("_", " ").capitalize()
		match StringName(request.get("kind", &"")):
			&"free_flight":
				shown.append(_plain("Free flight"))
				shown.append(_plain("Encounters: %s" % ("on" if bool(request.get("encounters", false)) else "off")))
			&"sandbox":
				shown.append(_plain("Sandbox: %s" % scenario))
			&"mission":
				shown.append(_plain("Mission: %s" % scenario))
	return {"title": TITLE_OBJECTIVES, "lines": shown}


## The right panel in the front end for a mission picked in the list: its title, then the briefing a paragraph a line.
static func briefing(title: String, text: String) -> Dictionary:
	var shown: Array[Dictionary] = []
	if not title.is_empty():
		shown.append(_plain(title))
	for paragraph: String in text.split("\n", false):
		shown.append(_plain(paragraph))
	return {"title": TITLE_BRIEFING, "lines": shown}


static func _plain(text: String) -> Dictionary:
	return _line(text, "", &"", true)


static func _line(text: String, mark: String, state: StringName, primary: bool) -> Dictionary:
	return {"text": text, "mark": mark, "state": state, "primary": primary, "optional": not primary}
