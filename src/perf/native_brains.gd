class_name NativeBrains
extends RefCounted
## The native brain host's facade (M4-T17, architecture §17.13): one `ScsBrains` per core, holding every `AiPilot`'s native
## brain as a slot over the core's rows. `host` gives it to the drivers, or null when `perf_native`, `perf_native_core` or
## `perf_native_brains` is off, no core is attached to the tree or the library lacks the class; the pilots then think in
## GDScript, which stays the reference. The nearest-k settings every native think picks with are pushed here as the
## drivers read them.

const NATIVE_CLASS: StringName = &"ScsBrains"

static var _host: Object = null
static var _core: Object = null
static var _class_known: int = -1
static var _enabled: int = -1
static var _nearest_k: int = 12
static var _static_k: int = 4


## The host over `tree`'s core, made on first ask and remade when the core changes; null when native brains are off.
static func host(tree: SceneTree) -> Object:
	if not enabled():
		return null
	var sim: SimCore = SimCore.for_tree(tree)
	if sim == null or sim.core == null:
		return null
	if _class_known < 0:
		_class_known = 1 if NativeLib.has_class(NATIVE_CLASS) else 0
	if _class_known == 0:
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


## Whether `perf_native_brains` asks for the native brains (with `perf_native`); follows the setting at once.
static func enabled() -> bool:
	if _enabled < 0:
		_enabled = 1 if bool(Settings.get_value(&"perf_native_brains")) else 0
		if not Settings.changed.is_connected(_on_setting_changed):
			Settings.changed.connect(_on_setting_changed)
	return _enabled == 1 and NativeLib.enabled()


## The nearest-k settings (`ai_nearest_k`, `ai_nearest_static_k`) every native think picks its lists with.
static func set_settings(nearest_k: int, static_k: int) -> void:
	_nearest_k = nearest_k
	_static_k = static_k
	if _host != null:
		_host.set_settings(nearest_k, static_k)


## Forgets the host (tests that swap cores).
static func drop() -> void:
	_host = null
	_core = null


static func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"perf_native_brains":
		_enabled = -1
