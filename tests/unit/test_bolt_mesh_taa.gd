extends GutTest
## M4-T38 fix round 1 (review I2, M5): `BoltMesh`'s wiring of the motion-vector mode, driven by a fake bolt source (no native
## library needed): under TAA every bolt material is opaque, a look or mesh made later too, and leaving TAA restores them; a bolt
## new to its slot is drawn collapsed for one frame; a grown buffer, a look drawn empty, the bolt rows switched off and on and a
## rebase each start the slots afresh; outside TAA the core's buffer is drawn as it is.

const FLOATS: int = 12


## Stands in for the core: `bolt_instances` and `bolt_transforms` as `SimCore.core` answers them, one buffer per look.
class FakeBolts:
	extends RefCounted
	var buffers: Dictionary = {}

	func bolt_instances(look: int) -> int:
		var buffer: PackedFloat32Array = buffers.get(look, PackedFloat32Array())
		@warning_ignore("integer_division")
		return buffer.size() / 12

	func bolt_transforms(look: int, _fraction: float, _scale: float, _child: Basis, min_instances: int) -> PackedFloat32Array:
		var out: PackedFloat32Array = (buffers.get(look, PackedFloat32Array()) as PackedFloat32Array).duplicate()
		if out.size() < min_instances * 12:
			out.resize(min_instances * 12)
		return out


var mesh: BoltMesh
var source: FakeBolts
var look: int
var weapon: WeaponSpec
var _forward: Vector3


func before_each() -> void:
	BoltMesh.set_motion_vectors(false)
	weapon = WeaponSpec.new()
	weapon.bolt_material = (Projectile.DEFAULT_MATERIAL as StandardMaterial3D).duplicate()
	look = BoltMesh.look_for(weapon)
	mesh = BoltMesh.new(null)
	add_child_autofree(mesh)
	source = FakeBolts.new()
	_forward = mesh.flight_axis()


func after_each() -> void:
	BoltMesh.set_motion_vectors(false)


# `n` bolts flying along the look's flight axis, bolt i at x = i * 5, `step` of the way along.
func _bolts(n: int, step: float) -> PackedFloat32Array:
	var basis := Basis.IDENTITY
	var out := PackedFloat32Array()
	for i: int in n:
		var origin: Vector3 = Vector3(float(i) * 5.0, 0.0, 0.0) + _forward * step
		out.append_array(PackedFloat32Array([basis.x.x, basis.y.x, basis.z.x, origin.x, basis.x.y, basis.y.y, basis.z.y, origin.y,
				basis.x.z, basis.y.z, basis.z.z, origin.z]))
	return out


func _drawn(slot: int) -> bool:
	var buffer: PackedFloat32Array = mesh.drawn_buffer(look)
	return buffer[slot * FLOATS] != 0.0 or buffer[slot * FLOATS + 1] != 0.0 or buffer[slot * FLOATS + 2] != 0.0


func _frame(n: int, step: float) -> void:
	source.buffers[look] = _bolts(n, step)
	mesh.update_from(source, true)


func test_under_taa_a_look_made_later_and_a_mesh_built_later_are_opaque() -> void:
	# Both materials made additive first (a copy taken under TAA would be a copy of the opaque default).
	var later := WeaponSpec.new()
	later.bolt_material = (Projectile.DEFAULT_MATERIAL as StandardMaterial3D).duplicate()
	var node_material := (Projectile.DEFAULT_MATERIAL as StandardMaterial3D).duplicate()
	BoltMesh.set_motion_vectors(true)
	BoltMesh.look_for(later)
	assert_eq((later.bolt_material as BaseMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "a look registered under TAA")
	Projectile.bolt_mesh(1.25, 0.05, node_material)
	assert_eq(node_material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "a node bolt's mesh built under TAA")
	BoltMesh.set_motion_vectors(false)
	assert_eq((later.bolt_material as BaseMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "back to the additive look")
	assert_eq((later.bolt_material as BaseMaterial3D).blend_mode, BaseMaterial3D.BLEND_MODE_ADD)
	assert_eq(node_material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)


func test_a_new_bolt_is_collapsed_its_first_frame_and_drawn_after() -> void:
	BoltMesh.set_motion_vectors(true)
	_frame(2, 0.0)
	assert_false(_drawn(0), "first frame collapsed")
	assert_eq(BoltMesh.collapsed_last_frame, 2)
	_frame(2, 10.0)
	assert_true(_drawn(0), "drawn from its second frame")
	assert_true(_drawn(1))
	assert_eq(BoltMesh.collapsed_last_frame, 0)


func test_a_grown_buffer_collapses_every_bolt_once() -> void:
	BoltMesh.set_motion_vectors(true)
	_frame(64, 0.0)
	_frame(64, 10.0)
	assert_eq(BoltMesh.collapsed_last_frame, 0, "64 steady bolts fill the first buffer")
	_frame(65, 20.0)
	assert_eq(BoltMesh.collapsed_last_frame, 65, "the multimesh doubled: no last frame to pair any slot with")
	_frame(65, 30.0)
	assert_eq(BoltMesh.collapsed_last_frame, 0, "and once only")


func test_a_look_drawn_empty_starts_its_slots_afresh() -> void:
	BoltMesh.set_motion_vectors(true)
	_frame(1, 0.0)
	_frame(1, 10.0)
	source.buffers[look] = PackedFloat32Array()
	mesh.update_from(source, true)
	_frame(1, 20.0)
	assert_false(_drawn(0), "a bolt after an empty frame is new, even moving on from the last one's place")


func test_the_bolt_rows_switched_off_and_on_start_the_slots_afresh() -> void:
	BoltMesh.set_motion_vectors(true)
	_frame(1, 0.0)
	_frame(1, 10.0)
	mesh.update_from(source, false)
	assert_eq(BoltMesh.collapsed_last_frame, 0, "nothing drawn with the rows off")
	_frame(1, 20.0)
	assert_false(_drawn(0), "the first frame after the switch pairs with nothing")


func test_a_rebase_starts_the_slots_afresh() -> void:
	BoltMesh.set_motion_vectors(true)
	_frame(1, 0.0)
	_frame(1, 10.0)
	mesh.note_rebase()
	_frame(1, 20.0)
	assert_false(_drawn(0), "the renderer's last frame is from before the shift")
	_frame(1, 30.0)
	assert_true(_drawn(0))


func test_leaving_taa_draws_the_core_buffer_as_it_is() -> void:
	BoltMesh.set_motion_vectors(true)
	_frame(1, 0.0)
	BoltMesh.set_motion_vectors(false)
	_frame(1, 10.0)
	var drawn: PackedFloat32Array = mesh.drawn_buffer(look)
	assert_eq(drawn.slice(0, FLOATS), source.buffers[look], "no slot check outside TAA: the bolt as the core wrote it")
	assert_eq(BoltMesh.collapsed_last_frame, 0)
	assert_eq((weapon.bolt_material as BaseMaterial3D).transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
