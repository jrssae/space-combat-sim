class_name Explosion
extends Node3D
## The explosion of a destroyed ship (architecture §15.7), made entirely in code (no textures): a light
## emitter, an additive billboard flash, a noisy fireball sphere, and sparks, fragments and a gas shell thrown from the `FxPool`
## (M3-T23). Transparent meshes and particles draw after the opaque hulls and are hidden behind hulls in front of them by their
## depth.
##
## - light: a `LightEmitter` (M3-T22), never a `Light3D` of its own. It competes through the `LightRig`'s `LightPicker`
##   for a slot, so nearby hulls are lit, and sits in the rig's candidate list only while it shines. Energy 0 -> 8 -> 0 over
##   0.25 s, range 4 x radius.
## - billboard flash: an additive quad, 0.15 s.
## - fireball: a sphere growing to 1.2 x radius over 0.8 s, `explosion_fireball.gdshader`, gone by 1.5 s.
## - pool bursts (`FxSpecs`): 80 sparks, 40-150 m/s, 0.6-1.2 s; 20 glowing fragments, 5-20 m/s, 2-3 s; a gas shell of 10 puffs.
##
## It drifts with `velocity` (it was the ship's), joins `world_shiftable` so a rebase moves it, and frees itself after
## 3 s. Animation is `_process` (visuals), so a paused game freezes it; `advance` is public for tests.
##
## The pool's bursts start where the ship blew up and fly on at the ship's velocity (they inherit it); their emitters are shifted
## by a rebase with the world (`FxPool`). The explosion owns no particle nodes of its own, so the count never changes.

const LIFETIME_S: float = 3.0
const LIGHT_S: float = 0.25
const LIGHT_PEAK_ENERGY: float = 8.0
const FLASH_S: float = 0.15
const FIREBALL_S: float = 1.5
const FIREBALL_GROW_S: float = 0.8
const FIREBALL_FINAL_SCALE: float = 1.2
const FIREBALL_SHADER: Shader = preload("res://src/combat/explosion_fireball.gdshader")
const GLOW_MATERIAL: StandardMaterial3D = preload("res://assets/materials/thruster_glow.tres")

## Radius of the dead ship (its bounding radius): everything scales with it.
var radius_m: float = 4.0
## World-frame drift velocity, m/s.
var velocity: Vector3 = Vector3.ZERO

var emitter: LightEmitter = null
var flash: MeshInstance3D = null
var fireball: MeshInstance3D = null
## Where the sparks, fragments and gas shell come from (`DestructionDirector` sets it); without one the explosion has none.
var fx: FxPool = null

var _age_s: float = 0.0
var _rig: LightRig = null
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
	if emitter == null:
		_build()  # instanced from the scene instead of `create`
	_rig = LightRig.of(self)
	if _rig != null:
		_rig.add_emitter(emitter)
	if fx != null:
		for effect: int in [FxSpecs.EXPLOSION_SPARKS, FxSpecs.EXPLOSION_FRAGMENTS, FxSpecs.EXPLOSION_GAS]:
			fx.burst(effect, global_position, Vector3.UP, velocity)
	advance(0.0)


func _exit_tree() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.remove_emitter(emitter)
	_rig = null


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
	emitter.energy = light_energy(_age_s)
	if _age_s >= LIGHT_S and _rig != null:
		_rig.remove_emitter(emitter)  # the light is over; the rest of the effect is meshes
		_rig = null
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


## Energy of the explosion's light `age_s` after it appeared: a triangle, up to the peak at a third of the way and back to zero.
static func light_energy(age_s: float) -> float:
	var t: float = clampf(age_s / LIGHT_S, 0.0, 1.0)
	var rise: float = 1.0 / 3.0
	return LIGHT_PEAK_ENERGY * (t / rise if t < rise else (1.0 - t) / (1.0 - rise))


## Seconds since it appeared.
func age_s() -> float:
	return _age_s


func _build() -> void:
	emitter = LightEmitter.new("explosion", LightEmitter.PRIORITY_EXPLOSION, Color(1.0, 0.78, 0.5), 0.0, 4.0 * radius_m)
	emitter.anchor = self

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
