class_name RadialMenu
extends RefCounted
## A radial menu's model (architecture §18.19, M5-T25): a stack of pages, each a ring of slices with one highlighted. Pure: the
## owner feeds it the stick's direction, a select or a back, and acts on the entry `select` returns. The target menu and the
## comms menu are built on it.
##
## A ring has one equal slice per entry (D90, M8-T24): three entries are 120 degrees each, five are 72. Slices are numbered
## clockwise from the top (slice 0 is straight up), in page order. A slot is `{label, sub, detail, color, payload}`; a page is
## given without blanks: an empty dictionary (an entry that is unavailable) is left out of the ring. `arrange` puts a "none"
## entry in the down slice, as every ring that has one must.

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


## The slice a direction points at (`v`: x right, y up, length 0..1), or -1 when it leans less than `threshold`: the slice whose
## centre is nearest. A direction on the boundary between two slices takes the one nearer the top (the later one when both are
## as near, straight down on an odd ring, where "none" sits), so a plain arrow key always means the same slice.
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


## Where a "none" entry sits in a ring of `count`: straight down, or on an odd ring (nothing centred down) the first slice past
## down, which is also where the stick pulled straight down points; the entries before it stay together on the right.
static func none_slice(count: int) -> int:
	return mini((count + 1) >> 1, count - 1) if count > 0 else -1


## Lays `entries` clockwise from the top, one slice each; blanks are left out. With a `none_entry` it takes `none_slice` and the
## others go round it in order.
static func arrange(entries: Array[Dictionary], none_entry: Dictionary = {}) -> Array[Dictionary]:
	var present: Array[Dictionary] = fitted(entries)
	if none_entry.is_empty():
		return present
	var count: int = present.size() + 1
	var slots: Array[Dictionary] = []
	slots.assign(present)
	slots.insert(none_slice(count), none_entry)
	return slots


## `slots` without the blanks: what a ring lays out.
static func fitted(slots: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: Dictionary in slots:
		if not slot.is_empty():
			out.append(slot)
	return out


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
	var present: Array[Dictionary] = fitted(slots)
	_pages.append({"title": title, "slots": present, "highlight": 0 if not present.is_empty() else -1, "color": color})


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


## The highlighted slice, or -1 (closed, or an empty page).
func highlight() -> int:
	return int(_pages.back()["highlight"]) if _open else -1


func highlighted() -> Dictionary:
	var at: int = highlight()
	return (_pages.back()["slots"] as Array)[at] if at >= 0 else {}


## Points the stick: the slice it leans toward becomes the highlight; a centred stick keeps the last one. Returns whether the
## highlight moved.
func point(v: Vector2) -> bool:
	return set_highlight(slice_at(v, slice_count()))


## Whether the ring showing has an entry at `index` (page order, 0 at the top): what the D-pad and the numbered keys reach.
func has_entry(index: int) -> bool:
	return _open and index >= 0 and index < slice_count()


## Highlights slice `index` (an entry's place in page order) if the ring has it. Returns whether the highlight moved.
func set_highlight(index: int) -> bool:
	if not has_entry(index) or index == highlight():
		return false
	_pages.back()["highlight"] = index
	return true


## A: the highlighted entry, for the owner to act on (push a page, or `close(&"pick")`); empty when there is none.
func select() -> Dictionary:
	var entry: Dictionary = highlighted()
	if not entry.is_empty():
		picks += 1
	return entry

