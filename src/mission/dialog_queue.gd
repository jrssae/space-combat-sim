class_name DialogQueue
extends RefCounted
## The order comms lines play in (architecture §18 D53): one at a time, in the order said, with a short gap between two lines; a
## `say` that interrupts cuts the line showing and takes its place. Pure: time is only the deltas `tick` is given (the mission's
## physics ticks), so a paused or skipped game moves no line.
##
## `started` and `finished` are what the comms panel plays its squelches and draws from; `finished` says whether the line ended
## by itself or was cut. `take_finished` is what the mission records as finished lines (`dialog_finished` triggers read them).

## A line began (its ticket, the id `say` returned).
signal started(ticket: int, line: DialogBook.Line)
## A line ended: `cut` when it was interrupted, cancelled or cleared rather than shown out.
signal finished(ticket: int, line: DialogBook.Line, cut: bool)

## Silence between a line's end and the next line's start, seconds.
const GAP_S: float = 0.4
## Slack when comparing summed tick times with a line's hold (120 ticks of 1/60 s must reach 2 s).
const TIME_EPS_S: float = 1e-6

## The line showing, or null.
var current: DialogBook.Line = null
var current_ticket: int = 0
## How long the current line has been up, seconds.
var elapsed_s: float = 0.0

var _waiting: Array[Entry] = []
var _gap_s: float = 0.0
var _serial: int = 0
var _ended: Array[StringName] = []


## A line said and waiting its turn.
class Entry extends RefCounted:
	var ticket: int = 0
	var line: DialogBook.Line = null

	func _init(p_ticket: int, p_line: DialogBook.Line) -> void:
		ticket = p_ticket
		line = p_line


## Queues `line` (it starts at once when nothing shows and no gap is running). With `interrupt` it cuts the line showing and
## starts now. Returns the ticket `is_pending` and `cancel` take.
func say(line: DialogBook.Line, interrupt: bool = false) -> int:
	_serial += 1
	var entry := Entry.new(_serial, line)
	if interrupt:
		_end_current(true)
		_start(entry)
		return entry.ticket
	_waiting.append(entry)
	_start_next_if_free()
	return entry.ticket


## Moves time on by `delta` seconds. A tick long enough to cover several lines plays through all of them.
func tick(delta: float) -> void:
	var left: float = delta
	while left > 0.0:
		if current != null:
			var needed: float = current.hold_s - TIME_EPS_S - elapsed_s
			if left < needed:
				elapsed_s += left
				return
			left -= maxf(needed, 0.0)
			_end_current(false)
		elif _gap_s > 0.0:
			if left < _gap_s:
				_gap_s -= left
				return
			left -= _gap_s
			_gap_s = 0.0
			_start_next_if_free()
		else:
			return


## Cuts line `ticket`, showing or waiting. Returns false when it is not pending. A cut line showing hands over to the next at once.
func cancel(ticket: int) -> bool:
	if current != null and current_ticket == ticket:
		_end_current(true)
		_gap_s = 0.0
		_start_next_if_free()
		return true
	for i: int in _waiting.size():
		if _waiting[i].ticket == ticket:
			var entry: Entry = _waiting[i]
			_waiting.remove_at(i)
			_ended.append(entry.line.id)
			finished.emit(entry.ticket, entry.line, true)
			return true
	return false


## Cuts the line showing and every line waiting, and drops the gap.
func clear() -> void:
	_end_current(true)
	_gap_s = 0.0
	var waiting: Array[Entry] = _waiting
	_waiting = []
	for entry: Entry in waiting:
		_ended.append(entry.line.id)
		finished.emit(entry.ticket, entry.line, true)


## Whether `ticket` is showing or waiting.
func is_pending(ticket: int) -> bool:
	if current != null and current_ticket == ticket:
		return true
	for entry: Entry in _waiting:
		if entry.ticket == ticket:
			return true
	return false


func queued_count() -> int:
	return _waiting.size()


## Seconds left on the current line (0 when nothing shows).
func remaining_s() -> float:
	return maxf(current.hold_s - elapsed_s, 0.0) if current != null else 0.0


## The ids of the lines that ended (shown out or cut) since the last call, oldest first.
func take_finished() -> Array[StringName]:
	var out: Array[StringName] = _ended
	_ended = []
	return out


# --- internals -------------------------------------------------------------------------------------------------------------


func _start(entry: Entry) -> void:
	current = entry.line
	current_ticket = entry.ticket
	elapsed_s = 0.0
	_gap_s = 0.0
	started.emit(entry.ticket, entry.line)


func _start_next_if_free() -> void:
	if current == null and _gap_s <= 0.0 and not _waiting.is_empty():
		var next: Entry = _waiting.pop_front()
		_start(next)


# A shown-out line leaves the gap behind it; a cut one does not.
func _end_current(cut: bool) -> void:
	if current == null:
		return
	var line: DialogBook.Line = current
	var ticket: int = current_ticket
	current = null
	current_ticket = 0
	elapsed_s = 0.0
	_gap_s = 0.0 if cut else GAP_S
	_ended.append(line.id)
	finished.emit(ticket, line, cut)
