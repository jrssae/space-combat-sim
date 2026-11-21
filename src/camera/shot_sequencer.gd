class_name ShotSequencer
extends RefCounted
## Cuts a cinematic whose stages last as long as the action does (M8-T31: docking) into short takes from a `ShotPool`: each take
## held to its longest (under 3 s, a feature under 5 s), then another of the same stage; a new stage cuts at once, or as soon as
## the take on screen has had its second (a feature take its 2.5 s). Takes are seeded per sequence, never the same twice in a row, never the last sequence's
## opening, and only those `usable(stage, id)` passes (the caller's clearance test). `stop` ends it all in one call (an abort).
## Pure but for `play(shot)` and `stop`'s callable, which the caller supplies.

var pool: ShotPool = null
## The caller's clearance test, `func(stage: StringName, id: String) -> bool`; unset: every take.
var usable: Callable = Callable()
## This sequence's takes in order: `{stage, id, at_s}` on its clock; and the clock.
var played: Array[Dictionary] = []
var clock_s: float = 0.0
## The last sequence's opening take, and sequences begun (each one's seed).
var last_opening: String = ""
var sequences: int = 0
## A take every sequence opens with instead of a pick (console captures); "" picks.
var pinned: String = ""

var _rng := RandomNumberGenerator.new()
var _tag: String = ""
var _stage: StringName = &""
var _wanted: StringName = &""  # a stage asked for while the take on screen has not had its second
var _take_at: float = 0.0
var _take_until: float = INF
var _running: bool = false


func _init(p_pool: ShotPool, seed_tag: String = "shots") -> void:
	pool = p_pool
	_tag = seed_tag


## Starts a sequence (`seed_extra` varies it between sessions) in `stage`.
func begin(stage: StringName, play: Callable, seed_extra: int = 0) -> void:
	_rng.seed = hash([_tag, sequences, seed_extra])
	sequences += 1
	if not played.is_empty():
		last_opening = String(played[0]["id"])
	played.clear()
	clock_s = 0.0
	_running = true
	_stage = stage
	_wanted = &""
	_cut(play)


## Moves to `stage`: a cut now, or once the take on screen has had its second. Nothing when it is the stage already.
func to_stage(stage: StringName, play: Callable) -> void:
	if not _running or (stage == _stage and _wanted == &"") or stage == _wanted:
		return
	_wanted = stage
	if clock_s - _take_at >= _least_hold_s():
		_stage = stage
		_wanted = &""
		_cut(play)


## One tick, `delta` seconds: a waiting stage once the take has had its second, else another take when this one has had its time.
func tick(delta: float, play: Callable) -> void:
	if not _running:
		return
	clock_s += delta
	if _wanted != &"" and clock_s - _take_at >= _least_hold_s():
		_stage = _wanted
		_wanted = &""
		_cut(play)
	elif clock_s >= _take_until:
		_cut(play)


## Ends the sequence: nothing more is cut and `stop_camera` ends the take on screen. The one call an abort makes.
func stop(stop_camera: Callable = Callable()) -> void:
	_running = false
	_wanted = &""
	_take_until = INF
	if stop_camera.is_valid():
		stop_camera.call()


func is_running() -> bool:
	return _running


## The stage on screen.
func stage() -> StringName:
	return _stage


## This sequence's takes as `stage/id`, in order.
func sequence() -> PackedStringArray:
	var out := PackedStringArray()
	for take: Dictionary in played:
		out.append("%s/%s" % [take["stage"], take["id"]])
	return out


# How long the take on screen is held before a new stage cuts in: a second, a feature take its `FEATURE_MIN_S`, so its moment
# plays out.
func _least_hold_s() -> float:
	if played.is_empty():
		return ShotPool.MIN_HOLD_S
	var last: Dictionary = played[played.size() - 1]
	return ShotPool.FEATURE_MIN_S if pool.is_feature(last["stage"], String(last["id"])) else ShotPool.MIN_HOLD_S


func _cut(play: Callable) -> void:
	var used := PackedStringArray()
	var previous: String = ""
	for take: Dictionary in played:
		if take["stage"] == _stage:
			used.append(String(take["id"]))
		previous = String(take["id"])
	var opening: bool = played.is_empty()
	var id: String = pinned if opening and pool.ids(_stage).has(pinned) else ""
	if id.is_empty():
		var check: Callable = usable if usable.is_valid() else func(_s: StringName, _i: String) -> bool: return true
		id = pool.next(_rng, _stage, used, previous, last_opening if opening else "", check)
	if id.is_empty():
		_take_until = INF
		return
	var made: Dictionary = CinematicShot.from_dict(StringName("%s_%s" % [_stage, id]), {"keys": pool.keys(_stage, id)})
	if not bool(made["ok"]):
		push_warning("ShotSequencer: %s" % made["error"])
		_take_until = INF
		return
	_take_at = clock_s
	_take_until = clock_s + pool.max_s(_stage, id)
	played.append({"stage": _stage, "id": id, "at_s": clock_s})
	play.call(made["shot"])
