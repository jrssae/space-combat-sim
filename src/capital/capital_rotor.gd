class_name CapitalRotor
extends AnimatableBody3D
## One rotating section of a capital ship (M10-T07, D12.4): a kinematic body turned about its pivot on the hull every tick,
## as the station's drum is (§20.1), so Jolt gives its skin the motion it has and ships collide with it. Built from the
## manifest's piece (`pivot`, `axis`, `spin_rad_s`) and its sections' collision, which sit in the piece's own frame.
##
## It is a child of its capital but placed by script in the World (`top_level`), aimed one tick ahead of the hull so the two
## move together through Jolt's step. Its hits and rams are the capital's: its `Damageable` shares the capital's hull points,
## routes its hits to the capital's sections and passes every signal on (the capital's `section_hit` names the section). A
## kinematic body is as heavy as the world to Jolt: a capital that rams another's rotor is stopped as by a wall (known gap
## until a ram resolver takes rotors).

## The hull this rotor belongs to.
var capital: CapitalShip = null
## The piece's name in the manifest, the pivot in the capital's frame, the turn axis (piece frame) and the spin, rad/s.
var piece_name: String = ""
var pivot: Vector3 = Vector3.ZERO
var axis: Vector3 = Vector3.BACK
var spin_rad_s: float = 0.0
## Its turn now, radians.
var angle: float = 0.0
var hull: Damageable = null
## Its sections' collision shapes, and its hit volumes as the core's surface takes them.
var shape_count: int = 0
var packed_volumes := PackedFloat64Array()
var packed_hulls := PackedFloat64Array()
## The picture, on a pivot under the capital turned each frame (interpolated with the hull).
var visual_pivot: Node3D = null


## A rotor for `cap` from manifest piece `entry` (named `p_name`) and its sections' `shapes` and `volumes`.
static func make(cap: CapitalShip, p_name: String, entry: Dictionary, shapes: Array[Dictionary], volumes: Array[HitShape]) -> CapitalRotor:
	var rotor := CapitalRotor.new()
	rotor.name = "Rotor_%s" % p_name.to_pascal_case()
	rotor.capital = cap
	rotor.piece_name = p_name
	rotor.pivot = _vec3(entry.get("pivot", [0.0, 0.0, 0.0]))
	var raw_axis: Vector3 = _vec3(entry.get("axis", [0.0, 0.0, 1.0]))
	rotor.axis = raw_axis.normalized() if raw_axis.length() > 1e-6 else Vector3.BACK
	rotor.spin_rad_s = float(entry.get("spin_rad_s", 0.0))
	rotor.top_level = true
	rotor.sync_to_physics = false  # the script places it each tick: Jolt moves it there with the speed that takes
	rotor.collision_layer = cap.collision_layer
	rotor.collision_mask = cap.collision_mask
	for shape: Dictionary in shapes:
		var node := CollisionShape3D.new()
		node.name = str(shape["name"]).to_pascal_case().validate_node_name()
		node.shape = shape["shape"]
		node.transform = shape["transform"]
		rotor.add_child(node, true)
	rotor.shape_count = shapes.size()
	rotor.packed_volumes = Station.pack_volumes(volumes)
	rotor.packed_hulls = Station.pack_hulls(shapes, volumes)
	var entries: Array[Dictionary] = []
	for v: HitShape in volumes:
		entries.append(Station.volume_entry(v))
	rotor.hull = Damageable.new()
	rotor.hull.name = "Hull"
	rotor.hull.setup(entries, 1.0, cap.faction)
	rotor.add_child(rotor.hull)
	return rotor


func _ready() -> void:
	add_collision_exception_with(capital)
	set_meta(Targetable.SPEAKS_FOR, capital.targetable)  # its shots and hits answer for the capital
	hull.hull = capital.damageable.hull  # one set of hull points for the whole ship
	hull.hit_router = capital.route_hit  # its hits land on its sections (M10-T08)
	hull.ram_mass_kg = capital.mass
	hull.ram_safe_dv_mps = capital.damageable.ram_safe_dv_mps
	hull.ram_lethal_dv_mps = capital.damageable.ram_lethal_dv_mps
	hull.hit_taken.connect(func(info: HitInfo) -> void:
		info.set_meta(CapitalShip.PIECE_META, piece_name)  # the capital names the section on this body
		capital.damageable.hit_taken.emit(info))
	hull.damaged.connect(func(info: HitInfo, applied: float) -> void: capital.damageable.damaged.emit(info, applied))
	hull.destroyed.connect(func(info: HitInfo) -> void: capital.damageable.destroyed.emit(info))
	hull.hits_landed.connect(func(summary: HitSummary) -> void: capital.damageable.hits_landed.emit(summary))


## Where the rotor stands with the hull at `hull_xform` and turned by `turn`, World frame.
func pose_for(hull_xform: Transform3D, turn: float) -> Transform3D:
	return hull_xform * Transform3D(Basis(axis, turn), pivot)


## One tick: turned on by `delta` and aimed where the hull will be after this tick's step.
func step(delta: float) -> void:
	angle = fposmod(angle + spin_rad_s * delta, TAU)
	if is_inside_tree():
		global_transform = pose_for(_hull_ahead(delta), angle)


## Puts the rotor where it belongs now with no motion (spawn, a rebase, back from the tier): moved as a kinematic body it would
## sweep the whole jump and ram whatever it crossed.
func snap() -> void:
	if not is_inside_tree():
		return
	var target: Transform3D = pose_for(capital.global_transform, angle)
	var rid: RID = get_rid()
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, target)
	PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_KINEMATIC)
	global_transform = target
	reset_physics_interpolation()


## The turn as drawn `fraction` of the way through the frame's tick.
func visual_angle(fraction: float) -> float:
	return fposmod(angle + spin_rad_s * (fraction - 1.0) / float(Engine.physics_ticks_per_second), TAU)


# The hull's pose one tick on, from its velocity and spin: where Jolt's step will take it.
func _hull_ahead(delta: float) -> Transform3D:
	var xform: Transform3D = capital.global_transform
	var w: Vector3 = capital.angular_velocity
	var turned: Basis = xform.basis
	if w.length_squared() > 1e-12:
		turned = Basis(w.normalized(), w.length() * delta) * turned
	return Transform3D(turned.orthonormalized(), xform.origin + capital.linear_velocity * delta)


static func _vec3(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO
