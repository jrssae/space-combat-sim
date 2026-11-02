class_name LightEmitter
extends RefCounted
## Something that gives off light, as `LightPicker` sees it (architecture §7.3). It owns no `Light3D`: only the rig's 8 slots are
## lights, and a picked emitter is copied into one of them each frame. The owner sets `energy` (0 = dark, not a candidate) and
## either `position` or an `anchor` to follow.

## Priority classes, the picker's multipliers: a player notices their own light first and a distant nozzle last.
const PRIORITY_CABIN: float = 1.0
const PRIORITY_NOZZLE: float = 2.0
const PRIORITY_MUZZLE_FLASH: float = 4.0
const PRIORITY_EXPLOSION: float = 8.0
const PRIORITY_PLAYER_OWN: float = 16.0

## The name the `lights` provider shows.
var label: String = ""
var priority: float = PRIORITY_NOZZLE
var color: Color = Color.WHITE
var energy: float = 0.0
var omni_range: float = 1.0
var attenuation: float = 1.0
## Global position; kept up to date by `follow` when the emitter has an `anchor`.
var position: Vector3 = Vector3.ZERO
## The node this emitter sits on, or null when the owner sets `position` itself.
var anchor: Node3D = null:
	set(value):
		anchor = value
		_anchored = value != null
## Where on `anchor`, in its local frame.
var offset: Vector3 = Vector3.ZERO

var _anchored: bool = false


func _init(p_label: String = "", p_priority: float = PRIORITY_NOZZLE, p_color: Color = Color.WHITE, p_energy: float = 0.0,
		p_range: float = 1.0, p_attenuation: float = 1.0) -> void:
	label = p_label
	priority = p_priority
	color = p_color
	energy = p_energy
	omni_range = p_range
	attenuation = p_attenuation


## Puts a lit emitter on its anchor's drawn pose, so the light does not judder against a moving hull. False when the anchor is
## gone or out of the tree (a freed or released ship): the rig drops the emitter, and its owner adds it again when it is back.
func follow() -> bool:
	if not _anchored:
		return true
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return false
	if energy > 0.0:
		position = anchor.get_global_transform_interpolated() * offset
	return true
