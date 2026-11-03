class_name DebriefModel
extends RefCounted
## What the debrief says (architecture §18, D56, AC9), built from the result of a finished mission: success or failure and why,
## every objective and its state, the mission time (sim time), the player's kills and assists, the wing losses, and the shots
## fired and hit. Pure: `DebriefScreen` draws `panel()`, the `debrief` console provider reads `summary()`.
##
## The result is `MissionApi.result` (`success`, `reason`, `scenario_id`, `title`, `objectives` as `ObjectiveBook.snapshot()`,
## `time_s`) plus the player's counters, which `DebriefRecorder` adds (`kills`, `assists`, `wing_losses`, `shots_fired`,
## `shots_hit`). A key the result lacks reads as 0 or empty.

const HEADLINE_SUCCESS: String = "MISSION COMPLETE"
const HEADLINE_FAILURE: String = "MISSION FAILED"
const PANEL_TITLE: String = "DEBRIEF"
## How `MissionApi` words a failure caused by a primary objective; the id after it becomes the objective's text.
const OBJECTIVE_FAILED_PREFIX: String = "objective failed: "

const MARKS: Dictionary = {&"done": "[x]", &"failed": "[!]", &"active": "[ ]", &"hidden": "[-]"}
const STATE_TEXTS: Dictionary = {&"done": "done", &"failed": "failed", &"active": "not finished", &"hidden": "not reached"}

var success: bool = false
var reason: String = ""
var scenario_id: StringName = &""
var title: String = ""
## One row per objective, in the order the mission declared them: `{id, text, primary, state, state_text}`.
var objectives: Array[Dictionary] = []
var time_s: float = 0.0
var kills: int = 0
var assists: int = 0
var wing_losses: int = 0
var shots_fired: int = 0
var shots_hit: int = 0


## The model for `result`, or null for an empty one (nothing ended, so there is nothing to debrief).
static func from_result(result: Dictionary) -> DebriefModel:
	if result.is_empty():
		return null
	var model := DebriefModel.new()
	model.success = bool(result.get("success", false))
	model.reason = str(result.get("reason", ""))
	model.scenario_id = StringName(str(result.get("scenario_id", "")))
	model.title = str(result.get("title", ""))
	model.time_s = float(result.get("time_s", 0.0))
	model.kills = int(result.get("kills", 0))
	model.assists = int(result.get("assists", 0))
	model.wing_losses = int(result.get("wing_losses", 0))
	model.shots_fired = int(result.get("shots_fired", 0))
	model.shots_hit = int(result.get("shots_hit", 0))
	for raw: Variant in result.get("objectives", []):
		var entry: Dictionary = raw as Dictionary
		var state := StringName(str(entry.get("state", &"hidden")))
		var text: String = str(entry.get("text", ""))
		model.objectives.append({"id": StringName(str(entry.get("id", ""))), "text": text if not text.is_empty() else str(entry.get("id", "")),
				"primary": bool(entry.get("primary", true)), "state": state, "state_text": STATE_TEXTS.get(state, str(state))})
	return model


func headline() -> String:
	return HEADLINE_SUCCESS if success else HEADLINE_FAILURE


## The verdict and why: `Failure - Player destroyed`, `Success - Every primary objective done`.
func result_text() -> String:
	var verdict: String = "Success" if success else "Failure"
	var why: String = _reason_text()
	return verdict if why.is_empty() else "%s - %s" % [verdict, why]


## Hits over shots, 0 to 1; 0 with no shots.
func accuracy() -> float:
	return clampf(float(shots_hit) / float(shots_fired), 0.0, 1.0) if shots_fired > 0 else 0.0


func accuracy_text() -> String:
	return "%d%%" % roundi(accuracy() * 100.0) if shots_fired > 0 else "no shots fired"


## Minutes and seconds (`4:12`), with hours past the hour; whole seconds, rounded down.
static func format_time(seconds: float) -> String:
	var total: int = maxi(floori(seconds), 0)
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	return "%d:%02d:%02d" % [hours, minutes, secs] if hours > 0 else "%d:%02d" % [minutes, secs]


## The right panel (`ObjectivesModel`'s shape: `{title, lines}`, a line is `{text, mark, state, primary, optional}`; `compact`
## asks for small lines, as a debrief has many): the mission, the verdict, each objective with its mark, then the time, the
## kills and assists, the wing losses and the shots.
func panel() -> Dictionary:
	var lines: Array[Dictionary] = []
	if not title.is_empty():
		lines.append(_line(title, "", &"", true))
	lines.append(_line(result_text(), "", &"done" if success else &"failed", true))
	for row: Dictionary in objectives:
		lines.append(_objective_line(row))
	lines.append(_line("Time: %s" % format_time(time_s), "", &"", true))
	lines.append(_line("Kills: %d   Assists: %d" % [kills, assists], "", &"", true))
	lines.append(_line("Wing losses: %d" % wing_losses, "", &"", true))
	lines.append(_line(_shots_text(), "", &"", true))
	return {"title": PANEL_TITLE, "lines": lines, "compact": true}


## One value per key, for the console's `debrief` provider.
func summary() -> Dictionary:
	var states := PackedStringArray()
	for row: Dictionary in objectives:
		states.append("%s %s" % [row["id"], row["state"]])
	return {"result": "success" if success else "failure", "reason": reason, "time": format_time(time_s), "kills": kills,
			"assists": assists, "wing_losses": wing_losses, "shots_fired": shots_fired, "shots_hit": shots_hit,
			"accuracy": accuracy_text(), "objectives": ", ".join(states)}


# The reason, with a failed objective's id turned into its text, and a capital letter.
func _reason_text() -> String:
	var text: String = reason.strip_edges()
	if text.begins_with(OBJECTIVE_FAILED_PREFIX):
		var id: String = text.substr(OBJECTIVE_FAILED_PREFIX.length())
		for row: Dictionary in objectives:
			if str(row["id"]) == id:
				text = OBJECTIVE_FAILED_PREFIX + str(row["text"])
				break
	return text.substr(0, 1).to_upper() + text.substr(1)


func _shots_text() -> String:
	if shots_fired <= 0:
		return "Shots: none fired"
	return "Shots: %d fired, %d hit (%s)" % [shots_fired, mini(shots_hit, shots_fired), accuracy_text()]


func _objective_line(row: Dictionary) -> Dictionary:
	var state: StringName = row["state"]
	var primary: bool = row["primary"]
	var text: String = str(row["text"])
	if not primary:
		text += " (optional)"
	if state == &"active" or state == &"hidden":
		text += " - %s" % row["state_text"]
	return _line(text, MARKS.get(state, ""), state, primary)


static func _line(text: String, mark: String, state: StringName, primary: bool) -> Dictionary:
	return {"text": text, "mark": mark, "state": state, "primary": primary, "optional": not primary}
