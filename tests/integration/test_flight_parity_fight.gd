extends GutTest
## Q16 for the native flight step (M4-T10): the same seeded fight with the flight batch on and off must give hits within 10 %,
## a behaviour mix within 5 points, and no ship more than 50 m from its twin at 10 s. Each fight runs in its own process (this
## Godot launched again, headless, on the combat sandbox: `bench furball 25 <s> seed=1`, then the `ai`, `combat` and `flight`
## providers), because a second fight in one process is never the same fight: the absolute sim clock, the pooled nodes and the
## statics differ from the first, and a 24-ship furball turns that into kilometres by 10 s on one path alone. A fresh process
## reproduces a seeded fight to the centimetre the console prints, and the step is bit-identical to the model, so the expected
## outcome is equality; the test prints how close it came. Skips, saying why, when the native library is not built.

const SHIPS: int = 25
const TWIN_AT_S: int = 10
const FIGHT_S: int = 30
const HIT_TOL: float = 0.10
const MIX_TOL_POINTS: float = 5.0
const TWIN_TOL_M: float = 50.0
## The bench warms up 5 s before measuring, so a measured window of this many seconds ends 10 s into the fight.
const TWIN_MEASURE_S: int = TWIN_AT_S - 5
const FIGHT_MEASURE_S: int = FIGHT_S - 5
const LABEL_ROOT: String = "test_flight_parity"


func _skipped() -> bool:
	if NativeLib.has_class(FlightBatch.NATIVE_CLASS):
		return false
	pending("the native library is not built (scripts/build_native.sh), so there is no native path to compare")
	return true


# Runs one seeded fight in a fresh process and returns the console's lines by key (`ai.ships`, `combat.hits`, ...).
func _fight(flight_batch_on: bool, measure_s: int, label: String) -> Dictionary:
	var script: String = "set settings.perf_native_flight %s; scenario combat_sandbox; wait 30; bench furball %d %d seed=1 label=%s/%s; state ai; state combat; state ram; state flight; quit" % [
			"true" if flight_batch_on else "false", SHIPS, measure_s, LABEL_ROOT, label]
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


func test_the_same_seeded_fight_with_the_batch_on_and_off_meets_q16() -> void:
	if _skipped():
		return
	# Positions 10 s into the fight.
	var on_10: Dictionary = await _fight_async(true, TWIN_MEASURE_S, "on_10s")
	var off_10: Dictionary = await _fight_async(false, TWIN_MEASURE_S, "off_10s")
	assert_eq(on_10.get("flight.path"), "native", "the batch flew the on path")
	assert_eq(on_10.get("flight.stepped"), str(SHIPS), "every ship in the batch")
	assert_eq(off_10.get("flight.path"), "gdscript", "the ships' own models flew the off path")
	var on_pos: Dictionary = _positions(on_10)
	var off_pos: Dictionary = _positions(off_10)
	assert_eq(on_pos.size(), SHIPS, "every ship printed its position")
	var worst_m: float = 0.0
	for ship_name: String in on_pos:
		assert_true(off_pos.has(ship_name), "%s flew on both paths" % ship_name)
		if off_pos.has(ship_name):
			worst_m = maxf(worst_m, (on_pos[ship_name] as Vector3).distance_to(off_pos[ship_name]))
	gut.p("Q16: worst twin distance at %d s %.3f m over %d ships" % [TWIN_AT_S, worst_m, on_pos.size()])
	assert_lt(worst_m, TWIN_TOL_M, "no ship more than 50 m from its twin at 10 s")
	# Hits and the behaviour mix over the 30 s fight.
	var on_30: Dictionary = await _fight_async(true, FIGHT_MEASURE_S, "on_30s")
	var off_30: Dictionary = await _fight_async(false, FIGHT_MEASURE_S, "off_30s")
	var hits_on: int = int(on_30.get("combat.hits", "0"))
	var hits_off: int = int(off_30.get("combat.hits", "0"))
	var mix_on: Dictionary = _mix(on_30)
	var mix_off: Dictionary = _mix(off_30)
	var worst_points: float = 0.0
	for behaviour: Variant in mix_on.keys() + mix_off.keys():
		var share_on: float = 100.0 * float(mix_on.get(behaviour, 0)) / float(SHIPS)
		var share_off: float = 100.0 * float(mix_off.get(behaviour, 0)) / float(SHIPS)
		worst_points = maxf(worst_points, absf(share_on - share_off))
	gut.p("Q16: hits over %d s %d with the batch and %d without; mix %s against %s (%.1f points)" % [FIGHT_S, hits_on, hits_off,
			mix_on, mix_off, worst_points])
	assert_gt(hits_off, 0, "the fight landed hits")
	assert_lte(absf(float(hits_on - hits_off)), HIT_TOL * float(maxi(hits_off, 1)), "hits within 10 %")
	assert_lte(worst_points, MIX_TOL_POINTS, "the behaviour mix within 5 points")
	if on_30.get("ai.ships") == off_30.get("ai.ships") and hits_on == hits_off and on_30.get("ram.events") == off_30.get("ram.events"):
		gut.p("the two fights ended with the same behaviour line for every ship and the same hits")


# `OS.execute` blocks this process; one idle frame first keeps the runner's output in order.
func _fight_async(flight_batch_on: bool, measure_s: int, label: String) -> Dictionary:
	await get_tree().process_frame
	return _fight(flight_batch_on, measure_s, label)
