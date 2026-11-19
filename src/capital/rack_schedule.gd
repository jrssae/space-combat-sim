class_name RackSchedule
extends RefCounted
## When a capital's missile racks may fire (M8-T09): each rack holds a few cells and reloads after a shot, and the ship fires
## no two missiles closer together than its gap. Pure: times in, a decision out; `MissileRacks` launches the missiles.

## A class's numbers (`data/capitals/capitals.json`, `missile_racks`), with their defaults.
const DEFAULTS: Dictionary = {
	"cells": 6,  # missiles a rack holds; an empty rack fires no more until it is restocked
	"reload_s": 20.0,  # a rack fires again this long after its shot
	"gap_s": 2.0,  # the ship's racks fire at least this far apart
	"retry_s": 0.5,  # with nothing to fire at, it looks again after this long
	"range_m": 3000.0,  # it fires at hostile fighters within this of the ship
}

var cells: int = 6
var reload_s: float = 20.0
var gap_s: float = 2.0
var retry_s: float = 0.5
var range_m: float = 3000.0

## Per rack: the missiles left in it and when it may fire again, s of sim time.
var left: PackedInt32Array = PackedInt32Array()
var ready_at_s: PackedFloat64Array = PackedFloat64Array()

var _next_s: float = -INF


## A schedule for `racks` racks with `tuning` over the defaults, every rack full and ready.
static func create(racks: int, tuning: Dictionary = {}) -> RackSchedule:
	var out := RackSchedule.new()
	var numbers: Dictionary = DEFAULTS.duplicate()
	numbers.merge(tuning, true)
	out.cells = maxi(int(numbers["cells"]), 0)
	out.reload_s = maxf(float(numbers["reload_s"]), 0.0)
	out.gap_s = maxf(float(numbers["gap_s"]), 0.0)
	out.retry_s = maxf(float(numbers["retry_s"]), 0.05)
	out.range_m = maxf(float(numbers["range_m"]), 0.0)
	out.left.resize(maxi(racks, 0))
	out.ready_at_s.resize(maxi(racks, 0))
	out.restock()
	return out


## Every rack full and ready again (the ship came back from its base).
func restock() -> void:
	left.fill(cells)
	ready_at_s.fill(-INF)
	_next_s = -INF


## Whether the ship should look for a target now: its gap has passed and a rack could fire.
func due(now_s: float) -> bool:
	return now_s >= _next_s and not ready(now_s).is_empty()


## The racks that could fire now.
func ready(now_s: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in left.size():
		if left[i] > 0 and now_s >= ready_at_s[i]:
			out.append(i)
	return out


## Rack `index` fired at `now_s`.
func fired(index: int, now_s: float) -> void:
	if index < 0 or index >= left.size():
		return
	left[index] = maxi(left[index] - 1, 0)
	ready_at_s[index] = now_s + reload_s
	_next_s = now_s + gap_s


## Nothing to fire at: it looks again after `retry_s`.
func missed(now_s: float) -> void:
	_next_s = now_s + retry_s


## Missiles left in all the racks.
func missiles_left() -> int:
	var n: int = 0
	for count: int in left:
		n += count
	return n


## Of the racks in `candidates`, the one whose way out (`forwards`, unit) points most nearly along `to_target`; -1 for none.
static func best_facing(candidates: PackedInt32Array, forwards: PackedVector3Array, to_target: Vector3) -> int:
	var best: int = -1
	var best_dot: float = -INF
	var way: Vector3 = to_target.normalized()
	for index: int in candidates:
		var facing: float = forwards[index].dot(way)
		if facing > best_dot:
			best = index
			best_dot = facing
	return best
