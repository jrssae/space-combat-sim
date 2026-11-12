class_name CapitalStandin
extends RigidBody3D
## A capital ship stand-in for the battle benchmark (M4-T07, Q19, Q22): bench-only, built by code with no assets, replaced by
## M12's capital ships. A box hull 300 m (cruiser), 600 m (destroyer) or 1 200 m (carrier) long with a `Targetable` of kind
## capital and a `Damageable` (hull points only), cruising on a fixed heading, with its gun turrets and interceptors as
## `TurretStandin` children and its two beam lasers as `BeamStandin` children (M4-T12). It costs the tick what a big body costs Jolt, the scan and every broad phase; `StandinDirector`
## steps its engines and turrets.
##
## Newtonian like every body (§15.16): no damping, and the engines hold the cruise velocity with a force each tick that also
## holds off the environment's pull (the gravity stand-in).

const CRUISE_MPS: float = 30.0
## How fast the engines bring the velocity back to cruise, s, and the most they can push, m/s^2.
const CRUISE_RESPONSE_S: float = 5.0
const MAX_ACCEL_MPS2: float = 2.0
const INTERCEPTORS_PER_CAPITAL: int = 4
const BEAMS_PER_CAPITAL: int = 2
## Where a carrier's launches leave from: this far below its keel, m.
const BAY_DROP_M: float = 40.0
## Per class: the hull box (m), mass (kg), hull points and gun turrets (the milestone's table).
const CLASSES: Dictionary = {
	&"cruiser": {"length": 300.0, "width": 60.0, "height": 40.0, "mass": 5.0e6, "hull": 2.0e4, "turrets": 8},
	&"destroyer": {"length": 600.0, "width": 110.0, "height": 70.0, "mass": 2.0e7, "hull": 5.0e4, "turrets": 10},
	&"carrier": {"length": 1200.0, "width": 220.0, "height": 140.0, "mass": 8.0e7, "hull": 1.2e5, "turrets": 12},
}
const HULL_COLOR: Color = Color(0.42, 0.44, 0.47)
## The generated hulls (M4-T27) and the looks a capital can take: the bench's plain box or the class's textured hull (M4-T30d).
const HULLS_ASSET: String = "capital_hulls"
const LOOK_BOX: StringName = &"box"
const LOOK_MESH: StringName = &"mesh"

var ship_class: StringName = &"cruiser"
var faction: StringName = Factions.NEUTRAL
## The velocity the engines hold, World frame, m/s.
var cruise_velocity: Vector3 = Vector3.ZERO
## For the environment's pull; null means none.
var world: WorldFrame = null
var targetable: Targetable = null
var damageable: Damageable = null

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


func _init() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	collision_layer = CollisionLayers.layer_of(&"capital")
	collision_mask = CollisionLayers.mask_of(&"capital")


func length_m() -> float:
	return float((CLASSES[ship_class] as Dictionary)["length"])


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


## Parks the body for the low-attention tier (M4-T21): hidden and not processing, its turrets and emitters with it, so it
## leaves Jolt, the scan and the weapon rows while its tier row cruises on.
func park_for_tier() -> void:
	set_meta(&"_scs_tier_row", true)
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Brings the body back from its tier row exactly where the row left it.
func unpark_from_tier(xform: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	if has_meta(&"_scs_tier_row"):
		remove_meta(&"_scs_tier_row")
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	global_transform = xform
	linear_velocity = velocity
	angular_velocity = spin
	reset_physics_interpolation()


## A velocity rebase (`WorldFrame.boost`): the hull and the cruise its engines hold keep their universe velocity.
func frame_boost(dv: Vector3) -> void:
	linear_velocity -= dv
	cruise_velocity -= dv


## Takes a destroyed capital out of play (M4-T23): hidden and not processing, its turrets and emitters with it, for good.
func leave_play() -> void:
	if has_meta(&"_scs_tier_row"):
		remove_meta(&"_scs_tier_row")
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Whether the body is parked for the tier now.
func is_tier_parked() -> bool:
	return has_meta(&"_scs_tier_row")


## The force the engines apply this tick: back toward the cruise velocity, plus what holds off the environment's pull.
func cruise_force(delta: float) -> Vector3:
	var wanted: Vector3 = (cruise_velocity - linear_velocity) / maxf(CRUISE_RESPONSE_S, delta)
	var pull: Vector3 = world.environment_accel(global_position) if world != null and is_instance_valid(world) else Vector3.ZERO
	return mass * (wanted - pull).limit_length(MAX_ACCEL_MPS2)


## One tick of the engines (forces are re-applied every tick).
func step_engines(delta: float) -> void:
	apply_central_force(cruise_force(delta))


func _build(display_name: String) -> void:
	var spec: Dictionary = CLASSES[ship_class]
	var size := Vector3(float(spec["width"]), float(spec["height"]), float(spec["length"]))
	mass = float(spec["mass"])
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
