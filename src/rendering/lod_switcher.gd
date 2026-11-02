class_name LodSwitcher
extends Node
## Keeps a ship's splats at the level of detail its size on screen calls for (M3-T19, Q22), by showing one of the ship's
## splat nodes and hiding the others: never by swapping a node's resource, which makes GDGS rebuild every buffer.
##
## It also keeps the visible splats under `settings.splat_budget` (M3-T20): once per frame, across every live switcher, the farthest
## ships in view draw coarser levels until the sum fits (`SplatBudgetMath`), and one warning says so when even the coarsest
## everywhere does not fit. That is applied on top of the level the ship's size calls for, like the tester's bias.
##
## The player's Starfury has one level finer than LOD0, the hero (M3-T24), as level -1 at the front of its chain: the other levels
## and their thresholds keep their numbers, and a chain that does not start at -1 never sees it.
##
## Console (§16.4): provider `lod` (`levels`, `visible_splats`) and `lod <ship|all> <n|auto>`, registered by the newest
## switcher and handed on when it leaves, like the AI console.

const VIEW_RADIUS_FACTOR: float = 1.5

## A level forced from the console (`LodSwitcherMath.HERO` is one), or `LodSwitcherMath.NONE` for automatic.
var forced: int = LodSwitcherMath.NONE
## The level chosen before the tester's bias, `NONE` before the first frame.
var unbiased: int = LodSwitcherMath.NONE
## The level the ship's size calls for before the budget steps it down, `NONE` before the first frame.
var wanted: int = LodSwitcherMath.NONE
## Levels the budget steps this ship down, on top of `wanted`.
var budget_extra: int = 0

var _ship: Ship = null
var _splat_counts: PackedInt32Array = PackedInt32Array()

static var _live: Array[LodSwitcher] = []
# The frame the budget last ran in: the first switcher to run in a frame does it for them all.
static var _budget_frame: int = -1
# True while even the coarsest level everywhere does not fit: one warning per spell.
static var _budget_warned: bool = false
## Warnings given so far, for the tests.
static var budget_warnings: int = 0


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
	_run_budget_once_this_frame()
	_apply()


## Picks this frame's level and applies it when it changed. `_process` picks for every ship at once; public for the tests and the
## console.
func update() -> void:
	_pick()
	_apply()


func _is_forced() -> bool:
	return forced != LodSwitcherMath.NONE


func _shown() -> bool:
	return _ship != null and _ship.is_inside_tree() and _ship.is_visible_in_tree()


# The level the ship's size calls for, or the forced one. Running it twice in a frame changes nothing.
func _pick() -> void:
	if not _shown():
		return
	var levels: PackedInt32Array = _ship.lod_levels()
	if levels.is_empty():
		return
	if _is_forced():
		wanted = clampi(forced, levels[0], levels[levels.size() - 1])
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return
	var px: float = LodSwitcherMath.projected_px(_ship.bounding_radius(), camera.global_position.distance_to(
			_ship.global_position), camera.fov, get_viewport().get_visible_rect().size.y)
	unbiased = LodSwitcherMath.next_level(px, unbiased, mini(levels[0], 0))
	wanted = LodSwitcherMath.applied(unbiased, float(Settings.get_value(&"splat_lod_bias")), levels[0], levels[levels.size() - 1])


func _apply() -> void:
	if not _shown() or wanted == LodSwitcherMath.NONE:
		return
	var levels: PackedInt32Array = _ship.lod_levels()
	if levels.is_empty():
		return
	var at: int = SplatBudgetMath.chain_index(levels, wanted)
	var level: int = levels[mini(at + (budget_extra if not _is_forced() else 0), levels.size() - 1)]
	if level != _ship.lod_level():
		_ship.set_lod_level(level)


# --- budget ----------------------------------------------------------------------------------------------------------


static func _run_budget_once_this_frame() -> void:
	var frame: int = Engine.get_process_frames()
	if frame == _budget_frame:
		return
	_budget_frame = frame
	run_budget()


## Picks every ship's level, then steps the farthest in view down until the visible splats fit. Once per frame; public for the tests.
static func run_budget() -> void:
	var budget: int = int(Settings.get_value(&"splat_budget"))
	var shown: Array[LodSwitcher] = []
	var wanted_sum: int = 0
	var current_sum: int = 0
	for s: LodSwitcher in _live:
		s._pick()
		s.budget_extra = 0
		if not s._shown() or s.wanted == LodSwitcherMath.NONE:
			continue
		var drawn: int = s._ship.visible_splat_count()
		if drawn <= 0:  # the mesh is drawn instead
			continue
		shown.append(s)
		current_sum += drawn
		wanted_sum += s._wanted_splats()
	var fixed: int = maxi(_flagged_splats() - current_sum, 0)
	# A plain sum first: over budget is rare, and the frustum test and the sort are not free.
	if wanted_sum + fixed <= budget:
		_budget_warned = false
		return
	var camera: Camera3D = shown[0].get_viewport().get_camera_3d() if not shown.is_empty() else null
	var planes := PackedFloat32Array()
	if camera != null:
		planes = GaussianVisibleTable.frustum_planes(Projection(camera.get_camera_transform().affine_inverse()), camera.get_camera_projection())
	var in_view: Array[LodSwitcher] = []
	var ships: Array[Dictionary] = []
	for s: LodSwitcher in shown:
		var entry: Dictionary = s._budget_entry(camera, planes)
		if not entry.is_empty():
			in_view.append(s)
			ships.append(entry)
	var plan: Dictionary = SplatBudgetMath.plan(ships, fixed, budget)
	var extra: PackedInt32Array = plan["extra"]
	for i: int in in_view.size():
		in_view[i].budget_extra = extra[i]
	if bool(plan["fits"]):
		_budget_warned = false
	elif not _budget_warned:
		_budget_warned = true
		budget_warnings += 1
		push_warning("LodSwitcher: %d visible splats do not fit settings.splat_budget (%d) even at the coarsest levels; the renderer will drop the rest"
				% [int(plan["total"]), budget])


# The splats the renderer's instances flag as shown, off-screen ones included. 0 with no backend, as on a headless run.
static func _flagged_splats() -> int:
	return int(GaussianRenderManager.get_stats().get("visible_flagged", 0))


func _wanted_splats() -> int:
	return _level_splats()[SplatBudgetMath.chain_index(_ship.lod_levels(), wanted)]


# A ship's chain is built once, so its counts are read once.
func _level_splats() -> PackedInt32Array:
	if _splat_counts.size() != _ship.lod_levels().size():
		_splat_counts = _ship.lod_splat_counts()
	return _splat_counts


# This ship as `SplatBudgetMath` wants it, or empty when the renderer culls it anyway. Generous with the radius: the renderer's
# sphere comes from the splats, and counting a ship it culls costs nothing.
func _budget_entry(camera: Camera3D, planes: PackedFloat32Array) -> Dictionary:
	var distance: float = 0.0
	if camera != null:
		var at: Vector3 = _ship.global_position
		if not GaussianVisibleTable.sphere_visible(planes, at.x, at.y, at.z, _ship.bounding_radius() * VIEW_RADIUS_FACTOR + 1.0):
			return {}
		distance = camera.global_position.distance_to(at)
	return {"wanted": wanted, "levels": _ship.lod_levels(), "splats": _level_splats(), "distance": distance, "forced": _is_forced()}


# --- console ---------------------------------------------------------------------------------------------------------


static func _register(registry: ConsoleRegistry, owner: Object) -> void:
	registry.register_provider(&"lod", ConsoleVars.new({
		&"levels": {"get": _levels, "doc": "Each ship in play: name and splat level (* when forced)"},
		&"visible_splats": {"get": _visible_splats, "doc": "Splats drawn by every ship in play at its current level"},
	}), owner)
	registry.register_command(ConsoleCommand.new(&"lod",
			"Force a ship's splat level (lod <ship|all> <hero|0-3|auto>; hero is the player's finest; auto lets its size on screen decide)",
			[ConsoleArg.string_rest(&"args")]), _cmd_lod, owner)


## A level as the console writes it: `hero` for the finest, else its number.
static func level_name(level: int) -> String:
	return "hero" if level == LodSwitcherMath.HERO else str(level)


static func _in_play() -> Array[LodSwitcher]:
	var out: Array[LodSwitcher] = []
	for s: LodSwitcher in _live:
		if s._ship != null and s._ship.is_inside_tree() and s._ship.can_process() and s._ship.is_visible_in_tree():
			out.append(s)
	return out


static func _levels() -> PackedStringArray:
	var out := PackedStringArray()
	for s: LodSwitcher in _in_play():
		out.append("%s %s%s" % [s._ship.display_name(), level_name(s._ship.lod_level()), "*" if s._is_forced() else ""])
	return out


static func _visible_splats() -> int:
	var total: int = 0
	for s: LodSwitcher in _in_play():
		total += s._ship.visible_splat_count()
	return total


static func _cmd_lod(args: Dictionary) -> ConsoleResult:
	var words: PackedStringArray = String(args[&"args"]).strip_edges().split(" ", false)
	if words.size() < 2:
		return ConsoleResult.failure("usage: lod <ship|all> <hero|0-3|auto>")
	var value: String = words[words.size() - 1].to_lower()
	var who: String = " ".join(words.slice(0, words.size() - 1))
	var level: int = LodSwitcherMath.NONE
	if value == "hero":
		level = LodSwitcherMath.HERO
	elif value != "auto":
		if not value.is_valid_int() or int(value) < 0 or int(value) > LodSwitcherMath.COARSEST:
			return ConsoleResult.failure("the level must be hero, 0-%d or auto, got '%s'" % [LodSwitcherMath.COARSEST, value])
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
