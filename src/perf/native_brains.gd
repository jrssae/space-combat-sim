class_name NativeBrains
extends RefCounted
## The native brain host's facade (M4-T17, architecture §17.13): one `ScsBrains` per core, holding every `AiPilot`'s native
## brain as a slot over the core's rows. `host` gives it to the drivers, or null when no core is attached to the tree (a
## native pilot then holds its last command). Only a brain the host cannot carry (not built from the default behaviours)
## thinks in GDScript. The nearest-k settings every native think picks with are pushed here as the drivers read them.

const NATIVE_CLASS: StringName = &"ScsBrains"

static var _host: Object = null
static var _core: Object = null
static var _nearest_k: int = 12
static var _static_k: int = 4


## The host over `tree`'s core, made on first ask and remade when the core changes; null without a core.
static func host(tree: SceneTree) -> Object:
	var sim: SimCore = SimCore.for_tree(tree)
	if sim == null or sim.core == null:
		return null
	if _host == null or _core != sim.core:
		var made: Object = NativeLib.instantiate(NATIVE_CLASS)
		if made == null:
			return null
		made.attach_core(sim.core)
		made.set_settings(_nearest_k, _static_k)
		_host = made
		_core = sim.core
	return _host


## The nearest-k settings (`ai_nearest_k`, `ai_nearest_static_k`) every native think picks its lists with.
static func set_settings(nearest_k: int, static_k: int) -> void:
	_nearest_k = nearest_k
	_static_k = static_k
	if _host != null:
		_host.set_settings(nearest_k, static_k)


## Forgets the host when `core` is the one it is over, so a world that leaves takes its core and step threads with it.
static func drop_for(core: Object) -> void:
	if core != null and _core == core:
		_host = null
		_core = null
