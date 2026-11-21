class_name CapitalStandin
extends CapitalBody
## A capital ship stand-in for the battle benchmark (M4-T07, Q19, Q22): bench-only, built by code with no assets, replaced by
## M12's capital ships. A box hull 300 m (cruiser), 600 m (destroyer) or 1 200 m (carrier) long with a `Targetable` of kind
## capital and a `Damageable` (hull points only), cruising on a fixed heading, with its gun turrets and interceptors as
## `TurretStandin` children and its two beam lasers as `BeamStandin` children (M4-T12). It costs the tick what a big body costs Jolt, the scan and every broad phase; `StandinDirector`
## steps its engines and turrets.
##
## M12-T19: the class `strike_carrier` is the first real hull: the raiders' strike carrier, drawn and collided from its generated
## asset (`CompoundCollision`), with its numbers in a `ShipSpec`, no weapons, a `CarrierDock` for its fighters and a helm that
## turns it (`heading`). It rides this class until it moves onto `CapitalShip` (M10-T07); what every capital shares is
## `CapitalBody`.
##
## Newtonian like every body (§15.16): no damping; gravity pulls it like any mover (D66, M6-T07), and the engines hold the
## cruise velocity with a force each tick that also holds off that pull.

const CRUISE_MPS: float = 30.0
## How fast the engines bring the velocity back to cruise, s, and the most they can push, m/s^2.
const CRUISE_RESPONSE_S: float = 5.0
const MAX_ACCEL_MPS2: float = 2.0
const INTERCEPTORS_PER_CAPITAL: int = 4
const BEAMS_PER_CAPITAL: int = 2
## Where a carrier's launches leave from: this far below its keel, m.
const BAY_DROP_M: float = 40.0
## Per class: the hull box (m), mass (kg), hull points, gun turrets (the milestone's table), whether it can open a jump point
## and how far from the point's mouth it holds it, m (M6-T23: every capital stand-in can; 0 takes twice its length).
const CLASSES: Dictionary = {
	&"cruiser": {"length": 300.0, "width": 60.0, "height": 40.0, "mass": 5.0e6, "hull": 2.0e4, "turrets": 8,
			"can_open_jump_point": true, "jump_hold_range_m": 0.0},
	&"destroyer": {"length": 600.0, "width": 110.0, "height": 70.0, "mass": 2.0e7, "hull": 5.0e4, "turrets": 10,
			"can_open_jump_point": true, "jump_hold_range_m": 0.0},
	&"carrier": {"length": 1200.0, "width": 220.0, "height": 140.0, "mass": 8.0e7, "hull": 1.2e5, "turrets": 12,
			"can_open_jump_point": true, "jump_hold_range_m": 0.0},
	# The raiders' strike carrier (M12-T19): its box is the generated hull's, its other numbers its `ShipSpec`'s.
	&"strike_carrier": {"length": 112.0, "width": 85.5, "height": 84.3, "mass": 1.35e7, "hull": 1.0e4, "turrets": 0,
			"can_open_jump_point": true, "jump_hold_range_m": 0.0, "spec": "res://assets/ships/raider_strike_carrier.tres"},
}
const STRIKE_CARRIER: StringName = &"strike_carrier"
## The helm brings the turn rate to what is asked within this long, s.
const HELM_RESPONSE_S: float = 2.0
const HULL_COLOR: Color = Color(0.42, 0.44, 0.47)
## The generated hulls (M4-T27) and the looks a capital can take: the bench's plain box or the class's textured hull (M4-T30d).
const HULLS_ASSET: String = "capital_hulls"
const LOOK_BOX: StringName = &"box"
const LOOK_MESH: StringName = &"mesh"

var ship_class: StringName = &"cruiser"

## Its docking cradles (M12-T19), null for a hull with none.
var dock: CarrierDock = null
## The way the helm turns the bow, World frame; zero: it holds no heading (the bench's capitals never turn).
var heading: Vector3 = Vector3.ZERO
## How the hull is drawn: the plain box, or the generated class's textured hull (`set_look`).
var look: StringName = LOOK_BOX

var _guns: Array[TurretStandin] = []
var _interceptors: Array[TurretStandin] = []
var _beams: Array[BeamStandin] = []
var _hull_mesh: MeshInstance3D = null
var _piece: RenderPiece = null

# The shared hull material and each class's box mesh.
static var _materials: Dictionary = {}


## A capital of `cls` for `p_faction`, called `display_name`, holding `velocity`. Add it to the tree (`WorldFrame.spawn`).
static func create(cls: StringName, p_faction: StringName, display_name: String, velocity: Vector3) -> CapitalStandin:
	var cap := CapitalStandin.new()
	cap.ship_class = cls if CLASSES.has(cls) else &"cruiser"
	cap.jump_drive.recharge_s = CapitalData.jump_recharge_s(cap.ship_class)
	cap.faction = p_faction
	cap.cruise_velocity = velocity
	cap.linear_velocity = velocity
	cap.name = display_name.replace(" ", "_")
	cap._build(display_name)
	return cap


## The hull box's half extents in its own frame (width, height, length), m.
func half_extents() -> Vector3:
	var spec: Dictionary = CLASSES[ship_class]
	return 0.5 * Vector3(float(spec["width"]), float(spec["height"]), float(spec["length"]))


## The radius of the sphere that holds the hull of a `cls` capital, m.
static func hull_radius(cls: StringName) -> float:
	var spec: Dictionary = CLASSES.get(cls, CLASSES[&"cruiser"])
	return 0.5 * Vector3(float(spec["width"]), float(spec["height"]), float(spec["length"])).length()


func length_m() -> float:
	return float((CLASSES[ship_class] as Dictionary)["length"])


## Whether this class can open a jump point (M6-T23, `JumpCapability`).
func can_open_jump_point() -> bool:
	if spec != null:
		return spec.can_open_jump_point
	return bool((CLASSES[ship_class] as Dictionary).get("can_open_jump_point", false))


## How far from its point's mouth it holds the point open, m.
func jump_hold_range_m() -> float:
	var anchor_m: float = (jump_anchor["position"] as Vector3).length() if not jump_anchor.is_empty() else 0.0
	if spec != null:
		return JumpCapability.hold_range_m(length_m(), spec.jump_hold_range_m, anchor_m)
	return JumpCapability.hold_range_m(length_m(), float((CLASSES[ship_class] as Dictionary).get("jump_hold_range_m", 0.0)), anchor_m)


## The radius across its nose, m: what its own jump point is sized for (it comes out nose first).
func cross_radius_m() -> float:
	var spec: Dictionary = CLASSES[ship_class]
	return 0.5 * Vector2(float(spec["width"]), float(spec["height"])).length()


func guns() -> Array[TurretStandin]:
	return _guns


func interceptors() -> Array[TurretStandin]:
	return _interceptors


func beams() -> Array[BeamStandin]:
	return _beams


## Whether it launches fighters (a carrier).
func is_carrier() -> bool:
	return ship_class == &"carrier"


## Where a launched fighter leaves from, World frame.
func bay_position() -> Vector3:
	var spec: Dictionary = CLASSES[ship_class]
	return global_position - global_basis.y * (float(spec["height"]) * 0.5 + BAY_DROP_M)


## The force the engines apply this tick: back toward the cruise velocity, plus what holds off the environment's pull.
func cruise_force(delta: float) -> Vector3:
	var wanted: Vector3 = (cruise_velocity - linear_velocity) / maxf(CRUISE_RESPONSE_S, delta)
	var pull: Vector3 = world.environment_accel(global_position) if world != null and is_instance_valid(world) else Vector3.ZERO
	return mass * (wanted - pull).limit_length(max_accel_mps2())


## The most its engines push, m/s^2: its spec's thrust over its mass, or the bench's figure.
func max_accel_mps2() -> float:
	return spec.pod_main_thrust / maxf(mass, 1.0) if spec != null and spec.pod_main_thrust > 0.0 else MAX_ACCEL_MPS2


## The torque the helm applies this tick, World frame: toward `heading` at up to its spec's turn rate, zero with no heading
## to hold and no spin to stop.
func helm_torque(delta: float) -> Vector3:
	if spec == null:
		return Vector3.ZERO
	var rate_max: float = deg_to_rad(spec.rate_max.y)
	var wanted: Vector3 = CarrierTactics.turn_rate(-global_basis.z, heading, rate_max)
	var inverse: Basis = get_inverse_inertia_tensor()
	if inverse.x.length() * inverse.y.length() * inverse.z.length() == 0.0:
		return Vector3.ZERO  # not in Jolt yet
	var torque: Vector3 = inverse.inverse() * ((wanted - angular_velocity) / maxf(HELM_RESPONSE_S, delta))
	return torque.limit_length(spec.rcs_torque_max.y)


## One tick of the engines and of the pull they hold off (forces are re-applied every tick).
func step_engines(delta: float) -> void:
	var force: Vector3 = cruise_force(delta)
	var pull: Vector3 = world.environment_accel(global_position) if world != null and is_instance_valid(world) else Vector3.ZERO
	if pull != Vector3.ZERO:
		force += mass * pull
	apply_central_force(force)
	if spec != null:
		apply_torque(helm_torque(delta))


func _build(display_name: String) -> void:
	var spec: Dictionary = CLASSES[ship_class]
	var size := Vector3(float(spec["width"]), float(spec["height"]), float(spec["length"]))
	mass = float(spec["mass"])
	if spec.has("spec") and _build_hull(display_name, String(spec["spec"])):
		return
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.name = "Hull"
	shape.shape = box
	add_child(shape)
	var hull_mesh := MeshInstance3D.new()
	hull_mesh.name = "HullMesh"
	hull_mesh.mesh = _box_mesh(ship_class, size)
	add_child(hull_mesh)
	_hull_mesh = hull_mesh
	targetable = Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = display_name
	targetable.faction = faction
	targetable.kind = Targetable.Kind.CAPITAL
	add_child(targetable)
	damageable = Damageable.new()
	damageable.name = "Damageable"
	add_child(damageable)
	var collision: Array[Dictionary] = [{"name": "hull", "shape": box, "transform": Transform3D.IDENTITY}]
	damageable.setup(collision, float(spec["hull"]), faction)
	_add_turrets(size, int(spec["turrets"]))


# A real hull from its generated asset (M12-T19): its mesh, its compound collision, its hit volumes, its hull points and its
# cradles; no weapons. False when the asset or its spec is missing (the class's plain box is built instead).
func _build_hull(display_name: String, spec_path: String) -> bool:
	var loaded: ShipSpec = load(spec_path) as ShipSpec if ResourceLoader.exists(spec_path) else null
	if loaded == null:
		return false
	var manifest: Dictionary = MeshAssets.read_manifest(loaded.asset_id)
	var section: Dictionary = manifest.get("collision", {}) if manifest.get("collision") is Dictionary else {}
	var solids: Array[Dictionary] = CompoundCollision.solids(section)
	var mesh: Mesh = MeshAssets.for_asset(loaded.asset_id) if not solids.is_empty() else null
	if mesh == null:
		push_warning("CapitalStandin: %s is not generated (run scripts/gen_assets.sh, then import); a plain box stands in" % loaded.asset_id)
		return false
	spec = loaded
	mass = spec.mass
	for solid: Dictionary in solids:
		var shape := CollisionShape3D.new()
		shape.name = "%s_%s" % [solid["piece"], solid["name"]]
		shape.shape = solid["shape"]
		shape.transform = solid["transform"]
		add_child(shape)
	var hull_mesh := MeshInstance3D.new()
	hull_mesh.name = "HullMesh"
	hull_mesh.mesh = mesh
	add_child(hull_mesh)
	_hull_mesh = hull_mesh
	targetable = Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = display_name
	targetable.faction = faction
	targetable.kind = Targetable.Kind.CAPITAL
	add_child(targetable)
	damageable = Damageable.new()
	damageable.name = "Damageable"
	damageable.ram_safe_dv_mps = spec.ram_safe_dv_mps
	damageable.ram_lethal_dv_mps = spec.ram_lethal_dv_mps
	add_child(damageable)
	damageable.setup(CompoundCollision.hit_volumes(section), spec.hull_max, faction)
	var text: String = FileAccess.get_file_as_string(spec.hardpoints_path())
	var hardpoints: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if hardpoints is Dictionary:
		var anchor: Variant = (hardpoints as Dictionary).get("jump_point")
		if anchor is Dictionary and (anchor as Dictionary).get("position") is Array and ((anchor as Dictionary)["position"] as Array).size() == 3:
			var at: Array = (anchor as Dictionary)["position"]
			jump_anchor = {"position": Vector3(float(at[0]), float(at[1]), float(at[2])),
					"mouth_radius_m": float((anchor as Dictionary).get("mouth_radius_m", 0.0))}
		var cradles: CarrierCradles = CarrierCradles.from_hardpoints((hardpoints as Dictionary).get("cradles", []))
		if cradles.count() > 0:
			dock = CarrierDock.new()
			dock.name = "Dock"
			dock.setup(cradles)
			add_child(dock)
	return true


# Guns along the spine, alternately on top and underneath so the two halves cover the whole sphere; interceptors at the
# four corners of the beam; the beam lasers at the bow.
func _add_turrets(size: Vector3, count: int) -> void:
	var rows: int = maxi(1, ceili(count / 2.0))
	for i: int in count:
		var row: int = i / 2
		var along: float = lerpf(-0.4, 0.4, float(row) / float(maxi(rows - 1, 1))) * size.z
		var above: float = (size.y * 0.5 + 3.0) * (1.0 if i % 2 == 0 else -1.0)
		_guns.append(_turret(TurretStandin.Role.GUN, Vector3(0.0, above, along), "Gun%d" % i))
	for i: int in INTERCEPTORS_PER_CAPITAL:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var end: float = 0.35 if i < 2 else -0.35
		_interceptors.append(_turret(TurretStandin.Role.INTERCEPTOR, Vector3(side * (size.x * 0.5 + 3.0), 0.0, end * size.z),
				"Interceptor%d" % i))
	# Beam lasers either side of the bow, on top.
	for i: int in BEAMS_PER_CAPITAL:
		var beam := BeamStandin.new()
		beam.name = "Beam%d" % i
		beam.capital = self
		beam.position = Vector3((0.25 if i % 2 == 0 else -0.25) * size.x, size.y * 0.5 + 2.0, -0.45 * size.z)
		add_child(beam)
		_beams.append(beam)


## Draws the hull as the plain box (the bench's) or as the generated class's textured hull (M4-T30d; any other look is the hull).
## The hull piece is built the first time it is asked for; without the generated asset the box stays.
func set_look(value: StringName) -> void:
	if value != LOOK_BOX:
		value = LOOK_MESH
	if value != LOOK_BOX and _piece == null:
		var manifest: Dictionary = MeshAssets.read_manifest(HULLS_ASSET)
		var entry: Dictionary = (manifest.get("classes", {}) as Dictionary).get(String(ship_class), {})
		if entry.is_empty():
			value = LOOK_BOX
		else:
			_piece = RenderPiece.new()
			_piece.name = "HullPiece"
			_piece.build(ShipSpec.ASSET_ROOT.path_join(HULLS_ASSET), entry)
			add_child(_piece)
	look = value
	if _hull_mesh != null:
		_hull_mesh.visible = look == LOOK_BOX
	if _piece != null:
		_piece.visible = look != LOOK_BOX


## The mesh the hull is drawn with now (the class's box or its textured hull): what its far proxy draws (M4-T23).
func drawn_mesh() -> Mesh:
	if look != LOOK_BOX and _piece != null and _piece.mesh() != null:
		return _piece.mesh()
	return _hull_mesh.mesh if _hull_mesh != null else null


## The hull piece, once a look other than the box was asked for.
func hull_piece() -> RenderPiece:
	return _piece


func _turret(role: TurretStandin.Role, at: Vector3, turret_name: String) -> TurretStandin:
	var turret := TurretStandin.new()
	turret.name = turret_name
	turret.role = role
	turret.position = at
	turret.capital = self
	add_child(turret)
	return turret


# One box per class, so every capital of a class shares its mesh (its far proxy is one multimesh per mesh, M4-T23).
static func _box_mesh(cls: StringName, size: Vector3) -> BoxMesh:
	var key := StringName("box_%s" % cls)
	if not _materials.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = _material()
		_materials[key] = mesh
	return _materials[key]


static func _material() -> StandardMaterial3D:
	if not _materials.has(&"hull"):
		var m := StandardMaterial3D.new()
		m.albedo_color = HULL_COLOR
		m.roughness = 0.8
		_materials[&"hull"] = m
	return _materials[&"hull"]
