class_name LookScene
extends Node
## The look sheets' scene (M4-T30a, checkpoint 1b): `sheet <asset_id> <distance_m> [lit|dark|off]` parks one idle ship of the asset
## ahead of the camera at that distance, three-quarters on, hides the player's own hull and turns the key star to light the ship from
## over the camera's shoulder (`lit`) or from behind it (`dark`), so `scripts/look_sheet.sh` can photograph it. `sheet off` (or
## `sheet <asset> 0 off`) puts everything back. The sheet's optional livery (`<wing>:<number>`, M4-T30b) paints the parked ship.
## `livery <wing> [number] [ship]` repaints any ship for a look (the player's by default), and the `livery` provider reports what the
## player's ship and the others wear. Bench-only: nothing in a scenario uses it.
##
## M4-T30d: the sheet also parks the hulls that are not pooled ships (`PROP_ASSETS`): a nav buoy, a ship's break-up chunks spread
## apart (`raider_fighter_chunks`, `starfury_aurora_chunks`), a capital stand-in of each class (`capital_cruiser`, `capital_destroyer`,
## `capital_carrier`) and the station stand-in (`b5_station`).

const LIGHTS: Array[StringName] = [&"lit", &"dark", &"off"]
## How the parked ship faces the camera: three-quarters on (the sheets' rows), its back (the dorsal number), or its left side.
const VIEWS: Array[StringName] = [&"three_quarter", &"top", &"side"]
const POOL_TYPES: Dictionary = {"starfury_aurora": ShipPool.ALLY_TYPE, "raider_fighter": ShipPool.DEFAULT_TYPE,
		"saturn_3_freighter": &"saturn_3_freighter", "saturn_4_transport": &"saturn_4_transport",
		"saturn_4_tanker": &"saturn_4_tanker", "saturn_8_transport": &"saturn_8_transport", "saturn_8_tanker": &"saturn_8_tanker",
		"skylark_transport": &"skylark_transport", "narn_transport": &"narn_transport",
		"centauri_brezebel": &"centauri_brezebel", "brakiri_bokmai": &"brakiri_bokmai"}  # the civilians (M5-T16)
## The hulls that are not pooled ships, for the sheets (M4-T30d).
const PROP_ASSETS: Array[String] = ["nav_buoy", "raider_fighter_chunks", "starfury_aurora_chunks", "capital_cruiser", "capital_destroyer",
		"capital_carrier", "b5_station"]
## How far apart a ship's chunks are spread for their sheet, as a share of their distance from the ship's centre.
const CHUNK_SPREAD: float = 0.8
## How the parked ship faces the camera: turned this much off nose-on, seen a little from above.
const YAW_DEG: float = 38.0
const PITCH_DEG: float = 16.0
const LIT_LIGHT: Vector3 = Vector3(0.3, -0.35, -1.0)  # camera frame: over the camera's left shoulder, down onto the ship
const DARK_LIGHT: Vector3 = Vector3(0.0, 0.4, 1.0)  # camera frame: from behind the ship, up a little, so a rim shows

## Wired by `Main` through the parent, or by a test directly.
var world: WorldFrame = null
var pool: ShipPool = null
var player: Ship = null
var key_star: DirectionalLight3D = null
## Where the props' generated files are read from (tests point it elsewhere).
var asset_root: String = ShipSpec.ASSET_ROOT

var _parked: Combatant = null
var _prop: Node3D = null
var _asset_id: String = ""
var _star_transform: Transform3D = Transform3D.IDENTITY
var _player_was_visible: bool = true


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"sheet",
			"Park one idle ship of an asset ahead of the camera for a look sheet, lit from behind the camera or from behind the ship; `sheet off` clears it",
			[ConsoleArg.string_required(&"asset_id"), ConsoleArg.float_optional(&"distance_m", 30.0, 0.0, 20000.0),
			ConsoleArg.enum_optional(&"light", LIGHTS, &"lit"), ConsoleArg.string_optional(&"livery", "-"), ConsoleArg.enum_optional(&"view", VIEWS, &"three_quarter")]), _cmd_sheet, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"livery",
			"Paint a ship in a wing's livery with a number (plain for none), for looking at it: the player's ship, `sheet` for the parked one, or a ship by name",
			[ConsoleArg.string_required(&"wing"), ConsoleArg.int_optional(&"number", 1, 0, 99), ConsoleArg.string_rest(&"ship").make_optional("player")]), _cmd_livery, self)
	DebugConsole.registry.register_provider(&"livery", ConsoleVars.new({
		&"player": {"get": func() -> String: return _describe(player if player != null else _player_ship()),
				"doc": "The player's ship's livery: wing, number, pattern"},
		&"list": {"get": _livery_list, "doc": "Every ship in the world and the livery it wears"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Whether a ship or a prop is parked now.
func is_active() -> bool:
	return _parked != null or _prop != null


## The parked prop (M4-T30d), or null.
func prop() -> Node3D:
	return _prop


## The parked ship, or null.
func parked() -> Combatant:
	return _parked


## Parks a ship of `asset_id` `distance_m` ahead of the current camera with the given light; "" on success, else why not.
func show(asset_id: String, distance_m: float, light: StringName, view: StringName = &"three_quarter") -> String:
	if not _resolve():
		return "sheet needs the world, the ship pool, the player's ship and the key star"
	if not POOL_TYPES.has(asset_id) and not PROP_ASSETS.has(asset_id):
		return "no pooled ship or prop draws %s (one of %s, %s)" % [asset_id, ", ".join(POOL_TYPES.keys()), ", ".join(PROP_ASSETS)]
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return "no current camera"
	if not is_active():
		_star_transform = key_star.global_transform
		_player_was_visible = player.visible
	else:
		_release()
	var error: String = _show_prop(asset_id, camera, distance_m, light, view) if PROP_ASSETS.has(asset_id) \
			else _show_ship(asset_id, camera, distance_m, light, view)
	if not error.is_empty():
		_release()
		_restore()  # a sheet that could not park its subject leaves the scene as it found it
	return error


# Parks one idle pooled ship of `asset_id` for the sheet.
func _show_ship(asset_id: String, camera: Camera3D, distance_m: float, light: StringName, view: StringName) -> String:
	var type: StringName = POOL_TYPES[asset_id]
	if pool.prepare(type, 1) < 1:
		return "the %s pool is empty" % type
	var at: Vector3 = camera.global_position - camera.global_basis.z * distance_m
	_parked = pool.acquire("SHEET", world.to_universe(at), _sheet_basis(camera, at, view), Vector3.ZERO, IdleBrain.new(true), type)
	if _parked == null:
		return "the %s pool gave no ship" % type
	_asset_id = asset_id
	player.visible = false
	set_light(light)
	return ""


# How the parked subject faces the camera: three-quarters on, its back (the nose up the picture), or its left side (the nose left).
func _sheet_basis(camera: Camera3D, at: Vector3, view: StringName) -> Basis:
	var cam: Transform3D = camera.global_transform
	var to_camera: Vector3 = (cam.origin - at).normalized()
	var basis := Basis.looking_at(to_camera, cam.basis.y).rotated(cam.basis.y, deg_to_rad(YAW_DEG)).rotated(cam.basis.x, deg_to_rad(-PITCH_DEG))
	if view == &"top":
		basis = Basis.looking_at(cam.basis.y, to_camera)
	elif view == &"side":
		basis = Basis.looking_at(-cam.basis.x, cam.basis.y)
	return basis.orthonormalized()


## Turns the key star for `lit` or `dark` (the camera's frame), or back to where it was for `off`.
func set_light(light: StringName) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if light == &"off" or camera == null:
		key_star.global_transform = _star_transform
		return
	var direction: Vector3 = (camera.global_basis * (LIT_LIGHT if light == &"lit" else DARK_LIGHT)).normalized()
	var up: Vector3 = camera.global_basis.y if absf(direction.dot(camera.global_basis.y)) < 0.99 else camera.global_basis.x
	key_star.global_transform = Transform3D(Basis.looking_at(direction, up), key_star.global_position)


## Returns the parked ship to the pool and restores the player's hull and the key star.
func clear() -> void:
	if not is_active():
		return
	_release()
	_restore()


# The player's hull and the key star as they were before the sheet.
func _restore() -> void:
	player.visible = _player_was_visible
	key_star.global_transform = _star_transform


func _release() -> void:
	if _parked != null:
		pool.release(_parked)
	if _prop != null and is_instance_valid(_prop):
		_prop.queue_free()
	_parked = null
	_prop = null
	_asset_id = ""


# Parks a prop (a buoy, a ship's chunks, a capital, the station) ahead of the camera, three-quarters on or as `view` asks.
func _show_prop(asset_id: String, camera: Camera3D, distance_m: float, light: StringName, view: StringName) -> String:
	var at: Vector3 = camera.global_position - camera.global_basis.z * distance_m
	var basis: Basis = _sheet_basis(camera, at, view)
	if asset_id == "nav_buoy":
		var buoy: NavBuoy = NavBuoy.create("SHEET BUOY")
		buoy.spin_dps = 0.0
		_prop = buoy
	elif asset_id.ends_with("_chunks"):
		var ship_asset: String = asset_id.trim_suffix("_chunks")
		var hardpoints: Hardpoints = Hardpoints.load_file(asset_root.path_join(ship_asset).path_join("hardpoints.json"))
		if not hardpoints.valid or hardpoints.chunks.is_empty():
			return "%s has no chunks (run scripts/gen_assets.sh, then import)" % ship_asset
		var group := Node3D.new()
		group.name = "SheetChunks"
		for entry: Dictionary in hardpoints.chunks:
			var chunk: DebrisChunk = DebrisChunk.create(entry, asset_root.path_join(ship_asset))
			chunk.position = (entry["offset"] as Vector3) * (1.0 + CHUNK_SPREAD)
			group.add_child(chunk)
		_prop = group
	elif asset_id.begins_with("capital_"):
		var cap: CapitalStandin = CapitalStandin.create(StringName(asset_id.trim_prefix("capital_")), Factions.NEUTRAL, "SHEET CAPITAL", Vector3.ZERO)
		cap.freeze = true
		_prop = cap
	else:
		var station := StationStandin.new()
		if not station.build():
			station.free()
			return "the b5_station asset is not generated (run scripts/gen_assets.sh, then import)"
		_prop = station
	_prop.name = "Sheet" + asset_id.to_pascal_case()
	world.add_child(_prop)
	_prop.global_transform = Transform3D(basis, at)
	if _prop is CapitalStandin:
		(_prop as CapitalStandin).set_look(CapitalStandin.LOOK_MESH)
	for chunk: Node in _prop.get_children():
		if chunk is DebrisChunk:
			(chunk as DebrisChunk).launch(chunk.global_transform, Vector3.ZERO, Vector3.ZERO)
	_asset_id = asset_id
	player.visible = false
	set_light(light)
	return ""


# From `Main` (the parent) when a test did not wire the nodes itself.
func _resolve() -> bool:
	var main := get_parent() as Main
	if main != null:
		if world == null:
			world = main.world
		if pool == null:
			pool = main.ships
		if player == null:
			player = main.ship
		if key_star == null and main.space_environment != null:
			key_star = main.space_environment.key_star
	return world != null and pool != null and player != null and key_star != null


func _cmd_sheet(args: Dictionary) -> ConsoleResult:
	var light: StringName = StringName(args[&"light"])
	var asset_id: String = String(args[&"asset_id"])
	if light == &"off" or asset_id == "off":
		clear()
		return ConsoleResult.line("sheet cleared")
	var error: String = show(asset_id, float(args[&"distance_m"]), light, StringName(args[&"view"]))
	if not error.is_empty():
		return ConsoleResult.failure(error)
	var livery_arg: String = String(args[&"livery"])
	if not livery_arg.is_empty() and livery_arg != "-":
		var pair: PackedStringArray = livery_arg.split(":")
		_parked.ship.set_livery(Livery.for_wing(pair[0] if pair[0] != "plain" else "", int(pair[1]) if pair.size() > 1 else 1,
				MeshAssets.livery_section(asset_id)))
	return ConsoleResult.line("sheet: %s at %.0f m, %s" % [asset_id, float(args[&"distance_m"]), light])


func _cmd_livery(args: Dictionary) -> ConsoleResult:
	var target: Ship = _ship_named(String(args[&"ship"]))
	if target == null:
		return ConsoleResult.failure("no ship called '%s' (player, sheet, or a name from `state ships.list`)" % String(args[&"ship"]))
	var wing: String = String(args[&"wing"])
	var livery: Livery = Livery.for_wing("" if wing.to_lower() == "plain" else wing, int(args[&"number"]),
			MeshAssets.livery_section(target.spec.asset_id))
	target.set_livery(livery)
	return ConsoleResult.line("livery: %s" % livery.describe())


# The player's ship for "" or "player", the parked ship for "sheet", else the ship in the world with that name (any case).
func _ship_named(ship_name: String) -> Ship:
	var key: String = ship_name.strip_edges().to_lower()
	if key.is_empty() or key == "player":
		return player if player != null else _player_ship()
	if key == "sheet":
		return _parked.ship if _parked != null else null
	_resolve()
	if pool != null:
		for combatant: Combatant in pool.alive():
			if combatant.display_name.to_lower() == key:
				return combatant.ship
	return null


func _player_ship() -> Ship:
	var main := get_parent() as Main
	return main.ship if main != null else null


func _describe(ship: Ship) -> String:
	return ship.livery.describe() if ship != null and ship.livery != null else "none"


func _livery_list() -> PackedStringArray:
	var out := PackedStringArray()
	_resolve()
	if pool == null:
		return out
	for combatant: Combatant in pool.alive():
		out.append("%s: %s" % [combatant.display_name, _describe(combatant.ship)])
	return out
