class_name WavePlan
extends RefCounted
## The wave sandbox's state machine (architecture §15.10), pure: time and the number of raiders alive come in as arguments
## (a fake clock in tests, `WaveDirector` in the game); spawn requests come out. Nothing here touches the scene tree.
##
## Per wave: `COUNTDOWN` (the wave's `delay_s`) -> `ACTIVE` (its spawns are issued at their `at_s` offsets; once all are issued
## and none is alive) -> `CLEARED` (`CLEARED_PAUSE_S`) -> the next wave's `COUNTDOWN`. After the last scripted wave the plan
## loops from wave `loop.from_wave` (1-based) over the waves from there to the end. The n-th time round a looped wave gets
## `n * loop.add_per_loop` more attackers (copies of its last spawn, 2 s apart), up to `max_spawns` (the pool size).
##
## `wave_number` counts waves played, from 1, and keeps counting through the loops; `wave_index(number)` is the scripted
## wave it plays.

enum State { IDLE, COUNTDOWN, ACTIVE, CLEARED }

const STATE_NAMES: Array[StringName] = [&"idle", &"countdown", &"active", &"cleared"]
const CLEARED_PAUSE_S: float = 3.0
## Extra attackers are spaced this far apart sideways and this many seconds in time.
const EXTRA_SPACING_M: float = 150.0
const EXTRA_INTERVAL_S: float = 2.0

## Scripted waves: `{name, delay_s, spawns: Array[{... at_s}]}`.
var waves: Array[Dictionary] = []
## 1-based wave to loop from (0 = no loop), extra attackers per pass, and the most spawns in one wave.
var loop_from: int = 0
var loop_add: int = 1
var max_spawns: int = 6

var state: State = State.IDLE
## The wave in its countdown, running or cleared (1-based); 0 before `start`.
var wave_number: int = 0

var _time_s: float = 0.0
var _spawn_list: Array[Dictionary] = []
var _issued: int = 0


func _init(p_waves: Array[Dictionary] = [], p_loop_from: int = 0, p_loop_add: int = 1, p_max_spawns: int = 6) -> void:
	waves = p_waves
	loop_from = p_loop_from
	loop_add = p_loop_add
	max_spawns = p_max_spawns


## Begins the countdown of scripted wave `first_index` (0-based).
func start(first_index: int = 0) -> void:
	if waves.is_empty():
		return
	wave_number = clampi(first_index, 0, waves.size() - 1) + 1
	_begin_countdown()


func stop() -> void:
	state = State.IDLE
	_issued = 0
	_spawn_list = []


## Abandons the current wave and goes to the next one's countdown (a finished plan stays idle).
func skip() -> void:
	if state == State.IDLE:
		return
	_advance()


## The current wave's countdown again.
func restart() -> void:
	if state == State.IDLE:
		return
	_begin_countdown()


func is_running() -> bool:
	return state != State.IDLE


## The scripted wave (0-based index) played as wave `number` (1-based).
func wave_index(number: int) -> int:
	var count: int = waves.size()
	if number <= count or loop_from <= 0:
		return mini(number, count) - 1
	var from: int = loop_from - 1
	return from + (number - 1 - from) % (count - from)


## How many times round the loop wave `number` is (0 for the first pass and anything not looped).
func loops_done(number: int) -> int:
	var count: int = waves.size()
	if number <= count or loop_from <= 0:
		return 0
	return (number - 1 - (loop_from - 1)) / (count - (loop_from - 1))


## The spawns of wave `number`, sorted by `at_s`, with the loop's extra attackers added.
func spawns_for(number: int) -> Array[Dictionary]:
	var base: Array[Dictionary] = []
	for spawn: Dictionary in waves[wave_index(number)]["spawns"]:
		base.append(spawn.duplicate(true))
	base.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at_s"]) < float(b["at_s"]))
	var extra: int = mini(loops_done(number) * loop_add, maxi(max_spawns - base.size(), 0))
	if extra > 0 and not base.is_empty():
		var last: Dictionary = base[-1]
		for k: int in range(1, extra + 1):
			var copy: Dictionary = last.duplicate(true)
			copy["at_s"] = float(last["at_s"]) + EXTRA_INTERVAL_S * float(k)
			copy["offset"] = (last["offset"] as Vector3) + Vector3(EXTRA_SPACING_M * float(k), 0.0, 0.0)
			base.append(copy)
	return base


func current_name() -> String:
	if wave_number <= 0 or waves.is_empty():
		return ""
	return String(waves[wave_index(wave_number)]["name"])


## Seconds until the wave activates (COUNTDOWN), else 0.
func countdown_remaining() -> float:
	if state != State.COUNTDOWN:
		return 0.0
	return maxf(_delay() - _time_s, 0.0)


## Number of spawns the current wave will issue in total.
func spawn_total() -> int:
	return _spawn_list.size()


func state_name() -> StringName:
	return STATE_NAMES[state]


## One step: `dt` seconds on, `alive` raiders in the world. Returns the spawns due now, each the spawn dictionary plus
## `wave_number`; empty most ticks.
func update(dt: float, alive: int) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	match state:
		State.COUNTDOWN:
			_time_s += dt
			if _time_s >= _delay():
				state = State.ACTIVE
				_time_s = 0.0
				_issued = 0
		State.ACTIVE:
			_time_s += dt
			while _issued < _spawn_list.size() and float(_spawn_list[_issued]["at_s"]) <= _time_s:
				var request: Dictionary = _spawn_list[_issued].duplicate(true)
				request["wave_number"] = wave_number
				due.append(request)
				_issued += 1
			# Cleared when everything has been issued and nothing is left: judged on a later tick than the last issue, so the
			# caller has had a chance to put the new ships in `alive`.
			if due.is_empty() and _issued >= _spawn_list.size() and alive <= 0:
				state = State.CLEARED
				_time_s = 0.0
		State.CLEARED:
			_time_s += dt
			if _time_s >= CLEARED_PAUSE_S:
				_advance()
	return due


# --- internals ---------------------------------------------------------------------------------------------------


func _delay() -> float:
	return float(waves[wave_index(wave_number)]["delay_s"])


func _begin_countdown() -> void:
	state = State.COUNTDOWN
	_time_s = 0.0
	_issued = 0
	_spawn_list = spawns_for(wave_number)


func _advance() -> void:
	if wave_number < waves.size() or loop_from > 0:
		wave_number += 1
		_begin_countdown()
	else:
		state = State.IDLE  # the last scripted wave is cleared and there is no loop
