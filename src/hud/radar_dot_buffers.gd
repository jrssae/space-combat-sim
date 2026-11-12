class_name RadarDotBuffers
extends RefCounted
## The radar's dots ready for the painter's multimeshes (M5-T34): `RadarModel.dot_buffers`' output for one surface. Each buffer
## is sized for the multimesh that takes it whole (`instances()`), and empty when there is nothing to draw.

## Floats per instance in a 2D multimesh with colours: a 2x3 transform padded to 8, then the colour.
const STRIDE: int = 12

## The plain dots (not on the rim, not selected).
var plain := PackedFloat32Array()
var plain_count: int = 0
## The hollow rim dots (not selected).
var rim := PackedFloat32Array()
var rim_count: int = 0
## A dark backing under every contact; empty on a surface that draws none.
var backing := PackedFloat32Array()
var backing_count: int = 0


## How many instances `buffer` holds.
static func instances(buffer: PackedFloat32Array) -> int:
	return buffer.size() / STRIDE
