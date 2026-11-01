class_name SplatLightRig
extends Node3D
## The scene's only lights (architecture §7.3): the key star (slot 0) and 7 omni slots, created once and never freed. Every frame
## `LightPicker` chooses which emitters fill the omni slots and this node copies their position, colour, energy and range across;
## GDGS re-reads the lights every frame, so a moved slot shows at once. An unused slot sits at energy 0, which GDGS skips. Meshes are
## lit by the same 8, so meshes and splats agree.
##
## It sits before `World` in the tree: GDGS's walk for lights stops after 20 000 nodes, and must find the slots when there are 500
## ships. It also keeps every lit splat node in line with the relight settings, live.
##
## Console (§6.4): provider `lights` (`picked`, `candidates`, `active`, `cost_us`) and `relight [on|off]`.

const GROUP: StringName = &"splat_light_rig"

var _picker: LightPicker = LightPicker.new()
var _emitters: Array[LightEmitter] = []
var _picked: Array[LightEmitter] = []
var _slots: Array[Light3D] = []
var _cost_us: int = 0

@onready var key_star: DirectionalLight3D = $KeyStar


## The rig of the scene `node` is in, or null when it has none.
static func of(node: Node) -> SplatLightRig:
	if node == null or not node.is_inside_tree():
		return null
	return node.get_tree().get_first_node_in_group(GROUP) as SplatLightRig


func _init() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_slots = [key_star]
	for i: int in LightPicker.SLOT_COUNT:
		var slot := OmniLight3D.new()
		slot.name = "Slot%d" % (i + 1)
		slot.light_energy = 0.0
		slot.shadow_enabled = false
		slot.top_level = true  # placed in World coordinates, whatever this node's parent does
		slot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # moved once per frame, from drawn poses
		add_child(slot)
		_slots.append(slot)
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.registry.register_provider(&"lights", ConsoleVars.new({
		&"picked": {"get": _picked_labels, "doc": "The emitters in the 7 omni slots this frame"},
		&"candidates": {"get": candidate_count, "doc": "Emitters competing for the slots, lit or not"},
		&"active": {"get": active_count, "doc": "Lights shining this frame, the key star included (8 at most)"},
		&"cost_us": {"get": func() -> int: return _cost_us, "unit": "us", "doc": "CPU cost of the last pick and copy"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"relight",
			"Toggle or set scene lighting on hulls, chunks and buoys (off draws their flat paint; meshes stay lit)",
			[ConsoleArg.bool_optional(&"state")]), _cmd_relight, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


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


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key in SplatLightingLoader.SETTINGS:
		for node: Node in get_tree().get_nodes_in_group(SplatLightingLoader.GROUP):
			SplatLightingLoader.apply_settings(node as GaussianSplatNode)


func _picked_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for emitter: LightEmitter in _picked:
		if emitter != null:
			out.append(emitter.label)
	return out


func _cmd_relight(args: Dictionary) -> ConsoleResult:
	return DebugConsole.registry.toggle("settings.splat_relight", args[&"state"])
