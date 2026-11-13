class_name FxPool
extends Node3D
## Sparks and glowing fragments for hits, rams, explosions and debris (M3-T23, architecture D8): a fixed set of one-shot
## `GPUParticles3D` emitters per effect (`FxSpecs`), built once and restarted for each burst, so the particle node count never
## changes while playing.
##
## Newtonian: the process materials have no gravity and no damping, and a burst inherits its source's velocity by moving its
## emitter at that velocity; particles live in the emitter's own frame (`local_coords`), so they go where it goes.
## A velocity rebase takes its `dv` off every busy emitter's velocity (`boost`).
## Rebase: every emitter is `top_level` and in `world_shiftable`, so `WorldFrame.rebase` shifts it, particles and all. A burst
## asked for in the physics tick is placed at once and only started (`restart`) in `_process`, so a rebase between the two
## shifts it too.
##
## `burst` is called from the physics tick, in numbers: it allocates nothing and looks nothing up in the tree. With every
## emitter of an effect busy, the oldest is restarted for the new burst (a fresh hit matters more than a fading one).
## `settings.particle_density` (0-1) scales the amounts; at 0 nothing is claimed and `_process` stays off. The node keeps
## `_process` on only while some emitter is busy.
##
## Hull depth: the particle meshes are additive transparent unshaded, like the plumes, so the hull depth proxies hide them behind
## hulls with no extra work.
##
## Console: provider `fx` (`emitters`, `busy`, `bursts`, `reused`, `density`) and command `fxburst <effect>`, which throws one
## burst of that effect 40 m in front of the camera.

const VISIBILITY_HALF_M: float = 220.0
const HANDLE_SLOT_MASK: int = 0xFFFF
const BURST_DISTANCE_M: float = 40.0

const _IDLE: int = 0
const _PENDING: int = 1
const _LIVE: int = 2

## `settings.particle_density`, kept here so a burst reads no setting.
var density: float = 1.0
var bursts: int = 0
var reused: int = 0

var _nodes: Array[GPUParticles3D] = []
var _first: PackedInt32Array = PackedInt32Array()
var _cursor: PackedInt32Array = PackedInt32Array()
var _effect_of: PackedInt32Array = PackedInt32Array()
var _state: PackedByteArray = PackedByteArray()
var _generation: PackedInt32Array = PackedInt32Array()
var _velocity: PackedVector3Array = PackedVector3Array()
var _age_s: PackedFloat32Array = PackedFloat32Array()
var _stop_emitting_s: PackedFloat32Array = PackedFloat32Array()
var _busy_s: PackedFloat32Array = PackedFloat32Array()
var _emitting: PackedByteArray = PackedByteArray()
var _busy_count: int = 0
var _built: bool = false


func _ready() -> void:
	build()
	var world: WorldFrame = WorldFrame.of(self)
	if world != null:
		world.boosted.connect(boost)
	density = float(Settings.get_value(&"particle_density"))
	Settings.changed.connect(_on_setting_changed)
	DebugConsole.registry.register_provider(&"fx", ConsoleVars.new({
		&"emitters": {"get": func() -> int: return _nodes.size(), "doc": "Particle emitters in the pools (fixed)"},
		&"busy": {"get": func() -> int: return _busy_count, "doc": "Emitters taken by a burst"},
		&"bursts": {"get": func() -> int: return bursts, "doc": "Bursts thrown this session"},
		&"reused": {"get": func() -> int: return reused, "doc": "Bursts that took the oldest busy emitter because all were busy"},
		&"density": {"get": func() -> float: return density, "doc": "settings.particle_density as applied"},
	}), self)
	var names: Array[StringName] = []
	for effect: int in FxSpecs.COUNT:
		names.append(StringName(FxSpecs.spec(effect)["name"]))
	DebugConsole.registry.register_command(ConsoleCommand.new(&"fxburst",
			"Throw one burst of an effect 40 m in front of the camera (for looking at it)",
			[ConsoleArg.enum_optional(&"effect", names, &"hit")]), _cmd_fxburst, self)
	set_process(false)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


## Creates every emitter, parked. Done once; `_ready` calls it, so a bare pool in a test can too.
func build() -> void:
	if _built:
		return
	_built = true
	_first.resize(FxSpecs.COUNT)
	_cursor.resize(FxSpecs.COUNT)
	var total: int = 0
	for effect: int in FxSpecs.COUNT:
		_first[effect] = total
		total += int(FxSpecs.spec(effect)["emitters"])
	_state.resize(total)
	_emitting.resize(total)
	_generation.resize(total)
	_effect_of.resize(total)
	_velocity.resize(total)
	_age_s.resize(total)
	_stop_emitting_s.resize(total)
	_busy_s.resize(total)
	for effect: int in FxSpecs.COUNT:
		var spec: Dictionary = FxSpecs.spec(effect)
		for i: int in int(spec["emitters"]):
			_effect_of[_first[effect] + i] = effect
			_nodes.append(_make_emitter("%s%d" % [String(spec["name"]).to_pascal_case(), i], spec))
			add_child(_nodes[-1])


## Starts a burst of `effect` at global `position`, its cone pointing along `direction`, flying on at `velocity` (the
## source's, m/s). `duration_s` is how long a vent keeps emitting. Returns a handle for `stop`, or 0 when nothing was thrown
## (density 0).
func burst(effect: int, position: Vector3, direction: Vector3, velocity: Vector3, duration_s: float = 0.0) -> int:
	var amount: int = FxSpecs.amount_for(effect, density)
	if amount <= 0:
		return 0
	var slot: int = _claim(effect)
	var node: GPUParticles3D = _nodes[slot]
	ShiftableRegistry.set_out(node, WorldFrame.PARKED_META, false)
	node.global_transform = Transform3D(FxSpecs.basis_facing(direction), position)
	node.amount_ratio = FxSpecs.ratio_for(effect, density)
	_velocity[slot] = velocity
	_age_s[slot] = 0.0
	_stop_emitting_s[slot] = duration_s if FxSpecs.spec(effect)["continuous"] else 0.0
	_busy_s[slot] = FxSpecs.busy_s(effect, duration_s)
	_state[slot] = _PENDING
	bursts += 1
	if not is_processing():
		set_process(true)
	return ((_generation[slot] & HANDLE_SLOT_MASK) << 16) | (slot + 1)


## Ends a vent early: no new particles, and the emitter is free once the ones in flight die. A handle from a burst that has since
## finished, or whose emitter another burst took, does nothing.
func stop(handle: int) -> void:
	var slot: int = _slot_of(handle)
	if slot < 0:
		return
	if _state[slot] == _PENDING:
		_release(slot)
		return
	if _state[slot] == _LIVE and _emitting[slot] == 1:
		_nodes[slot].emitting = false
		_emitting[slot] = 0
		_busy_s[slot] = _age_s[slot] + float(FxSpecs.spec(_effect_of[slot])["lifetime_s"])


## Emitters in the pools: a constant.
func emitter_count() -> int:
	return _nodes.size()


## Emitters of `effect`, or all of them.
func emitters_of(effect: int) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	for i: int in int(FxSpecs.spec(effect)["emitters"]):
		out.append(_nodes[_first[effect] + i])
	return out


## The emitters of `effect` that a burst has taken.
func busy_emitters(effect: int) -> Array[GPUParticles3D]:
	var out: Array[GPUParticles3D] = []
	for i: int in int(FxSpecs.spec(effect)["emitters"]):
		if _state[_first[effect] + i] != _IDLE:
			out.append(_nodes[_first[effect] + i])
	return out


## Seconds the busy emitter behind `handle` keeps emitting (0 for a one-shot or a stale handle), and in all how long it stays taken.
func vent_s(handle: int) -> float:
	return _stop_emitting_s[(handle & HANDLE_SLOT_MASK) - 1] if is_live(handle) else 0.0


func taken_s(handle: int) -> float:
	return _busy_s[(handle & HANDLE_SLOT_MASK) - 1] if is_live(handle) else 0.0


## Emitters taken by a burst, of `effect` or (-1) of all.
func busy_count(effect: int = -1) -> int:
	if effect < 0:
		return _busy_count
	var n: int = 0
	for i: int in int(FxSpecs.spec(effect)["emitters"]):
		n += 1 if _state[_first[effect] + i] != _IDLE else 0
	return n


## A velocity rebase by `dv` (`WorldFrame.boosted`): every emitter keeps its universe velocity. Its particles live in its
## own frame, so they follow.
func boost(dv: Vector3) -> void:
	for slot: int in _velocity.size():
		if _state[slot] != _IDLE:
			_velocity[slot] -= dv


## The velocity the emitter behind `handle` flies at, or ZERO for a stale handle.
func velocity_of(handle: int) -> Vector3:
	var slot: int = _slot_of(handle)
	if slot < 0:
		return Vector3.ZERO
	return _velocity[slot]


## True while the emitter behind `handle` is still taken by that burst.
func is_live(handle: int) -> bool:
	var slot: int = _slot_of(handle)
	return slot >= 0 and _state[slot] != _IDLE


## The emitter behind `handle`, or null for a stale one.
func emitter_of(handle: int) -> GPUParticles3D:
	return _nodes[(handle & HANDLE_SLOT_MASK) - 1] if is_live(handle) else null


func _process(delta: float) -> void:
	for slot: int in _nodes.size():
		var state: int = _state[slot]
		if state == _IDLE:
			continue
		var node: GPUParticles3D = _nodes[slot]
		if state == _PENDING:
			node.visible = true
			node.restart()
			_state[slot] = _LIVE
			_emitting[slot] = 1
			continue
		_age_s[slot] += delta
		node.global_position += _velocity[slot] * delta
		var age: float = _age_s[slot]
		if _emitting[slot] == 1 and _stop_emitting_s[slot] > 0.0 and age >= _stop_emitting_s[slot]:
			node.emitting = false
			_emitting[slot] = 0
		if age >= _busy_s[slot]:
			_release(slot)
	if _busy_count == 0:
		set_process(false)


# The emitter slot `handle` names, or -1 when its burst has been replaced.
func _slot_of(handle: int) -> int:
	var slot: int = (handle & HANDLE_SLOT_MASK) - 1
	if slot < 0 or slot >= _nodes.size() or ((handle >> 16) & HANDLE_SLOT_MASK) != (_generation[slot] & HANDLE_SLOT_MASK):
		return -1
	return slot


# A free emitter of `effect`, else the oldest busy one. Its old handle goes stale.
func _claim(effect: int) -> int:
	var count: int = int(FxSpecs.spec(effect)["emitters"])
	var first: int = _first[effect]
	var slot: int = -1
	for i: int in count:
		var candidate: int = first + (_cursor[effect] + i) % count
		if _state[candidate] == _IDLE:
			slot = candidate
			break
	if slot < 0:
		slot = first
		for i: int in count:
			if _age_s[first + i] > _age_s[slot]:
				slot = first + i
		reused += 1
		_busy_count -= 1  # it is counted again below
	_cursor[effect] = (slot - first + 1) % count
	_generation[slot] += 1
	_busy_count += 1
	return slot


func _release(slot: int) -> void:
	if _state[slot] == _IDLE:
		return
	var node: GPUParticles3D = _nodes[slot]
	node.emitting = false
	node.visible = false
	ShiftableRegistry.set_out(node, WorldFrame.PARKED_META, true)  # rebases leave it: `burst` places it (M6-T21)
	_state[slot] = _IDLE
	_emitting[slot] = 0
	_generation[slot] += 1
	_busy_count -= 1
	if _busy_count == 0:
		set_process(false)


func _make_emitter(node_name: String, spec: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.top_level = true
	p.local_coords = true
	p.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	p.set_meta(WorldFrame.PARKED_META, true)  # idle until its first burst places it (M6-T21)
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.amount = int(spec["amount"])
	p.lifetime = float(spec["lifetime_s"])
	p.one_shot = not bool(spec["continuous"])
	p.explosiveness = 0.0 if bool(spec["continuous"]) else 1.0
	p.fixed_fps = 0
	p.emitting = false
	p.visible = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3.ONE * -VISIBILITY_HALF_M, Vector3.ONE * (2.0 * VISIBILITY_HALF_M))
	p.draw_pass_1 = load(String(spec["mesh"])) as Mesh
	p.process_material = load(String(spec["material"])) as ParticleProcessMaterial
	return p


func _on_setting_changed(key: StringName, value: Variant) -> void:
	if key == &"particle_density":
		density = float(value)


func _cmd_fxburst(args: Dictionary) -> ConsoleResult:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return ConsoleResult.failure("no camera to throw the burst in front of")
	var effect: int = -1
	for i: int in FxSpecs.COUNT:
		if FxSpecs.spec(i)["name"] == String(args[&"effect"]):
			effect = i
	var forward: Vector3 = -camera.global_basis.z
	var handle: int = burst(effect, camera.global_position + forward * BURST_DISTANCE_M, -forward, Vector3.ZERO,
			FxSpecs.DEBRIS_MIN_S)
	return ConsoleResult.line("%s burst%s" % [args[&"effect"], "" if handle != 0 else " (density 0: nothing thrown)"])
