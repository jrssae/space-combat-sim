extends GutTest
## PerfProbe (M4-T01): which ticks had their body sync timed. A tick closed by the next tick's start keeps its own flag.

var _probe: PerfProbe = null


func before_each() -> void:
	_probe = PerfProbe.new()
	_probe.time_sync = true


func after_each() -> void:
	_probe.free()


# One tick that followed an idle frame, so its sync was timed.
func _open_tick_after_idle() -> void:
	_probe._idle_end_us = Time.get_ticks_usec()
	_probe._idle_end_valid = true
	_probe._on_physics_frame()
	_probe._end_script()


func test_a_timed_tick_closed_by_an_idle_frame_is_marked_timed() -> void:
	_open_tick_after_idle()
	_probe.time_sync = false  # no end-of-frame timer: the probe is not in a tree here
	_probe._on_process_frame()
	assert_eq(_probe.value(&"sync_on"), 1)


func test_a_timed_tick_closed_by_the_next_tick_back_to_back_is_still_marked_timed() -> void:
	_open_tick_after_idle()
	_probe._on_physics_frame()  # catching up: the next tick starts with no idle frame between
	assert_eq(_probe.value(&"sync_on"), 1, "the closed tick's sync was timed")


func test_a_back_to_back_tick_is_not_timed() -> void:
	_open_tick_after_idle()
	_probe._on_physics_frame()
	_probe._end_script()
	_probe._on_physics_frame()
	assert_eq(_probe.value(&"sync_on"), 0, "its sync went into the tick before")
