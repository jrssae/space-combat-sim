class_name JumpArrival
extends Node3D
## A jump point opening (architecture §18 D51, Q12): a short bright flash, a light and the generated `jump_in` sound where a
## ship comes out of hyperspace; the ship appears inside it and flies out on its own velocity. A placeholder until M6's
## jumpgate vortex. Meshes only, never splats (D22): built once with the pool and only shown and hidden afterwards.
##
## Timing (sim time from the frame's delta, so a pause freezes it): the flash swells to full in `SWELL_S`, then shrinks and fades
## out by `FLASH_S`; the light (a `LightEmitter` competing for the rig's slots) peaks at `LIGHT_PEAK_ENERGY` a third of the way
## through `LIGHT_S`. In `world_shiftable`, so a rebase moves it.

const LIFETIME_S: float = 1.4
const SWELL_S: float = 0.18
const FLASH_S: float = 1.2
const LIGHT_S: float = 0.9
const LIGHT_PEAK_ENERGY: float = 10.0
const COLOR: Color = Color(0.75, 0.9, 2.6)
const GLOW_MATERIAL: StandardMaterial3D = preload("res://assets/materials/thruster_glow.tres")
const SOUND_PATH: String = "res://assets/generated/sfx_world/jump_in.wav"
const SOUND_DB: float = 2.0

## Radius of the opening, metres: the flash and the light's reach scale with it.
var radius_m: float = 40.0
var flash: MeshInstance3D = null
var core: MeshInstance3D = null
var sound: AudioStreamPlayer3D = null
var emitter: LightEmitter = null

var _age_s: float = 0.0
var _open: bool = false
var _rig: LightRig = null

static var _stream: AudioStreamWAV = null
static var _stream_checked: bool = false


func _init() -> void:
	name = "JumpArrival"
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	_build()
	visible = false
	set_process(false)


func _exit_tree() -> void:
	_leave_rig()


## Opens the point at World-local `at` (the caller converts from the universe position).
func open(at: Vector3, p_radius_m: float = 40.0) -> void:
	radius_m = maxf(p_radius_m, 1.0)
	position = at
	reset_physics_interpolation()
	_age_s = 0.0
	_open = true
	visible = true
	emitter.omni_range = 6.0 * radius_m
	_rig = LightRig.of(self)
	if _rig != null:
		_rig.add_emitter(emitter)
	if sound.stream != null:
		sound.play()
	set_process(true)
	advance(0.0)


## Whether it is showing now.
func is_open() -> bool:
	return _open


## Seconds since it opened.
func age_s() -> float:
	return _age_s


func _process(delta: float) -> void:
	advance(delta)


## Moves the effect `delta` seconds on; it closes itself at `LIFETIME_S`. Public for tests.
func advance(delta: float) -> void:
	if not _open:
		return
	_age_s += delta
	if _age_s >= LIFETIME_S:
		close()
		return
	emitter.energy = light_energy(_age_s)
	var size: float = flash_scale(_age_s)
	flash.visible = size > 0.0
	flash.scale = Vector3.ONE * radius_m * 2.0 * size
	flash.transparency = clampf((_age_s - SWELL_S) / (FLASH_S - SWELL_S), 0.0, 1.0)
	core.visible = _age_s < SWELL_S * 2.0
	core.scale = Vector3.ONE * radius_m * 0.6 * (1.0 - clampf(_age_s / (SWELL_S * 2.0), 0.0, 1.0))


## Hides it until it opens again.
func close() -> void:
	_open = false
	visible = false
	emitter.energy = 0.0
	_leave_rig()
	set_process(false)


## The flash's size, 0..1 of its full size, `age_s` after opening: a fast swell, then a slower shrink to nothing.
static func flash_scale(age_s: float) -> float:
	if age_s < 0.0 or age_s >= FLASH_S:
		return 0.0
	if age_s < SWELL_S:
		return sqrt(age_s / SWELL_S)
	return 1.0 - pow((age_s - SWELL_S) / (FLASH_S - SWELL_S), 2.0)


## The light's energy `age_s` after opening: up to the peak a third of the way through `LIGHT_S`, then back to dark.
static func light_energy(age_s: float) -> float:
	var t: float = clampf(age_s / LIGHT_S, 0.0, 1.0)
	var rise: float = 1.0 / 3.0
	return LIGHT_PEAK_ENERGY * (t / rise if t < rise else (1.0 - t) / (1.0 - rise))


func _leave_rig() -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.remove_emitter(emitter)
	_rig = null


func _build() -> void:
	emitter = LightEmitter.new("jump_in", LightEmitter.PRIORITY_EXPLOSION, Color(0.7, 0.85, 1.0), 0.0, 6.0 * radius_m)
	emitter.anchor = self
	flash = _billboard("Flash", COLOR)
	core = _billboard("Core", Color(2.4, 2.6, 3.0))
	sound = AudioStreamPlayer3D.new()
	sound.name = "Sound"
	sound.bus = AudioDirector.BUS
	sound.unit_size = 120.0
	sound.max_distance = 15000.0
	sound.volume_db = SOUND_DB
	sound.stream = _jump_sound()
	add_child(sound)


func _billboard(node_name: String, color: Color) -> MeshInstance3D:
	var glow := GLOW_MATERIAL.duplicate() as StandardMaterial3D
	glow.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.albedo_color = color
	glow.emission = color
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = glow
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.mesh = quad
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visible = false
	add_child(mesh)
	return mesh


# The generated sound, loaded once for every jump point; without it (assets not built) the point opens silently.
static func _jump_sound() -> AudioStreamWAV:
	if not _stream_checked:
		_stream_checked = true
		if ResourceLoader.exists(SOUND_PATH):
			_stream = load(SOUND_PATH) as AudioStreamWAV
		else:
			push_warning("JumpArrival: %s is missing or not imported (run scripts/gen_assets.sh, then import); jump points are silent" % SOUND_PATH)
	return _stream
