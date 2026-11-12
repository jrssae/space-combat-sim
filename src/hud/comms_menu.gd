class_name CommsMenu
extends RefCounted
## The in-flight comms menu's pages on a `RadialMenu` (architecture §18.22, M5-T46), pure. The first ring is the wing orders; an
## entry that carries a `page` opens that ring over it (a mission's replies, sub-orders), and B goes back down the stack.
## `select` returns the entry a pilot confirmed and closes the menu; the owner acts on it once the game runs again.
##
## An entry is `{label, sub?, color?, payload?, page?: {title, entries}}`.

const HEADING: String = "COMMS"
## The fewest slices a ring has: the wing orders sit on the four compass directions, as the D-pad pointed them before.
const MIN_SLICES: int = 4
## The most an entry ring holds before the labels get cramped.
const MAX_SLOTS: int = 8
const COLOR: Color = Color(0.45, 0.85, 1.0)

var radial: RadialMenu = RadialMenu.new()

var _root_title: String = ""
var _root_entries: Array[Dictionary] = []


## The wing orders page: the four orders in the order of keys 1-4, payload an `AiContext.Order`.
static func wing_orders() -> Array[Dictionary]:
	return [
		{"label": "ATTACK", "sub": "my target", "payload": AiContext.Order.ATTACK_MY_TARGET},
		{"label": "FORM ON ME", "sub": "", "payload": AiContext.Order.FORM_ON_ME},
		{"label": "ENGAGE", "sub": "at will", "payload": AiContext.Order.ENGAGE_AT_WILL},
		{"label": "COVER ME", "sub": "", "payload": AiContext.Order.COVER_ME},
	]


## Sets the first ring's title and entries (shown by the next `open`).
func set_root_page(title: String, entries: Array[Dictionary]) -> void:
	_root_title = title
	_root_entries = entries


## Opens on the first ring.
func open() -> void:
	if _root_entries.is_empty():
		return
	radial.open(_root_title, _slots(_root_title, _root_entries), COLOR)


## Puts a ring over the current one while the menu is open.
func push_page(title: String, entries: Array[Dictionary]) -> void:
	radial.push(title, _slots(title, entries), COLOR)


## A: opens the highlighted entry's page and returns {}, or closes the menu and returns the entry (empty when none is lit).
func select() -> Dictionary:
	var entry: Dictionary = radial.select()
	if entry.is_empty():
		return entry
	var page: Variant = entry.get("page")
	if page is Dictionary:
		push_page(str((page as Dictionary).get("title", "")), _entries_of(page as Dictionary))
		return {}
	radial.close(&"pick")
	return entry


## B: one ring back, or out of the menu from the first. Returns whether it is still open.
func back() -> bool:
	return radial.back()


func close(reason: StringName = &"close") -> void:
	radial.close(reason)


func is_open() -> bool:
	return radial.is_open()


## How many rings are stacked (0 closed).
func page_count() -> int:
	return radial.depth()


func page_title() -> String:
	return radial.title()


func picks() -> int:
	return radial.picks


func closed_by() -> StringName:
	return radial.closed_by


func _entries_of(page: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(page.get("entries", []))
	return out


func _slots(title: String, entries: Array[Dictionary]) -> Array[Dictionary]:
	if entries.size() > MAX_SLOTS:
		push_warning("CommsMenu: page '%s' has %d entries; only the first %d show" % [title, entries.size(), MAX_SLOTS])
	return RadialMenu.arrange(entries.slice(0, MAX_SLOTS), {}, MIN_SLICES)
