class_name VortexTransits
extends Node3D
## Every ship flying a jump vortex's funnel (M6-T22, the maintainer's answers of 2026-11-13), one per World, made on first use.
## Whoever opens a vortex or brings a ship to it (a gate, a jump point, a mission, the encounters, the battle's arrivals, the
## player's jump) hands the ship over here; the rules are `VortexTransit`'s and the scaling `TransitScale`'s.
##
## Arriving (`begin_arrival`): the ship waits on the funnel's base, as good as gone, through its vortex's opening flash (a gate's
## vortex is already open), then comes out at the black ring in a white flash of its own, shrunk to the ring, and flies straight out to its place in the mouth at its speed through the funnel, growing back to its whole size by the mouth. It
## then leaves with the velocity its spawn asked for. Departing (`begin_departure`, from the moment it crosses the mouth): it
## flies on down the axis, shrinking, and when its nose touches the base it vanishes in a white flash and its opener is told.
## In between it is an ordinary ship, scaled: targetable, hittable and colliding, except with the other ships in the same
## funnel (they start together at the ring). An AI pilot is held for the passage (an arriving ship coasts out on its course, a
## departing one is steered down the axis); the player's ship is flown by its jump. A ship in a funnel stays out of the
## low-attention tier, and the vortex stays open until its last ship is through.
##
## The flashes are one multimesh (`MAX_FLASHES` at once, nothing made per flash), so a wave of a hundred points bringing in
## hundreds of ships costs one draw call. It is a rendering-server instance, not a node: each flash is kept in its vortex's frame
## and placed from it every tick, so a rebase moves it with its funnel, and nothing new sits in World space (this node is a bare
## holder at the World's origin and joins no shift group: an extra member would reorder the rebase's walk and the seeded battles'
## sums). Console: provider `transit`.

const NODE_NAME: StringName = &"VortexTransits"
const FLASH_SHADER: Shader = preload("res://src/props/transit_flash.gdshader")
const MAX_FLASHES: int = 256
## Each tick a ship is in its funnel the vortex is kept open for the rest of its passage plus this.
const KEEP_OPEN_S: float = 0.3
## The ships whose shapes and hit volumes may be rebuilt to their scale in one tick (`TransitScale`); the rest wait their turn.
const COLLISION_STEPS_PER_TICK: int = 6
## A passage taking this many times its planned time (or a departure this long) is ended anyway: something stopped the ship.
const STALL_FACTOR: float = 3.0
const DEPARTURE_LIMIT_S: float = 30.0

## Passages begun and finished (arrivals out of the mouth, departures through the ring), and flashes shown, so far.
var arrivals_begun: int = 0
var arrivals_done: int = 0
var departures_begun: int = 0
var departures_done: int = 0
var flashes_shown: int = 0
## Arrivals too small on screen to fly their passage (`VortexTransit.worth_flying`): placed as before, with the ring's flash.
var arrivals_unseen: int = 0
## The last tick's own cost, us, and the worst so far: a profiling readout, never gameplay time.
var step_us: int = 0
var worst_step_us: int = 0

var _passages: Array[VortexPassage] = []
var _steps_left: int = 0  # this tick's shape rebuilds still allowed
var _by_body: Dictionary = {}  # body -> VortexPassage
var _flash_mesh: QuadMesh = null  # the rendering-server multimesh's mesh and material, kept alive with it
var _flash_material: ShaderMaterial = null
var _flash_multimesh := RID()
var _flash_instance := RID()
var _flash_shown: bool = false
var _flash_vortex: Array[JumpVortex] = []  # each flash's vortex, which it moves with
var _flash_at := PackedVector3Array()  # in its vortex's frame
var _flash_radius := PackedFloat32Array()
var _flash_age := PackedFloat32Array()
var _flash_colour := PackedColorArray()
var _world: WorldFrame = null


## The transits of `world`, or null.
static func of(world: Node) -> VortexTransits:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as VortexTransits


## The transits of `world`, made on first use.
static func attach(world: Node) -> VortexTransits:
	var found: VortexTransits = of(world)
	if found != null or world == null or not is_instance_valid(world):
		return found
	var made := VortexTransits.new()
	made.name = NODE_NAME
	world.add_child(made)
	return made


## The transits of the World `node` is in (null outside one).
static func for_node(node: Node) -> VortexTransits:
	var at: Node = node
	while at != null and not (at is WorldFrame):
		at = at.get_parent()
	return attach(at)


func _ready() -> void:
	_world = get_parent() as WorldFrame
	_build_flashes()
	_sync_processing()
	_register_console()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _flash_instance.is_valid():
		RenderingServer.free_rid(_flash_instance)
	if _flash_multimesh.is_valid():
		RenderingServer.free_rid(_flash_multimesh)
	_flash_instance = RID()
	_flash_multimesh = RID()


## Brings `body` out of `vortex`: it starts at the ring now, shrunk, and flies out to where it was placed (`exit_position`, World),
## leaving the funnel with `exit_velocity` (World-local, the frame's rest included). A ship too small on screen to see stays at its
## place unless `always` (the player's own). False when it cannot (no such vortex).
func begin_arrival(body: RigidBody3D, vortex: JumpVortex, exit_position: Vector3, exit_velocity: Vector3,
		always: bool = false) -> bool:
	if body == null or vortex == null or not body.is_inside_tree():
		return false
	cancel(body)
	var frame: Transform3D = vortex.true_frame()
	var local: Vector3 = frame.affine_inverse() * exit_position
	if not always and not _seen(body, exit_position):
		# Too small on screen to see it shrink: it stays at its place, and only the ring's flash shows.
		flash(vortex, frame * VortexTransit.arrival_start(vortex.fit, Vector2(local.x, local.y)))
		arrivals_unseen += 1
		return true
	var p: VortexPassage = _start(body, vortex, VortexPassage.Kind.ARRIVAL)
	p.lateral = VortexTransit.clamp_lateral(vortex.fit, Vector2(local.x, local.y))
	var rest: Vector3 = _rest()
	p.exit_velocity_rel = exit_velocity - rest
	if _due(p):
		_emerge(p, frame)
	else:
		_hold(p, frame)
	arrivals_begun += 1
	return true


## Takes `body` on down `vortex`'s funnel from its mouth; `on_through(body)` runs once its nose touches the base (it has vanished
## in the flash by then and is whole again). False when it cannot.
func begin_departure(body: RigidBody3D, vortex: JumpVortex, on_through: Callable) -> bool:
	if body == null or vortex == null or not body.is_inside_tree():
		return false
	cancel(body)
	var p: VortexPassage = _start(body, vortex, VortexPassage.Kind.DEPARTURE)
	p.on_through = on_through
	p.limit_s = DEPARTURE_LIMIT_S
	var axis: Vector3 = vortex.true_frame().basis.z.normalized()
	p.speed_mps = VortexTransit.transit_speed(vortex.fit.depth_m, (body.linear_velocity - _rest()).dot(axis))
	var ship := body as Ship
	if p.driver != null and ship != null and ship.spec != null:
		p.capability = ShipCapability.from_spec(ship.spec, ship.get_layout())
	departures_begun += 1
	return true


## Ends `body`'s passage now, whole again and its pilot let go (a scene change, a cancelled jump). Nothing when it has none.
func cancel(body: Node) -> void:
	var p: VortexPassage = _by_body.get(body)
	if p != null:
		_end(p)


## Ends `body`'s departure now (its opener changed its mind), leaving an arrival under way alone.
func cancel_departure(body: Node) -> void:
	var p: VortexPassage = _by_body.get(body)
	if p != null and p.kind == VortexPassage.Kind.DEPARTURE:
		_end(p)


## The bodies in `vortex`'s funnel now, arriving or departing (M6-T23).
func bodies_in(vortex: JumpVortex) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for p: VortexPassage in _passages:
		if p.vortex == vortex and is_instance_valid(p.body):
			out.append(p.body)
	return out


## Destroys every ship in `vortex`'s funnel (its point collapsed, M6-T23): no shooter, no kill credit. Returns how many died.
func kill_in(vortex: JumpVortex) -> int:
	var killed: int = 0
	for body: RigidBody3D in bodies_in(vortex):
		var damageable: Damageable = Damageable.of(body)
		if damageable != null and body.is_inside_tree() and damageable.kill(HitInfo.CAUSE_VORTEX_COLLAPSE):
			killed += 1
		cancel(body)
	return killed


## Whether `body` is in a funnel now.
func is_passing(body: Node) -> bool:
	return _by_body.has(body)


## The scale `body` is drawn at now (1 when it is in no funnel).
func scale_of(body: Node) -> float:
	var p: VortexPassage = _by_body.get(body)
	return p.scaler.scale if p != null else 1.0


## Ships in funnels now, and flashes showing.
func count() -> int:
	return _passages.size()


func flash_count() -> int:
	return _flash_age.size()


## Shows a ship's white flash at `at` (World) in `vortex`, sized to its ring and in its flash colour; it stays with the vortex.
func flash(vortex: JumpVortex, at: Vector3) -> void:
	flashes_shown += 1
	if _flash_age.size() >= MAX_FLASHES:
		return  # the oldest still fading keeps its slot; this one is lost in the crowd
	_flash_vortex.append(vortex)
	_flash_at.append(vortex.true_frame().affine_inverse() * at)
	_flash_radius.append(VortexTransit.flash_radius_m(vortex.fit))
	_flash_age.append(0.0)
	_flash_colour.append(vortex.flash_colour)
	_sync_processing()


func _physics_process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()  # profiling readout only
	_steps_left = COLLISION_STEPS_PER_TICK
	for i: int in range(_passages.size() - 1, -1, -1):
		if i < _passages.size():
			_step(_passages[i], delta)
	_step_flashes(delta)
	_sync_processing()
	step_us = Time.get_ticks_usec() - started
	worst_step_us = maxi(worst_step_us, step_us)


# One tick of one passage.
func _step(p: VortexPassage, delta: float) -> void:
	var body: RigidBody3D = p.body
	if not is_instance_valid(body) or not body.is_inside_tree() or not body.is_visible_in_tree() \
			or not is_instance_valid(p.vortex) or _destroyed(body):
		_end(p)  # gone back to its pool, destroyed or parked: whole again for its next life
		return
	p.age_s += delta
	var fit: VortexFit = p.vortex.fit
	var frame: Transform3D = p.vortex.true_frame()
	if p.kind == VortexPassage.Kind.ARRIVAL and not p.emerged:
		if not _due(p):
			_hold(p, frame)  # the point may widen for the rest of its group meanwhile
			return
		_emerge(p, frame)
	var local: Vector3 = frame.affine_inverse() * body.global_position
	var factor: float = VortexTransit.scale_at(fit, local.z, p.lateral_radius_m)
	if p.scaler.apply(factor, _steps_left > 0):
		_steps_left -= 1
	var left_m: float = maxf(local.z, 0.0) if p.kind == VortexPassage.Kind.ARRIVAL else maxf(fit.depth_m - local.z, 0.0)
	p.vortex.extend(left_m / maxf(p.speed_mps, 1.0) + KEEP_OPEN_S)
	if p.kind == VortexPassage.Kind.ARRIVAL:
		if (local.z <= 0.0 and factor >= 1.0) or p.age_s > p.limit_s:
			body.linear_velocity = _rest() + p.exit_velocity_rel
			arrivals_done += 1
			_end(p)
		return
	if p.capability != null and body is Ship:
		var axis: Vector3 = frame.basis.z.normalized()
		var ship := body as Ship
		ship.set_flight_command(GateAutopilot.follow_axis(ship.global_position, ship.linear_velocity - _rest(), ship.global_basis,
				frame.origin, axis, frame.basis.y, p.speed_mps, p.capability))
	if VortexTransit.reached_base(fit, local.z, p.bounding_radius_m * factor) or p.age_s > p.limit_s:
		flash(p.vortex, body.global_position)
		if p.vortex.opener == body and p.vortex.held:
			p.vortex.opener_through_at_s = SimClock.now()  # its own point holds a moment for the ships behind it (M6-T23)
			p.vortex.extend(JumpCapability.OWN_DEPARTURE_HOLD_S + KEEP_OPEN_S)
		var on_through: Callable = p.on_through
		departures_done += 1
		_end(p)
		if on_through.is_valid():
			on_through.call(body)


# The passage's start: the body scaled, held and kept out of the tier, exempt from its funnel's other ships.
func _start(body: RigidBody3D, vortex: JumpVortex, kind: VortexPassage.Kind) -> VortexPassage:
	var p := VortexPassage.new()
	p.kind = kind
	p.body = body
	p.vortex = vortex
	p.scaler = TransitScale.new(body)
	var damageable: Damageable = Damageable.of(body)
	if damageable != null and damageable.bounding_radius > 0.0:
		p.lateral_radius_m = VortexTransit.lateral_radius(damageable.ram_bounds)
		p.bounding_radius_m = damageable.bounding_radius
	else:
		p.lateral_radius_m = 10.0
		p.bounding_radius_m = 10.0
	if &"tier_exempt" in body:  # a pooled ship or a capital stand-in
		p.tier_exempt_was = bool(body.get(&"tier_exempt"))
		body.set(&"tier_exempt", true)
	for child: Node in body.get_children():
		if child is AiPilotDriver and (child as AiPilotDriver).brain != null:
			p.driver = child as AiPilotDriver
	if p.driver != null:
		p.driver.in_passage = true
		if p.driver.combatant != null:
			p.driver.combatant.apply_commands(FlightCommand.new(), CombatCommand.new())
	for other: VortexPassage in _passages:
		if other.vortex == vortex and is_instance_valid(other.body):
			body.add_collision_exception_with(other.body)
			other.body.add_collision_exception_with(body)
			p.exempt.append(other.body)
			other.exempt.append(body)
	vortex.passing += 1
	_passages.append(p)
	_by_body[body] = p
	_sync_processing()
	return p


# Whether an arriving ship comes out now: once its vortex's opening flash has faded and the funnel has begun to unfold from the
# base (`VortexTransit.emerge_age_s`), so the ring's own flash is seen apart from it and the ship stays inside the drawn funnel.
func _due(p: VortexPassage) -> bool:
	var vortex: JumpVortex = p.vortex
	return not vortex.is_active() or vortex.direction != JumpVortex.Direction.ARRIVAL \
			or vortex.age_s >= VortexTransit.emerge_age_s(vortex.timing.lead_s)


# Waits "in hyperspace" until it is due: on the base, as good as gone (`VortexTransit.HELD_SCALE`), at rest in the vortex's frame,
# hidden in the vortex's own flash.
func _hold(p: VortexPassage, frame: Transform3D) -> void:
	var body: RigidBody3D = p.body
	var at: Vector3 = frame * VortexTransit.arrival_start(p.vortex.fit, p.lateral)
	if p.scaler.scale == VortexTransit.HELD_SCALE and body.global_position.distance_to(at) < 0.5:
		return  # at rest where it waits
	var xform := Transform3D(body.global_basis, at)
	if body is Ship:
		(body as Ship).reset_to(xform)
	else:
		body.global_transform = xform
		body.angular_velocity = Vector3.ZERO
	body.linear_velocity = _rest()
	p.scaler.apply(VortexTransit.HELD_SCALE)
	body.reset_physics_interpolation()


# Comes out: on the base at the ring in its white flash, shrunk to the ring, heading out along its line to its place in the mouth.
func _emerge(p: VortexPassage, frame: Transform3D) -> void:
	var fit: VortexFit = p.vortex.fit
	var start: Vector3 = VortexTransit.arrival_start(fit, p.lateral)
	var out: Vector3 = VortexTransit.arrival_exit(fit, p.lateral) - start
	p.speed_mps = VortexTransit.transit_speed(out.length(), p.exit_velocity_rel.length())
	p.limit_s = p.age_s + STALL_FACTOR * out.length() / maxf(p.speed_mps, 1.0)
	p.emerged = true
	var at: Vector3 = frame * start
	var body: RigidBody3D = p.body
	var xform := Transform3D(body.global_basis, at)
	if body is Ship:
		(body as Ship).reset_to(xform)
	else:
		body.global_transform = xform
		body.angular_velocity = Vector3.ZERO
	body.linear_velocity = _rest() + frame.basis * out.normalized() * p.speed_mps
	p.scaler.apply(VortexTransit.scale_at(fit, fit.depth_m, p.lateral_radius_m))
	body.reset_physics_interpolation()  # no blend from where it waited, or from its held size
	flash(p.vortex, at)


# The passage's end: the body whole, its pilot let go, back in the tier's reach, colliding with everything again.
func _end(p: VortexPassage) -> void:
	_passages.erase(p)
	_by_body.erase(p.body)
	if is_instance_valid(p.vortex):
		p.vortex.passing = maxi(p.vortex.passing - 1, 0)
	p.scaler.restore()
	var body: RigidBody3D = p.body if is_instance_valid(p.body) else null
	for other: RigidBody3D in p.exempt:
		if body != null and is_instance_valid(other):
			body.remove_collision_exception_with(other)
			other.remove_collision_exception_with(body)
			var theirs: VortexPassage = _by_body.get(other)
			if theirs != null:
				theirs.exempt.erase(body)
	p.exempt.clear()
	if body != null and &"tier_exempt" in body:
		body.set(&"tier_exempt", p.tier_exempt_was)
	if p.driver != null and is_instance_valid(p.driver):
		p.driver.in_passage = false


func _step_flashes(delta: float) -> void:
	var i: int = 0
	while i < _flash_age.size():
		_flash_age[i] += delta
		if VortexTransit.flash_level(_flash_age[i]) <= 0.0 or not is_instance_valid(_flash_vortex[i]):
			var last: int = _flash_age.size() - 1
			_flash_vortex[i] = _flash_vortex[last]
			_flash_at[i] = _flash_at[last]
			_flash_radius[i] = _flash_radius[last]
			_flash_age[i] = _flash_age[last]
			_flash_colour[i] = _flash_colour[last]
			_flash_vortex.resize(last)
			_flash_at.resize(last)
			_flash_radius.resize(last)
			_flash_age.resize(last)
			_flash_colour.resize(last)
			continue
		i += 1
	if not _flash_multimesh.is_valid():
		return
	for k: int in _flash_age.size():
		var level: float = VortexTransit.flash_level(_flash_age[k])
		var size: float = _flash_radius[k] * maxf(sqrt(level), 1e-3)
		var at: Vector3 = _flash_vortex[k].true_frame() * _flash_at[k]
		RenderingServer.multimesh_instance_set_transform(_flash_multimesh, k,
				Transform3D(Basis.from_scale(Vector3.ONE * size), at))
		var c: Color = _flash_colour[k]
		c.a = level
		RenderingServer.multimesh_instance_set_color(_flash_multimesh, k, c)
	RenderingServer.multimesh_set_visible_instances(_flash_multimesh, _flash_age.size())
	var shown: bool = not _flash_age.is_empty()
	if shown != _flash_shown:
		_flash_shown = shown
		RenderingServer.instance_set_visible(_flash_instance, shown)


func _build_flashes() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	var material := ShaderMaterial.new()
	material.shader = FLASH_SHADER
	material.set_shader_parameter(&"tint", Vector3(3.0, 3.0, 3.0))
	material.set_shader_parameter(&"lift", 0.0)
	material.render_priority = 1  # after the funnels it sits in (all flashes share one far-reaching box, so sorting cannot tell)
	_flash_mesh = quad
	_flash_material = material
	_flash_multimesh = RenderingServer.multimesh_create()
	RenderingServer.multimesh_allocate_data(_flash_multimesh, MAX_FLASHES, RenderingServer.MULTIMESH_TRANSFORM_3D, true)
	RenderingServer.multimesh_set_mesh(_flash_multimesh, quad.get_rid())
	RenderingServer.multimesh_set_visible_instances(_flash_multimesh, 0)
	# Flashes are placed in global coordinates every tick, so the instance sits at the identity.
	_flash_instance = RenderingServer.instance_create2(_flash_multimesh, get_world_3d().scenario)
	RenderingServer.instance_geometry_set_material_override(_flash_instance, material.get_rid())
	RenderingServer.instance_geometry_set_cast_shadows_setting(_flash_instance, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	RenderingServer.instance_set_custom_aabb(_flash_instance, AABB(-Vector3.ONE * 1.0e6, Vector3.ONE * 2.0e6))  # anywhere in play
	RenderingServer.instance_set_visible(_flash_instance, false)


# Whether `body` at `at` is big enough on the viewport's camera to fly its passage (always, with no camera).
func _seen(body: RigidBody3D, at: Vector3) -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return true
	var damageable: Damageable = Damageable.of(body)
	var radius: float = damageable.bounding_radius if damageable != null and damageable.bounding_radius > 0.0 else 10.0
	var px: float = VortexLod.px_per_unit(camera.fov, get_viewport().get_visible_rect().size.y)
	return VortexTransit.worth_flying(radius, camera.global_position.distance_to(at), px)


func _rest() -> Vector3:
	return _world.rest_velocity() if _world != null and is_instance_valid(_world) else Vector3.ZERO


static func _destroyed(body: Node) -> bool:
	var damageable: Damageable = Damageable.of(body)
	return damageable != null and damageable.hull != null and damageable.hull.destroyed


# Ticks only while a ship is in a funnel or a flash shows.
func _sync_processing() -> void:
	set_physics_process(not _passages.is_empty() or not _flash_age.is_empty())


func _register_console() -> void:
	DebugConsole.registry.register_provider(&"transit", ConsoleVars.new({
		&"passing": {"get": func() -> int: return _passages.size(), "doc": "Ships flying a jump vortex's funnel now (M6-T22)"},
		&"arrivals": {"get": func() -> int: return arrivals_begun, "doc": "Ships brought out of a funnel so far"},
		&"arrived": {"get": func() -> int: return arrivals_done, "doc": "Ships out of a funnel's mouth at their whole size so far"},
		&"unseen": {"get": func() -> int: return arrivals_unseen,
				"doc": "Arrivals too small on screen to fly their passage, placed at once with the ring's flash"},
		&"departures": {"get": func() -> int: return departures_begun, "doc": "Ships taken down a funnel so far"},
		&"departed": {"get": func() -> int: return departures_done, "doc": "Ships gone through a funnel's ring so far"},
		&"flashes": {"get": func() -> int: return _flash_age.size(), "doc": "Ring flashes showing now"},
		&"flashes_shown": {"get": func() -> int: return flashes_shown, "doc": "Ring flashes shown so far"},
		&"step_us": {"get": func() -> int: return step_us, "unit": "us", "doc": "The last tick's cost of every passage and flash (profiling)"},
		&"worst_step_us": {"get": func() -> int: return worst_step_us, "unit": "us", "doc": "The worst tick's cost so far (profiling)"},
	}), self)
