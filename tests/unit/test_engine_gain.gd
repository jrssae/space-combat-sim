extends GutTest
## The engines' steady level (M8-T12, roadmap M7-5): a ship's loudness follows its throttle, not which of its thrusters fire.
## Pods and jets starting, stopping, overlapping and trading load at one throttle keep the ship's summed power flat; a change
## of throttle moves it smoothly, without a jump or overshoot.

const STARFURY: String = "res://tests/fixtures/hardpoints_nominal.json"
const DT: float = 1.0 / 60.0

var starfury: ThrusterLayout


func before_each() -> void:
	starfury = ThrusterLayout.load_file(STARFURY)
	assert_true(starfury.valid, "fixture loads")


func _player() -> EngineVoices:
	var voices := EngineVoices.new()
	voices.add_ship(starfury, true)
	voices.begin_allocation(true)
	voices.finish_allocation()
	return voices


func _output(mains: Array, retros: Array = [0.0, 0.0, 0.0, 0.0]) -> FlightOutput:
	var output := FlightOutput.new()
	output.main_levels = PackedFloat64Array(mains)
	output.retro_levels = PackedFloat64Array(retros)
	return output


# The ship's summed power, dB, over one kind of voice.
func _total_db(voices: EngineVoices, kind: EngineVoices.Kind) -> float:
	var power: float = 0.0
	for v: int in voices.voices_of(0):
		if voices.voice_kind[v] == kind:
			power += voices.gain[v] * voices.gain[v]
	return 10.0 * log(maxf(power, 1e-12)) / log(10.0)


# Runs `frames` frames, the output picked per frame by `pattern(frame)`; returns the summed power per frame after `settle`.
func _run(voices: EngineVoices, frames: int, settle: int, pattern: Callable, kind := EngineVoices.Kind.POD) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for f: int in frames:
		voices.set_output(0, pattern.call(f) as FlightOutput)
		voices.step(DT)
		if f >= settle:
			out.append(_total_db(voices, kind))
	return out


func _swing(levels: PackedFloat64Array) -> float:
	var lo: float = INF
	var hi: float = -INF
	for x: float in levels:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi - lo


func test_pods_starting_and_stopping_at_one_throttle_keep_the_level_flat() -> void:
	var voices := _player()
	# One pod at full throughout; the others drop out and come back on their own rhythms, as the flight computer turns.
	var pattern := func(f: int) -> FlightOutput:
		return _output([1.0, 1.0 if (f / 7) % 2 == 0 else 0.0, 1.0 if (f / 11) % 2 == 0 else 0.3, 0.0 if (f / 5) % 3 == 0 else 0.8])
	var levels: PackedFloat64Array = _run(voices, 600, 30, pattern)
	assert_lt(_swing(levels), 0.1, "the ship's level stays put while its pods trade load (swing %.3f dB)" % _swing(levels))
	assert_almost_eq(levels[levels.size() - 1], 0.0, 0.1, "at full throttle the pods sum to the mix level")


func test_pods_trading_load_every_frame_keep_the_level_flat() -> void:
	var voices := _player()
	var pattern := func(f: int) -> FlightOutput:
		return _output([1.0, 0.6, 1.0, 0.6] if f % 2 == 0 else [0.6, 1.0, 0.6, 1.0])
	var levels: PackedFloat64Array = _run(voices, 300, 30, pattern)
	assert_lt(_swing(levels), 0.1, "swing %.3f dB" % _swing(levels))


func test_a_main_and_a_retro_overlapping_do_not_add_up() -> void:
	var voices := _player()
	var pattern := func(f: int) -> FlightOutput:
		var retro: float = 0.7 if (f / 9) % 2 == 0 else 0.0
		return _output([0.7, 0.7, 0.0, 0.0], [0.0, 0.0, retro, retro])
	var levels: PackedFloat64Array = _run(voices, 400, 30, pattern)
	assert_lt(_swing(levels), 0.1, "swing %.3f dB" % _swing(levels))
	assert_almost_eq(levels[0], 20.0 * log(0.7) / log(10.0), 0.1, "the level is the throttle's")


func test_flight_computer_chatter_is_smoothed() -> void:
	var voices := _player()
	# Every pod pulsing on and off together at 15 Hz: the old per-pod envelopes swung by more than 25 dB.
	var pattern := func(f: int) -> FlightOutput:
		var on: float = 0.8 if (f / 2) % 2 == 0 else 0.0
		return _output([on, on, on, on])
	var levels: PackedFloat64Array = _run(voices, 300, 60, pattern)
	assert_lt(_swing(levels), 10.0, "pulsing stays a murmur, not a stutter (swing %.2f dB)" % _swing(levels))


func test_a_throttle_change_moves_the_level_smoothly_without_overshoot() -> void:
	var voices := _player()
	var pattern := func(f: int) -> FlightOutput:
		var throttle: float = 0.25 if f < 60 else (1.0 if f < 120 else 0.5)
		return _output([throttle, throttle, throttle, throttle])
	var levels: PackedFloat64Array = _run(voices, 240, 0, pattern)
	assert_lt(levels[60], -3.0, "the rise takes several frames, not one (%.2f dB after one)" % levels[60])
	for f: int in range(61, 120):
		assert_gte(levels[f], levels[f - 1] - 1e-6, "rises without a dip")
		assert_lte(levels[f], 0.01, "never above full level")
	assert_gt(levels[120], levels[119] - 3.0, "the fall to half throttle is gradual")
	assert_almost_eq(levels[110], 0.0, 0.2, "full throttle reaches the full level")
	assert_almost_eq(levels[levels.size() - 1], 20.0 * log(0.5) / log(10.0), 0.2, "half throttle sits 6 dB down")


func test_the_level_dies_once_the_throttle_is_closed() -> void:
	var voices := _player()
	var pattern := func(f: int) -> FlightOutput:
		var throttle: float = 1.0 if f < 30 else 0.0
		return _output([throttle, throttle, throttle, throttle])
	_run(voices, 90, 0, pattern)
	for v: int in voices.voices_of(0):
		assert_eq(voices.gain[v], 0.0, "silent 1 s after the throttle closed")


func test_overlapping_jets_keep_the_rcs_level_flat() -> void:
	var voices := _player()
	# A sway held at one level while a yaw comes and goes: more clusters fire, the ship's jets stay as loud.
	var pattern := func(f: int) -> FlightOutput:
		var output := FlightOutput.new()
		output.rcs_force_level = Vector3(0.6, 0.0, 0.0)
		output.rcs_torque_level = Vector3(0.0, 0.6 if (f / 8) % 2 == 0 else 0.0, 0.0)
		return output
	var levels: PackedFloat64Array = _run(voices, 400, 60, pattern, EngineVoices.Kind.RCS)
	assert_lt(_swing(levels), 0.1, "swing %.3f dB" % _swing(levels))


func test_the_frame_cost_stays_one_unit_per_voice() -> void:
	var voices := _player()
	voices.set_output(0, _output([1.0, 0.0, 0.5, 0.0]))
	voices.step(DT)
	assert_eq(voices.step_work, voices.active.size())
