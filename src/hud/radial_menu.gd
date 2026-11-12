class_name RadialMenu
extends RefCounted
## A radial menu's model (architecture §18.19, M5-T25): a stack of pages, each a ring of slices with one highlighted. Pure: the
## owner feeds it the stick's direction, a select or a back, and acts on the entry `select` returns. The target menu is built
## on it, and the comms menu moves onto it in T46.
##
## Slices are numbered clockwise from the top (slice 0 is straight up). A slot is `{label, sub, detail, color, payload}`; an
## empty dictionary is a blank slice the highlight never lands on. `arrange` lays entries out so that a "none" entry sits in the
## down slice, as every ring that has one must.

## How far the stick must lean (0..1, after the deadzone) to point at a slice; nearer the centre the highlight stays.
const POINT_THRESHOLD: float = 0.5
# A direction this close to a boundary between two slices (in slice widths) counts as on it.
const _BOUNDARY_EPS: float = 1e-3

## Why the menu last closed: pick, back, or the reason given to `close`. Empty before the first close.
var closed_by: StringName = &""
## Entries selected so far.
var picks: int = 0

var _open: bool = false
var _pages: Array[Dictionary] = []  # {"title": String, "slots": Array[Dictionary], "highlight": int, "color": Color}


## The centre of slice `index` of `count`, radians clockwise from straight up.
static func slice_angle(index: int, count: int) -> float:
	return TAU * float(index) / float(maxi(count, 1))


## The slice a direction points at (`v`: x right, y up, length 0..1), or -1 when it leans less than `threshold`. A direction on
## the boundary between two slices takes the one nearer the top, so a plain left or right arrow key means the same on both sides.
static func slice_at(v: Vector2, count: int, threshold: float = POINT_THRESHOLD) -> int:
	if count <= 0 or v.length() < threshold:
		return -1
	var turns: float = fposmod(atan2(v.x, v.y), TAU) / TAU * float(count) + 0.5
	var nearest_edge: float = roundf(turns)
	if absf(turns - nearest_edge) <= _BOUNDARY_EPS:
		var after: int = posmod(int(nearest_edge), count)
		var before: int = posmod(after - 1, count)
		return before if mini(before, count - before) < mini(after, count - after) else after
	return posmod(int(floorf(turns)), count)


## The slice straight down in a ring of `count`, or -1 when no slice is centred there (an odd count).
static func down_slice(count: int) -> int:
	return (count >> 1) if count > 0 and count % 2 == 0 else -1


## Lays `entries` clockwise from the top in a ring of at least `min_slices`. With a `none_entry` the ring has an even count and
## that entry takes the down slice, the others going round it; without one the entries fill the slices in order.
static func arrange(entries: Array[Dictionary], none_entry: Dictionary = {}, min_slices: int = 0) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	if none_entry.is_empty():
		slots.assign(entries)
		while slots.size() < min_slices:
			slots.append({})
		return slots
	var count: int = maxi(entries.size() + 1, maxi(min_slices, 2))
	count += count % 2
	var down: int = down_slice(count)
	var next: int = 0
	for i: int in count:
		if i == down:
			slots.append(none_entry)
		elif next < entries.size():
			slots.append(entries[next])
			next += 1
		else:
			slots.append({})
	return slots


## Opens the menu on one root page.
func open(title: String, slots: Array[Dictionary], color: Color = Color.WHITE) -> void:
	_pages.clear()
	_open = true
	closed_by = &""
	push(title, slots, color)


## Puts a page over the current one (a category's ring, a comms sub-page).
func push(title: String, slots: Array[Dictionary], color: Color = Color.WHITE) -> void:
	if not _open:
		return
	_pages.append({"title": title, "slots": slots, "highlight": _first_filled(slots), "color": color})


## B: back one page, or out of the menu from the first. Returns whether the menu is still open.
func back() -> bool:
	if not _open:
		return false
	if _pages.size() > 1:
		_pages.pop_back()
		return true
	close(&"back")
	return false


func close(reason: StringName = &"close") -> void:
	if not _open:
		return
	_open = false
	_pages.clear()
	closed_by = reason


func is_open() -> bool:
	return _open


## Pages open: 1 on the first ring, 2 on a ring opened from it; 0 when closed.
func depth() -> int:
	return _pages.size()


func title() -> String:
	return String(_pages.back()["title"]) if _open else ""


func color() -> Color:
	return _pages.back()["color"] as Color if _open else Color.WHITE


func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _open:
		out.assign(_pages.back()["slots"])
	return out


func slice_count() -> int:
	return (_pages.back()["slots"] as Array).size() if _open else 0


## The highlighted slice, or -1 (closed, or a page of blanks).
func highlight() -> int:
	return int(_pages.back()["highlight"]) if _open else -1


func highlighted() -> Dictionary:
	var at: int = highlight()
	return (_pages.back()["slots"] as Array)[at] if at >= 0 else {}


## Points the stick: the slice it leans toward becomes the highlight; a centred stick or a blank slice keeps the last one.
## Returns whether the highlight moved.
func point(v: Vector2) -> bool:
	return set_highlight(slice_at(v, slice_count()))


## Highlights slice `index` if it holds an entry. Returns whether the highlight moved.
func set_highlight(index: int) -> bool:
	if not _open or index < 0 or index >= slice_count() or index == highlight():
		return false
	if ((_pages.back()["slots"] as Array)[index] as Dictionary).is_empty():
		return false
	_pages.back()["highlight"] = index
	return true


## A: the highlighted entry, for the owner to act on (push a page, or `close(&"pick")`); empty when there is none.
func select() -> Dictionary:
	var entry: Dictionary = highlighted()
	if not entry.is_empty():
		picks += 1
	return entry


static func _first_filled(slots: Array[Dictionary]) -> int:
	for i: int in slots.size():
		if not slots[i].is_empty():
			return i
	return -1
