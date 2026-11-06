class_name ImpactFlash
extends MeshInstance3D
## A bolt hit (architecture §15.5): a short additive flash, a child of the ship that was hit so it rides with it, tinted with the
## bolt's colour. The sparks are the `FxPool`'s hit burst, thrown by the hit resolver beside it (M3-T23).
##
## Add it as a child of the hit ship with `position` set in the ship's body frame. Timing is visual (the frame's delta, in the
## `FramePasses` hit flashes pass), so a paused game freezes it.
##
## One node per hit, from a pool (M4-T36, §17.21): it used to be the flash and 6 to 10 mesh sparks, about ten nodes built and
## freed per hit beside the particle sparks. When it is over it leaves the ship for the pool, kept under the tree's
## `FramePasses`, and `create` hands it out again; with no pool (a scene without the passes yet) it frees itself. Flashes of one
## colour share their quad and material (M4-T08); the fade is per flash (`transparency` on the instance).

const FLASH_S: float = 0.08
const FLASH_SIZE_M: float = 1.6
const GLOW_MATERIAL: StandardMaterial3D = preload("res://assets/materials/thruster_glow.tres")

## Colours whose resources are kept; past this a flash makes its own (bolt colours come from a few weapon specs).
const MAX_SHARED_COLOURS: int = 64
## Spare flashes the pool keeps; past this a finished one is freed.
const POOL_MAX: int = 256

# Colour -> the flash quad with its glow material.
static var _shared: Dictionary = {}
## Flashes built in this process (tests and profiling, never gameplay).
static var built_count: int = 0

var _age_s: float = 0.0


## A flash for a hit tinted `color`, from the pool when it has one. `seed_value` is kept for the callers' signature (the sparks it
## seeded are the particle burst's now).
static func create(color: Color, _seed_value: int = 0) -> ImpactFlash:
	var flash: ImpactFlash = _from_pool()
	if flash == null:
		flash = ImpactFlash.new()
		flash.name = "ImpactFlash"
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		built_count += 1
	flash.mesh = _quad_for(color)
	flash._age_s = 0.0
	flash.visible = true
	flash.scale = Vector3.ONE * (FLASH_SIZE_M * 0.6)
	flash.transparency = 0.0
	return flash


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and is_playing() and not _in_pool():
		var passes: FramePasses = FramePasses.of(self)
		if passes != null:
			passes.add_impact(self)


## Moves the effect `delta` seconds on; when it is over it goes back to the pool (or is freed). Public for tests.
func advance(delta: float) -> void:
	_age_s += delta
	if not is_playing():
		_finish()
		return
	var life: float = _age_s / FLASH_S
	scale = Vector3.ONE * (FLASH_SIZE_M * lerpf(0.6, 1.0, life))
	transparency = life


## Seconds since it appeared.
func age_s() -> float:
	return _age_s


## True until the flash is over.
func is_playing() -> bool:
	return _age_s < FLASH_S


func is_flash_visible() -> bool:
	return visible and is_playing()


# Off the ship and into the pool, hidden; freed when there is no pool or it is full.
func _finish() -> void:
	visible = false
	var passes: FramePasses = FramePasses.of(self) if is_inside_tree() else null
	if passes == null or passes.impact_pool_size() >= POOL_MAX:
		queue_free()
		return
	get_parent().remove_child(self)
	passes.keep_impact(self)


func _in_pool() -> bool:
	return get_parent() is FramePasses


static func _from_pool() -> ImpactFlash:
	var passes: FramePasses = FramePasses.current()
	return passes.take_impact() if passes != null else null


# The flash quad for `color`, made once per colour.
static func _quad_for(color: Color) -> QuadMesh:
	var kept: Variant = _shared.get(color)
	if kept != null:
		return kept as QuadMesh
	var glow := GLOW_MATERIAL.duplicate() as StandardMaterial3D
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_color = color
	glow.emission = color
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = glow
	if _shared.size() < MAX_SHARED_COLOURS:
		_shared[color] = quad
	return quad
