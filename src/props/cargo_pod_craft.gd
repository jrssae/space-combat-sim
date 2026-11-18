class_name CargoPodCraft
extends Node3D
## One cargo pod (M7-T34): the craft of M7-T33 (`CargoPodRig`, the skinned `cargo_pod_craft` model) on a node that follows its
## `CargoPodMotion`, its arms posed from the motion each frame. Ambient, as the maintenance bots are: no `Targetable`, no body and
## no row in the native core. A hidden pod stays in the tree (inside the cargo bay's wall) and is only not drawn.
##
## It hangs from the station's frame (`CargoPodFleet.frame_parent`), so it rides the station through rebases; `CargoPodFleet`
## drives it each physics tick.

## How quickly the nose follows the heading, 1/s (a smooth swing, never a snap); while it holds a block it turns with the block.
const TURN_RATE: float = 2.0
## Past this the 6 m craft is far under a pixel and is not drawn.
const DRAW_RANGE_M: float = 20000.0

var motion: CargoPodMotion = null
var rig: CargoPodRig = null

var _was_visible: bool = true


## Builds the craft flying `p_motion`, its model from `asset_root`; without the asset it still flies, undrawn.
func setup(p_name: String, p_motion: CargoPodMotion, asset_root: String = ShipSpec.ASSET_ROOT) -> void:
	name = p_name
	motion = p_motion
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	rig = CargoPodRig.new()
	rig.name = "Rig"
	add_child(rig)
	if rig.build(asset_root):
		for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_end = DRAW_RANGE_M
	transform = Transform3D(motion.target_basis(), motion.position)
	visible = motion.is_visible()
	_was_visible = visible
	_pose_arms()


## Moves the craft `delta` seconds on and puts its node where it now is.
func advance(delta: float, alarm: bool) -> void:
	motion.step(delta, alarm)
	var shown: bool = motion.is_visible()
	var target: Basis = motion.target_basis()
	var came_out: bool = shown and not _was_visible
	if came_out or motion.phase == CargoPodMotion.Phase.CARRY:
		basis = target  # holding a block, its hands stay on the face
	else:
		basis = Basis(basis.get_rotation_quaternion().slerp(target.get_rotation_quaternion(), 1.0 - exp(-TURN_RATE * delta)))
	position = motion.position
	if shown != _was_visible:
		visible = shown
		if came_out:
			reset_physics_interpolation()
	_was_visible = shown


func _process(_delta: float) -> void:
	if visible:
		_pose_arms()


func _pose_arms() -> void:
	if rig != null and (rig.extend != motion.extend or rig.jaw_open != motion.jaw_open):
		rig.set_pose(motion.extend, 0.0, motion.jaw_open)


## Where a hand's grip point is now (`side` "r" or "l"), in the station's frame: for tests and the console.
func grip_point(side: String) -> Vector3:
	rig.set_pose(motion.extend, 0.0, motion.jaw_open)
	return transform * rig.grip_point(side)
