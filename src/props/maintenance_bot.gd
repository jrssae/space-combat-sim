class_name MaintenanceBot
extends Node3D
## One maintenance bot (M7-T11, Q11, D78): the generated `maintenance_bot` mesh on a node that follows its `BotMotion`. Ambient
## only: no `Targetable`, no `Damageable`, no body and no row in the native core, so nothing targets it, shoots it, rams it or
## sees it as a contact. A hidden bot stays in the tree (the fleet is its pool) and is only not drawn.
##
## It is a child of the station's frame or of the drum's pivot, so it rides the station through rebases and turns with the drum
## with no work of its own. `BotFleet` drives it each physics tick.

const ASSET_ID: String = "maintenance_bot"
## How quickly the nose follows the heading, 1/s: a bot swings round a hatch's corner over a second or so, never snaps.
const TURN_RATE: float = 2.0

var motion: BotMover = null
## The body whose frame the loop is in: `StationHardpoints.FRAME` or `DRUM`.
var home_body: String = ""
var loop_name: String = ""

var _mesh_node: MeshInstance3D = null
var _was_visible: bool = true


func setup(p_name: String, p_loop_name: String, p_body: String, p_motion: BotMover, mesh: Mesh) -> void:
	name = p_name
	loop_name = p_loop_name
	home_body = p_body
	motion = p_motion
	# Interpolated on its own even under the drum's pivot, which is turned each frame and so is not: the bot's own steps are
	# physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "Body"
	_mesh_node.mesh = mesh
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_node)
	transform = Transform3D(motion.target_basis(), motion.position)
	visible = motion.is_visible()
	_was_visible = visible


## Moves the bot `delta` seconds on and puts its node where it now is.
func advance(delta: float, alarm: bool) -> void:
	motion.step(delta, alarm)
	var shown: bool = motion.is_visible()
	var target: Basis = motion.target_basis()
	var came_out: bool = shown and not _was_visible
	if came_out:
		basis = target
	else:
		basis = Basis(basis.get_rotation_quaternion().slerp(target.get_rotation_quaternion(), 1.0 - exp(-TURN_RATE * delta)))
	position = motion.position
	if shown != _was_visible:
		visible = shown
		if came_out:
			reset_physics_interpolation()
	_was_visible = shown

