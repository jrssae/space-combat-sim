class_name StarColor
extends RefCounted
## A star's colour from its temperature (Q30). Pure.

## The fit's range (Kim et al. 2002, the Planckian locus): colder or hotter stars hold the nearest end.
const MIN_K: float = 1667.0
const MAX_K: float = 25000.0


## Linear sRGB with the largest channel at 1, agreeing with the sky generator's `blackbody_rgb` to about 0.03.
static func linear_from_kelvin(temperature_k: float) -> Color:
	var t: float = clampf(temperature_k, MIN_K, MAX_K)
	var a: float = 1.0e3 / t
	var x: float
	if t < 4000.0:
		x = -0.2661239 * a * a * a - 0.2343589 * a * a + 0.8776956 * a + 0.179910
	else:
		x = -3.0258469 * a * a * a + 2.1070379 * a * a + 0.2226347 * a + 0.240390
	var y: float
	if t < 2222.0:
		y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
	elif t < 4000.0:
		y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
	else:
		y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
	var big_x: float = x / y
	var big_z: float = (1.0 - x - y) / y
	var r: float = maxf(3.2406 * big_x - 1.5372 - 0.4986 * big_z, 0.0)
	var g: float = maxf(-0.9689 * big_x + 1.8758 + 0.0415 * big_z, 0.0)
	var b: float = maxf(0.0557 * big_x - 0.2040 + 1.0570 * big_z, 0.0)
	var top: float = maxf(r, maxf(g, b))
	return Color(r / top, g / top, b / top)
