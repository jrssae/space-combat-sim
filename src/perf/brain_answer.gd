class_name BrainAnswer
extends RefCounted
## One tick's answer of the native brains to a rows batch (M4-T33): the drivers and pilots that joined the batch keep it
## and read their own place in it when they next need it, so nothing is unpacked ship by ship at the flush.

## `BrainBatch.STRIDE` numbers per ship, in the order the ships joined (empty when the host gave nothing).
var out := PackedFloat64Array()
## Whether the batch has flushed (before that the place holds nothing yet).
var ready: bool = false


## Whether the ship at `index` thought (false while not flushed, or when the host declined it).
func thought(index: int) -> bool:
	var base: int = index * BrainBatch.STRIDE
	return ready and out.size() >= base + BrainBatch.STRIDE and out[base] != 0.0
