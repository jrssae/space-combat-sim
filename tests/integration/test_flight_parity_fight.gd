extends GutTest
## Q16 for the native flight step (M4-T10): a seeded fight (`bench furball 25 <s> seed=1` on the combat sandbox, then the
## `ai`, `combat` and `flight` providers) with the flight batch against the same fight on the ships' own GDScript models must
## give hits within 10 %, a behaviour mix within 5 points (printed only since M7-T16, below), and no ship more than 50 m from
## its twin at 10 s. Each fight runs in
## its own process (this Godot launched again, headless), because a second fight in one process is never the same fight: the
## absolute sim clock, the pooled nodes and the statics differ from the first.
##
## Since M4-T37 both references are recordings (`tests/fixtures/parity/flight_parity_fight.json`, `ParityFixture`), taken
## before the GDScript flight path and the single-thread step were removed:
## - `gdscript_*`: the console lines of the fight on the ships' own models on the single-thread step, Q16's reference; the
##   batch gave the same lines on that step (checked when recorded). On the threaded step a command reaches its ship one tick
##   later (Q53, new reference outcomes accepted): the mix stays within 5 points and the hits within 20 %; the twins' distance
##   is printed, not gated.
## - `native_*`: the batch's lines on the delayed step (the threaded step's bit-for-bit reference), which the threaded fight
##   must print exactly.

const SHIPS: int = 25
const TWIN_AT_S: int = 10
const FIGHT_S: int = 30
## Hits against the GDScript reference on the threaded step: Q16's 10 % widened for the one-tick handover (Q53).
const HIT_TOL: float = 0.20
## The bench warms up 5 s before measuring, so a measured window of this many seconds ends 10 s into the fight.
const TWIN_MEASURE_S: int = TWIN_AT_S - 5
const FIGHT_MEASURE_S: int = FIGHT_S - 5
const LABEL_ROOT: String = "test_flight_parity"
const FIXTURE: String = "flight_parity_fight"
## The console lines a fight is held to.
const KEPT: Array[String] = ["flight.positions", "combat.hits", "ai.by_behaviour", "ai.ships", "ram.events"]


# A slow file (M4-T36, Q58): runs with GUT_SLOW=1 (the full run and CI), skipped in focused runs.
@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


# Runs one seeded fight in a fresh process and returns the console's lines by key (`ai.ships`, `combat.hits`, ...).
func _fight(settings: String, measure_s: int, label: String) -> Dictionary:
	var script: String = "%s; scenario combat_sandbox; wait 30; bench furball %d %d seed=1 label=%s/%s; state ai; state combat; state ram; state flight; quit" % [
			settings, SHIPS, measure_s, LABEL_ROOT, label]
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--console-strict",
			"--console-exec=" + script])
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = "\n".join(output)
	var lines: Dictionary = {}
	for line: String in text.split("\n"):
		var m: RegExMatch = _LINE.search(line)
		if m != null:
			lines[m.get_string(1)] = m.get_string(2)
	assert_eq(code, 0, "%s: the fight's process exits cleanly (%s)" % [label, text.right(600) if code != 0 else "ok"])
	assert_true(lines.has("combat.hits"), "%s: the fight printed its state" % label)
	return lines


static var _LINE: RegEx = RegEx.create_from_string("^\\[console\\] (\\w+\\.\\w+) = (.*)$")


# `flight.positions`: name and World position per ship.
static func _positions(lines: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var text: String = str(lines.get("flight.positions", "[]")).trim_prefix("[").trim_suffix("]")
	for item: String in text.split(", ", false):
		var parts: PackedStringArray = item.rsplit(" ", true, 3)
		if parts.size() == 4:
			out[parts[0]] = Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
	return out


# `ai.by_behaviour`: `{attack: 19, evade: 6}` as counts by behaviour.
static func _mix(lines: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var text: String = str(lines.get("ai.by_behaviour", "{}")).trim_prefix("{").trim_suffix("}")
	for item: String in text.split(",", false):
		var parts: PackedStringArray = item.strip_edges().split(":")
		if parts.size() == 2:
			out[parts[0].strip_edges()] = int(parts[1].strip_edges())
	return out


func test_the_seeded_fight_matches_its_recordings() -> void:
	var case: String = "furball_%d_seed_1" % SHIPS
	if ParityFixture.recording():  # the delayed step's lines are the threaded fight's reference (M7-T16 re-recorded them)
		ParityFixture.rerecorded(FIXTURE, case, _kept(await _fight_async(_DELAYED, TWIN_MEASURE_S, "delayed_10s")), "native_10s")
		ParityFixture.rerecorded(FIXTURE, case, _kept(await _fight_async(_DELAYED, FIGHT_MEASURE_S, "delayed_30s")), "native_30s")
	var recorded: Variant = ParityFixture.stored(FIXTURE, case)
	assert_not_null(recorded, "the references were recorded")
	if recorded == null:
		return
	var on_10: Dictionary = await _fight_async(_THREADED, TWIN_MEASURE_S, "on_10s")
	var on_30: Dictionary = await _fight_async(_THREADED, FIGHT_MEASURE_S, "on_30s")
	assert_eq(on_10.get("flight.path"), "native", "the batch flew the fight")
	assert_eq(on_10.get("flight.stepped"), str(SHIPS), "every ship in the batch")
	assert_eq(ParityFixture.encode(_kept(on_10)), recorded["native_10s"], "the threaded fight's 10 s are the recorded ones")
	assert_eq(ParityFixture.encode(_kept(on_30)), recorded["native_30s"], "and its 30 s")
	# Q16 against the GDScript fight.
	var on_pos: Dictionary = _positions(on_10)
	var off_pos: Dictionary = _positions(recorded["gdscript_10s"])
	assert_eq(on_pos.size(), SHIPS, "every ship printed its position")
	var worst_m: float = 0.0
	for ship_name: String in on_pos:
		assert_true(off_pos.has(ship_name), "%s flew in the reference too" % ship_name)
		if off_pos.has(ship_name):
			worst_m = maxf(worst_m, (on_pos[ship_name] as Vector3).distance_to(off_pos[ship_name]))
	var off_30: Dictionary = recorded["gdscript_30s"]
	var hits_on: int = int(on_30.get("combat.hits", "0"))
	var hits_off: int = int(off_30.get("combat.hits", "0"))
	var mix_on: Dictionary = _mix(on_30)
	var mix_off: Dictionary = _mix(off_30)
	var worst_points: float = 0.0
	for behaviour: Variant in mix_on.keys() + mix_off.keys():
		var share_on: float = 100.0 * float(mix_on.get(behaviour, 0)) / float(SHIPS)
		var share_off: float = 100.0 * float(mix_off.get(behaviour, 0)) / float(SHIPS)
		worst_points = maxf(worst_points, absf(share_on - share_off))
	gut.p("Q16 against the GDScript fight: worst twin at %d s %.3f m over %d ships; hits over %d s %d against %d; mix %s against %s (%.1f points)" % [
			TWIN_AT_S, worst_m, on_pos.size(), FIGHT_S, hits_on, hits_off, mix_on, mix_off, worst_points])
	assert_gt(hits_off, 0, "the reference fight landed hits")
	assert_lte(absf(float(hits_on - hits_off)), HIT_TOL * float(maxi(hits_off, 1)), "hits within 20 % of the GDScript fight")
	# The mix is printed, no longer gated (M7-T16): the GDScript fight flew the raider as it was until M7-T16, and with the
	# GDScript flight path gone (M4-T37) it cannot be flown again on the raider's new hull, whose fights mix differently
	# (12 points on this seed). The hits stay gated; the bit-for-bit gate above holds the native step.
	gut.p("the behaviour mix %.1f points from the M4 GDScript fight (printed, not gated since M7-T16)" % worst_points)


const _THREADED: String = "set settings.sim_step threaded"
const _DELAYED: String = "set settings.sim_step delayed"


# The lines a fight is held to, as recorded.
static func _kept(lines: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in KEPT:
		out[key] = str(lines.get(key, ""))
	return out


# The recording (M4-T37) was taken at `0586e3e`, whose game code is the tag `m4-gdscript-reference`'s (README): the fight on the ships' own models on the
# single-thread step (`gdscript_*`), which the batch matched bit for bit on that step, and the batch's fight on the
# delayed step (`native_*`). Both paths are gone, so `gdscript_*` is read, never recorded again; M7-T16 re-recorded `native_*`
# from the delayed step for the raider's new hull (README).


# `OS.execute` blocks this process; one idle frame first keeps the runner's output in order.
func _fight_async(settings: String, measure_s: int, label: String) -> Dictionary:
	await get_tree().process_frame
	return _fight(settings, measure_s, label)
