extends GutTest
## EngineVoices (M5-T19, AC15, D60): RCS jets grouped by position, voices at their nozzles, the cap and its order (the
## player first, then whole ships nearest first within range), envelopes on the reference's numbers stepped on sim time,
## and a per-frame update linear in voices, not in ships times nozzles (work counts, never milliseconds).

const STARFURY: String = "res://tests/fixtures/hardpoints_nominal.json"
const RAIDER: String = "res://tests/fixtures/hardpoints_raider_nominal.json"
const DT: float = 1.0 / 60.0
const TOL: float = 1e-5

var starfury: ThrusterLayout
var raider: ThrusterLayout


func before_each() -> void:
	starfury = ThrusterLayout.load_file(STARFURY)
	raider = ThrusterLayout.load_file(RAIDER)
	assert_true(starfury.valid and raider.valid, "fixtures load")


# --- helpers -------------------------------------------------------------------------------------------------------


## A made-up hull: `pods` pods alternating right and left, and `jets` RCS jets in a ring well off the centre.
func _hull(pods: int, jets: int) -> ThrusterLayout:
	var pod_list: Array = []
	for p: int in pods:
		var x: float = (2.0 + p) * (1.0 if p % 2 == 0 else -1.0)
		pod_list.append({"name": "p%d" % p, "side": "right" if p % 2 == 0 else "left",
				"main": {"position": [x, 0.0, 5.0], "exhaust": [0.0, 0.0, 1.0]},
				"retro": {"position": [x, 0.0, -5.0], "exhaust": [0.0, 0.0, -1.0]}})
	var rcs: Array = []
	for j: int in jets:
		var angle: float = TAU * float(j) / float(maxi(jets, 1))
		rcs.append({"name": "j%d" % j, "pod": "p0", "position": [10.0 * cos(angle), 10.0 * sin(angle), 8.0],
				"exhaust": [1.0, 0.0, 0.0], "tags": ["yaw_left", "sway_right"]})
	var layout := ThrusterLayout.from_dict({"pods": pod_list, "rcs": rcs}, Vector3.ZERO)
	assert_true(layout.valid, layout.error)
	return layout


func _output(mains: Array[float], retros: Array[float]) -> FlightOutput:
	var output := FlightOutput.new()
	output.main_levels = PackedFloat64Array(mains)
	output.retro_levels = PackedFloat64Array(retros)
	return output


func _distances(values: Array[float]) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for metres: float in values:
		out.append(metres * metres if metres >= 0.0 else -1.0)
	return out


## Voices of `ship` among the granted ones.
func _granted_of(voices: EngineVoices, ship: int) -> int:
	var n: int = 0
	for v: int in voices.active:
		n += 1 if voices.voice_ship[v] == ship else 0
	return n


## Seconds for a voice's level to go from `from` to `to` (rising or falling) under a steady target, stepping at 1 kHz.
func _time_between(voices: EngineVoices, v: int, from: float, to: float, limit_s: float) -> float:
	var started: float = -1.0
	var t: float = 0.0
	while t < limit_s:
		voices.step(0.001)
		t += 0.001
		var lvl: float = voices.level[v]
		var past_from: bool = lvl >= from if to > from else lvl <= from
		var past_to: bool = lvl >= to if to > from else lvl <= to
		if started < 0.0 and past_from:
			started = t
		if past_to:
			return t - started
	return INF


# --- RCS clusters --------------------------------------------------------------------------------------------------


func test_the_starfurys_sixteen_jets_make_four_clusters_one_per_pod() -> void:
	var clusters: Array[Dictionary] = EngineVoices.rcs_clusters(starfury)
	assert_eq(clusters.size(), 4)
	for cluster: Dictionary in clusters:
		var members: PackedInt32Array = cluster["members"]
		assert_eq(members.size(), 4)
		var pod: String = str(starfury.rcs_nozzles[members[0]]["pod"])
		var centre := Vector3.ZERO
		for j: int in members:
			assert_eq(str(starfury.rcs_nozzles[j]["pod"]), pod, "the jets of one pod, found by position alone")
			centre += starfury.rcs_nozzles[j]["position"] as Vector3
		assert_almost_eq(cluster["position"] as Vector3, centre / 4.0, Vector3.ONE * TOL, "the voice sits at their centre")


func test_the_raiders_six_jets_make_four_clusters() -> void:
	var clusters: Array[Dictionary] = EngineVoices.rcs_clusters(raider)
	assert_eq(clusters.size(), 4, "two wing tips (two jets each) and two edges")
	var sizes: Array[int] = []
	for cluster: Dictionary in clusters:
		sizes.append((cluster["members"] as PackedInt32Array).size())
	sizes.sort()
	assert_eq(sizes, [1, 1, 2, 2] as Array[int])


func test_clusters_come_from_positions_not_names() -> void:
	# Every jet claims pod "p0"; a centre-line jet and the far side still get clusters of their own.
	var layout := ThrusterLayout.from_dict({
		"pods": [{"name": "p0", "side": "right", "main": {"position": [2, 0, 5], "exhaust": [0, 0, 1]},
				"retro": {"position": [2, 0, -5], "exhaust": [0, 0, -1]}},
			{"name": "p1", "side": "left", "main": {"position": [-2, 0, 5], "exhaust": [0, 0, 1]},
				"retro": {"position": [-2, 0, -5], "exhaust": [0, 0, -1]}}],
		"rcs": [
			{"name": "a", "pod": "p0", "position": [6, 1, 4], "exhaust": [1, 0, 0], "tags": ["yaw_right"]},
			{"name": "b", "pod": "p0", "position": [6, 1.5, 4.5], "exhaust": [0, 1, 0], "tags": ["heave_down"]},
			{"name": "c", "pod": "p0", "position": [-6, 1, 4], "exhaust": [-1, 0, 0], "tags": ["yaw_left"]},
			{"name": "d", "pod": "p0", "position": [0.1, 1, -12], "exhaust": [0, 1, 0], "tags": ["pitch_up"]},
		]}, Vector3.ZERO)
	var clusters: Array[Dictionary] = EngineVoices.rcs_clusters(layout)
	assert_eq(clusters.size(), 3)
	assert_eq(clusters[0]["members"], PackedInt32Array([0, 1]), "two jets side by side share a voice")
	assert_eq(clusters[0]["tags"], PackedStringArray(["yaw_right", "heave_down"]), "and every tag either answers to")
	assert_eq(clusters[1]["members"], PackedInt32Array([2]), "the mirror image is another place")
	assert_eq(clusters[2]["members"], PackedInt32Array([3]), "a nose jet on the centre line is its own")


func test_no_jets_no_clusters() -> void:
	assert_eq(EngineVoices.rcs_clusters(_hull(2, 0)).size(), 0)


# --- voices of a ship ----------------------------------------------------------------------------------------------


func test_the_player_has_a_voice_per_pod_and_per_cluster_and_others_per_pod_only() -> void:
	var voices := EngineVoices.new()
	var me: int = voices.add_ship(starfury, true)
	var them: int = voices.add_ship(raider, false)
	assert_eq(voices.voices_of(me).size(), 4 + 4, "four pods, four RCS clusters")
	assert_eq(voices.voices_of(them).size(), 2, "two pods, no RCS")
	var pods: int = 0
	for v: int in voices.voices_of(me):
		if voices.voice_kind[v] == EngineVoices.Kind.POD:
			var pod: int = pods
			assert_eq(voices.voice_position[v], starfury.nozzle_positions[pod], "at the pod's main nozzle")
			assert_eq(voices.voice_retro_position[v], starfury.nozzle_positions[starfury.pod_count() + pod], "and its retro")
			pods += 1
	assert_eq(pods, 4)
	var clusters: Array[Dictionary] = EngineVoices.rcs_clusters(starfury)
	var c: int = 0
	for v: int in voices.voices_of(me):
		if voices.voice_kind[v] == EngineVoices.Kind.RCS:
			assert_eq(voices.voice_position[v], clusters[c]["position"] as Vector3, "at the cluster's centre")
			c += 1
	for v: int in voices.voices_of(them):
		assert_eq(voices.voice_kind[v], EngineVoices.Kind.POD)
		assert_eq(voices.voice_ship[v], them)


# --- the cap -------------------------------------------------------------------------------------------------------


func test_the_player_first_then_whole_ships_nearest_first_up_to_the_cap() -> void:
	var voices := EngineVoices.new()
	assert_eq(voices.cap, 24, "the default (settings.engine_voice_cap)")
	voices.add_ship(starfury, true)
	var metres: Array[float] = [0.0]
	for i: int in 10:
		voices.add_ship(raider, false)
		metres.append(1000.0 - 90.0 * i)  # the last added is nearest
	voices.allocate(_distances(metres))
	assert_eq(voices.active.size(), 24)
	assert_eq(_granted_of(voices, 0), 8, "the player's own voices")
	for ship: int in range(3, 11):
		assert_eq(_granted_of(voices, ship), 2, "raider %d, among the nearest eight" % ship)
	assert_eq(_granted_of(voices, 1) + _granted_of(voices, 2), 0, "the two farthest wait")
	assert_eq(voices.voiced_ships.size(), 9)


func test_ships_out_of_range_or_out_of_play_get_no_voices() -> void:
	var voices := EngineVoices.new()
	voices.add_ship(starfury, true)
	voices.add_ship(raider, false)
	voices.add_ship(raider, false)
	voices.allocate(_distances([0.0, EngineVoices.AUDIBLE_RANGE_M + 1.0, -1.0]))
	assert_eq(voices.active.size(), 8, "beyond hearing, and parked, are silent")
	voices.allocate(_distances([-1.0, 100.0, 200.0]))
	assert_eq(_granted_of(voices, 0), 0, "a player out of play has no voices either")
	assert_eq(voices.active.size(), 4)


func test_only_whole_ships_are_voiced() -> void:
	var voices := EngineVoices.new()
	voices.cap = 11
	voices.add_ship(starfury, true)
	voices.add_ship(starfury, false)  # nearest, but its four pods do not fit in the three left
	voices.add_ship(raider, false)
	voices.allocate(_distances([0.0, 50.0, 300.0]))
	assert_eq(_granted_of(voices, 1), 0)
	assert_eq(_granted_of(voices, 2), 2, "the next ship that fits")
	assert_eq(voices.active.size(), 10)


func test_a_cap_below_the_players_count_keeps_its_pods_first() -> void:
	var voices := EngineVoices.new()
	voices.cap = 5
	voices.add_ship(starfury, true)
	voices.allocate(_distances([0.0]))
	assert_eq(voices.active.size(), 5)
	var pods: int = 0
	for v: int in voices.active:
		pods += 1 if voices.voice_kind[v] == EngineVoices.Kind.POD else 0
	assert_eq(pods, 4)


func test_a_voice_that_loses_its_grant_is_listed_and_restarts_cold() -> void:
	var voices := EngineVoices.new()
	voices.add_ship(starfury, true)
	var them: int = voices.add_ship(raider, false)
	voices.allocate(_distances([0.0, 100.0]))
	voices.set_output(them, _output([1.0, 1.0], [0.0, 0.0]))
	voices.step(0.5)
	var v: int = voices.voices_of(them)[0]
	assert_gt(voices.level[v], 0.9)
	voices.allocate(_distances([0.0, EngineVoices.AUDIBLE_RANGE_M * 2.0]))
	assert_eq(voices.revoked, voices.voices_of(them), "both of its voices")
	assert_eq(voices.level[v], 0.0)
	voices.allocate(_distances([0.0, EngineVoices.AUDIBLE_RANGE_M * 2.0]))
	assert_eq(voices.revoked.size(), 0, "listed once")


# --- levels --------------------------------------------------------------------------------------------------------


func test_a_pod_voice_follows_its_pods_main_and_retro_and_sits_at_the_one_firing() -> void:
	var voices := EngineVoices.new()
	var me: int = voices.add_ship(starfury, true)
	voices.allocate(_distances([0.0]))
	var pods: PackedInt32Array = voices.voices_of(me).slice(0, 4)
	voices.set_output(me, _output([1.0, 0.0, 0.0, 0.0], [0.0, 0.6, 0.0, 0.0]))
	voices.step(0.2)
	assert_almost_eq(voices.target[pods[0]], 1.0, TOL)
	assert_almost_eq(voices.level[pods[0]], 1.0, 1e-3, "settled after 0.2 s")
	assert_eq(voices.at_retro[pods[0]], 0)
	assert_almost_eq(voices.target[pods[1]], 0.6, TOL, "the retro drives the same voice")
	assert_eq(voices.at_retro[pods[1]], 1, "heard at the retro nozzle")
	assert_eq(voices.level[pods[2]], 0.0, "an idle pod is silent")


func test_a_cluster_voice_follows_the_strongest_of_its_jets() -> void:
	var voices := EngineVoices.new()
	var me: int = voices.add_ship(starfury, true)
	voices.allocate(_distances([0.0]))
	var output := FlightOutput.new()
	output.rcs_force_level = Vector3(0.7, 0.0, 0.0)  # sway right: the -x jets of every pod
	voices.set_output(me, output)
	voices.step(DT)
	var clusters: Array[Dictionary] = EngineVoices.rcs_clusters(starfury)
	var c: int = 0
	for v: int in voices.voices_of(me):
		if voices.voice_kind[v] == EngineVoices.Kind.RCS:
			var expected: float = ThrusterGlowLevels.rcs_level(clusters[c]["tags"], output.rcs_force_level, output.rcs_torque_level)
			assert_almost_eq(voices.target[v], expected, TOL)
			assert_almost_eq(voices.target[v], 0.7, TOL, "every pod has a jet that sways right")
			c += 1


func test_a_whisper_of_demand_stays_silent() -> void:
	var voices := EngineVoices.new()
	var me: int = voices.add_ship(starfury, true)
	voices.allocate(_distances([0.0]))
	voices.set_output(me, _output([EngineVoices.GATE * 0.5, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]))
	voices.step(0.5)
	assert_eq(voices.target[voices.voices_of(me)[0]], 0.0)
	assert_eq(voices.level[voices.voices_of(me)[0]], 0.0)


func test_no_output_yet_is_silence() -> void:
	var voices := EngineVoices.new()
	var me: int = voices.add_ship(starfury, true)
	voices.allocate(_distances([0.0]))
	voices.step(DT)
	for v: int in voices.voices_of(me):
		assert_eq(voices.level[v], 0.0)


# --- envelopes -----------------------------------------------------------------------------------------------------


func test_envelopes_step_exactly_whatever_the_frame_rate() -> void:
	var a: float = 0.0
	for i: int in 6:
		a = EngineVoices.step_level(a, 1.0, 1.0 / 60.0, 0.03, 0.2)
	var b: float = EngineVoices.step_level(0.0, 1.0, 0.1, 0.03, 0.2)
	assert_almost_eq(a, b, 1e-9, "six 60 Hz frames are one 0.1 s step")
	assert_eq(EngineVoices.step_level(0.5, 1.0, -1.0, 0.03, 0.2), 0.5, "a negative step does nothing")
	assert_lt(EngineVoices.step_level(1.0, 0.0, 0.01, 0.03, 0.2), 1.0, "falls toward a lower target")
	assert_gt(EngineVoices.step_level(1.0, 0.0, 0.01, 0.03, 0.2), EngineVoices.step_level(1.0, 0.0, 0.01, 0.03, 0.1),
			"at the release rate, not the attack's")


func test_a_pod_rises_in_5_to_35_ms_and_stops_in_30_to_50_ms() -> void:
	# Reference step roar: attack (10-90 %) 5-35 ms; cut 30-50 ms.
	var voices := EngineVoices.new()
	var me: int = voices.add_ship(starfury, true)
	voices.allocate(_distances([0.0]))
	var v: int = voices.voices_of(me)[0]
	voices.set_output(me, _output([1.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]))
	var rise: float = _time_between(voices, v, 0.1, 0.9, 1.0)
	assert_between(rise, 0.005, 0.035, "attack %.3f s" % rise)
	voices.step(1.0)
	voices.set_output(me, _output([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]))
	var cut: float = _time_between(voices, v, 1.0, db_to_linear(-30.0), 1.0)
	assert_between(cut, 0.030, 0.050, "30 dB down in %.3f s" % cut)


func test_a_jet_rises_in_25_to_100_ms_and_releases_slower_after_a_long_burn() -> void:
	# Reference swell and jet: attack 25-100 ms; release tau 120-250 ms after a pulse, up to 0.65 s after a long burn.
	var voices := EngineVoices.new()
	var me: int = voices.add_ship(starfury, true)
	voices.allocate(_distances([0.0]))
	var v: int = voices.voices_of(me)[4]
	assert_eq(voices.voice_kind[v], EngineVoices.Kind.RCS)
	var firing := FlightOutput.new()
	firing.rcs_force_level = Vector3(-1.0, 0.0, 0.0)  # sway left: every pod has a +x jet
	voices.set_output(me, firing)
	var rise: float = _time_between(voices, v, 0.1, 0.9, 1.0)
	assert_between(rise, 0.025, 0.100, "attack %.3f s" % rise)
	assert_between(EngineVoices.rcs_release_tau(0.1), 0.12, 0.25, "after a pulse")
	assert_almost_eq(EngineVoices.rcs_release_tau(5.0), 0.65, TOL, "after a long burn")
	assert_lt(EngineVoices.rcs_release_tau(0.1), EngineVoices.rcs_release_tau(1.0))
	voices.step(3.0)  # a long burn
	voices.set_output(me, FlightOutput.new())
	var tau: float = _time_between(voices, v, 1.0, exp(-1.0), 3.0)
	assert_almost_eq(tau, 0.65, 0.01, "1/e after %.3f s" % tau)


func test_a_jets_brightness_follows_its_level() -> void:
	# Reference: brightness rises about an octave in the attack and falls in the release; the game plays the jet lower.
	assert_almost_eq(EngineVoices.rcs_pitch(0.0), 0.5, TOL, "an octave low at silence")
	assert_almost_eq(EngineVoices.rcs_pitch(1.0), 1.0, TOL, "its own pitch at full level")
	assert_lt(EngineVoices.rcs_pitch(0.3), EngineVoices.rcs_pitch(0.6))


func test_voices_start_at_different_points_of_their_loop() -> void:
	var seen: Dictionary = {}
	for v: int in 24:
		var at: float = EngineVoices.start_offset(v, 4.0)
		assert_between(at, 0.0, 4.0)
		seen[snappedf(at, 0.01)] = true
	assert_eq(seen.size(), 24, "no two voices of a ship in step (they would comb-filter)")


# --- cost ----------------------------------------------------------------------------------------------------------


## Work of one allocation and one step with the player and `ships` others of `layout`, every one in range.
func _work(ships: int, layout: ThrusterLayout, cap: int) -> Dictionary:
	var voices := EngineVoices.new()
	voices.cap = cap
	voices.add_ship(starfury, true)
	var metres: Array[float] = [0.0]
	for i: int in ships:
		voices.add_ship(layout, false)
		metres.append(10.0 + float(i))
	voices.allocate(_distances(metres))
	var output := _output([1.0, 1.0, 1.0, 1.0], [0.0, 0.0, 0.0, 0.0])
	for ship: int in voices.voiced_ships:
		voices.set_output(ship, output)
	voices.step(DT)
	return {"step": voices.step_work, "voices": voices.active.size(), "allocate": voices.allocate_work}


func test_the_per_frame_step_is_linear_in_voices_not_ships_times_nozzles() -> void:
	var few: Dictionary = _work(4, raider, 24)
	var many: Dictionary = _work(300, _hull(16, 64), 24)
	assert_eq(few["step"], few["voices"], "one unit of work per granted voice")
	assert_eq(many["step"], many["voices"])
	assert_lte(many["step"], 24, "300 ships of 16 pods and 64 jets: still bounded by the cap")
	assert_eq(many["step"], 8 + 16, "the player and one sixteen-pod ship")
	var wide: Dictionary = _work(300, _hull(2, 64), 48)
	assert_eq(wide["step"], 48, "a bigger cap, proportionally more work")
	var bare: Dictionary = _work(300, _hull(2, 0), 48)
	assert_eq(bare["step"], wide["step"], "the jets of ships without RCS voices cost nothing")


func test_allocation_is_linear_in_ships_and_ignores_nozzles() -> void:
	assert_eq(_work(10, _hull(2, 0), 24)["allocate"], 11)
	assert_eq(_work(300, _hull(2, 0), 24)["allocate"], 301)
	assert_eq(_work(300, _hull(16, 64), 24)["allocate"], 301, "the same with eight times the nozzles")
