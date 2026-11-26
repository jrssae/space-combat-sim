class_name ExplosionView
extends RefCounted
## Test fixture (M10-T11): one live explosion of an `ExplosionPool`, as the tests read it. The pool draws explosions from slots
## with no node each, so tests that once looked for `Explosion` nodes under `World/Effects` read these instead.

var pool: ExplosionPool = null
var slot: int = -1
var radius_m: float = 0.0
var reduced: bool = false
var tag: int = 0


## The live explosions under `effects`, oldest first (so the last is the newest).
static func live(effects: Node) -> Array[ExplosionView]:
	var out: Array[ExplosionView] = []
	var pool: ExplosionPool = ExplosionPool.of(effects)
	if pool == null:
		return out
	for s: int in pool.live_slots():
		var view := ExplosionView.new()
		view.pool = pool
		view.slot = s
		view.radius_m = pool.radius_of(s)
		view.reduced = pool.is_reduced(s)
		view.tag = pool.tag_of(s)
		out.append(view)
	return out


## Where it is now, World-local.
func position() -> Vector3:
	return pool.position_of(slot)


func velocity() -> Vector3:
	return pool.velocity_of(slot)


func lit() -> bool:
	return pool.is_lit(slot)


func age_s() -> float:
	return pool.age_of(slot)


func emitter() -> LightEmitter:
	return pool.emitter_of(slot)


func alive() -> bool:
	return pool.is_alive(slot)
