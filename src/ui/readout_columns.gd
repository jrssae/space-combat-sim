class_name ReadoutColumns
extends RefCounted
## Where each part of a debug readout's line is drawn (M8-T21): the game's font is not fixed-width, so columns cannot be made
## with padding spaces. A line's cells are separated by two or more spaces. After a short label the cells stand in columns:
## a number ends at its column's right edge, so a row of numbers stays in line whatever their digits. Pure.

## The label column and each number column, as multiples of the text size, and the gap before a cell that is not a number.
const LABEL_EM: float = 3.6
const NUMBER_EM: float = 5.6
const GAP_EM: float = 0.9
## A line's first cell is a label when it is this short and one word (`SPD`, `VRAM`).
const LABEL_CHARS: int = 4


## A line's cells: its text cut at every run of two or more spaces.
static func cells(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	for cell: String in line.split("  ", false):
		var trimmed: String = cell.strip_edges()
		if not trimmed.is_empty():
			out.append(trimmed)
	return out


## Whether `cell` is a bare number (`+12.5`, `-0.0`, `42`).
static func is_number(cell: String) -> bool:
	return cell.is_valid_float() and not cell.is_empty()


## The cells of `line` with the x each starts at: `[{text, x}]`. `measure` gives a text's drawn width at the size `px`.
static func place(line: String, px: float, measure: Callable) -> Array[Dictionary]:
	var placed: Array[Dictionary] = []
	var parts: PackedStringArray = cells(line)
	if parts.is_empty():
		return placed
	var labelled: bool = parts.size() > 1 and parts[0].length() <= LABEL_CHARS and not parts[0].contains(" ")
	placed.append({"text": parts[0], "x": 0.0})
	# Where the next cell may start: after the label column, or after the cell before it.
	var x: float = LABEL_EM * px if labelled else float(measure.call(parts[0])) + GAP_EM * px
	for i: int in range(1, parts.size()):
		var width: float = float(measure.call(parts[i]))
		if labelled and is_number(parts[i]):
			var edge: float = x + maxf(NUMBER_EM * px, width + 0.5 * GAP_EM * px)  # a number too long for its column pushes on
			placed.append({"text": parts[i], "x": edge - width})
			x = edge
		else:
			# After numbers a gap; straight after the label none.
			var at: float = x + (GAP_EM * px if i > 1 else 0.0) if labelled else x
			placed.append({"text": parts[i], "x": at})
			x = at + width + (0.0 if labelled else GAP_EM * px)
	return placed
