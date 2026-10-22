class_name MuzzleFlash
extends MeshInstance3D
## A billboard quad that pops at a cannon muzzle for 50 ms when a shot leaves (architecture §7.1). `PulseCannon` adds
## one under each muzzle marker, so it rides with the ship; `trigger()` shows it, and it grows from a small spot to
## full size while fading out, then hides itself.
##
## A visual, so it animates in `_process` from the frame `delta` (and `advance` for tests); how it looks is (H).

const MATERIAL: Material = preload("res://assets/materials/muzzle_flash.tres")
const DURATION_S: float = 0.05
## Edge length of the quad at full size, m.
const SIZE_M: float = 1.2
## Size at the start of the flash, as a fraction of full size.
const START_SCALE: float = 0.3

var _age_s: float = INF


## A hidden flash with its quad mesh, ready to be added under a muzzle.
static func create() -> MuzzleFlash:
	var flash := MuzzleFlash.new()
	flash.name = &"MuzzleFlash"
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = MATERIAL
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.visible = false
	return flash


func _process(delta: float) -> void:
	advance(delta)


## Starts (or restarts) the 50 ms flash.
func trigger() -> void:
	_age_s = 0.0
	_apply()


## True while the flash is showing.
func is_active() -> bool:
	return _age_s < DURATION_S


## Ages the flash by `delta` seconds; hides it once `DURATION_S` has passed.
func advance(delta: float) -> void:
	if _age_s == INF:
		return  # idle: nothing to animate
	_age_s += delta
	_apply()


func _apply() -> void:
	if not is_active():
		visible = false
		_age_s = INF
		return
	var t: float = _age_s / DURATION_S
	visible = true
	scale = Vector3.ONE * (SIZE_M * lerpf(START_SCALE, 1.0, t))
	transparency = t
