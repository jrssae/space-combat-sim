class_name FarPropHost
extends Node
## The far props' console and the station's stand-in for them (M6-T15, D70, AC9): provider `far` (each far prop's draw path,
## distance and size on screen) and command `far` (`status`, `station` to place the station's stand-in where the scenarios put
## the station, `view <gate|station> <km>` to hold the camera that far from one for captures, `off`).
##
## The stand-in has no `Targetable` of its own yet, so it is heard, and drawn, as far as a gate or a nav buoy: 1 000 km. A
## scenario that anchors on the station's rail has `Main` place it for good (`place_station`, M6-T09).

const NODE_NAME: String = "FarPropHost"
const ACTIONS: Array[StringName] = [&"status", &"station", &"view", &"off"]
const TARGETS: Array[StringName] = [&"gate", &"station"]
## The station's stand-in is seen as far as a nav beacon is heard (D69, M3-T17).
const STATION_RANGE_M: float = 1.0e6
## `far view`: the camera's bearing from the prop's centre in the prop's frame (in front, a little up and to the side, so a gate
## reads as one), and its field of view.
const VIEW_BEARING: Vector3 = Vector3(-0.35, 0.25, -1.0)
const VIEW_FOV_DEG: float = 50.0

var main: Main = null
## The station's stand-in, placed by the scenario or by `far station`, or null.
var station: StationStandin = null
## Where the station stands in the scenario's coordinates (M6-T09): where `far station` puts it back.
var station_place: UniversePos = null

var _view_prop: Node3D = null


## Gives the station's stand-in its far drawing: both pieces shrunk together, then a dot. Call after `build()`, before it is
## spawned. Null when its asset has no far section.
static func dress_station(standin: StationStandin, range_m: float = STATION_RANGE_M) -> FarProp:
	var manifest: Dictionary = MeshAssets.read_manifest(StationStandin.ASSET_ID)
	return FarProp.attach(standin, [standin.frame_piece, standin.drum_pivot] as Array[Node3D], manifest.get("far", {}),
			FarProp.albedo_of(manifest), range_m, "STATION")


func _ready() -> void:
	DebugConsole.registry.register_provider(&"far", ConsoleVars.new({
		&"props": {"get": prop_count, "doc": "Big props drawn far out by a FarProp (M6-T15): the jumpgates and the station's stand-in"},
		&"layout": {"get": _layout_text, "doc": "Each far prop: its draw path (near, shrunk, fading, dot), distance, shrink, bounding radius and covered area on screen, and its range"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"far",
			"Far props (M6-T15): status, station (place the station's stand-in at the station's place, or take it away), view <gate|station> <km> (hold the camera that far from it for captures), off (end the view)",
			[ConsoleArg.enum_optional(&"action", ACTIONS), ConsoleArg.enum_optional(&"target", TARGETS),
					ConsoleArg.float_optional(&"km", null, 0.0)]), _cmd_far, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Far props in the tree now.
func prop_count() -> int:
	return get_tree().get_nodes_in_group(FarProp.GROUP).size() if is_inside_tree() else 0


## Places the station's stand-in for good at `at` (three numbers in the scenario's coordinates, M6-T09), dressed for the
## far field. False, with nothing placed, when `at` is empty, beyond the stand-in's range, or its asset is missing.
func place_station(at: PackedFloat64Array) -> bool:
	if at.size() < 3 or Vector3(at[0], at[1], at[2]).length() > STATION_RANGE_M:
		return false
	station_place = UniversePos.new(at[0], at[1], at[2], main.world.origin.system_id)
	if station != null and is_instance_valid(station):
		station.queue_free()
		station = null
	return toggle_station()


## Places the station's stand-in at the station's place (where the scenario put it, else the scenario's origin), or takes it
## away when it is there. False when its asset is missing.
func toggle_station() -> bool:
	if station != null and is_instance_valid(station):
		station.queue_free()
		station = null
		return true
	var made := StationStandin.new()
	made.name = "Station"
	if not made.build():
		made.free()
		return false
	dress_station(made)
	var at: UniversePos = station_place if station_place != null else UniversePos.new(0.0, 0.0, 0.0, main.world.origin.system_id)
	main.world.spawn(made, at, Basis.IDENTITY, main.world)
	station = made
	return true


func _layout_text() -> String:
	var lines := PackedStringArray()
	if not is_inside_tree():
		return ""
	for node: Node in get_tree().get_nodes_in_group(FarProp.GROUP):
		var f := node as FarProp
		lines.append("%s %s at %.1f km shrink %.4f bounding %.1f px cover %.2f px2 fade %.2f range %.0f km" % [f.display_name,
				f.path(), f.distance_m / 1000.0, f.shrink, f.math.bounding_px(f.distance_m, f.k_px_per_rad), f.cover_px2(), f.fade,
				f.range_m / 1000.0])
	return "; ".join(lines) if not lines.is_empty() else "none"


func _target(which: StringName) -> Node3D:
	if which == &"station":
		return station if station != null and is_instance_valid(station) else null
	return main.gates.gate() if main.gates != null else null


# Holds the cinematic camera `km` from the prop's centre on `VIEW_BEARING`, aimed at it.
func _view(which: StringName, km: float) -> ConsoleResult:
	var prop: Node3D = _target(which)
	var far: FarProp = FarProp.of(prop)
	if prop == null or far == null:
		return ConsoleResult.failure("far view: no %s drawn far out here (far station places the station's stand-in)" % which)
	var centre: Vector3 = far.math.centre
	var at: Vector3 = centre + VIEW_BEARING.normalized() * maxf(km * 1000.0, 0.1)
	var frame: Dictionary = {"position": {"actor": "far", "offset": [at.x, at.y, at.z]},
			"look_at": {"actor": "far", "offset": [centre.x, centre.y, centre.z]}, "fov": VIEW_FOV_DEG}
	var made: Dictionary = CinematicShot.from_dict(&"far_view", {"keys": [frame.merged({"t": 0.0}), frame.merged({"t": 3600.0})]})
	if not bool(made["ok"]):
		return ConsoleResult.failure(String(made["error"]))
	_view_prop = prop
	main.camera_rig.play_shot(made["shot"], _view_pose, _origin_to_local)
	main.letterbox.shown = false
	return ConsoleResult.line("far view %s %.3f km" % [which, km])


func _view_pose(actor: String) -> Variant:
	if actor == "far" and _view_prop != null and is_instance_valid(_view_prop):
		return _view_prop.global_transform
	return null


func _origin_to_local(offset: PackedFloat64Array) -> Vector3:
	return main.world.universe_to_local(UniversePos.new(offset[0], offset[1], offset[2], main.world.origin.system_id))


func _cmd_far(args: Dictionary) -> ConsoleResult:
	var action: StringName = StringName(args[&"action"]) if args[&"action"] != null else &"status"
	match action:
		&"station":
			if not toggle_station():
				return ConsoleResult.failure("the babylon5_station asset is not generated (run scripts/gen_assets.sh, then import)")
			return ConsoleResult.line("far station: %s" % ("placed at the station's place" if station != null else "taken away"))
		&"view":
			if args[&"target"] == null or args[&"km"] == null:
				return ConsoleResult.failure("far view <gate|station> <km>")
			return _view(StringName(args[&"target"]), float(args[&"km"]))
		&"off":
			if main.camera_rig.is_playing_shot():
				main.camera_rig.stop_shot()
			_view_prop = null
			return ConsoleResult.line("far view off")
	return ConsoleResult.line("far: %d props; %s" % [prop_count(), _layout_text()])
