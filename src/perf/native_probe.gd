class_name NativeProbe
extends RefCounted
## Facade over the native `ScsNativeProbe` (M4-T05a): the same answers from native code when the library is loaded
## and `perf_native` is on, from GDScript otherwise. It proves the seam and is the pattern later native ports follow.

const NATIVE_CLASS: StringName = &"ScsNativeProbe"

var _native: Object


## `use_native` false forces the GDScript path, so a test or the boundary bench can pair the two.
func _init(use_native: bool = true) -> void:
	_native = NativeLib.instantiate(NATIVE_CLASS) if use_native else null


## Which code answers: &"native" or &"gdscript".
func path() -> StringName:
	return &"native" if _native != null else &"gdscript"


## Returns its argument: the cheapest possible call, for the boundary's per-call cost.
func echo(value: int) -> int:
	if _native != null:
		return int(_native.call(&"echo", value))
	return value


## Indices of `positions` within `range_m` of `origin`, in order (the shape of the contact queries).
func in_range(positions: PackedVector3Array, origin: Vector3, range_m: float) -> PackedInt32Array:
	if _native != null:
		return _native.call(&"in_range", positions, origin, range_m)
	var out := PackedInt32Array()
	var range_sq: float = range_m * range_m
	for i: int in positions.size():
		if positions[i].distance_squared_to(origin) <= range_sq:
			out.append(i)
	return out
