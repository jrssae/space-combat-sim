class_name TargetMenuDirector
extends Node
## Runs the target menu in flight (architecture §18.19, M5-T25): a thin node around the pure `TargetMenu`, its `RadialMenuView`
## and the `HudWaypoint`. A hold of the target button opens it: the candidate list is read once, then the game pauses (as
## behind the pause menu) and the pad belongs to the menu until a pick, B out of the first ring, or Start (which hands over
## to the pause menu). A picked ship becomes the target; a picked beacon or objective becomes the HUD waypoint and never the
## target. Closed, it does nothing per tick: `Main` only calls `step` while it is open. While the second ring is open the
## highlighted entry shows in the `TargetPreview` panel at the other side (§18.20, T43), read once per highlight.
##
## Console: provider `target_menu`, command `targetmenu open|pick <entry>|highlight <entry>|back|close`.

const HINT_ROOT: String = "A  OPEN      B  CLOSE"
const HINT_TARGET: String = "A  TARGET      B  BACK"
const HINT_WAYPOINT: String = "A  WAYPOINT      B  BACK"
const ACTIONS: Array[StringName] = [&"open", &"pick", &"highlight", &"back", &"close"]
## What "none" says in the preview panel.
const NONE_CLEARS_TARGET: String = "Clears the target"
const NONE_CLEARS_WAYPOINT: String = "Clears the waypoint"

var main: Main = null
var menu: TargetMenu = TargetMenu.new()
var view: RadialMenuView = null
var preview: TargetPreview = null
var waypoint: HudWaypoint = HudWaypoint.new()
## Times it opened, and how long the last opening took (reading the candidates and building the first ring), microseconds:
## a measurement for the console, never gameplay.
var opens: int = 0
var last_open_usec: int = 0
## How many candidates the last opening read.
var last_candidates: int = 0
## What the last pick did: `target RAIDER 2`, `waypoint NAV BETA`, `clear_target`, `clear_waypoint`; "" before the first.
var last_pick: String = ""

var _paused_before: bool = false
# The ring and slice the preview last read, so an entry is read once per highlight.
var _previewed: Vector2i = Vector2i(-2, -2)


func _ready() -> void:
	name = "TargetMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS
	view = RadialMenuView.new()
	view.name = "TargetMenuView"
	view.menu = menu.radial
	add_child(view)
	preview = TargetPreview.new()
	preview.name = "TargetPreview"
	add_child(preview)
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
		return "the target menu is already open"
	if main == null or main.ship == null or not main.player_alive:
		return "there is no ship to target from"
	if main.pause_menu != null and main.pause_menu.is_open():
		return "the pause menu is open"
	if main.comms != null and main.comms.is_open():
		return "the comms menu is open"
	if main.controls_locked() or main.camera_rig.is_playing_shot():
		return "the controls are held (a cinematic or the mission)"
	return ""


## Opens the menu and pauses the game. Returns "" or why it did not open.
func open() -> String:
	var why: String = why_not()
	if not why.is_empty():
		return why
	# The list is read before the pause: a paused ship's marker does not count as in play.
	var started: int = Time.get_ticks_usec()
	var candidates: Array[TargetInfo] = main.ship.targeting.candidates()
	menu.open(candidates, main.ship.global_position, main.combatant.faction, _objectives())
	last_open_usec = Time.get_ticks_usec() - started
	last_candidates = candidates.size()
	opens += 1
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
	if not ui.radial_point.is_zero_approx():
		view.pointer = ui.radial_point
		menu.point(ui.radial_point)
	if ui.radial_back:
		back()
	elif ui.radial_select:
		select()
	if menu.is_open():
		view.refresh()
		_sync_preview()


## A on the highlighted entry: opens a category, or carries out the pick and resumes.
func select() -> void:
	var picked: Dictionary = menu.select()
	if menu.is_open():
		view.pointer = Vector2.ZERO
		_show_page()
		return
	_resume()
	_carry_out(picked)


## B: back to the categories, or out of the menu.
func back() -> void:
	if menu.back():
		_show_page()
	else:
		_resume()


func close(reason: StringName = &"close") -> void:
	if not menu.is_open():
		return
	menu.close(reason)
	_resume()


## The last word on this frame's HUD waypoint (`Hud.final_input`): the pilot's pick or the script's, whichever came later.
func fill_hud_input(input: HudInput) -> void:
	waypoint.offer_script(input.waypoint_key)
	if waypoint.shows_pick():
		var at: Variant = _pick_position()
		if at == null:
			waypoint.drop_pick()
			return
		input.has_waypoint = true
		input.waypoint_position = at as Vector3
		input.waypoint_label = String(waypoint.pick["label"])
		input.waypoint_id = int(waypoint.pick["target_id"])
	elif not waypoint.shows_script():
		input.has_waypoint = false
		input.waypoint_id = 0


# The game resumes as it was, with nothing held over from the menu.
func _resume() -> void:
	view.set_showing(false)
	_sync_preview()
	get_tree().paused = _paused_before
	main.adapter.end_radial(main.input_source)


func _show_page() -> void:
	if menu.category < 0:
		view.hint = HINT_ROOT
	else:
		view.hint = HINT_WAYPOINT if TargetMenu.WAYPOINT_CATEGORIES.has(menu.category) else HINT_TARGET
	view.refresh()
	_sync_preview()


# The preview follows the highlight on the second ring and hides everywhere else. An entry is read when the highlight
# lands on it, never again while it stays (the game is paused, so nothing in it changes).
func _sync_preview() -> void:
	var at := Vector2i(menu.category, menu.radial.highlight()) if menu.is_open() and menu.category >= 0 else Vector2i(-1, -1)
	if at == _previewed:
		return
	_previewed = at
	if at.x < 0:
		preview.hide_panel()
		return
	preview.ring_right_side = view.right_side
	var slot: Dictionary = menu.radial.highlighted()
	var source: Variant = slot.get("source")
	var own: Vector3 = main.ship.global_position
	if source is TargetInfo:
		var info: TargetInfo = source
		var model: TargetPreviewModel = TargetPreviewModel.contact(info, own, main.ship.linear_velocity, main.combatant.faction,
				_facts(info.id))
		preview.show_model(model, _hull_key(info.id, model.hull_id), _parts(info.id))
	elif source is Dictionary:
		var objective: Dictionary = source
		var id: int = int(objective.get("target_id", 0))
		var model: TargetPreviewModel = TargetPreviewModel.objective(objective, own, String(_facts(id).get("asset_id", "")))
		preview.show_model(model, _hull_key(id, model.hull_id), _parts(id))
	else:
		var clears_waypoint: bool = TargetMenu.WAYPOINT_CATEGORIES.has(menu.category)
		preview.show_model(TargetPreviewModel.none(str(slot.get("label", "")),
				NONE_CLEARS_WAYPOINT if clears_waypoint else NONE_CLEARS_TARGET))


# The body a marker sits on, or null once it is gone.
func _owner_of(id: int) -> Node:
	var marker := instance_from_id(id) as Targetable if id != 0 and is_instance_id_valid(id) else null
	return marker.get_parent() if marker != null else null


# What the candidate list does not carry about an entry: its hull, its cargo pods, whether it is after the pilot.
func _facts(id: int) -> Dictionary:
	var body: Node = _owner_of(id)
	var ship := body as Ship
	if ship != null and ship.spec != null:
		var facts: Dictionary = {"asset_id": ship.spec.asset_id}
		var pods: CargoPods = CargoPods.of(ship)
		if pods != null:
			facts["cargo_pods"] = pods.count
			facts["cargo_mounts"] = pods.mount_count()
		facts["attacking_you"] = _attacks_pilot(ship)
		return facts
	if body is NavBuoy:
		return {"asset_id": NavBuoy.ASSET_ID}
	return {}


# Whether `ship`'s pilot has the player selected and is attacking (not idling, fleeing or flying past).
func _attacks_pilot(ship: Ship) -> bool:
	var own_marker: Targetable = main.combatant.targetable
	var driver := ship.get_node_or_null(^"AiPilotDriver") as AiPilotDriver
	if own_marker == null or driver == null or driver.brain == null or ship.targeting == null:
		return false
	if ship.targeting.selected_id() != own_marker.get_instance_id():
		return false
	var doing: Dictionary = driver.brain.describe()
	return TargetPreviewModel.is_attacking(str(doing.get("behaviour", "")), str(doing.get("state", "")))


# The hull's meshes in its own frame: the hull, then the pods mounted on it.
func _parts(id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var body: Node = _owner_of(id)
	var ship := body as Ship
	if ship != null:
		if ship.hull_mesh() != null:
			out.append({"mesh": ship.hull_mesh(), "transform": Transform3D.IDENTITY})
			var pods: CargoPods = CargoPods.of(ship)
			if pods != null:
				out.append_array(pods.mounted_parts())
	elif body is NavBuoy:
		var mesh: Mesh = MeshAssets.for_asset(NavBuoy.ASSET_ID)
		if mesh != null:
			out.append({"mesh": mesh, "transform": Transform3D.IDENTITY})
	return out


# Names what the wireframe shows: the asset, and its pods when it carries some.
func _hull_key(id: int, asset_id: String) -> String:
	var pods: CargoPods = CargoPods.of(_owner_of(id) as Ship)
	return "%s+%d pods" % [asset_id, pods.count] if pods != null and pods.count > 0 and not asset_id.is_empty() else asset_id


# Makes the pick real. The game is running again by now, so the ship's targeting sees its candidates.
func _carry_out(picked: Dictionary) -> void:
	if picked.is_empty():
		return
	var action: StringName = picked["action"]
	match action:
		TargetMenu.ACTION_TARGET:
			main.ship.targeting.select_id(int(picked["id"]))
			last_pick = "target %s" % picked["label"]
		TargetMenu.ACTION_CLEAR_TARGET:
			main.ship.targeting.clear_selection()
			last_pick = String(action)
		TargetMenu.ACTION_WAYPOINT:
			waypoint.set_pick(String(picked["label"]), int(picked["id"]), picked.get("point") as UniversePos)
			last_pick = "waypoint %s" % picked["label"]
		TargetMenu.ACTION_CLEAR_WAYPOINT:
			waypoint.clear_pick()
			last_pick = String(action)


# The mission's active objectives that name an actor in play or a fixed place, in the mission's order.
func _objectives() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var runner: MissionRunner = main.mission
	if runner == null or runner.api == null or runner.stage == null:
		return out
	for objective: Dictionary in runner.api.book.active():
		var subject: Dictionary = runner.api.book.subject(objective["id"])
		var entry: Dictionary = {"text": HudLayout.objective_text(objective)}
		for actor: String in subject["actors"] as PackedStringArray:
			var at: Variant = runner.stage.local_position(actor)
			if at != null:
				entry.merge({"label": actor, "target_id": runner.stage.target_id(actor), "point": null, "position": at})
				break
		if not entry.has("label") and subject["point"] != null:
			var point: UniversePos = subject["point"]
			entry.merge({"label": String(objective["id"]), "target_id": 0, "point": point, "position": main.world.universe_to_local(point)})
		if entry.has("label"):
			out.append(entry)
	return out


# Where the pilot's waypoint is this frame, World-local, or null once its contact is gone.
func _pick_position() -> Variant:
	var id: int = int(waypoint.pick["target_id"])
	if id == 0:
		var point: UniversePos = waypoint.pick["point"]
		return main.world.universe_to_local(point) if point != null else null
	var marker := instance_from_id(id) as Targetable if is_instance_id_valid(id) else null
	if marker == null or not marker.is_inside_tree():
		return null
	if marker.is_visible_in_tree():
		return marker.global_position
	# A ship in the low-attention tier is parked; its row flies on.
	var row: TargetInfo = TierTargets.info_of(get_tree(), id)
	return row.position if row != null else null


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"target_menu", ConsoleVars.new({
		&"open": {"get": func() -> bool: return menu.is_open(), "doc": "The target menu is showing (the game is paused behind it)"},
		&"page": {"get": func() -> String: return menu.page_name() if menu.is_open() else "none",
				"doc": "The ring showing: categories, a category's name, or none"},
		&"highlight": {"get": func() -> String: return str(menu.radial.highlighted().get("label", "none")),
				"doc": "The entry the stick points at"},
		&"entries": {"get": _console_entries, "doc": "The ring's slices clockwise from the top (- for a blank one)"},
		&"selection": {"get": func() -> String: return _console_selection(), "doc": "The ship's target (as the HUD names it), or none"},
		&"waypoint": {"get": func() -> String: return waypoint.describe(),
				"doc": "The HUD waypoint: the pilot's pick by name, script (a mission's or the route's), or none"},
		&"last_pick": {"get": func() -> String: return last_pick if not last_pick.is_empty() else "none",
				"doc": "What the last pick did"},
		&"closed_by": {"get": func() -> String: return String(menu.radial.closed_by), "doc": "Why it last closed: pick, back, pause or close"},
		&"focus": {"get": func() -> float: return view.focus_amount(), "doc": "The focus pull on the view behind the menu, 0 sharp to 1 full"},
		&"opens": {"get": func() -> int: return opens, "doc": "Times it has opened"},
		&"last_open_ms": {"get": func() -> float: return float(last_open_usec) / 1000.0, "unit": "ms",
				"doc": "What the last opening cost: reading the candidates and building the first ring"},
		&"last_candidates": {"get": func() -> int: return last_candidates, "doc": "Candidates the last opening read"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"targetmenu",
			"The target menu: open (pauses the game), pick <entry> (a slice 0-5 clockwise from the top, or its label: enemies, none, "
			+ "\"raider 2\"), highlight <entry> (points at it without picking; the preview panel shows it), back, close",
			[ConsoleArg.enum_required(&"action", ACTIONS), ConsoleArg.string_optional(&"entry", "").with_suggestions(_console_entries)]),
			_cmd_targetmenu, self)


func _console_entries() -> PackedStringArray:
	var out := PackedStringArray()
	for slot: Dictionary in menu.radial.slots():
		out.append(str(slot.get("label", "-")).to_lower())
	return out


func _console_selection() -> String:
	if main == null or main.ship == null or not main.ship.targeting.system.has_selection():
		return "none"
	return main.ship.targeting.selected_name() if main.ship.targeting.selection_identified else TargetMenu.UNKNOWN_LABEL


func _cmd_targetmenu(args: Dictionary) -> ConsoleResult:
	var action := StringName(args[&"action"])
	var entry: String = String(args[&"entry"]).strip_edges()
	if not entry.is_empty() and action != &"pick" and action != &"highlight":
		return ConsoleResult.failure("targetmenu %s takes no entry (only targetmenu pick or highlight <entry>)" % action)
	if action == &"open":
		var why: String = open()
		return ConsoleResult.failure(why) if not why.is_empty() else _describe()
	if not menu.is_open():
		return ConsoleResult.failure("the target menu is not open (targetmenu open)")
	match action:
		&"pick":
			var index: int = _entry_index(entry)
			if index < 0:
				return ConsoleResult.failure("no entry '%s' on this ring (it has: %s)" % [entry, ", ".join(_console_entries())])
			menu.radial.set_highlight(index)
			select()
		&"highlight":
			var index: int = _entry_index(entry)
			if index < 0:
				return ConsoleResult.failure("no entry '%s' on this ring (it has: %s)" % [entry, ", ".join(_console_entries())])
			menu.radial.set_highlight(index)
			view.refresh()
			_sync_preview()
		&"back":
			back()
		&"close":
			close()
	return _describe()


# A slice by its number or by its label (the first match, case-insensitive); -1 for none or a blank slice.
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
		return ConsoleResult.line("target menu closed (%s); target %s, waypoint %s" % [menu.radial.closed_by, _console_selection(),
				waypoint.describe()])
	return ConsoleResult.line("target menu: %s: %s" % [menu.page_name(), ", ".join(_console_entries())])
