class_name ImpactFlash
extends Node3D
## A bolt hit (architecture §15.5): a short additive flash and a handful of spark streaks, a child of the ship that was
## hit so it rides with it. Meshes, never splats (D22), tinted with the bolt's colour. It frees itself.
##
## Add it as a child of the hit ship with `position` set in the ship's body frame. Timing is visual (`_process` delta), so
## a paused game freezes it.

const FLASH_S: float = 0.08
const SPARK_S: float = 0.18
const MIN_SPARKS: int = 6
const MAX_SPARKS: int = 10
const FLASH_SIZE_M: float = 1.6
const SPARK_SPEED_MPS: Vector2 = Vector2(8.0, 22.0)
const SPARK_LENGTH_M: float = 0.7
const GLOW_MATERIAL: StandardMaterial3D = preload("res://assets/materials/thruster_glow.tres")

static var _spark_mesh: BoxMesh = null

var _age_s: float = 0.0
var _flash: MeshInstance3D = null
var _sparks: Array[MeshInstance3D] = []
var _spark_velocities: Array[Vector3] = []


## A flash for a hit tinted `color`. `seed_value` fixes the spark directions (same hit, same sparks).
static func create(color: Color, seed_value: int = 0) -> ImpactFlash:
	var flash := ImpactFlash.new()
	flash.name = "ImpactFlash"
	flash._build(color, seed_value)
	return flash


func _process(delta: float) -> void:
	advance(delta)


## Moves the effect `delta` seconds on; frees it when over. Public for tests.
func advance(delta: float) -> void:
	_age_s += delta
	if _age_s >= SPARK_S:
		queue_free()
		return
	_flash.visible = _age_s < FLASH_S
	if _flash.visible:
		var life: float = _age_s / FLASH_S
		_flash.scale = Vector3.ONE * (FLASH_SIZE_M * lerpf(0.6, 1.0, life))
		_flash.transparency = life
	var fade: float = 1.0 - _age_s / SPARK_S
	for i: int in _sparks.size():
		_sparks[i].position += _spark_velocities[i] * delta
		_sparks[i].scale = Vector3(1.0, 1.0, maxf(fade, 0.01))


## Seconds since it appeared.
func age_s() -> float:
	return _age_s


func spark_count() -> int:
	return _sparks.size()


func is_flash_visible() -> bool:
	return _flash != null and _flash.visible


func _build(color: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var glow := GLOW_MATERIAL.duplicate() as StandardMaterial3D
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_color = color
	glow.emission = color
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = glow
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.mesh = quad
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)

	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_material.albedo_color = color
	for i: int in rng.randi_range(MIN_SPARKS, MAX_SPARKS):
		var direction := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		if direction.is_zero_approx():
			direction = Vector3.UP
		var spark := MeshInstance3D.new()
		spark.name = "Spark%d" % i
		spark.mesh = _shared_spark_mesh()
		spark.material_override = spark_material
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		spark.basis = Basis.looking_at(direction, up)  # the box's long side is its -Z
		add_child(spark)
		_sparks.append(spark)
		_spark_velocities.append(direction * rng.randf_range(SPARK_SPEED_MPS.x, SPARK_SPEED_MPS.y))


static func _shared_spark_mesh() -> BoxMesh:
	if _spark_mesh == null:
		_spark_mesh = BoxMesh.new()
		_spark_mesh.size = Vector3(0.025, 0.025, SPARK_LENGTH_M)
	return _spark_mesh
