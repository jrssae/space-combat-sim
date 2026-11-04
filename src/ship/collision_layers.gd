class_name CollisionLayers
extends RefCounted
## Which Jolt bodies can touch which (M4-T14, architecture §17.12). Every kind keeps the pairs it can hit; what the layers rule out
## is a rock against a rock, which never moves. Fighters collide with fighters (Q33), so Jolt's contact response stays Newtonian.
##
## Two bodies collide when either one's mask holds the other's layer, as Godot's physics does.

const PLAYER: int = 1  # the layer every body had before: the player's ship, props and test fixtures
const FIGHTER: int = 2  # AI fighters
const CAPITAL: int = 4
const ROCK: int = 8
const ALL: int = 0xFFFFF

const _LAYERS: Dictionary = {&"player": PLAYER, &"fighter": FIGHTER, &"capital": CAPITAL, &"rock": ROCK}
const _MASKS: Dictionary = {
	&"player": ALL,
	&"fighter": PLAYER | FIGHTER | CAPITAL | ROCK,
	&"capital": PLAYER | FIGHTER | CAPITAL | ROCK,
	&"rock": PLAYER | FIGHTER | CAPITAL,
}


## The layer bit of a kind of body (`player`, `fighter`, `capital`, `rock`); the default layer for any other.
static func layer_of(kind: StringName) -> int:
	return _LAYERS.get(kind, PLAYER)


## The layers a kind of body collides with.
static func mask_of(kind: StringName) -> int:
	return _MASKS.get(kind, PLAYER)


## Whether two bodies with these layers and masks can touch.
static func collide(a_layer: int, a_mask: int, b_layer: int, b_mask: int) -> bool:
	return (a_mask & b_layer) != 0 or (b_mask & a_layer) != 0
