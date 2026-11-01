class_name LodSwitcher
extends Node
## Keeps a ship's splats at the level of detail its size on screen calls for (M3-T19, Q22), by showing one of the ship's
## splat nodes and hiding the others: never by swapping a node's resource, which makes GDGS rebuild every buffer.
##
## Console (§16.4): provider `lod` (`levels`, `visible_splats`) and `lod <ship|all> <n|auto>`, registered by the newest
## switcher and handed on when it leaves, like the AI console.

## A level forced from the console, or -1 for automatic.
var forced: int = -1
## The level chosen before the tester's bias, -1 before the first frame.
var unbiased: int = -1

var _ship: Ship = null

static var _live: Array[LodSwitcher] = []


func _ready() -> void:
	_ship = get_parent() as Ship
	if _ship == null:
		push_warning("LodSwitcher: needs a Ship parent; not switching")
		set_process(false)


func _enter_tree() -> void:
	_live.append(self)
	_register(DebugConsole.registry, self)


func _exit_tree() -> void:
	_live.erase(self)
	DebugConsole.registry.unregister_owner(self)
	if not _live.is_empty():
		_register(DebugConsole.registry, _live.back())


func _process(_delta: float) -> void:
	update()


## Picks this frame's level and applies it when it changed. `_process` calls it; public for the tests.
func update() -> void:
	if _ship == null or not _ship.is_inside_tree() or not _ship.is_visible_in_tree():
		return
	var levels: PackedInt32Array = _ship.lod_levels()
	if levels.is_empty():
		return
	var level: int
	if forced >= 0:
		level = clampi(forced, levels[0], levels[levels.size() - 1])
	else:
		var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		if camera == null:
			return
		var px: float = LodSwitcherMath.projected_px(_ship.bounding_radius(), camera.global_position.distance_to(
				_ship.global_position), camera.fov, get_viewport().get_visible_rect().size.y)
		unbiased = LodSwitcherMath.next_level(px, unbiased)
		level = LodSwitcherMath.applied(unbiased, float(Settings.get_value(&"splat_lod_bias")), levels[0],
				levels[levels.size() - 1])
	if level != _ship.lod_level():
		_ship.set_lod_level(level)


# --- console ---------------------------------------------------------------------------------------------------------


static func _register(registry: ConsoleRegistry, owner: Object) -> void:
	registry.register_provider(&"lod", ConsoleVars.new({
		&"levels": {"get": _levels, "doc": "Each ship in play: name and splat level (* when forced)"},
		&"visible_splats": {"get": _visible_splats, "doc": "Splats drawn by every ship in play at its current level"},
	}), owner)
	registry.register_command(ConsoleCommand.new(&"lod",
			"Force a ship's splat level (lod <ship|all> <0-3|auto>; auto lets its size on screen decide)",
			[ConsoleArg.string_rest(&"args")]), _cmd_lod, owner)


static func _in_play() -> Array[LodSwitcher]:
	var out: Array[LodSwitcher] = []
	for s: LodSwitcher in _live:
		if s._ship != null and s._ship.is_inside_tree() and s._ship.can_process() and s._ship.is_visible_in_tree():
			out.append(s)
	return out


static func _levels() -> PackedStringArray:
	var out := PackedStringArray()
	for s: LodSwitcher in _in_play():
		out.append("%s %d%s" % [s._ship.display_name(), s._ship.lod_level(), "*" if s.forced >= 0 else ""])
	return out


static func _visible_splats() -> int:
	var total: int = 0
	for s: LodSwitcher in _in_play():
		total += s._ship.visible_splat_count()
	return total


static func _cmd_lod(args: Dictionary) -> ConsoleResult:
	var words: PackedStringArray = String(args[&"args"]).strip_edges().split(" ", false)
	if words.size() < 2:
		return ConsoleResult.failure("usage: lod <ship|all> <0-3|auto>")
	var value: String = words[words.size() - 1].to_lower()
	var who: String = " ".join(words.slice(0, words.size() - 1))
	var level: int = -1
	if value != "auto":
		if not value.is_valid_int() or int(value) < 0 or int(value) > LodSwitcherMath.COARSEST:
			return ConsoleResult.failure("the level must be 0-%d or auto, got '%s'" % [LodSwitcherMath.COARSEST, value])
		level = int(value)
	var hit: int = 0
	for s: LodSwitcher in _in_play():
		if who.to_lower() == "all" or s._ship.display_name().to_lower() == who.to_lower():
			s.forced = level
			s.update()
			hit += 1
	if hit == 0:
		return ConsoleResult.failure("no ship in play named '%s'" % who)
	return ConsoleResult.line("%d ship(s): splat level %s" % [hit, value])
