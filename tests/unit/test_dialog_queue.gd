extends GutTest
## DialogQueue (architecture §18 D53, M5-T06): comms lines play one at a time, in order, with a short gap between them; a `say`
## that interrupts cuts the line showing; time comes from the deltas it is given and nothing else.

const DT: float = 1.0 / 60.0

var queue: DialogQueue
## Every event the queue raised, in order: `start a`, `end a`, `cut a`.
var events: Array[String] = []


func before_each() -> void:
	queue = DialogQueue.new()
	events = []
	queue.started.connect(func(_ticket: int, line: DialogBook.Line) -> void: events.append("start %s" % line.id))
	queue.finished.connect(func(_ticket: int, line: DialogBook.Line, cut: bool) -> void:
			events.append("%s %s" % ["cut" if cut else "end", line.id]))


func _line(id: StringName, hold_s: float = 2.0) -> DialogBook.Line:
	return DialogBook.Line.new(id, &"control", "text of %s" % id, &"voice", hold_s)


func _run(seconds: float) -> void:
	var ticks: int = roundi(seconds / DT)
	for _i: int in ticks:
		queue.tick(DT)


# --- one line --------------------------------------------------------------------------------------------------------------


func test_a_line_said_while_idle_starts_at_once() -> void:
	var ticket: int = queue.say(_line(&"a"))
	assert_gt(ticket, 0)
	assert_eq(queue.current.id, &"a")
	assert_eq(queue.current_ticket, ticket)
	assert_eq(queue.queued_count(), 0)
	assert_true(queue.is_pending(ticket))
	assert_eq(events, ["start a"] as Array[String])


func test_the_line_ends_after_its_hold_time_and_not_before() -> void:
	var ticket: int = queue.say(_line(&"a", 2.0))
	_run(1.9)
	assert_not_null(queue.current)
	assert_true(queue.is_pending(ticket))
	_run(0.1 + DT)
	assert_null(queue.current)
	assert_false(queue.is_pending(ticket))
	assert_eq(events, ["start a", "end a"] as Array[String])


func test_120_ticks_of_a_sixtieth_reach_a_two_second_line() -> void:
	queue.say(_line(&"a", 2.0))
	for _i: int in 120:
		queue.tick(DT)
	assert_null(queue.current, "summed deltas may fall a hair short; the queue allows for it")


func test_elapsed_time_counts_only_the_deltas_it_is_given() -> void:
	queue.say(_line(&"a", 4.0))
	queue.tick(0.0)
	queue.tick(-1.0)
	assert_eq(queue.elapsed_s, 0.0, "a zero or negative delta moves nothing")
	queue.tick(1.5)
	assert_almost_eq(queue.elapsed_s, 1.5, 1e-9)
	assert_almost_eq(queue.remaining_s(), 2.5, 1e-9)


# --- order -----------------------------------------------------------------------------------------------------------------


func test_lines_play_one_at_a_time_in_the_order_said_with_a_gap() -> void:
	queue.say(_line(&"a", 1.0))
	queue.say(_line(&"b", 1.0))
	queue.say(_line(&"c", 1.0))
	assert_eq(queue.current.id, &"a")
	assert_eq(queue.queued_count(), 2)
	_run(1.0 + DT)
	assert_null(queue.current, "the gap: nothing shows between two lines")
	assert_eq(queue.queued_count(), 2)
	_run(DialogQueue.GAP_S)
	assert_eq(queue.current.id, &"b")
	_run(1.0 + DialogQueue.GAP_S + 2.0 * DT)
	assert_eq(queue.current.id, &"c")
	_run(1.0 + 2.0 * DT)
	assert_null(queue.current)
	assert_eq(events, ["start a", "end a", "start b", "end b", "start c", "end c"] as Array[String])


func test_a_line_said_inside_the_gap_waits_for_it() -> void:
	queue.say(_line(&"a", 1.0))
	_run(1.0 + DT)
	queue.say(_line(&"b", 1.0))
	assert_null(queue.current, "still in the gap after a")
	assert_eq(queue.queued_count(), 1)
	_run(DialogQueue.GAP_S + 2.0 * DT)
	assert_eq(queue.current.id, &"b")


func test_a_line_said_after_the_gap_starts_at_once() -> void:
	queue.say(_line(&"a", 1.0))
	_run(1.0 + DialogQueue.GAP_S + 0.5)
	queue.say(_line(&"b", 1.0))
	assert_eq(queue.current.id, &"b")


func test_one_big_tick_plays_through_every_line_it_covers() -> void:
	queue.say(_line(&"a", 1.0))
	queue.say(_line(&"b", 1.0))
	queue.tick(1.0 + DialogQueue.GAP_S + 1.0 + 0.1)
	assert_eq(events, ["start a", "end a", "start b", "end b"] as Array[String])
	assert_null(queue.current)


func test_the_same_line_said_twice_plays_twice_under_two_tickets() -> void:
	var first: int = queue.say(_line(&"a", 1.0))
	var second: int = queue.say(_line(&"a", 1.0))
	assert_ne(first, second)
	_run(1.0 + DT)
	assert_false(queue.is_pending(first))
	assert_true(queue.is_pending(second))


# --- interrupting ----------------------------------------------------------------------------------------------------------


func test_an_interrupt_cuts_the_line_showing_and_starts_at_once() -> void:
	var first: int = queue.say(_line(&"a", 5.0))
	queue.say(_line(&"b", 2.0))
	_run(1.0)
	var urgent: int = queue.say(_line(&"c", 1.0), true)
	assert_eq(queue.current.id, &"c")
	assert_eq(queue.current_ticket, urgent)
	assert_false(queue.is_pending(first), "the cut line is done")
	assert_eq(queue.queued_count(), 1, "b still waits")
	assert_eq(events, ["start a", "cut a", "start c"] as Array[String])
	_run(1.0 + DialogQueue.GAP_S + 3.0 * DT)
	assert_eq(queue.current.id, &"b", "the queue carries on after the interruption")


func test_an_interrupt_while_idle_or_in_the_gap_just_plays() -> void:
	queue.say(_line(&"a", 1.0), true)
	assert_eq(queue.current.id, &"a")
	_run(1.0 + DT)
	assert_null(queue.current)
	queue.say(_line(&"b", 1.0), true)
	assert_eq(queue.current.id, &"b", "no waiting out the gap")
	assert_eq(events, ["start a", "end a", "start b"] as Array[String])


func test_an_interrupt_goes_ahead_of_the_waiting_lines() -> void:
	queue.say(_line(&"a", 5.0))
	queue.say(_line(&"b", 1.0))
	queue.say(_line(&"c", 1.0), true)
	queue.say(_line(&"d", 1.0), true)
	assert_eq(queue.current.id, &"d")
	_run(1.0 + DialogQueue.GAP_S + 3.0 * DT)
	assert_eq(queue.current.id, &"b", "waiting lines keep their order; c was cut as the current line, never queued")


# --- cancelling ------------------------------------------------------------------------------------------------------------


func test_cancelling_a_waiting_line_removes_it() -> void:
	queue.say(_line(&"a", 5.0))
	var waiting: int = queue.say(_line(&"b"))
	assert_true(queue.cancel(waiting))
	assert_false(queue.is_pending(waiting))
	assert_eq(queue.queued_count(), 0)
	assert_eq(queue.current.id, &"a")
	assert_false(queue.cancel(waiting), "already gone")
	assert_eq(events, ["start a", "cut b"] as Array[String])


func test_cancelling_the_line_showing_ends_it_and_the_next_starts_at_once() -> void:
	var showing: int = queue.say(_line(&"a", 5.0))
	queue.say(_line(&"b", 1.0))
	assert_true(queue.cancel(showing))
	assert_eq(queue.current.id, &"b", "a skip leaves no silence behind")
	assert_eq(events, ["start a", "cut a", "start b"] as Array[String])


func test_clear_cuts_everything_and_leaves_the_queue_idle() -> void:
	queue.say(_line(&"a", 5.0))
	queue.say(_line(&"b"))
	queue.say(_line(&"c"))
	queue.clear()
	assert_null(queue.current)
	assert_eq(queue.queued_count(), 0)
	assert_eq(events, ["start a", "cut a", "cut b", "cut c"] as Array[String])
	_run(1.0)
	assert_eq(events.size(), 4, "nothing more happens")
	queue.say(_line(&"d"))
	assert_eq(queue.current.id, &"d", "and it takes lines again, with no gap held over")


# --- what finished ---------------------------------------------------------------------------------------------------------


func test_take_finished_hands_over_each_ended_line_once_cut_or_not() -> void:
	queue.say(_line(&"a", 1.0))
	queue.say(_line(&"b", 5.0))
	_run(1.0 + DialogQueue.GAP_S + 3.0 * DT)
	assert_eq(queue.take_finished(), [&"a"] as Array[StringName])
	assert_eq(queue.take_finished(), [] as Array[StringName], "handed over once")
	queue.clear()
	assert_eq(queue.take_finished(), [&"b"] as Array[StringName], "a cut line counts as finished too")
