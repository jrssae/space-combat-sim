class_name Formation
extends RefCounted
## Where each member of a wing flies relative to its leader (architecture §16 D36, M3-T07): slot offsets in the leader's
## body frame (x right, y up, +z behind, since the nose is -Z), in units of `spacing_m`. Pure.
##
## Slot 0 is the leader, at the origin; the members fly slots 1, 2, 3, ... (ALPHA 2, 3, 4 when the player leads). Every
## shape is level (no height offsets), and no two slots are closer than `spacing_m`: avoidance pushes ships about 35 m
## apart (two Starfury bounding radii plus its 15 m margin), so a slot never asks for less.
## - `finger_four` (the default): #2 (slot 1) left and behind at (-1, 0, 1); #3 right and behind at (1, 0, 1); #4 right of
##   #3 and further back at (2, 0, 2). Further slots carry the echelon on to the right.
## - `wedge`: a V. #2 left, #3 right, #4 left of #2, #5 right of #3, ...: slot k at (-n or +n, 0, n), n = ceil(k / 2).
## - `line_abreast`: the finger-four flattened onto the leader's line (z = 0), so every pilot keeps its side and place
##   when the shape changes.

enum Shape { FINGER_FOUR, WEDGE, LINE_ABREAST }

## Shape names (scenario `formation`, the console's `wing formation`), by `Shape` value.
const NAMES: Array[StringName] = [&"finger_four", &"wedge", &"line_abreast"]
const DEFAULT_SPACING_M: float = 40.0

var shape: Shape = Shape.FINGER_FOUR
var spacing_m: float = DEFAULT_SPACING_M


func _init(p_shape: Shape = Shape.FINGER_FOUR, p_spacing_m: float = DEFAULT_SPACING_M) -> void:
	shape = p_shape
	spacing_m = p_spacing_m


## The `Shape` for a name of `NAMES` (any case), or -1.
static func shape_from_name(shape_name_text: String) -> int:
	return NAMES.find(StringName(shape_name_text.to_lower()))


func shape_name() -> StringName:
	return NAMES[shape]


## Slot `slot`'s offset from the leader, in the leader's body frame, m. Slot 0 (the leader) and below give the origin.
func offset(slot: int) -> Vector3:
	if slot <= 0:
		return Vector3.ZERO
	var unit := Vector3.ZERO
	match shape:
		Shape.WEDGE:
			var rank: float = float(ceili(slot * 0.5))
			unit = Vector3(-rank if slot % 2 == 1 else rank, 0.0, rank)
		_:
			# Finger-four: #2 on the left, then the echelon to the right; line abreast is the same without the depth.
			var step: float = -1.0 if slot == 1 else float(slot - 1)
			unit = Vector3(step, 0.0, absf(step))
			if shape == Shape.LINE_ABREAST:
				unit.z = 0.0
	return unit * spacing_m


## The World point of a body-frame `offset` from a leader at `position` whose nose is `forward` and top is `up` (both unit,
## World frame): `position + B_L * offset`, with B_L's columns right, up and back.
static func slot_point(position: Vector3, forward: Vector3, up: Vector3, body_offset: Vector3) -> Vector3:
	var right: Vector3 = forward.cross(up)
	return position + right * body_offset.x + up * body_offset.y - forward * body_offset.z
