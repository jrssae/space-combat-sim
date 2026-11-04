class_name CommsMenu
extends RefCounted
## The in-flight comms menu (architecture §18 D54, M5-T07): pages of up to four entries, one per D-pad direction. The first page
## is the wing orders; a later mission can push a page of replies on top. Pure model: `Main` feeds it the player's picks and the
## tick, and acts on the entry a pick returns. It closes after a pick, on B, or when `CLOSE_S` of sim time passes untouched.

## Entries a page holds: up, right, down and left on the D-pad.
const SLOTS: int = 4
## How long an untouched menu stays open (s).
const CLOSE_S: float = 4.0

## Why the menu last closed: pick, close (B or the game), timeout. Empty before the first close.
var closed_by: StringName = &""
## Entries picked so far.
var picks: int = 0

var _open: bool = false
var _remaining_s: float = 0.0
var _pages: Array[Dictionary] = []  # {"title": String, "entries": Array[Dictionary]}; the first is the root


## The wing orders page: the four orders in the order of keys 1-4, payload an `AiContext.Order`.
static func wing_orders() -> Array[Dictionary]:
	return [
		{"label": "ATTACK MY TARGET", "payload": AiContext.Order.ATTACK_MY_TARGET},
		{"label": "FORM ON ME", "payload": AiContext.Order.FORM_ON_ME},
		{"label": "ENGAGE AT WILL", "payload": AiContext.Order.ENGAGE_AT_WILL},
		{"label": "COVER ME", "payload": AiContext.Order.COVER_ME},
	]


## Replaces every page with one root page. Entries are {"label": String, "payload": Variant}.
func set_root_page(title: String, entries: Array[Dictionary]) -> void:
	_pages.clear()
	_pages.append(_make_page(title, entries))


## Puts a page over the current one (a mission's replies) and restarts the timer so it can be read.
func push_page(title: String, entries: Array[Dictionary]) -> void:
	_pages.append(_make_page(title, entries))
	_remaining_s = CLOSE_S


## Goes back one page; the root page stays.
func pop_page() -> void:
	if _pages.size() > 1:
		_pages.pop_back()
		_remaining_s = CLOSE_S


func open() -> void:
	if _pages.is_empty():
		return
	while _pages.size() > 1:
		_pages.pop_back()
	_open = true
	_remaining_s = CLOSE_S


## Closes the menu (B, or the game taking the controls away).
func close() -> void:
	_end(&"close")


func is_open() -> bool:
	return _open


func page_title() -> String:
	return String(_pages.back()["title"]) if not _pages.is_empty() else ""


func page_count() -> int:
	return _pages.size()


func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not _pages.is_empty():
		out.assign(_pages.back()["entries"])
	return out


func remaining_s() -> float:
	return _remaining_s if _open else 0.0


## Counts the close timer down on sim time.
func tick(dt: float) -> void:
	if not _open:
		return
	_remaining_s -= dt
	if _remaining_s <= 1e-9:
		_end(&"timeout")


## The entry in slot `index` (0 up, 1 right, 2 down, 3 left), which closes the menu; empty when closed or the slot has none.
func pick(index: int) -> Dictionary:
	var page: Array[Dictionary] = entries()
	if not _open or index < 0 or index >= page.size():
		return {}
	var entry: Dictionary = page[index]
	picks += 1
	_end(&"pick")
	return entry


func _end(reason: StringName) -> void:
	if not _open:
		return
	_open = false
	_remaining_s = 0.0
	closed_by = reason


func _make_page(title: String, entries_in: Array[Dictionary]) -> Dictionary:
	if entries_in.size() > SLOTS:
		push_warning("CommsMenu: page '%s' has %d entries; only the first %d show" % [title, entries_in.size(), SLOTS])
	return {"title": title, "entries": entries_in.slice(0, SLOTS)}
