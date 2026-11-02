class_name TargetingController
extends Node
## The ship's targeting computer (architecture §3, §6.3): a thin node around the pure `TargetingSystem`. Every
## physics tick it rebuilds the candidate list from group `targetable` (so nothing survives a `World.rebase()` stale)
## and drops a selection that left sensor range; `apply(cmd)` handles the `target_next` / `target_ahead` edges.
##
## It lives under the ship but is handed the ship's body explicitly (`setup(body)`) rather than reaching up the tree:
## it reads the body's position, `linear_velocity` and forward axis (`-global_basis.z`). Targetables under that body
## (the ship's own marker, later) are never candidates.
##
## Console (§6.4, §15.1 D27): only the player's controller registers (`setup(body, true)`): provider `targeting`
## (`selected` writable by display name or `none`, `range_m`, `closing_mps`, `candidates`), so
## `set targeting.selected "NAV BRAVO"` works without a dedicated command.
##
## Inactive targetables (`Targetable.is_active()`: hidden, or their owner not processing) are never candidates, and a
## selection that turns inactive is cleared on the next refresh, emitting `target_changed`.

## The selection changed: a target id (`Targetable` instance id), or `TargetingSystem.NO_TARGET` when it cleared.
signal target_changed(id: int)

## Runs after the ship and the props (default priority 0) so the candidates reflect this tick's kinematic moves.
const LATE_PRIORITY: int = 100

var system: TargetingSystem = TargetingSystem.new()

var _body: RigidBody3D = null


func _init() -> void:
	process_physics_priority = LATE_PRIORITY


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"targeting", ConsoleVars.new({
		&"selected": {"get": _console_selected, "set": _console_set_selected, "type": TYPE_STRING,
				"choices": _console_choices, "doc": "Selected target by display name, or none"},
		&"range_m": {"get": _console_range, "unit": "m", "doc": "Range to the selected target"},
		&"closing_mps": {"get": _console_closing, "unit": "m/s",
				"doc": "Closing speed of the selected target (positive = closing)"},
		&"candidates": {"get": _console_candidates, "doc": "Targets in sensor range, nearest first"},
	}), self)


## The body whose position, velocity and nose the targeting works from (the player ship, or an AI's ship), and
## whether this is the player's controller, which registers the `targeting` console provider.
func setup(body: RigidBody3D, register_console: bool = false) -> void:
	_body = body
	if register_console:
		_register_console()
	refresh()


func _physics_process(_delta: float) -> void:
	refresh()


## Rebuilds the candidates now and clears a selection that is gone or out of range (emits `target_changed` then).
func refresh() -> void:
	var before: int = system.selected_id()
	_gather()
	_emit_if_changed(before)


## Applies this tick's combat command: `target_next` / `target_prev` cycle by range, `target_ahead` picks the target nearest the
## nose. Both act on candidates gathered now, so it does not matter whether the caller runs before this node.
func apply(cmd: CombatCommand) -> void:
	if cmd == null or not (cmd.target_next or cmd.target_prev or cmd.target_ahead) or not _has_body():
		return
	var before: int = system.selected_id()
	_gather()
	if cmd.target_next:
		system.select_next(_ship_position())
	if cmd.target_prev:
		system.select_prev(_ship_position())
	if cmd.target_ahead:
		system.select_ahead(_ship_position(), _ship_forward())
	_emit_if_changed(before)


## Readout of the selected target from the live ship and target state, or null when nothing is selected.
func selected_readout() -> TargetReadout:
	if not _has_body() or not system.has_selection():
		return null
	var target := instance_from_id(system.selected_id()) as Targetable
	if target == null or not target.is_inside_tree():
		return null
	return TargetingSystem.compute_readout(target.to_target_info(), _ship_position(), _body.linear_velocity,
			_ship_forward())


## Line of sight from the ship to the selected target, World frame, m; zero when nothing is selected. Read live from
## the target node, so it is current even in a tick where this node has not refreshed yet (the ship's brake uses it
## to face the target, §5.5).
func selected_offset() -> Vector3:
	if not _has_body() or not system.has_selection():
		return Vector3.ZERO
	var target := instance_from_id(system.selected_id()) as Targetable
	if target == null or not target.is_inside_tree():
		return Vector3.ZERO
	return target.global_position - _ship_position()


## `TargetingSystem.NO_TARGET` (0) when nothing is selected.
func selected_id() -> int:
	return system.selected_id()


## Display name of the selection, or "" when nothing is selected.
func selected_name() -> String:
	var target: TargetInfo = system.selected()
	return target.display_name if target != null else ""


## Selectable targets as of the last refresh: in sensor range, nearest first.
func candidates() -> Array[TargetInfo]:
	if not _has_body():
		return []
	return system.in_range(_ship_position())


## Selects the nearest in-range target hostile to this ship's faction (the AI's choice); clears the selection when there
## is none. Returns whether a hostile is selected.
func select_nearest_hostile() -> bool:
	if not _has_body():
		return false
	var before: int = system.selected_id()
	_gather()
	var order: Array[TargetInfo] = system.cycle_order(_ship_position())
	var found: bool = not order.is_empty() and Factions.is_hostile(system.own_faction, order[0].faction)
	if found:
		system.select_id(order[0].id, _ship_position())
	else:
		system.clear()
	_emit_if_changed(before)
	return found


## Selects the in-range target with this display name (case-insensitive). Returns false if there is none.
func select_by_name(display_name: String) -> bool:
	if not _has_body():
		return false
	var before: int = system.selected_id()
	_gather()
	var target: TargetInfo = system.find_by_name(display_name, _ship_position())
	if target != null:
		system.select_id(target.id, _ship_position())
	_emit_if_changed(before)
	return target != null


## Selects the in-range target with this id (a `Targetable` instance id: an AI brain's choice), from the candidates of the
## last refresh, gathering them again only when it is not among them. Returns whether it is selected.
func select_id(target_id: int) -> bool:
	if not _has_body():
		return false
	var before: int = system.selected_id()
	if before != target_id and not system.select_id(target_id, _ship_position()):
		_gather()
		system.select_id(target_id, _ship_position())
	_emit_if_changed(before)
	return system.selected_id() == target_id


func clear_selection() -> void:
	var before: int = system.selected_id()
	system.clear()
	_emit_if_changed(before)


func _gather() -> void:
	if not _has_body() or not is_inside_tree():
		return
	var infos: Array[TargetInfo] = []
	for node: Node in get_tree().get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or _body.is_ancestor_of(targetable) or not targetable.is_active():
			continue
		infos.append(targetable.to_target_info())
	system.update(infos, _ship_position())


func _emit_if_changed(before: int) -> void:
	if system.selected_id() != before:
		target_changed.emit(system.selected_id())


func _has_body() -> bool:
	return _body != null and is_instance_valid(_body) and _body.is_inside_tree()


func _ship_position() -> Vector3:
	return _body.global_position


func _ship_forward() -> Vector3:
	return -_body.global_basis.z


# --- console -----------------------------------------------------------------------------------------------------


func _console_selected() -> String:
	return selected_name() if system.has_selection() else "none"


func _console_set_selected(value: Variant) -> String:
	var wanted: String = String(value)
	if wanted.to_lower() == "none":
		clear_selection()
		return ""
	if not select_by_name(wanted):
		return "no target named '%s' in sensor range" % wanted
	return ""


func _console_choices() -> PackedStringArray:
	var out := PackedStringArray(["none"])
	for info: TargetInfo in candidates():
		out.append(info.display_name)
	return out


func _console_range() -> Variant:
	var readout: TargetReadout = selected_readout()
	return readout.range_m if readout != null else null


func _console_closing() -> Variant:
	var readout: TargetReadout = selected_readout()
	return readout.closing_mps if readout != null else null


func _console_candidates() -> PackedStringArray:
	var out := PackedStringArray()
	if not _has_body():
		return out
	for info: TargetInfo in candidates():
		out.append("%s %.0f m" % [info.display_name, TargetingSystem.range_between(_ship_position(), info.position)])
	return out
