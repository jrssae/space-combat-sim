class_name LookScene
extends Node
## The look sheets' scene (M4-T30a, checkpoint 1b): `sheet <asset_id> <distance_m> [lit|dark|off] [splat|painted|textured]` parks one idle
## ship of the asset ahead of the camera at that distance, three-quarters on, hides the player's own hull and turns the key star to light
## the ship from over the camera's shoulder (`lit`) or from behind it (`dark`), so `scripts/look_sheet.sh` can photograph the same ship
## as splats, as T27's painted mesh and as the textured mesh. `sheet off` (or `sheet <asset> 0 off`) puts everything back. The sheet's
## optional livery (`<wing>:<number>`, M4-T30b) paints the parked ship. `livery <wing> [number] [ship]` repaints any ship for a look
## (the player's by default), and the `livery` provider reports what the player's ship and the others wear.
## Bench-only: nothing in a scenario uses it.

const LIGHTS: Array[StringName] = [&"lit", &"dark", &"off"]
const LOOKS: Array[StringName] = [&"splat", &"painted", &"textured"]
const POOL_TYPES: Dictionary = {"starfury_aurora": ShipPool.ALLY_TYPE, "raider_fighter": ShipPool.DEFAULT_TYPE}
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

var _parked: Combatant = null
var _asset_id: String = ""
var _star_transform: Transform3D = Transform3D.IDENTITY
var _render_before: StringName = &""
var _player_was_visible: bool = true


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"sheet",
			"Park one idle ship of an asset ahead of the camera for a look sheet, lit from behind the camera or from behind the ship, as splats, the painted or the textured mesh; `sheet off` clears it",
			[ConsoleArg.string_required(&"asset_id"), ConsoleArg.float_optional(&"distance_m", 30.0, 0.0, 20000.0),
			ConsoleArg.enum_optional(&"light", LIGHTS, &"lit"), ConsoleArg.enum_optional(&"look", LOOKS, &"textured"),
			ConsoleArg.string_optional(&"livery", "")]), _cmd_sheet, self)
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


## Whether a ship is parked now.
func is_active() -> bool:
	return _parked != null


## The parked ship, or null.
func parked() -> Combatant:
	return _parked


## Parks a ship of `asset_id` `distance_m` ahead of the current camera with the given light and look; "" on success, else why not.
func show(asset_id: String, distance_m: float, light: StringName, look: StringName) -> String:
	if not _resolve():
		return "sheet needs the world, the ship pool, the player's ship and the key star"
	if not POOL_TYPES.has(asset_id):
		return "no pooled ship draws %s (one of %s)" % [asset_id, ", ".join(POOL_TYPES.keys())]
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return "no current camera"
	if _parked == null:
		_star_transform = key_star.global_transform
		_render_before = StringName(Settings.get_value(&"ship_render"))
		_player_was_visible = player.visible
	else:
		_release()
	var type: StringName = POOL_TYPES[asset_id]
	if pool.prepare(type, 1) < 1:
		return "the %s pool is empty" % type
	var cam: Transform3D = camera.global_transform
	var at: Vector3 = cam.origin - cam.basis.z * distance_m
	var to_camera: Vector3 = (cam.origin - at).normalized()
	var basis := Basis.looking_at(to_camera, cam.basis.y).rotated(cam.basis.y, deg_to_rad(YAW_DEG)).rotated(cam.basis.x, deg_to_rad(-PITCH_DEG))
	_parked = pool.acquire("SHEET", world.to_universe(at), basis.orthonormalized(), Vector3.ZERO, IdleBrain.new(true), type)
	if _parked == null:
		return "the %s pool gave no ship" % type
	_asset_id = asset_id
	player.visible = false
	set_light(light)
	return set_look(look)


## Turns the key star for `lit` or `dark` (the camera's frame), or back to where it was for `off`.
func set_light(light: StringName) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if light == &"off" or camera == null:
		key_star.global_transform = _star_transform
		return
	var direction: Vector3 = (camera.global_basis * (LIT_LIGHT if light == &"lit" else DARK_LIGHT)).normalized()
	var up: Vector3 = camera.global_basis.y if absf(direction.dot(camera.global_basis.y)) < 0.99 else camera.global_basis.x
	key_star.global_transform = Transform3D(Basis.looking_at(direction, up), key_star.global_position)


## Draws the parked ship as splats, as T27's painted mesh or as the textured mesh (`settings.ship_render` follows); "" or why not.
func set_look(look: StringName) -> String:
	if _parked == null:
		return "no ship is parked"
	Settings.set_value(&"ship_render", &"splat" if look == &"splat" else &"mesh")
	if look != &"painted":
		return ""
	var manifest: Dictionary = SplatLod.read_manifest(_asset_id)
	var entry: Dictionary = manifest.get("paint_mesh", {})
	var painted: Mesh = MeshAssets.load_entry(ShipSpec.ASSET_ROOT.path_join(_asset_id), entry) if not entry.is_empty() else null
	if painted == null:
		return "%s has no painted mesh" % _asset_id
	var proxy: HullDepthProxy = _hull_node(_parked.ship)
	if proxy == null:
		return "the parked ship has no hull node to swap"
	proxy.use_mesh(painted, true)
	return ""


## Returns the parked ship to the pool and restores the player's hull, the key star and the render setting.
func clear() -> void:
	if _parked == null:
		return
	_release()
	player.visible = _player_was_visible
	key_star.global_transform = _star_transform
	Settings.set_value(&"ship_render", _render_before)


func _release() -> void:
	if _parked != null:
		pool.release(_parked)
	_parked = null
	_asset_id = ""


# A lean ship's one hull node, the depth proxy that draws its mesh.
func _hull_node(ship: Ship) -> HullDepthProxy:
	for child: Node in ship.get_children():
		if child is HullDepthProxy:
			return child as HullDepthProxy
	return null


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
	var look: StringName = StringName(args[&"look"])
	var error: String = show(asset_id, float(args[&"distance_m"]), light, look)
	if not error.is_empty():
		return ConsoleResult.failure(error)
	var livery_arg: String = String(args[&"livery"])
	if not livery_arg.is_empty():
		var pair: PackedStringArray = livery_arg.split(":")
		_parked.ship.set_livery(Livery.for_wing(pair[0] if pair[0] != "plain" else "", int(pair[1]) if pair.size() > 1 else 1,
				MeshAssets.livery_section(asset_id)))
	return ConsoleResult.line("sheet: %s at %.0f m, %s, %s" % [asset_id, float(args[&"distance_m"]), light, look])


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
