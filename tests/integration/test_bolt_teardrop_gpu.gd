extends GutTest
## M7-T52: a bolt's bright core shows in the teardrop, both drawn additive (SMAA) and drawn opaque for TAA's motion vectors, where
## an opaque envelope used to hide it: the head's centre outshines the envelope round it and the tail. Reads the rendered frame.
## Needs the real renderer: headless runs have no RenderingDevice and mark these pending. Run with a window:
## `.tools/godot/godot --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_bolt_teardrop_gpu.gd -gexit`

const DISTANCE_M: float = 60.0
## Drawn this many times its size, so the head spans a good many pixels and the whole drop stays in view.
const SCALE: float = 25.0


## Stands in for the core: one bolt of one look, crossing the view along +X.
class OneBolt:
	extends RefCounted
	var look: int = -1
	var origin: Vector3 = Vector3.ZERO

	func bolt_instances(p_look: int) -> int:
		return 1 if p_look == look else 0

	func bolt_transforms(_look: int, _fraction: float, scale: float, child: Basis, min_instances: int,
			_tail_m: float) -> PackedFloat32Array:
		var b: Basis = Basis.looking_at(Vector3.RIGHT, Vector3.UP) * child * scale
		var out := PackedFloat32Array([b.x.x, b.y.x, b.z.x, origin.x, b.x.y, b.y.y, b.z.y, origin.y, b.x.z, b.y.z, b.z.z, origin.z])
		out.resize(maxi(min_instances, 1) * 12)
		return out


var camera: Camera3D
var bolts: BoltMesh
var source: OneBolt
var weapon: WeaponSpec
var _aa_backup: StringName
var _scale_backup: float


func before_each() -> void:
	_aa_backup = AntiAliasingMode.read(get_viewport())
	_scale_backup = Projectile.visual_scale
	Projectile.visual_scale = SCALE
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child_autofree(world)
	camera = Camera3D.new()
	camera.fov = 60.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(camera)
	camera.current = true
	weapon = load("res://assets/weapons/pulse_cannon_ef.tres") as WeaponSpec
	source = OneBolt.new()
	source.look = BoltMesh.look_for(weapon)
	source.origin = Vector3(20.0, 0.0, -DISTANCE_M)  # the tail runs off to the left
	bolts = BoltMesh.new(null)
	add_child_autofree(bolts)
	if FramePasses.current() != null:
		FramePasses.current().remove_bolt_mesh(bolts)  # drawn from here, not from the game's frame pass


func after_each() -> void:
	BoltMesh.set_motion_vectors(false)
	AntiAliasingMode.apply(get_viewport(), _aa_backup)
	Projectile.visual_scale = _scale_backup


func _gpu() -> bool:
	if RenderingServer.get_rendering_device() == null:
		pending("needs the real renderer (no RenderingDevice headless)")
		return false
	return true


# Draws the still bolt for some frames (TAA settles) and returns the frame.
func _render() -> Image:
	for i: int in 16:
		bolts.update_from(source, true)
		await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


# The red channel at a point in the world, where the bolt's blue saturates first.
func _red(image: Image, at: Vector3) -> float:
	var px: Vector2 = camera.unproject_position(at)
	var scale: Vector2 = Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	return image.get_pixelv(Vector2i(px * scale)).r


func _check_core(mode: StringName) -> void:
	var head: float = BoltShape.head_radius(weapon.bolt_radius_m) * SCALE
	var tail: float = BoltShape.total_length(weapon.bolt_length_m, weapon.bolt_radius_m) * SCALE - head
	var image: Image = await _render()
	var centre: float = _red(image, source.origin)
	var rim: float = _red(image, source.origin + Vector3.UP * 0.8 * head)  # outside the core (half the head's radius)
	var back: float = _red(image, source.origin - Vector3.RIGHT * 0.6 * tail)
	var sky: float = _red(image, source.origin + Vector3.UP * 3.0 * head)
	assert_gt(rim, sky + 0.05, "%s: the envelope is drawn (rim %.3f, sky %.3f)" % [mode, rim, sky])
	assert_gt(centre, rim + 0.2, "%s: the core outshines the envelope (centre %.3f, rim %.3f)" % [mode, centre, rim])
	assert_gt(centre, back + 0.2, "%s: the head outshines the tail (centre %.3f, tail %.3f)" % [mode, centre, back])


func test_under_taa_the_opaque_bolts_core_shows() -> void:
	if not _gpu():
		return
	AntiAliasingMode.apply(get_viewport(), &"taa")
	BoltMesh.set_motion_vectors(true)
	assert_eq((weapon.bolt_material as BaseMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "drawn opaque")
	await _check_core(&"taa")


func test_drawn_additive_the_core_shows() -> void:
	if not _gpu():
		return
	AntiAliasingMode.apply(get_viewport(), &"smaa")
	BoltMesh.set_motion_vectors(false)
	await _check_core(&"smaa")
