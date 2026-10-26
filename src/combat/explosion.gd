class_name Explosion
extends Node3D
## The explosion of a destroyed ship (architecture §15.7), made entirely in code (no textures, no splats): a light
## flash, an additive billboard flash, a noisy fireball sphere, one-shot sparks and embers. Transparent meshes and
## particles draw after the splats and are hidden behind hulls in front of them by the hull depth proxy.
##
## - `OmniLight3D`: energy 0 -> 8 -> 0 over 0.25 s, range 4 x radius (it lights meshes only; splats are unlit).
## - billboard flash: an additive quad, 0.15 s.
## - fireball: a sphere growing to 1.2 x radius over 0.8 s, `explosion_fireball.gdshader`, gone by 1.5 s.
## - sparks: 80 streaks, 40-150 m/s, 0.6-1.2 s; embers: 20, 5-20 m/s, 2-3 s (`GPUParticles3D`, one shot).
##
## It drifts with `velocity` (it was the ship's), joins `world_shiftable` so a rebase moves it, and frees itself after
## 3 s. Animation is `_process` (visuals), so a paused game freezes it; `advance` is public for tests.
##
## The sparks and embers stay where the ship blew up while the ball drifts on (M2). Their nodes are `top_level` (they do not
## follow the drifting node), placed where it appears, in `world_shiftable` themselves, and keep their particles in their own
## frame (`local_coords`), so a rebase moves the particles too (M3-T14): particles in global space would be left behind.

const LIFETIME_S: float = 3.0
const LIGHT_S: float = 0.25
const LIGHT_PEAK_ENERGY: float = 8.0
const FLASH_S: float = 0.15
const FIREBALL_S: float = 1.5
const FIREBALL_GROW_S: float = 0.8
const FIREBALL_FINAL_SCALE: float = 1.2
const SPARK_COUNT: int = 80
const EMBER_COUNT: int = 20
const FIREBALL_SHADER: Shader = preload("res://src/combat/explosion_fireball.gdshader")
const GLOW_MATERIAL: StandardMaterial3D = preload("res://assets/materials/thruster_glow.tres")

## Radius of the dead ship (its bounding radius): everything scales with it.
var radius_m: float = 4.0
## World-frame drift velocity, m/s.
var velocity: Vector3 = Vector3.ZERO

var light: OmniLight3D = null
var flash: MeshInstance3D = null
var fireball: MeshInstance3D = null
var sparks: GPUParticles3D = null
var embers: GPUParticles3D = null

var _age_s: float = 0.0
var _fireball_material: ShaderMaterial = null


## An explosion of `p_radius` metres that drifts at `p_velocity`. Add it under `World/Effects` and place it.
static func create(p_radius: float, p_velocity: Vector3) -> Explosion:
	var e := Explosion.new()
	e.name = "Explosion"
	e.radius_m = maxf(p_radius, 0.5)
	e.velocity = p_velocity
	e._build()
	return e


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)


func _ready() -> void:
	if light == null:
		_build()  # instanced from the scene instead of `create`
	for particles: GPUParticles3D in [sparks, embers]:
		particles.global_transform = Transform3D(Basis.IDENTITY, global_position)  # top_level: where it blew up
		particles.restart()
	advance(0.0)


func _physics_process(delta: float) -> void:
	global_position += velocity * delta


func _process(delta: float) -> void:
	advance(delta)


## Moves the animation `delta` seconds on; frees the node at `LIFETIME_S`. Public for tests.
func advance(delta: float) -> void:
	_age_s += delta
	if _age_s >= LIFETIME_S:
		queue_free()
		return
	# Light: a triangle, up to the peak at a third of the way and back to zero.
	var t_light: float = clampf(_age_s / LIGHT_S, 0.0, 1.0)
	var rise: float = 1.0 / 3.0
	light.light_energy = LIGHT_PEAK_ENERGY * (t_light / rise if t_light < rise else (1.0 - t_light) / (1.0 - rise))
	light.visible = _age_s < LIGHT_S
	# Billboard flash: full to start, linear fade, then hidden.
	var t_flash: float = clampf(_age_s / FLASH_S, 0.0, 1.0)
	flash.visible = _age_s < FLASH_S
	flash.transparency = t_flash
	flash.scale = Vector3.ONE * radius_m * lerpf(1.6, 3.2, t_flash)
	# Fireball: ease out to its final size over 0.8 s, shader age drives the colour, gone by 1.5 s.
	fireball.visible = _age_s < FIREBALL_S
	var grow: float = 1.0 - pow(1.0 - clampf(_age_s / FIREBALL_GROW_S, 0.0, 1.0), 2.0)
	fireball.scale = Vector3.ONE * radius_m * FIREBALL_FINAL_SCALE * lerpf(0.15, 1.0, grow)
	_fireball_material.set_shader_parameter(&"age", _age_s)


## Seconds since it appeared.
func age_s() -> float:
	return _age_s


func _build() -> void:
	light = OmniLight3D.new()
	light.name = "Light"
	light.omni_range = 4.0 * radius_m
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 0.0
	light.shadow_enabled = false
	add_child(light)

	var glow := GLOW_MATERIAL.duplicate() as StandardMaterial3D
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_color = Color(2.4, 1.7, 1.0)
	glow.emission = Color(2.4, 1.7, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = glow
	flash = MeshInstance3D.new()
	flash.name = "Flash"
	flash.mesh = quad
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)

	_fireball_material = ShaderMaterial.new()
	_fireball_material.shader = FIREBALL_SHADER
	_fireball_material.set_shader_parameter(&"duration", FIREBALL_S)
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	sphere.material = _fireball_material
	fireball = MeshInstance3D.new()
	fireball.name = "Fireball"
	fireball.mesh = sphere
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fireball)

	sparks = _particles("Sparks", SPARK_COUNT, Vector2(0.6, 1.2), Vector2(40.0, 150.0), _spark_mesh(), 0.8)
	embers = _particles("Embers", EMBER_COUNT, Vector2(2.0, 3.0), Vector2(5.0, 20.0), _ember_mesh(), 0.5)
	add_child(sparks)
	add_child(embers)


func _particles(node_name: String, count: int, lifetime_s: Vector2, speed: Vector2, mesh: Mesh, damping: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = count
	p.lifetime = lifetime_s.y
	p.one_shot = true
	p.explosiveness = 1.0
	p.top_level = true
	p.local_coords = true
	p.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	p.emitting = false
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3(-300.0, -300.0, -300.0), Vector3(600.0, 600.0, 600.0))
	p.draw_pass_1 = mesh
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.25 * radius_m
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = speed.x
	material.initial_velocity_max = speed.y
	material.gravity = Vector3.ZERO
	material.damping_min = damping
	material.damping_max = damping * 2.0
	material.lifetime_randomness = 1.0 - lifetime_s.x / lifetime_s.y
	material.particle_flag_align_y = true
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1.0), Color(1.0, 0.5, 0.15, 0.9), Color(0.6, 0.12, 0.03, 0.0)])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	material.color_ramp = ramp_texture
	p.process_material = material
	return p


func _spark_mesh() -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.9, 0.03)  # long along +Y, which the particle aligns with its velocity
	mesh.material = _particle_material(Color(3.0, 2.0, 1.0))
	return mesh


func _ember_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = _particle_material(Color(3.0, 1.1, 0.3))
	return mesh


static func _particle_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	return material
