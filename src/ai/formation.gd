class_name Formation
extends RefCounted
## Where each member of a wing flies relative to its leader (architecture §16 D36, M3-T07): slot offsets in the leader's
## body frame (x right, y up, +z behind, since the nose is -Z), in units of `spacing_m`. Pure.
##
## Slot 0 is the leader, at the origin; the members fly slots 1, 2, 3, ... (ALPHA 2, 3, 4 when the player leads). Every
## shape is level (no height offsets), and no two slots are closer than `spacing_m`: avoidance pushes ships about 35 m
## apart (two Starfury bounding radii plus its 15 m margin), so a slot never asks for less.
## - `finger_four` (the default): #2 (slot 1) left and behind at (-1, 0, 1); #3 right and behind at (1, 0, 1); #4 right of
##   #3 and further back at (2, 0, 2). A bigger wing (Alpha grown to eleven, M7-T58) carries on as a V whose arms stay even
##   (M7-T74): each further pair one step back and out, the pairs starting on alternate arms (#5 and #6 left, #7 and #8 right,
##   #9 and #10 left, #11 right), so filled in order the arms never differ by more than one ship.
## - `wedge`: a V. #2 left, #3 right, #4 left of #2, #5 right of #3, ...: slot k at (-n or +n, 0, n), n = ceil(k / 2).
## - `line_abreast`: the finger-four flattened onto the leader's line (z = 0), so every pilot keeps its side and place
##   when the shape changes.
## A wing of more than `FINGER_FOUR_SLOTS` with an odd count of slots puts its last on the centreline (`centre_slot`), between the
## second pair in the V shapes (closing the front triangle) and one step behind the leader abreast, so the arms stay even.
## Only the centre slot depends on the wing's size: resizing a wing moves no ship on an arm.

enum Shape { FINGER_FOUR, WEDGE, LINE_ABREAST }

## Shape names (scenario `formation`, the console's `wing formation`), by `Shape` value.
const NAMES: Array[StringName] = [&"finger_four", &"wedge", &"line_abreast"]
const DEFAULT_SPACING_M: float = 40.0
## Member slots of a finger-four; a wing with more gets a centre slot when the count is odd.
const FINGER_FOUR_SLOTS: int = 3
## How far behind the leader the centre slot sits in the V shapes, in spacings: between the second pair.
const CENTRE_RANK: float = 2.0

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


## Slot `slot`'s offset from the leader of a wing of `size` member slots, in the leader's body frame, m. Slot 0 (the leader)
## and below give the origin.
func offset(slot: int, size: int = FINGER_FOUR_SLOTS) -> Vector3:
	if slot <= 0:
		return Vector3.ZERO
	var unit := Vector3.ZERO
	if slot == centre_slot(size):
		unit = Vector3(0.0, 0.0, 1.0 if shape == Shape.LINE_ABREAST else CENTRE_RANK)
	else:
		var rank: int = ceili(slot * 0.5)
		var first_of_pair: bool = slot % 2 == 1
		var left: bool = first_of_pair if shape == Shape.WEDGE else first_of_pair == (rank % 2 == 1)
		unit = Vector3(-rank if left else rank, 0.0, 0.0 if shape == Shape.LINE_ABREAST else rank)
	return unit * spacing_m


## The centreline slot of a wing of `size` member slots (its last, when it takes the odd one out of a V), or 0 for none.
static func centre_slot(size: int) -> int:
	return size if size > FINGER_FOUR_SLOTS and size % 2 == 1 else 0


## Which side of the leader slot `slot` flies in a wing of `size`: -1 left, 1 right, 0 on the centreline.
func side(slot: int, size: int = FINGER_FOUR_SLOTS) -> int:
	return int(signf(offset(slot, size).x))


## The World point of a body-frame `offset` from a leader at `position` whose nose is `forward` and top is `up` (both unit,
## World frame): `position + B_L * offset`, with B_L's columns right, up and back.
static func slot_point(position: Vector3, forward: Vector3, up: Vector3, body_offset: Vector3) -> Vector3:
	var right: Vector3 = forward.cross(up)
	return position + right * body_offset.x + up * body_offset.y - forward * body_offset.z
