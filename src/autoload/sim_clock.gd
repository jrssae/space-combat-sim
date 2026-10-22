extends Node
## SimClock autoload: the only gameplay clock (architecture §13, §14.3).
## 64-bit simulation time advanced by the physics delta (which already includes `Engine.time_scale`) times
## `warp`. Gameplay timers read `now()` or their own `delta`, never wall-clock time, so time warp can come later
## without hunting timers. `warp` is fixed at 1.0 in M1; M8 replaces the setter with real warp.

signal warp_changed(warp: float)

var sim_time_s: float = 0.0
var warp: float = 1.0:
	set = set_warp


func _physics_process(delta: float) -> void:
	advance(delta)


func now() -> float:
	return sim_time_s


func advance(delta: float) -> void:
	sim_time_s += delta * warp


func set_warp(value: float) -> void:
	if not is_equal_approx(value, 1.0):
		push_warning("SimClock: warp is fixed at 1.0 in M1 (requested %s)" % value)
		return
	if warp != value:
		warp = value
		warp_changed.emit(warp)


## Test and respawn helper; gameplay never rewinds time.
func reset(time_s: float = 0.0) -> void:
	sim_time_s = time_s
