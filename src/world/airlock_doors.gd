class_name AirlockDoors
extends RefCounted
## The main docking bay's inner doors (M7-T25): how far open they stand, moving open while any ship asks and shut once none does.
## Pure; `StationAirlock` steps it each tick and slides the leaves, the traffic asks and lets go for its ships.

enum Mode { AUTO, OPEN, SHUT }

## Seconds to open fully, and to shut.
var open_s: float = 3.0
var close_s: float = 3.0
## 0 shut, 1 open.
var fraction: float = 0.0
## AUTO follows the asks; the console can hold the doors open or shut.
var mode: Mode = Mode.AUTO
var _asks: Dictionary = {}


## Ship (or anything) `key` wants the doors open.
func ask(key: Variant) -> void:
	_asks[key] = true


## `key` no longer needs them.
func release(key: Variant) -> void:
	_asks.erase(key)


## Whether `key` is asking.
func has_ask(key: Variant) -> bool:
	return _asks.has(key)


func asking() -> int:
	return _asks.size()


func wants_open() -> bool:
	match mode:
		Mode.OPEN:
			return true
		Mode.SHUT:
			return false
	return not _asks.is_empty()


## Moves the doors `delta` seconds toward where they are wanted.
func step(delta: float) -> void:
	if wants_open():
		fraction = minf(1.0, fraction + (delta / open_s if open_s > 0.0 else 1.0))
	else:
		fraction = maxf(0.0, fraction - (delta / close_s if close_s > 0.0 else 1.0))


func is_open() -> bool:
	return fraction >= 1.0


func is_shut() -> bool:
	return fraction <= 0.0


func state_name() -> String:
	if is_open():
		return "open"
	if is_shut():
		return "shut"
	return "opening" if wants_open() else "closing"
