class_name MuzzleFlash
extends MeshInstance3D
## A billboard quad that pops at a cannon muzzle for 50 ms when a shot leaves (architecture §7.1). `PulseCannon` adds
## one under each muzzle marker, so it rides with the ship; `trigger()` shows it, and it grows from a small spot to
## full size while fading out, then hides itself.
##
## A shot also lights the nose (M3-T22): the flash owns one `LightEmitter`, made once with the node and reused for every shot, so a
## shot allocates nothing. It enters the `LightRig`'s candidates for `EmitterCurves.FLASH_S` (60 ms) and leaves them when
## the flash ends, the ship is parked or the node leaves the tree.
##
## A visual, so it animates from the frame `delta`: only while it shows, in the `FramePasses` flashes pass (M4-T36; `advance` for
## tests), so the 2 to 4 idle flashes on every ship cost the frame nothing. How it looks is (H).

const MATERIAL: Material = preload("res://assets/materials/muzzle_flash.tres")
const DURATION_S: float = 0.05
## Edge length of the quad at full size, m.
const SIZE_M: float = 1.2
## Size at the start of the flash, as a fraction of full size.
const START_SCALE: float = 0.3

var _age_s: float = INF
var _light: LightEmitter = null
var _rig: LightRig = null


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


func _init() -> void:
	_light = LightEmitter.new("muzzle flash", LightEmitter.PRIORITY_MUZZLE_FLASH, Color(1.0, 0.85, 0.6), 0.0,
			EmitterCurves.FLASH_RANGE_M)
	_light.offset = Vector3(0.0, 0.0, -EmitterCurves.FLASH_OFFSET_M)  # the muzzle's -Z is down the barrel


func _notification(what: int) -> void:
	# A parked ship stops processing mid-flash and would leave its light shining.
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_DISABLED:
		_end_light()


## Starts (or restarts) the 50 ms flash.
func trigger() -> void:
	_age_s = 0.0
	_apply()
	_start_light()
	var passes: FramePasses = FramePasses.of(self)
	if passes != null:
		passes.add_flash(self)


## Ends the flash at once: a ship back in play shows nothing of its last shot.
func reset() -> void:
	_age_s = INF
	visible = false
	_end_light()


## The flash's light record (always the same one), for the lights provider and tests.
func light_emitter() -> LightEmitter:
	return _light


## True while the flash is showing.
func is_active() -> bool:
	return _age_s < DURATION_S


## True when neither the flash nor its light is left to animate: the flashes pass lets it go.
func is_idle() -> bool:
	return _age_s == INF


## Ages the flash by `delta` seconds; the quad hides after `DURATION_S` and the light after `EmitterCurves.FLASH_S`.
func advance(delta: float) -> void:
	if _age_s == INF:
		return  # idle: nothing to animate
	_age_s += delta
	_apply()
	_apply_light()


func _apply() -> void:
	if not is_active():
		visible = false
		return
	var t: float = _age_s / DURATION_S
	visible = true
	scale = Vector3.ONE * (SIZE_M * lerpf(START_SCALE, 1.0, t))
	transparency = t


# The light outlasts the quad by 10 ms; when it is over the flash is idle again.
func _apply_light() -> void:
	if _age_s >= EmitterCurves.FLASH_S:
		_age_s = INF
		_end_light()
		return
	_light.energy = EmitterCurves.flash_energy(_age_s)


# Puts the flash's light on the muzzle marker this node sits under and enters it in the rig's competition.
func _start_light() -> void:
	var muzzle := get_parent() as Node3D
	if muzzle == null:
		return
	if _rig == null or not is_instance_valid(_rig):
		_rig = LightRig.of(self)
	if _rig == null:
		return
	_light.anchor = muzzle
	_light.energy = EmitterCurves.flash_energy(0.0)
	_rig.add_emitter(_light)


func _end_light() -> void:
	_light.energy = 0.0
	if _rig != null and is_instance_valid(_rig):
		_rig.remove_emitter(_light)
