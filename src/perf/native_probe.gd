class_name NativeProbe
extends RefCounted
## Facade over the native `ScsNativeProbe` (M4-T05a): proves the library (required since M4-T37) loads and answers, and
## is what `NativeBoundaryBench` times a call into the library with.

const NATIVE_CLASS: StringName = &"ScsNativeProbe"

var _native: Object = NativeLib.instantiate(NATIVE_CLASS)


## Which code answers: &"native", or &"none" when the library is missing (the game then refuses to start).
func path() -> StringName:
	return &"native" if _native != null else &"none"


## Returns its argument: the cheapest possible call, for the boundary's per-call cost.
func echo(value: int) -> int:
	return int(_native.call(&"echo", value))


## Indices of `positions` within `range_m` of `origin`, in order (the shape of the contact queries).
func in_range(positions: PackedVector3Array, origin: Vector3, range_m: float) -> PackedInt32Array:
	return _native.call(&"in_range", positions, origin, range_m)
