extends GutTest
## WavePlan (M2-T09, AC11, architecture §15.10): the countdown -> active -> cleared -> next state machine with a fake clock,
## the loop from wave 3, and the extra attackers per loop up to the pool size.

const DT: float = 0.5


func _spawn(at_s: float = 0.0, x: float = 0.0) -> Dictionary:
	return {"type": &"raider_fighter", "name": "", "anchor": &"player", "offset": Vector3(x, 0.0, -1000.0), "velocity": Vector3.ZERO,
			"at_s": at_s, "behaviour": {"type": "attack"}}


func _wave(wave_name: String, delay: float, spawns: Array[Dictionary]) -> Dictionary:
	return {"name": wave_name, "delay_s": delay, "spawns": spawns}


## The shipped shape: three waves, 3 / 3 / 4 spawns (the last 2 s apart), loop from wave 3.
func _plan(loop_from: int = 3, max_spawns: int = 6) -> WavePlan:
	var waves: Array[Dictionary] = [
		_wave("ONE", 5.0, [_spawn(), _spawn(), _spawn()] as Array[Dictionary]),
		_wave("TWO", 8.0, [_spawn(), _spawn(), _spawn()] as Array[Dictionary]),
		_wave("THREE", 8.0, [_spawn(0.0), _spawn(2.0), _spawn(4.0), _spawn(6.0)] as Array[Dictionary]),
	]
	return WavePlan.new(waves, loop_from, 1, max_spawns)


## Advances until `state`, with `alive` raiders; returns the seconds it took and every spawn issued.
func _run_until(plan: WavePlan, state: WavePlan.State, alive: int = 0, limit_s: float = 120.0) -> Dictionary:
	var elapsed: float = 0.0
	var issued: Array[Dictionary] = []
	while plan.state != state and elapsed < limit_s:
		issued.append_array(plan.update(DT, alive))
		elapsed += DT
	return {"elapsed": elapsed, "issued": issued}


func test_it_starts_idle_and_does_nothing() -> void:
	var plan: WavePlan = _plan()
	assert_eq(plan.state, WavePlan.State.IDLE)
	assert_eq(plan.update(1.0, 0), [])
	assert_eq(plan.wave_number, 0)
	assert_eq(plan.current_name(), "")
	assert_false(plan.is_running())


func test_start_begins_the_first_wave_countdown() -> void:
	var plan: WavePlan = _plan()
	plan.start()
	assert_eq(plan.state, WavePlan.State.COUNTDOWN)
	assert_eq(plan.wave_number, 1)
	assert_eq(plan.current_name(), "ONE")
	assert_almost_eq(plan.countdown_remaining(), 5.0, 1e-9)
	assert_true(plan.is_running())


func test_the_countdown_runs_its_delay_then_the_wave_is_active() -> void:
	var plan: WavePlan = _plan()
	plan.start()
	var r: Dictionary = _run_until(plan, WavePlan.State.ACTIVE)
	assert_almost_eq(float(r["elapsed"]), 5.0, DT, "a 5 s delay")
	assert_eq(plan.countdown_remaining(), 0.0)


func test_all_of_a_waves_spawns_are_issued_at_their_times() -> void:
	var plan: WavePlan = _plan()
	plan.start(2)
	_run_until(plan, WavePlan.State.ACTIVE)
	var issued: Array[Dictionary] = []
	var t: float = 0.0
	var times: Array[float] = []
	while t < 7.0:
		var due: Array[Dictionary] = plan.update(DT, 1)
		for spawn: Dictionary in due:
			times.append(t + DT)
		issued.append_array(due)
		t += DT
	assert_eq(issued.size(), 4)
	assert_eq(times.size(), 4)
	assert_almost_eq(times[0], 0.5, DT, "the first at once")
	assert_almost_eq(times[1] - times[0], 2.0, DT)
	assert_almost_eq(times[3] - times[0], 6.0, DT)
	for spawn: Dictionary in issued:
		assert_eq(spawn["wave_number"], 3)


func test_the_wave_clears_only_after_every_spawn_is_issued_and_none_is_alive() -> void:
	var plan: WavePlan = _plan()
	plan.start(2)
	_run_until(plan, WavePlan.State.ACTIVE)
	for i: int in 6:
		plan.update(DT, 0)  # 3 s in, none alive yet, spawns still to come
	assert_eq(plan.state, WavePlan.State.ACTIVE, "not cleared while spawns are pending")
	for i: int in 12:
		plan.update(DT, 2)  # 6 more seconds with two alive
	assert_eq(plan.state, WavePlan.State.ACTIVE, "not cleared while raiders live")
	plan.update(DT, 0)
	assert_eq(plan.state, WavePlan.State.CLEARED)


func test_a_just_issued_spawn_does_not_clear_the_wave_in_the_same_tick() -> void:
	var waves: Array[Dictionary] = [_wave("ONE", 0.0, [_spawn()] as Array[Dictionary])]
	var plan := WavePlan.new(waves)
	plan.start()
	plan.update(0.1, 0)  # countdown over
	var due: Array[Dictionary] = plan.update(0.1, 0)
	assert_eq(due.size(), 1)
	assert_eq(plan.state, WavePlan.State.ACTIVE, "the caller has not yet counted it as alive")
	plan.update(0.1, 1)
	assert_eq(plan.state, WavePlan.State.ACTIVE)
	plan.update(0.1, 0)
	assert_eq(plan.state, WavePlan.State.CLEARED)


func test_cleared_waits_then_the_next_countdown_begins() -> void:
	var plan: WavePlan = _plan()
	plan.start()
	_run_until(plan, WavePlan.State.ACTIVE)
	plan.update(DT, 3)
	_run_until(plan, WavePlan.State.CLEARED, 0)
	assert_eq(plan.state, WavePlan.State.CLEARED)
	var r: Dictionary = _run_until(plan, WavePlan.State.COUNTDOWN)
	assert_almost_eq(float(r["elapsed"]), WavePlan.CLEARED_PAUSE_S, DT)
	assert_eq(plan.wave_number, 2)
	assert_eq(plan.current_name(), "TWO")
	assert_almost_eq(plan.countdown_remaining(), 8.0, 1e-9)


func _play(plan: WavePlan, waves_to_play: int) -> Array[int]:
	var counts: Array[int] = []
	for i: int in waves_to_play:
		_run_until(plan, WavePlan.State.ACTIVE)
		var issued: Array[Dictionary] = []
		var guard: int = 0
		while plan.state == WavePlan.State.ACTIVE and guard < 400:
			issued.append_array(plan.update(DT, 0 if issued.size() >= plan.spawn_total() else 1))
			guard += 1
		counts.append(issued.size())
		_run_until(plan, WavePlan.State.COUNTDOWN)
	return counts


func test_it_loops_from_wave_3_with_one_more_attacker_per_loop_up_to_the_pool() -> void:
	var plan: WavePlan = _plan()
	plan.start()
	var counts: Array[int] = _play(plan, 6)
	assert_eq(counts, [3, 3, 4, 5, 6, 6], "waves 4 and 5 add one each, then the pool of 6 caps it")
	assert_eq(plan.wave_number, 7)


func test_loop_bookkeeping() -> void:
	var plan: WavePlan = _plan()
	assert_eq([plan.wave_index(1), plan.wave_index(2), plan.wave_index(3), plan.wave_index(4), plan.wave_index(9)], [0, 1, 2, 2, 2])
	assert_eq([plan.loops_done(3), plan.loops_done(4), plan.loops_done(5)], [0, 1, 2])
	var two_wave_loop: WavePlan = _plan(2)  # loops over waves 2 and 3
	assert_eq([two_wave_loop.wave_index(4), two_wave_loop.wave_index(5), two_wave_loop.wave_index(6)], [1, 2, 1])
	assert_eq([two_wave_loop.loops_done(3), two_wave_loop.loops_done(4), two_wave_loop.loops_done(5), two_wave_loop.loops_done(6)], [0, 1, 1, 2])


func test_extra_attackers_are_copies_of_the_last_spawn_spaced_out() -> void:
	var plan: WavePlan = _plan()
	var spawns: Array[Dictionary] = plan.spawns_for(4)
	assert_eq(spawns.size(), 5)
	var last: Dictionary = spawns[3]
	var extra: Dictionary = spawns[4]
	assert_eq(extra["behaviour"], last["behaviour"])
	assert_almost_eq(float(extra["at_s"]), float(last["at_s"]) + WavePlan.EXTRA_INTERVAL_S, 1e-9)
	assert_almost_eq((extra["offset"] as Vector3).x - (last["offset"] as Vector3).x, WavePlan.EXTRA_SPACING_M, 1e-9)
	assert_eq(plan.spawns_for(3).size(), 4, "the first pass is the scripted wave")


func test_without_a_loop_the_plan_ends_after_the_last_wave() -> void:
	var plan: WavePlan = _plan(0)
	plan.start(2)
	_run_until(plan, WavePlan.State.ACTIVE)
	plan.update(DT, 1)
	_run_until(plan, WavePlan.State.CLEARED, 0)
	assert_eq(plan.state, WavePlan.State.CLEARED)
	for i: int in 20:
		plan.update(DT, 0)
	assert_eq(plan.state, WavePlan.State.IDLE, "nothing after the last wave")
	assert_eq(plan.wave_number, 3)


func test_start_at_a_later_wave() -> void:
	var plan: WavePlan = _plan()
	plan.start(1)
	assert_eq(plan.wave_number, 2)
	assert_eq(plan.current_name(), "TWO")
	plan.start(99)
	assert_eq(plan.wave_number, 3, "clamped to the last scripted wave")


func test_skip_goes_to_the_next_countdown_and_restart_to_this_one_again() -> void:
	var plan: WavePlan = _plan()
	plan.start()
	_run_until(plan, WavePlan.State.ACTIVE)
	plan.skip()
	assert_eq(plan.state, WavePlan.State.COUNTDOWN)
	assert_eq(plan.wave_number, 2)
	plan.update(3.0, 0)
	assert_almost_eq(plan.countdown_remaining(), 5.0, 1e-9)
	plan.restart()
	assert_almost_eq(plan.countdown_remaining(), 8.0, 1e-9, "the full delay again")
	assert_eq(plan.wave_number, 2)


func test_stop_and_the_idle_plan_ignore_skip_and_restart() -> void:
	var plan: WavePlan = _plan()
	plan.skip()
	plan.restart()
	assert_eq(plan.state, WavePlan.State.IDLE)
	plan.start()
	plan.stop()
	assert_eq(plan.state, WavePlan.State.IDLE)
	assert_eq(plan.update(10.0, 0), [])


func test_an_empty_plan_cannot_start() -> void:
	var plan := WavePlan.new()
	plan.start()
	assert_eq(plan.state, WavePlan.State.IDLE)


func test_state_names() -> void:
	var plan: WavePlan = _plan()
	assert_eq(plan.state_name(), &"idle")
	plan.start()
	assert_eq(plan.state_name(), &"countdown")
