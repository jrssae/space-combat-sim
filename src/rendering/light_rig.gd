class_name LightRig
extends Node3D
## The scene's only lights (architecture §7.3): the key star (slot 0) and 7 omni slots, created once and never freed. The star
## casts shadows, but only of the big sectioned pieces (the station), on everything: without them the sun glinted off every arm,
## tooth and deck on a station's night side and shone into its bays (M7). Ships cast none (500 of them would cost four more
## passes each). Every frame
## `LightPicker` chooses which emitters fill the omni slots and this node copies their position, colour, energy and range across.
## An unused slot sits at energy 0, so the renderer skips it. A budget of 8 lights keeps the clustered renderer cheap at 500 ships
## (M4-T31: the light budget outlived the renderer it was made for).
##
## Console (§6.4): provider `lights` (`picked`, `candidates`, `active`, `cost_us`).

const GROUP: StringName = &"light_rig"
## The render layer of what stands inside a closed space (a station's launch halls, door wells and bays). No light casts shadows,
## so the key star would light a hall's walls like the hull outside and glint off a door at the bottom of its well; the star's
## light leaves this layer out, and the omni slots, emissive paint and ambient light it. Cameras see every layer.
const INTERIOR_LAYER: int = 1 << 1
## The render layer of what casts the key star's shadow, beside its own layer: a station's sections and props.
const SHADOW_CASTER_LAYER: int = 1 << 2
## How far from the camera the star's shadows are drawn, m, in four cascades: a station fills the view from 20 km in.
const STAR_SHADOW_M: float = 20000.0
## The four cascades' atlas, px a side: about 1 m a texel in the nearest cascade at this reach.
const STAR_SHADOW_ATLAS_PX: int = 8192

var _picker: LightPicker = LightPicker.new()
var _emitters: Array[LightEmitter] = []
var _picked: Array[LightEmitter] = []
var _slots: Array[Light3D] = []
var _cost_us: int = 0

@onready var key_star: DirectionalLight3D = $KeyStar


## The rig of the scene `node` is in, or null when it has none.
static func of(node: Node) -> LightRig:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as LightRig


func _init() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_slots = [key_star]
	key_star.light_cull_mask &= ~(INTERIOR_LAYER | SHADOW_CASTER_LAYER)
	key_star.shadow_enabled = true
	key_star.shadow_caster_mask = SHADOW_CASTER_LAYER
	key_star.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key_star.directional_shadow_max_distance = STAR_SHADOW_M
	key_star.directional_shadow_blend_splits = true
	RenderingServer.directional_shadow_atlas_set_size(STAR_SHADOW_ATLAS_PX, true)
	for i: int in LightPicker.SLOT_COUNT:
		var slot := OmniLight3D.new()
		slot.name = "Slot%d" % (i + 1)
		slot.light_energy = 0.0
		slot.shadow_enabled = false
		slot.light_cull_mask &= ~SHADOW_CASTER_LAYER  # a caster is lit through its own layer, as the star lights it
		slot.top_level = true  # placed in World coordinates, whatever this node's parent does
		slot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # moved once per frame, from drawn poses
		add_child(slot)
		_slots.append(slot)
	DebugConsole.registry.register_provider(&"lights", ConsoleVars.new({
		&"picked": {"get": _picked_labels, "doc": "The emitters in the 7 omni slots this frame"},
		&"candidates": {"get": candidate_count, "doc": "Emitters competing for the slots, lit or not"},
		&"active": {"get": active_count, "doc": "Lights shining this frame, the key star included (8 at most)"},
		&"cost_us": {"get": func() -> int: return _cost_us, "unit": "us", "doc": "CPU cost of the last pick and copy"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	update(camera.global_position if camera != null else Vector3.ZERO)


## Picks for a camera at `camera_position` and fills the slots. `_process` calls it; public for the tests.
func update(camera_position: Vector3) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	for i: int in range(_emitters.size() - 1, -1, -1):
		if not _emitters[i].follow():
			_emitters.remove_at(i)
	_picked = _picker.pick(_emitters, camera_position)
	for i: int in LightPicker.SLOT_COUNT:
		_fill(_slots[i + 1] as OmniLight3D, _picked[i])
	_cost_us = Time.get_ticks_usec() - started_us


## Enters an emitter into the competition for the slots.
func add_emitter(emitter: LightEmitter) -> void:
	if not _emitters.has(emitter):
		_emitters.append(emitter)


## Whether the emitter is in the competition.
func has_emitter(emitter: LightEmitter) -> bool:
	return _emitters.has(emitter)


## Takes an emitter out; its slot goes dark at the next `update`.
func remove_emitter(emitter: LightEmitter) -> void:
	_emitters.erase(emitter)


## The 8 lights: the key star, then the omni slots.
func slots() -> Array[Light3D]:
	return _slots


## This frame's emitter per omni slot (null = dark).
func picked() -> Array[LightEmitter]:
	return _picked


func candidate_count() -> int:
	return _emitters.size()


func active_count() -> int:
	var n: int = 0
	for light: Light3D in _slots:
		n += 1 if light.light_energy > 0.0 and light.is_visible_in_tree() else 0
	return n


static func _fill(slot: OmniLight3D, emitter: LightEmitter) -> void:
	if emitter == null:
		if slot.light_energy != 0.0:
			slot.light_energy = 0.0
		return
	slot.global_position = emitter.position
	slot.light_color = emitter.color
	slot.light_energy = emitter.energy
	slot.omni_range = emitter.omni_range
	slot.omni_attenuation = emitter.attenuation


func _picked_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for emitter: LightEmitter in _picked:
		if emitter != null:
			out.append(emitter.label)
	return out

