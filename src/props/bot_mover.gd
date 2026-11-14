class_name BotMover
extends RefCounted
## What a maintenance bot's node reads from whatever moves it (M7-T11): where it is, which way it faces, whether it is drawn.
## `BotMotion` flies a loop round the hull and `BotFerryMotion` shuttles between the cargo bay and a freighter; both are pure.

var position: Vector3 = Vector3.ZERO
var heading: Vector3 = Vector3.FORWARD
## Which way is away from the hull the bot works on, for its roll.
var up: Vector3 = Vector3.UP
var speed_mps: float = 0.0


## Moves it `delta` seconds on. `alarm` is true while fighting is near it.
func step(_delta: float, _alarm: bool) -> void:
	pass


## Whether the bot is drawn: only hidden when it is inside the hull.
func is_visible() -> bool:
	return true


## What the bot is doing, as a word, for the console.
func phase_name() -> String:
	return ""


## The orientation the bot wants: nose along the heading, its top away from the hull.
func target_basis() -> Basis:
	var top: Vector3 = up - heading * up.dot(heading)
	if top.length_squared() < 0.01:
		top = heading.cross(Vector3.RIGHT)
		if top.length_squared() < 0.01:
			top = heading.cross(Vector3.UP)
	return Basis.looking_at(heading, top.normalized())
