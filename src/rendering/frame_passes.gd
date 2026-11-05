class_name FramePasses
extends Node
## The frame's per-ship visual work, one pass per subsystem (M4-T36, architecture §17.21). Thruster plumes, muzzle flashes, hit
## flashes and the far-dot decision used to be a `_process` on every ship (or every flash, idle or not); at 500 ships those
## callbacks had no owner and cost the frame several milliseconds. Each subsystem now registers its nodes here and this one node
## walks each list once a frame: the plumes of the ships in play and shown, only the muzzle and hit flashes that are showing,
## every LOD switcher with the camera and the dot distance read once. It also keeps the finished hit flashes for the next hits
## (hidden children of this node), so a hit no longer builds and frees nodes.
##
## One per game: the autoload `FramePassesNode`, so it runs from the first frame in every scene, tests and scenes without `Main`
## included (`of` finds it; without the autoload it is made under the root on first use). It runs before the default priority, as
## the per-node callbacks it replaces ran before the nodes that read what they set. A node takes part
## only while it could process (`can_process()`), as its own `_process` did, so a parked ship or a paused game freezes.
##
## Console (§6.4): provider `frame` (each pass's cost in the last frame and what it walks).

## The autoload's name (project.godot): a class name cannot also name an autoload.
const NODE_NAME: StringName = &"FramePassesNode"
## Before the default priority (0).
const PRIORITY: int = -10

static var _instance: FramePasses = null

var _plumes: Array[ThrusterVisuals] = []
var _flashes: Array[MuzzleFlash] = []
var _impacts: Array[ImpactFlash] = []
# Finished hit flashes kept for the next hits.
var _impact_pool: Array[ImpactFlash] = []
var _switchers: Array[LodSwitcher] = []
var _cost_us: Dictionary[StringName, int] = {&"plumes": 0, &"flashes": 0, &"impacts": 0, &"lod": 0}


## The game's passes when they exist, else null (never makes them).
static func current() -> FramePasses:
	return _instance if _instance != null and is_instance_valid(_instance) else null


## The game's passes (the autoload), or made under the root on first use without it; null outside a tree.
static func of(node: Node) -> FramePasses:
	if _instance != null and is_instance_valid(_instance):
		return _instance  # in the tree, or about to be
	if node == null or not node.is_inside_tree():
		return null
	var root: Window = node.get_tree().root
	var found := root.get_node_or_null(NodePath(String(NODE_NAME))) as FramePasses
	if found == null:
		found = FramePasses.new()
		root.add_child.call_deferred(found)  # a node may ask while the root is busy adding children
	_instance = found
	return found


func _init() -> void:
	name = NODE_NAME
	_instance = self
	process_priority = PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS  # each node's own `can_process()` decides, as its `_process` did


func _ready() -> void:
	DebugConsole.registry.register_provider(&"frame", ConsoleVars.new({
		&"plumes_us": {"get": func() -> int: return _cost_us[&"plumes"], "unit": "us", "doc": "Thruster plumes pass, last frame"},
		&"plumes": {"get": func() -> int: return _plumes.size(), "doc": "Ships' plume sets in the pass (in play and shown)"},
		&"flashes_us": {"get": func() -> int: return _cost_us[&"flashes"], "unit": "us", "doc": "Muzzle flashes pass, last frame"},
		&"flashes": {"get": func() -> int: return _flashes.size(), "doc": "Muzzle flashes showing"},
		&"impacts_us": {"get": func() -> int: return _cost_us[&"impacts"], "unit": "us", "doc": "Hit flashes pass, last frame"},
		&"impacts": {"get": func() -> int: return _impacts.size(), "doc": "Hit flashes showing"},
		&"impact_pool": {"get": impact_pool_size, "doc": "Spare hit flashes kept for the next hits"},
		&"lod_us": {"get": func() -> int: return _cost_us[&"lod"], "unit": "us", "doc": "Far-dot decision pass, last frame"},
		&"switchers": {"get": func() -> int: return _switchers.size(), "doc": "LOD switchers registered"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _instance == self:
		_instance = null


func _process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()  # profiling readouts only, never gameplay time
	for visuals: ThrusterVisuals in _plumes:
		if visuals.can_process():
			visuals.frame_update(delta)
	var plumes_done: int = Time.get_ticks_usec()
	advance_flashes(delta)
	var flashes_done: int = Time.get_ticks_usec()
	advance_impacts(delta)
	var impacts_done: int = Time.get_ticks_usec()
	update_lod()
	_cost_us[&"plumes"] = plumes_done - started
	_cost_us[&"flashes"] = flashes_done - plumes_done
	_cost_us[&"impacts"] = impacts_done - flashes_done
	_cost_us[&"lod"] = Time.get_ticks_usec() - impacts_done


## The far-dot decision for every registered ship: the camera and the dot distance read once (M4-T11's rule per ship). Public
## for the tests.
func update_lod() -> void:
	if _switchers.is_empty():
		return
	var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return
	var eye: Vector3 = camera.global_position
	var far_m: float = float(Settings.get_value(&"far_ship_dot_m"))
	for switcher: LodSwitcher in _switchers:
		if switcher.can_process():
			switcher.decide(eye, far_m)


## Ages every showing flash by `delta`; one that is over leaves the list. Public for the tests.
func advance_flashes(delta: float) -> void:
	var i: int = 0
	while i < _flashes.size():
		var flash: MuzzleFlash = _flashes[i]
		if not is_instance_valid(flash):
			_flashes.remove_at(i)
			continue
		if flash.can_process():
			flash.advance(delta)
		if flash.is_idle():
			_flashes.remove_at(i)
			continue
		i += 1


## Ages every showing hit flash by `delta`; one that is over has gone back to the pool and leaves the list. Public for the tests.
func advance_impacts(delta: float) -> void:
	var i: int = 0
	while i < _impacts.size():
		var impact: ImpactFlash = _impacts[i]
		if not is_instance_valid(impact) or not impact.is_inside_tree():
			_impacts.remove_at(i)  # freed with its ship, or taken off it
			continue
		if impact.can_process():
			impact.advance(delta)
		if not impact.is_playing():
			_impacts.remove_at(i)
			continue
		i += 1


# --- registration --------------------------------------------------------------------------------------------------------


func add_plumes(visuals: ThrusterVisuals) -> void:
	if not _plumes.has(visuals):
		_plumes.append(visuals)


func remove_plumes(visuals: ThrusterVisuals) -> void:
	_plumes.erase(visuals)


func has_plumes(visuals: ThrusterVisuals) -> bool:
	return _plumes.has(visuals)


## A flash that started showing: advanced each frame until it is idle again.
func add_flash(flash: MuzzleFlash) -> void:
	if not _flashes.has(flash):
		_flashes.append(flash)


func remove_flash(flash: MuzzleFlash) -> void:
	_flashes.erase(flash)


func has_flash(flash: MuzzleFlash) -> bool:
	return _flashes.has(flash)


## A hit flash that started showing on a ship: advanced each frame until it is over.
func add_impact(impact: ImpactFlash) -> void:
	if not _impacts.has(impact):
		_impacts.append(impact)


func has_impact(impact: ImpactFlash) -> bool:
	return _impacts.has(impact)


## Keeps a finished hit flash, hidden under this node, for a later hit.
func keep_impact(impact: ImpactFlash) -> void:
	if is_instance_valid(impact) and impact.get_parent() == null:
		add_child(impact)
		_impact_pool.append(impact)


## A spare hit flash out of the pool (with no parent), or null when there is none.
func take_impact() -> ImpactFlash:
	while not _impact_pool.is_empty():
		var impact: ImpactFlash = _impact_pool.pop_back()
		if is_instance_valid(impact):
			remove_child(impact)
			return impact
	return null


func impact_pool_size() -> int:
	return _impact_pool.size()


func add_switcher(switcher: LodSwitcher) -> void:
	if not _switchers.has(switcher):
		_switchers.append(switcher)


func remove_switcher(switcher: LodSwitcher) -> void:
	_switchers.erase(switcher)


func has_switcher(switcher: LodSwitcher) -> bool:
	return _switchers.has(switcher)
