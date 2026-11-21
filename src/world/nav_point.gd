class_name NavPoint
extends Node3D
## A place the player can target and act on that is not a ship (M7-T27): the station's main docking bay and cargo bay. A thin
## holder for a navigation `Targetable` (role BEACON, neutral, a prop) with an interaction, placed as a child of what carries it.
## Moves with its parent; its marker's velocity is the World anchor's rest motion, as the station's own. The core knows it as a
## navigation marker (`SimCore.set_navigation`), so the AI's avoidance flies through it: a docking ship's lane runs through the mouth.

## The marker it holds.
var targetable: Targetable = null
## What it is, for the target menu's preview ("Docking bay"): it has no hull to name it.
var class_text: String = ""
## Whose dock it is, when its interaction is `dock` (M8-T06): the id fighters name as their home (`Combatant.home`), "babylon5"
## for the station's bay. A nav point that offers `dock` is in `DOCKS_GROUP`, so the docking rules find every dock alike.
var home_id: StringName = &""

const DOCKS_GROUP: StringName = &"docks"
const KIND_DOCK: StringName = &"dock"


## A nav point named `display_name` that offers `interaction`, heard `broadcast_range_m` out (its carrier's beacon).
static func make(display_name: String, interaction: TargetInteraction, broadcast_range_m: float) -> NavPoint:
	var point := NavPoint.new()
	point.name = display_name.to_pascal_case()
	var marker := Targetable.new()
	marker.name = "Targetable"
	marker.display_name = display_name
	marker.faction = &"neutral"
	marker.kind = Targetable.Kind.PROP
	marker.role = Targetable.Role.BEACON
	marker.interaction = interaction
	point.targetable = marker
	point.add_child(marker)
	marker.broadcast_range_m = broadcast_range_m
	return point


func _enter_tree() -> void:
	SimCore.set_navigation(get_instance_id(), true)
	if targetable != null and targetable.interaction != null and targetable.interaction.kind == KIND_DOCK:
		add_to_group(DOCKS_GROUP)


func _exit_tree() -> void:
	SimCore.set_navigation(get_instance_id(), false)


func _physics_process(_delta: float) -> void:
	# The station rides the World's anchor: a ship at rest against it sees this point at rest too.
	var world: WorldFrame = WorldFrame.of(self)
	if world != null and targetable != null:
		targetable.velocity = world.rest_velocity()
