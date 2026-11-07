class_name TargetingController
extends Node
## The ship's targeting computer (architecture §3, §6.3): a thin node around the pure `TargetingSystem`. Every
## physics tick it drops a selection that left its reach or play; `apply(cmd)` handles the `target_next` / `target_ahead`
## edges. The player's controller (`keeps_candidates`) also rebuilds its whole candidate list from group `targetable` every
## tick, for the HUD and the radar; other ships build theirs only when asked (M4-T02). Lists are built from the live nodes,
## so nothing survives a `World.rebase()` stale.
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
##
## Tier ships (M4-T23): a ship in the low-attention tier is parked, so its targetable is not active; its row in the core
## stands in for it (`TierTargets`): candidates, the nearest hostile, a selection and its readout read the row, by the same
## marker id, so a selection survives the ship's promotion and demotion. A controller whose own ship is in the tier reads
## its own position from its row too.
##
## On the core (M4-T35): an AI ship's controller (one that does not keep candidates) hands its
## check to the core, which runs every watched ship's in one pass over the rows at this priority and names the ships whose
## selection must clear; this node then stops ticking itself and only clears (`clear_selection`, the same signal).

## The selection changed: a target id (`Targetable` instance id), or `TargetingSystem.NO_TARGET` when it cleared.
signal target_changed(id: int)

## Runs after the ship and the props (default priority 0) so the candidates reflect this tick's kinematic moves.
const LATE_PRIORITY: int = 100

var system: TargetingSystem = TargetingSystem.new()
## Whether every tick rebuilds the whole candidate list (M4-T02): the player's does, since the HUD and the radar read it every
## frame. Other ships only check their selection each tick and build a list when something asks for one, so their ticks
## cost nothing per targetable (with every ship gathering, targeting was two thirds of a 100-ship tick).
var keeps_candidates: bool = true

var _body: RigidBody3D = null
# The list was not built since the last refresh (M4-T34, built on read): the next reader builds it.
var _stale: bool = false
# What the last refresh's list held, light (M4-T34, on read): each target's id, position, broadcast range and name, so the
# selection, its name and `select_id` answer as from the list the refresh used to build. Valid until a command gathers anew.
var _snap_ids := PackedInt64Array()
var _snap_positions := PackedVector3Array()
var _snap_reach := PackedFloat64Array()
var _snap_names := PackedStringArray()
var _snap_valid: bool = false
# Every controller in a tree, so the core can rebind them when its selection check comes or goes (M4-T35); the core this
# one's check runs on, or null.
static var _live: Array[TargetingController] = []
var _sim: SimCore = null


func _init() -> void:
	process_physics_priority = LATE_PRIORITY


func _enter_tree() -> void:
	_live.append(self)
	if _body != null:
		_bind()


func _exit_tree() -> void:
	_live.erase(self)
	_unbind()
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
	_bind()


## Whether the core runs this controller's selection check now (M4-T35).
func on_core() -> bool:
	return _sim != null


## Sets the sensor range (`TargetingSystem.sensor_range_m`) and tells the core's check, which took the range when it bound.
func set_sensor_range_m(value: float) -> void:
	system.sensor_range_m = value
	if _sim != null and _body != null:
		_sim.watch_selection(self, _body.get_instance_id(), value)


## Binds every controller to the core's selection check, or back to its own tick, as the core and the setting stand.
static func rebind_all() -> void:
	for controller: TargetingController in _live:
		if is_instance_valid(controller) and controller._body != null:
			controller._bind()


# Hands the check to the core when it runs them and this controller only checks its selection; else ticks itself.
func _bind() -> void:
	var sim: SimCore = SimCore.for_tree(get_tree()) if is_inside_tree() else null
	var wanted: bool = sim != null and not keeps_candidates and SimCore.selection_check_enabled() and _has_body()
	if not wanted:
		_unbind()
		return
	if _sim == sim:
		return
	_unbind()
	_sim = sim
	sim.watch_selection(self, _body.get_instance_id(), system.sensor_range_m)
	set_physics_process(false)


func _unbind() -> void:
	if _sim != null and is_instance_valid(_sim) and _body != null:
		_sim.unwatch_selection(_body.get_instance_id())
	_sim = null
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	refresh()


## Clears a selection that is gone or out of reach (emits `target_changed` then), and rebuilds the candidates now when the
## controller keeps them.
func refresh() -> void:
	var before: int = system.selected_id()
	if not keeps_candidates:
		_check_selection()
	else:
		_snapshot()
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
	var info: TargetInfo = _live_info(system.selected_id())
	if info == null:
		return null
	return TargetingSystem.compute_readout(info, _ship_position(), _body.linear_velocity, _ship_forward())


## Line of sight from the ship to the selected target, World frame, m; zero when nothing is selected. Read live from
## the target node, so it is current even in a tick where this node has not refreshed yet (the ship's brake uses it
## to face the target, §5.5).
func selected_offset() -> Vector3:
	if not _has_body() or not system.has_selection():
		return Vector3.ZERO
	var target := instance_from_id(system.selected_id()) as Targetable
	if target == null or not target.is_inside_tree():
		return Vector3.ZERO
	if not target.is_active():
		var row: TargetInfo = TierTargets.info_of(get_tree(), system.selected_id())
		if row != null:
			return row.position - _ship_position()
	return target.global_position - _ship_position()


## `TargetingSystem.NO_TARGET` (0) when nothing is selected.
func selected_id() -> int:
	return system.selected_id()


## Display name of the selection, or "" when nothing is selected.
func selected_name() -> String:
	if keeps_candidates and _snap_valid:
		var k: int = _snap_ids.find(system.selected_id())
		return _snap_names[k] if k >= 0 else ""
	var target: TargetInfo = system.selected()
	return target.display_name if target != null else ""


## Selectable targets: in sensor range, nearest first. As of the last refresh when the controller keeps its candidates,
## gathered now when it does not.
func candidates() -> Array[TargetInfo]:
	if not _has_body():
		return []
	if not keeps_candidates:
		var before: int = system.selected_id()
		_gather()
		_emit_if_changed(before)
	else:
		_ensure_list()
	return system.in_range(_ship_position())


## Selects the nearest in-range target hostile to this ship's faction (the AI's choice); clears the selection when there
## is none. Returns whether a hostile is selected.
func select_nearest_hostile() -> bool:
	if not _has_body():
		return false
	var before: int = system.selected_id()
	var found: bool = false
	if keeps_candidates:
		_gather()
		var order: Array[TargetInfo] = system.cycle_order(_ship_position())
		found = not order.is_empty() and Factions.is_hostile(system.own_faction, order[0].faction)
		if found:
			system.select_id(order[0].id, _ship_position())
		else:
			system.clear()
	else:
		var nearest: TargetInfo = _nearest_hostile()
		found = nearest != null
		if found:
			_select_alone(nearest)
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
## last refresh (on read, from what that refresh's list held), gathering them again only when it is not among them; a
## controller that does not keep its candidates checks that one target alone. Returns whether it is selected.
func select_id(target_id: int) -> bool:
	if not _has_body():
		return false
	var before: int = system.selected_id()
	if before != target_id:
		if not keeps_candidates:
			var target: TargetInfo = _selectable(target_id)
			if target != null:
				_select_alone(target)
			else:
				_check_selection()
		elif not (_snap_select(target_id) if _snap_valid else system.select_id(target_id, _ship_position())):
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
	_stale = false
	_snap_valid = false
	system.update(_infos(), _ship_position())


# A `TargetInfo` for every targetable this ship could list now (in play, not its own).
func _infos() -> Array[TargetInfo]:
	var infos: Array[TargetInfo] = []
	for node: Node in get_tree().get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or _body.is_ancestor_of(targetable) or not targetable.is_active():
			continue
		infos.append(targetable.to_target_info())
	var rows: TierTargets = _tier_rows()
	for k: int in rows.size():
		infos.append(rows.info(k))
	return infos


# The refresh on read (M4-T34): notes what the list would hold (in play, not its own, at its position now) and clears the
# selection as `TargetingSystem.update` would over that list; the full list waits for its first reader.
func _snapshot() -> void:
	if not _has_body() or not is_inside_tree():
		return
	_snap_ids.clear()
	_snap_positions.clear()
	_snap_reach.clear()
	_snap_names.clear()
	for node: Node in get_tree().get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or _body.is_ancestor_of(targetable) or not targetable.is_active():
			continue
		_snap_ids.append(targetable.get_instance_id())
		_snap_positions.append(targetable.global_position)
		_snap_reach.append(targetable.broadcast_range_m)
		_snap_names.append(targetable.display_name)
	var rows: TierTargets = _tier_rows()
	_snap_ids.append_array(rows.ids)
	_snap_positions.append_array(rows.positions)
	_snap_reach.append_array(rows.reach)
	_snap_names.append_array(rows.names)
	_snap_valid = true
	_stale = true
	if system.has_selection() and not _snap_in_reach(_snap_ids.find(system.selected_id())):
		system.clear()


# Whether snapshot entry `k` is listed and within reach of the ship now (`TargetingSystem.in_range`'s test).
func _snap_in_reach(k: int) -> bool:
	return k >= 0 and TargetingSystem.range_between(_ship_position(), _snap_positions[k]) \
			<= maxf(system.sensor_range_m, _snap_reach[k])


# `TargetingSystem.select_id` over what the last refresh's list held; true when the target was there and within reach.
func _snap_select(target_id: int) -> bool:
	if not _snap_in_reach(_snap_ids.find(target_id)):
		return false
	system.select_listed(target_id)
	return true


# Builds the kept list now if no one has since the last refresh (M4-T34), leaving the selection as the refresh left it;
# true when it did.
func _ensure_list() -> bool:
	if not (keeps_candidates and _stale) or not _has_body() or not is_inside_tree():
		return false
	_stale = false
	system.set_candidates(_infos())
	return true


# Clears a selection this ship could no longer select, without gathering anything.
func _check_selection() -> void:
	if system.has_selection() and _has_body() and is_inside_tree() and _selectable(system.selected_id()) == null:
		system.clear()


# The target with this id if this ship could select it now (in play or in the tier, not its own, within reach), else null.
func _selectable(target_id: int) -> TargetInfo:
	if target_id == TargetingSystem.NO_TARGET or not is_instance_id_valid(target_id):
		return null
	var target := instance_from_id(target_id) as Targetable
	if target == null or _body.is_ancestor_of(target):
		return null
	var at: Vector3 = target.global_position
	var broadcast: float = target.broadcast_range_m
	var row: TargetInfo = null
	if not target.is_active():
		row = TierTargets.info_of(get_tree(), target_id)
		if row == null:
			return null
		at = row.position
	if TargetingSystem.range_between(_ship_position(), at) > maxf(system.sensor_range_m, broadcast):
		return null
	return row if row != null else target.to_target_info()


# The target with this id as it is now (a live targetable, or a tier ship's row), or null when it is neither.
func _live_info(target_id: int) -> TargetInfo:
	var target := instance_from_id(target_id) as Targetable if is_instance_id_valid(target_id) else null
	if target == null or not target.is_inside_tree():
		return null
	if target.is_active():
		return target.to_target_info()
	return TierTargets.info_of(get_tree(), target_id)


# The tier ships this ship could list now (M4-T23).
func _tier_rows() -> TierTargets:
	return TierTargets.gather(get_tree(), _ship_position(), _body.get_instance_id(), system.sensor_range_m)


# The nearest targetable hostile to this ship within its reach, ties to the lower id, or null. The same pick as the head of
# `TargetingSystem.cycle_order`, without building a list.
func _nearest_hostile() -> TargetInfo:
	var ship_pos: Vector3 = _ship_position()
	var hostile: Dictionary = {}  # faction -> hostile to this ship, looked up once per faction
	var best: Targetable = null
	var best_id: int = 0
	var best_range: float = INF
	for node: Node in get_tree().get_nodes_in_group(Targetable.GROUP):
		var targetable := node as Targetable
		if targetable == null or _body.is_ancestor_of(targetable) or not targetable.is_active():
			continue
		var faction: StringName = targetable.faction
		if not hostile.has(faction):
			hostile[faction] = Factions.is_hostile(system.own_faction, faction)
		if not hostile[faction]:
			continue
		var r: float = TargetingSystem.range_between(ship_pos, targetable.global_position)
		if r > maxf(system.sensor_range_m, targetable.broadcast_range_m):
			continue
		if best_id == 0 or r < best_range or (r == best_range and targetable.get_instance_id() < best_id):
			best = targetable
			best_id = targetable.get_instance_id()
			best_range = r
	var rows: TierTargets = _tier_rows()
	var best_row: int = -1
	for k: int in rows.size():
		var faction: StringName = rows.factions[k]
		if not hostile.has(faction):
			hostile[faction] = Factions.is_hostile(system.own_faction, faction)
		if not hostile[faction]:
			continue
		var r: float = TargetingSystem.range_between(ship_pos, rows.positions[k])
		if best_id == 0 or r < best_range or (r == best_range and rows.ids[k] < best_id):
			best_row = k
			best_id = rows.ids[k]
			best_range = r
	if best_row >= 0:
		return rows.info(best_row)
	return best.to_target_info() if best != null else null


# Selects a target `_selectable` passed, holding it as the only candidate (a controller that does not keep the list).
func _select_alone(target: TargetInfo) -> void:
	var only: Array[TargetInfo] = [target]
	system.update(only, _ship_position())
	system.select_id(target.id, _ship_position())


func _emit_if_changed(before: int) -> void:
	if system.selected_id() != before:
		if _body != null:
			SimCore.note_selection_changed(_body.get_instance_id(), system.selected_id())  # the core's column (M4-T35)
		target_changed.emit(system.selected_id())


func _has_body() -> bool:
	return _body != null and is_instance_valid(_body) and _body.is_inside_tree()


# Where this ship is: its body, or its row while it flies in the low-attention tier (M4-T23).
func _ship_position() -> Vector3:
	if _body.has_meta(TierDirector.TIER_META):
		var sim: SimCore = SimCore.for_tree(get_tree())
		if sim != null and sim.core != null:
			var row: Vector4 = sim.core.tier_position(_body.get_instance_id())
			if row.w > 0.0:
				return Vector3(row.x, row.y, row.z)
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
