class_name NativeProbe
extends RefCounted
## Facade over the native `ScsNativeProbe` (M4-T05a): the same answers from native code when the library is loaded
## (required since M4-T37), from GDScript when a test asks for the reference. It proves the seam and is the pattern later native ports follow.

const NATIVE_CLASS: StringName = &"ScsNativeProbe"

var _use_native: bool
var _native: Object = null


## `use_native` false forces the GDScript path, so a test or the boundary bench can pair the two.
func _init(use_native: bool = true) -> void:
	_use_native = use_native


## Which code answers: &"native" or &"gdscript".
func path() -> StringName:
	return &"native" if _active() != null else &"gdscript"


## Returns its argument: the cheapest possible call, for the boundary's per-call cost.
func echo(value: int) -> int:
	var native: Object = _active()
	if native != null:
		return int(native.call(&"echo", value))
	return value


## Indices of `positions` within `range_m` of `origin`, in order (the shape of the contact queries).
func in_range(positions: PackedVector3Array, origin: Vector3, range_m: float) -> PackedInt32Array:
	var native: Object = _active()
	if native != null:
		return native.call(&"in_range", positions, origin, range_m)
	var out := PackedInt32Array()
	var range_sq: float = range_m * range_m
	for i: int in positions.size():
		if positions[i].distance_squared_to(origin) <= range_sq:
			out.append(i)
	return out


# The native object when this call should use it (made on first use), or null for the GDScript path.
func _active() -> Object:
	if not _use_native:
		return null
	if _native == null:
		_native = NativeLib.instantiate(NATIVE_CLASS)
	return _native
