class_name BotAlert
extends RefCounted
## Where and when fighting happened near the station's maintenance bots (M7-T11, Q11): a short log of combat events, so a bot
## can ask whether any came within reach of it lately. Pure: points are in the station's frame and times are the fleet's own
## clock, so a rebase or a drifting station changes nothing here.

## How near an event makes a bot go in, metres, and how long after the last one it stays in, seconds.
const RADIUS_M: float = 1500.0
const QUIET_S: float = 60.0
const MAX_EVENTS: int = 32

var _points := PackedVector3Array()
var _times := PackedFloat64Array()
var _next: int = 0
## Until when everyone is alarmed whatever their distance (the grid going weapons free).
var _everywhere_until_s: float = -INF


func _init() -> void:
	_points.resize(MAX_EVENTS)
	_times.resize(MAX_EVENTS)
	_times.fill(-INF)


## A shot or hit at `point` at time `now_s`.
func note(point: Vector3, now_s: float) -> void:
	_points[_next] = point
	_times[_next] = now_s
	_next = (_next + 1) % MAX_EVENTS


## Fighting somewhere on the station, which is every bot's concern.
func note_everywhere(now_s: float) -> void:
	_everywhere_until_s = now_s + QUIET_S


## Whether fighting is recent and near enough that a bot at `point` stays out of it.
func is_alarmed(point: Vector3, now_s: float) -> bool:
	if now_s < _everywhere_until_s:
		return true
	for i: int in MAX_EVENTS:
		if now_s - _times[i] < QUIET_S and _points[i].distance_squared_to(point) <= RADIUS_M * RADIUS_M:
			return true
	return false


## Forgets everything, as `bots show` does.
func clear() -> void:
	_times.fill(-INF)
	_everywhere_until_s = -INF
