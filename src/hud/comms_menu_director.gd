class_name CommsMenuDirector
extends Node
## Runs the comms menu in flight (architecture §18.22, M5-T46): a thin node around the pure `CommsMenu` and a `RadialMenuView`,
## the same ring, side and focus pull as the target menu. D-pad Right opens it and pauses the game; the pad then belongs to
## the menu (`InputAdapter.sample_radial`) until an order is sent, B backs out of the first ring, D-pad Right again closes it,
## or Start hands over to the pause menu. The order is given once the game runs again, through the call keys 1-4 make. Closed,
## it does nothing per tick: `Main` only calls `step` while it is open.
##
## Console: provider `comms_menu`, command `commsmenu open|pick <entry>|highlight <entry>|back|close`.

const HINT_ROOT: String = "A  SEND      B  CLOSE"
const HINT_SUB: String = "A  SEND      B  BACK"
const ACTIONS: Array[StringName] = [&"open", &"pick", &"highlight", &"back", &"close"]

var main: Main = null
var menu: CommsMenu = CommsMenu.new()
var view: RadialMenuView = null
## What the last pick did, as its label; "" before the first.
var last_pick: String = ""

var _paused_before: bool = false


func _ready() -> void:
	name = "CommsMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu.set_root_page("WING ORDERS", CommsMenu.wing_orders())
	view = RadialMenuView.new()
	view.name = "CommsMenuView"
	view.menu = menu.radial
	add_child(view)
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if menu.is_open() and get_tree() != null:
		get_tree().paused = _paused_before


func is_open() -> bool:
	return menu.is_open()


## Why the menu cannot open now, or "" when it can.
func why_not() -> String:
	if menu.is_open():
		return "the comms menu is already open"
	if main == null or main.ship == null or not main.player_alive:
		return "there is no ship to give orders from"
	if main.pause_menu != null and main.pause_menu.is_open():
		return "the pause menu is open"
	if main.target_menu != null and main.target_menu.is_open():
		return "the target menu is open"
	if main.controls_locked() or main.camera_rig.is_playing_shot():
		return "the controls are held (a cinematic or the mission)"
	return ""


## Opens the menu and pauses the game. Returns "" or why it did not open.
func open() -> String:
	var why: String = why_not()
	if not why.is_empty():
		return why
	menu.open()
	if not menu.is_open():
		return "the comms menu has no entries"
	_paused_before = get_tree().paused
	get_tree().paused = true
	main.adapter.begin_radial(main.input_source)
	view.pointer = Vector2.ZERO
	_show_page()
	view.set_showing(true)
	return ""


## One tick of the open menu, from `InputAdapter.sample_radial`.
func step(ui: UiCommand) -> void:
	if not menu.is_open():
		return
	if ui.pause:
		close(&"pause")
		main.pause_menu.on_pause_action()
		return
	if not main.player_alive or main.controls_locked() or main.camera_rig.is_playing_shot():
		close()  # a script took the controls (D55) or the pilot is gone
		return
	if ui.comms_open:
		close()  # the key that opened it closes it
		return
	if not ui.radial_point.is_zero_approx():
		view.pointer = ui.radial_point
		menu.radial.point(ui.radial_point)
	if ui.radial_back:
		back()
	elif ui.radial_select:
		select()
	if menu.is_open():
		view.refresh()


## A: opens a sub-page, or sends the highlighted order and resumes.
func select() -> void:
	var picked: Dictionary = menu.select()
	if menu.is_open():
		view.pointer = Vector2.ZERO
		_show_page()
		return
	_resume()
	_carry_out(picked)


## B: back a page, or out of the menu.
func back() -> void:
	if menu.back():
		view.pointer = Vector2.ZERO
		_show_page()
	else:
		_resume()


func close(reason: StringName = &"close") -> void:
	if not menu.is_open():
		return
	menu.close(reason)
	_resume()


# The game resumes as it was, with nothing held over from the menu.
func _resume() -> void:
	view.set_showing(false)
	get_tree().paused = _paused_before
	main.adapter.end_radial(main.input_source)


func _show_page() -> void:
	view.hint = HINT_ROOT if menu.page_count() <= 1 else HINT_SUB
	view.refresh()


# An order goes to the wing as keys 1-4 give it; other payloads are a mission's to read from `last_pick`.
func _carry_out(picked: Dictionary) -> void:
	if picked.is_empty():
		return
	last_pick = str(picked.get("label", ""))
	if picked.get("payload") is int and main.player_alive:
		main.wings.give_order(picked["payload"] as AiContext.Order)


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"comms_menu", ConsoleVars.new({
		&"open": {"get": func() -> bool: return menu.is_open(), "doc": "The comms menu is showing (the game is paused behind it)"},
		&"page": {"get": func() -> String: return menu.page_title(), "doc": "The title of the ring showing"},
		&"highlight": {"get": func() -> String: return str(menu.radial.highlighted().get("label", "none")),
				"doc": "The entry the stick points at"},
		&"entries": {"get": _console_entries, "doc": "The ring's slices clockwise from the top (- for a blank one)"},
		&"picks": {"get": func() -> int: return menu.picks(), "doc": "Entries selected so far"},
		&"last_pick": {"get": func() -> String: return last_pick if not last_pick.is_empty() else "none", "doc": "The last order sent"},
		&"closed_by": {"get": func() -> String: return String(menu.closed_by()), "doc": "Why it last closed: pick, back, pause or close"},
		&"focus": {"get": func() -> float: return view.focus_amount(), "doc": "The focus pull on the view behind the menu, 0 sharp to 1 full"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"commsmenu",
			"The comms menu: open (pauses the game), pick <entry> (a slice 0-3 clockwise from the top, or its label: attack, form on me, "
			+ "engage, cover me), highlight <entry> (points at it without sending), back, close",
			[ConsoleArg.enum_required(&"action", ACTIONS), ConsoleArg.string_optional(&"entry", "").with_suggestions(_console_entries)]),
			_cmd_commsmenu, self)


func _console_entries() -> PackedStringArray:
	var out := PackedStringArray()
	for slot: Dictionary in menu.radial.slots():
		out.append(str(slot.get("label", "-")).to_lower())
	return out


func _cmd_commsmenu(args: Dictionary) -> ConsoleResult:
	var action := StringName(args[&"action"])
	var entry: String = String(args[&"entry"]).strip_edges()
	if not entry.is_empty() and action != &"pick" and action != &"highlight":
		return ConsoleResult.failure("commsmenu %s takes no entry (only commsmenu pick or highlight <entry>)" % action)
	if action == &"open":
		var why: String = open()
		return ConsoleResult.failure(why) if not why.is_empty() else _describe()
	if not menu.is_open():
		return ConsoleResult.failure("the comms menu is not open (commsmenu open)")
	match action:
		&"pick", &"highlight":
			var index: int = _entry_index(entry)
			if index < 0:
				return ConsoleResult.failure("no entry '%s' on this ring (it has: %s)" % [entry, ", ".join(_console_entries())])
			menu.radial.set_highlight(index)
			if action == &"pick":
				select()
			else:
				view.refresh()
		&"back":
			back()
		&"close":
			close()
	return _describe()


# A slice by its number or its label (the first match, case-insensitive); -1 for none or a blank slice.
func _entry_index(entry: String) -> int:
	var slots: Array[Dictionary] = menu.radial.slots()
	var index: int = entry.to_int() if entry.is_valid_int() else -1
	if index < 0:
		for i: int in slots.size():
			if str(slots[i].get("label", "")).to_lower() == entry.to_lower():
				index = i
				break
	return index if index >= 0 and index < slots.size() and not slots[index].is_empty() else -1


func _describe() -> ConsoleResult:
	if not menu.is_open():
		return ConsoleResult.line("comms menu closed (%s); last order %s" % [menu.closed_by(), last_pick if not last_pick.is_empty() else "none"])
	return ConsoleResult.line("comms menu: %s: %s" % [menu.page_title(), ", ".join(_console_entries())])
