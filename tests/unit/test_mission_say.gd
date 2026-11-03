extends GutTest
## `MissionApi.say` with a dialog book (architecture §18 D51, D53, M5-T06): a line is queued, shown for its hold time and the
## call resolves when it has finished; the `dialog_finished` trigger sees it; a skipped step logs lines and shows none; an
## interrupt cuts the line showing; the mission ending cuts what is left. Without a book it resolves at once (T05's tests).

const DT: float = 1.0 / 60.0


## Two one-second lines, one after the other, then a step that waits for a third.
class Talker extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"talk", &"wait_for_three"]

	func step_talk(m: MissionApi) -> void:
		trace.append("talk")
		await m.say(&"one")
		trace.append("one done")
		await m.say(&"two")
		trace.append("two done")

	func step_wait_for_three(m: MissionApi) -> void:
		m.say(&"three")  # not awaited: the next line is waited for through its trigger
		await m.until(TriggerSpec.dialog_finished(&"three"))
		trace.append("three finished")


## A line that is not awaited and an urgent one that cuts it.
class Interrupter extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"cut"]

	func step_cut(m: MissionApi) -> void:
		m.say(&"long")
		await m.say(&"urgent", true)
		trace.append("urgent done")


## Waits in its first step, says a line in its second, and is sent past it to the third.
class Late extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"first", &"middle", &"last"]

	func step_first(m: MissionApi) -> void:
		await m.wait(5.0)

	func step_middle(m: MissionApi) -> void:
		await m.say(&"two")
		trace.append("middle")

	func step_last(m: MissionApi) -> void:
		trace.append("last")
		await m.wait(100.0)


## Says a line that is not in the book.
class Typo extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"oops"]

	func step_oops(m: MissionApi) -> void:
		await m.say(&"no_such_line")
		trace.append("went on")


## Ends the mission while its line is showing.
class EndsMidLine extends MissionScript:
	var trace: Array[String] = []

	func steps() -> Array[StringName]:
		return [&"talk"]

	func step_talk(m: MissionApi) -> void:
		m.say(&"long")
		await m.wait(0.5)
		m.end(true)
		trace.append("ended")


var world: MissionWorld
var api: MissionApi
var started: Array[StringName] = []
var finished: Array[String] = []


func before_each() -> void:
	world = MissionWorld.new()
	api = MissionApi.new(world, ObjectiveBook.new())
	started = []
	finished = []
	api.dialog.started.connect(func(_ticket: int, line: DialogBook.Line) -> void: started.append(line.id))
	api.dialog.finished.connect(func(_ticket: int, line: DialogBook.Line, cut: bool) -> void:
			finished.append("%s%s" % [line.id, " (cut)" if cut else ""]))


func after_each() -> void:
	api.release()


func _book() -> DialogBook:
	var book := DialogBook.new()
	assert_eq(book.add_speakers({"speakers": [{"id": "control", "name": "Control", "callsign": "CONTROL", "faction": "earth_alliance"}]},
			"t"), "")
	var lines: Array = []
	for entry: Array in [["one", 1.0], ["two", 1.0], ["three", 1.0], ["long", 10.0], ["urgent", 1.0]]:
		lines.append({"id": entry[0], "speaker": "control", "text": "line %s" % entry[0], "voice": "v", "hold_s": entry[1]})
	assert_eq(book.add_lines({"lines": lines}, "t"), "")
	return book


func _start(script: MissionScript, with_book: bool = true) -> void:
	if with_book:
		api.dialog_book = _book()
	assert_eq(api.begin(script), "")


func _ticks(count: int) -> void:
	for _i: int in count:
		api.tick(DT, {})


# --- a line is shown, then the call resolves ---------------------------------------------------------------------------------


func test_say_queues_the_line_and_resolves_when_it_has_finished_showing() -> void:
	var script := Talker.new()
	_start(script)
	assert_eq(api.dialog.current.id, &"one", "shown at once")
	assert_eq(script.trace, ["talk"] as Array[String], "and the step waits")
	_ticks(59)
	assert_eq(script.trace, ["talk"] as Array[String], "a second is 60 ticks")
	assert_false(world.line_finished(&"one"))
	_ticks(2)
	assert_eq(script.trace, ["talk", "one done"] as Array[String])
	assert_true(world.line_finished(&"one"), "recorded for dialog_finished triggers")
	assert_has(api.journal, "say one")


func test_the_next_line_waits_out_the_gap_and_then_shows() -> void:
	var script := Talker.new()
	_start(script)
	_ticks(61)
	assert_null(api.dialog.current, "the gap after one")
	assert_eq(api.dialog.queued_count(), 1)
	_ticks(roundi(DialogQueue.GAP_S / DT) + 1)
	assert_eq(api.dialog.current.id, &"two")
	_ticks(61)
	assert_eq(script.trace, ["talk", "one done", "two done"] as Array[String])
	assert_eq(api.step_name(), &"wait_for_three")
	assert_eq(started, [&"one", &"two"] as Array[StringName], "three comes after the gap that follows two")


func test_a_dialog_finished_trigger_fires_when_its_line_ends() -> void:
	var script := Talker.new()
	_start(script)
	_ticks(61 + 25 + 61 + 1)  # one, the gap, two
	assert_eq(api.step_name(), &"wait_for_three")
	assert_false(script.trace.has("three finished"))
	_ticks(25 + 61)  # the gap, three
	assert_true(script.trace.has("three finished"))
	assert_true(world.line_finished(&"three"))


func test_mission_time_is_what_moves_a_line() -> void:
	var script := Talker.new()
	_start(script)
	api.dialog.tick(0.0)
	assert_eq(api.dialog.elapsed_s, 0.0)
	_ticks(30)
	assert_almost_eq(api.dialog.elapsed_s, 30.0 * DT, 1e-9, "each mission tick moves it one tick")


# --- skipping --------------------------------------------------------------------------------------------------------------


func test_skipping_a_step_logs_its_lines_and_shows_none_after_the_one_showing() -> void:
	var script := Talker.new()
	_start(script)
	_ticks(10)
	assert_eq(api.skip(), "")
	assert_eq(script.trace, ["talk", "one done", "two done"] as Array[String], "the step ran to its end at once")
	assert_eq(started, [&"one", &"three"] as Array[StringName], "two was never shown; three is the next, unskipped step")
	assert_eq(finished, ["one (cut)"] as Array[String], "the line showing was cut")
	assert_true(world.line_finished(&"one"))
	assert_true(world.line_finished(&"two"), "logged and finished though never shown")
	assert_has(api.journal, "say two")
	assert_eq(api.dialog.current.id, &"three", "the step after the skip speaks normally")


func test_goto_skips_every_line_before_the_named_step() -> void:
	var script := Talker.new()
	_start(script)
	assert_eq(api.goto(&"wait_for_three"), "")
	assert_eq(started, [&"one", &"three"] as Array[StringName], "one was showing when the skip came")
	assert_true(world.line_finished(&"two"))


func test_a_step_that_starts_skipped_never_shows_its_lines() -> void:
	var script := Late.new()
	_start(script)
	assert_eq(api.goto(&"last"), "")
	assert_eq(script.trace, ["middle", "last"] as Array[String])
	assert_eq(started.size(), 0, "the middle step was skipped from its first line")
	assert_true(world.line_finished(&"two"), "and its line counts as said")
	assert_has(api.journal, "say two")


# --- interrupting, errors and the end --------------------------------------------------------------------------------------


func test_an_interrupting_say_cuts_the_line_showing() -> void:
	var script := Interrupter.new()
	_start(script)
	assert_eq(started, [&"long", &"urgent"] as Array[StringName])
	assert_eq(finished, ["long (cut)"] as Array[String])
	assert_true(world.line_finished(&"long"), "a cut line is finished: nothing may wait for it forever")
	_ticks(61)
	assert_eq(script.trace, ["urgent done"] as Array[String])


func test_a_line_that_is_not_in_the_book_is_an_error_and_the_step_goes_on() -> void:
	var script := Typo.new()
	_start(script)
	assert_push_error("no_such_line")
	assert_eq(script.trace, ["went on"] as Array[String])
	assert_true(world.line_finished(&"no_such_line"), "so nothing waits on it")
	assert_eq(started.size(), 0)


func test_without_a_book_say_is_logged_and_finished_at_once() -> void:
	var script := Talker.new()
	_start(script, false)
	assert_eq(script.trace.slice(0, 3), ["talk", "one done", "two done"] as Array[String])
	assert_true(world.line_finished(&"one"))
	assert_eq(started.size(), 0)


func test_the_mission_ending_cuts_the_line_showing() -> void:
	var script := EndsMidLine.new()
	_start(script)
	assert_eq(api.dialog.current.id, &"long")
	_ticks(31)
	assert_true(api.has_ended())
	assert_null(api.dialog.current, "nothing keeps talking over the debrief")
	assert_eq(finished, ["long (cut)"] as Array[String])
