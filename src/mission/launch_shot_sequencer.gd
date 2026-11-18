class_name LaunchShotSequencer
extends RefCounted
## When a launch's camera cuts (M7-T08, maintainer: "minimum 1 second hold per camera angle"; in a wave, hold to see a few fighters
## launch before cutting). Given the cut's shots that are due, it says which to play: never before the shot on screen has had
## `min_shot_s`, and a row shot not before `row_ejections` fighters were let go during it (or the wave has none left, or `row_max_s`
## passed). Shots that came due while one held are superseded by the latest of them. Pure: the director feeds it the time, the due
## shots and the ejection count each tick, so a test can run a whole launch through it.

var profile: LaunchProfile = null
## The shot on screen (an index into the cut, -1 none), since when, and the ejections counted when it started.
var current: int = -1
var started_s: float = 0.0
var _ejections_at_start: int = 0
var _taken: Dictionary = {}  # cut indices played or superseded
## Every shot played: `{index, start}`, in order.
var log: Array[Dictionary] = []


func _init(p_profile: LaunchProfile) -> void:
	profile = p_profile


## The cut index to play now, or -1 to keep the shot on screen. `due` are the cut indices whose time has come, `cut` the cut,
## `ejections` how many fighters of the launch were let go so far, `left` how many of its first wave are still to go.
func next(now: float, due: PackedInt32Array, cut: Array[Dictionary], ejections: int, left: int) -> int:
	var pending: int = -1
	for i: int in due:
		if not _taken.has(i):
			pending = maxi(pending, i)
	if pending < 0 or not may_cut(now, cut, ejections, left):
		return -1
	for i: int in due:
		if i <= pending:
			_taken[i] = true
	current = pending
	started_s = now
	_ejections_at_start = ejections
	log.append({"index": pending, "start": now})
	return pending


## Whether the shot on screen may give way now.
func may_cut(now: float, cut: Array[Dictionary], ejections: int, left: int) -> bool:
	if current < 0:
		return true
	var held: float = now - started_s
	if held < profile.min_shot_s - LaunchSequence.EPS_S:
		return false
	if bool(cut[current].get("row", false)) and held < profile.row_max_s - LaunchSequence.EPS_S:
		return ejections - _ejections_at_start >= profile.row_ejections or left == 0
	return true


## How many fighters were let go since the shot on screen started.
func ejections_during(ejections: int) -> int:
	return ejections - _ejections_at_start
