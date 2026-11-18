class_name HangarBackdrop
extends Node3D
## The front end's backdrop (M7-T09, M7-T20; D77, Q7): Alpha wing's Cobra-bay hall (`b5_interior`, the top arm's) with a Starfury
## held over each of its six launch doors and the second row of six beside them, ready for M8 to go from the menu straight into
## a launch. The hall's pieces come from the generator; the fighters are the real `starfury_aurora` in Alpha wing's livery,
## numbered 1 to 12 (each fighter's `id`, `door`, `wave` and release point are in the manifest's `fighters` for the launch). Lit cheaply: the hall's glow is emissive, one work
## lamp per bay through the light rig (6 emitters for its 7 omni slots, so none ever swaps) and the key light turned into a dim
## red fill from above. Without the generated interior it stays empty and the front end keeps M5's sky.
##
## Console (§6.4): `backdrop <move|wide|close|rack|second> [time_s]` picks the camera's view (and the move's clock); provider `backdrop`.

const ASSET_ID: String = "b5_interior"
const WING: String = "alpha"
const VIEWS: Array[StringName] = [&"move", &"wide", &"close", &"rack", &"second"]

## Where the generated assets are read from (tests point it elsewhere).
var asset_root: String = ShipSpec.ASSET_ROOT
## The sky's environment, whose key light becomes the hall's fill; null leaves the key light alone.
var environment: SpaceEnvironment = null

var _manifest: Dictionary = {}
var _camera_move: HangarCamera = null
var _view: HangarCamera.View = HangarCamera.View.MOVE
var _elapsed_s: float = 0.0
var _emitters: Array[LightEmitter] = []
var _fighters: Array[MeshInstance3D] = []
var _pieces: Array[MeshInstance3D] = []


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"backdrop",
			"Show the menu's hangar from its slow camera move (at a time into it) or from a fixed view: wide, close, the racks or the second row",
			[ConsoleArg.enum_required(&"view", VIEWS), ConsoleArg.float_optional(&"time_s", -1.0, -1.0, 100000.0)]), _cmd_backdrop, self)
	DebugConsole.registry.register_provider(&"backdrop", ConsoleVars.new({
		&"loaded": {"get": is_loaded, "doc": "The hangar interior is behind the menu (else M5's sky)"},
		&"fighters": {"get": func() -> int: return _fighters.size(), "doc": "Starfuries in the hall: on the racks and in the second row"},
		&"lights": {"get": func() -> int: return _emitters.size(), "doc": "Work lamps entered into the light rig"},
		&"view": {"get": func() -> String: return String(VIEWS[_view]), "doc": "The camera's view: move, wide, close, rack or second"},
		&"time_s": {"get": func() -> float: return snappedf(_elapsed_s, 0.01), "unit": "s", "doc": "How far into the slow move"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


## Builds the hangar from the generated interior; false (and nothing built) when it is missing or not imported.
func load_interior() -> bool:
	_clear()
	_manifest = MeshAssets.read_manifest(ASSET_ID, asset_root)
	if _manifest.is_empty():
		return false
	var dir: String = asset_root.path_join(ASSET_ID)
	var pieces: Dictionary = _manifest.get("pieces", {})
	for name: String in ["bay", "ends", "signs"]:
		var entry: Dictionary = pieces.get(name, {})
		var mesh: Mesh = MeshAssets.load_textured(dir, entry.get("mesh", {}))
		if mesh == null:
			_clear()
			return false
		var origins: Array = entry.get("instances", [{"name": name, "origin": [0.0, 0.0, 0.0]}])
		for instance: Dictionary in origins:
			_pieces.append(_add_mesh(String(instance.get("name", name)), mesh, Transform3D(Basis.IDENTITY, _vec(instance.get("origin", [])))))
	_add_fighters()
	_add_lights()
	_camera_move = HangarCamera.from_manifest(_manifest)
	return true


func is_loaded() -> bool:
	return _camera_move != null


## The camera's pose after `delta` more seconds of the move (or the fixed view the console picked).
func advance(delta: float) -> Transform3D:
	_elapsed_s += delta
	return camera_pose()


func camera_pose() -> Transform3D:
	return _camera_move.pose(_elapsed_s, _view) if _camera_move != null else Transform3D.IDENTITY


func fighters() -> Array[MeshInstance3D]:
	return _fighters


func emitters() -> Array[LightEmitter]:
	return _emitters


func _add_mesh(label: String, mesh: Mesh, where: Transform3D) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.transform = where
	add_child(instance)
	return instance


# The real Starfury at every fighter's place, nose toward the arm's head, in Alpha wing's livery with its number; named by its id.
func _add_fighters() -> void:
	var fighter: String = String(_manifest.get("fighter", "starfury_aurora"))
	var mesh: Mesh = MeshAssets.for_asset(fighter, asset_root)
	if mesh == null:
		push_warning("HangarBackdrop: %s is missing; the hall stays empty" % fighter)
		return
	var section: Dictionary = MeshAssets.livery_section(fighter, asset_root)
	for entry: Dictionary in _manifest.get("fighters", []):
		var basis := Basis.looking_at(_vec(entry.get("forward", [0.0, 0.0, -1.0])), _vec(entry.get("up", [0.0, 1.0, 0.0])))
		var ship: MeshInstance3D = _add_mesh(String(entry.get("id", "fighter")), mesh, Transform3D(basis, _vec(entry.get("position", []))))
		Livery.for_wing(String(entry.get("wing", WING)), int(entry.get("number", 0)), section).apply(ship)
		_fighters.append(ship)


# The work lamps into the light rig, and the key light as the hall's dim red fill from above.
func _add_lights() -> void:
	var rig: LightRig = LightRig.of(self)
	if rig == null:
		return
	for light: Dictionary in _manifest.get("lights", []):
		var colour: Array = light.get("colour", [1.0, 1.0, 1.0])
		var emitter := LightEmitter.new(String(light.get("name", "work")), LightEmitter.PRIORITY_CABIN,
				Color(float(colour[0]), float(colour[1]), float(colour[2])), float(light.get("energy", 1.0)), float(light.get("range_m", 10.0)))
		emitter.position = to_global(_vec(light.get("position", [])))
		rig.add_emitter(emitter)
		_emitters.append(emitter)
	var fill: Dictionary = _manifest.get("fill", {})
	if fill.is_empty() or rig.key_star == null:
		return
	if environment != null:
		environment.hold_key_star(true)  # the sun is not seen in here
	var colour: Array = fill.get("colour", [1.0, 0.4, 0.3])
	rig.key_star.light_color = Color(float(colour[0]), float(colour[1]), float(colour[2]))
	rig.key_star.light_energy = float(fill.get("energy", 0.3))
	rig.key_star.global_basis = Basis.looking_at(global_basis * _vec(fill.get("direction", [0.0, -1.0, 0.0])).normalized(), Vector3.FORWARD)


func _clear() -> void:
	for node: MeshInstance3D in _pieces + _fighters:
		node.queue_free()
	for emitter: LightEmitter in _emitters:
		emitter.energy = 0.0  # dark, so the rig no longer picks it
	_pieces.clear()
	_fighters.clear()
	_emitters.clear()
	_camera_move = null


## Shows the hangar from `view` (move, wide or close); a `time_s` of 0 or more also sets the move's clock.
func show_view(view: StringName, time_s: float = -1.0) -> void:
	_view = maxi(VIEWS.find(view), 0) as HangarCamera.View
	if time_s >= 0.0:
		_elapsed_s = time_s


func _cmd_backdrop(args: Dictionary) -> ConsoleResult:
	if not is_loaded():
		return ConsoleResult.failure("the hangar interior is not loaded (run scripts/gen_assets.sh, then import)")
	show_view(args[&"view"], float(args[&"time_s"]))
	return ConsoleResult.line("backdrop %s at %.1f s" % [VIEWS[_view], _elapsed_s])


static func _vec(values: Variant) -> Vector3:
	var a: Array = values if values is Array else []
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a.size() >= 3 else Vector3.ZERO
