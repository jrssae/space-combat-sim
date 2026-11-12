class_name HudWaypoint
extends RefCounted
## Whose waypoint the HUD shows (architecture §18.19, M5-T25), pure: the pilot's pick from the target menu or the one a script
## set (a mission's `m.waypoint`, the instructor's route), whichever came last. A script's waypoint is known by a key that
## changes whenever the script sets it anew, so the same place set twice still counts as the later word.

const PLAYER: StringName = &"player"
const SCRIPT: StringName = &"script"

## Who spoke last.
var source: StringName = SCRIPT
## The pilot's pick, or empty: `{label: String, target_id: int (0 for a bare place), point: UniversePos or null}`.
var pick: Dictionary = {}

var _script_key: String = ""


## The pilot picked a beacon or an objective.
func set_pick(label: String, target_id: int, point: UniversePos = null) -> void:
	pick = {"label": label, "target_id": target_id, "point": point}
	source = PLAYER


## The pilot picked "none": no waypoint shows, a script's included, until a script sets one anew.
func clear_pick() -> void:
	pick = {}
	source = PLAYER


## The pick's target is gone: the script's waypoint, if any, shows again.
func drop_pick() -> void:
	pick = {}
	source = SCRIPT


## This frame's script waypoint key ("" for none). A changed key means the script spoke after the pilot.
func offer_script(key: String) -> void:
	if key != _script_key:
		_script_key = key
		source = SCRIPT


## The pilot's pick is the one to show.
func shows_pick() -> bool:
	return source == PLAYER and not pick.is_empty()


## The script's waypoint is the one to show (when it has one).
func shows_script() -> bool:
	return source == SCRIPT


## What the console reads: the pick's label, `script`, or `none`.
func describe() -> String:
	if shows_pick():
		return String(pick["label"])
	return "script" if shows_script() and not _script_key.is_empty() else "none"
