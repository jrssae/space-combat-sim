class_name CapitalShip
extends CapitalBody
## A capital ship in the game (M10-T07, D12.4, AC7), built from its catalogue entry and its generated asset (T05's framework):
##
## - **Flight.** Its numbers are a capital-scale `ShipSpec` (mass, inertia, slow turn rates, thrust per engine, propulsion,
##   `can_open_jump_point`). Its engines are the flight step's nozzles (`CapitalPropulsion`) and `CapitalFlight` flies it through
##   the native flight step each tick from its helm's command (`CapitalHelm`: a heading and `cruise_velocity`). No damping;
##   forces are re-applied every tick.
## - **Collision.** The hull piece's sections are compound shapes on this body (Jolt's compound); each rotating piece is a
##   `CapitalRotor`, a kinematic body turned about its pivot. Every section's hit volumes, with the convex hulls they are fitted
##   to, go to the native core as the body's surface (`ScsSimCore.set_surface`), so the hit sweep, the rams and the turrets' line
##   of fire see the real shape; a hit or ram is named by its section (`section_hit`) for T08.
## - **In play.** `Targetable` of kind capital, heard as far as its class broadcasts (`CapitalData.broadcast_range_m`); in the
##   low-attention tier it is a capital row (`CapitalBody`); it opens and holds its own jump point at its anchor when its type
##   can (`open_own_point`).
##
## Console: provider and command `capital` (`CapitalConsole`).

## A hit or a ram landed: the section it landed on ("" when none was found) and the hit.
signal section_hit(section: String, info: HitInfo)

const GROUP: StringName = &"capital_ships"
## Contact points Jolt keeps for the hull, which the ram tracker reads by body RID (as a ship's, `Ship.CONTACTS_REPORTED`).
const CONTACTS_REPORTED: int = 16
## Set on a hit a rotor passes on: the piece it landed on (none: the hull).
const PIECE_META: StringName = &"capital_piece"

## The catalogue type it was built from and its capital class (`capital_class` there: what its broadcast and drive read).
var type_id: StringName = &""
var capital_class: StringName = &""
## The sections as its collision knows them, the engines as nozzles, the spec the flight step flies and the helm.
var sections: CapitalSections = null
var layout: ThrusterLayout = null
var flight_spec: ShipSpec = null
var helm: CapitalHelm = null
var rotors: Array[CapitalRotor] = []
var hull_piece: RenderPiece = null
## 1 when this ship wears its style's second colouring (M10-T06: about a fifth of the Vorlons are red-based), else 0: drawn from
## the ship's own name, the same in every run. Its break-up chunks take the same value (`HullSheenMaterial.set_variant`).
var skin_variant: float = 0.0
## The section the last hit or ram landed on, and how many landed per section (a readout for T08 and the console).
var last_section: String = ""
var section_hits: Dictionary = {}
## The flight step's slot (set by `CapitalFlight`; -1 when not registered).
var flight_slot: int = -1

static var _by_body: Dictionary[int, CapitalShip] = {}

var _dir: String = ""
var _manifest: Dictionary = {}
var _hardpoints: Dictionary = {}
var _half: Vector3 = Vector3.ZERO
var _hull_shapes: int = 0
var _packed_volumes := PackedFloat64Array()  # the hull's sections as the core's surface takes them
var _packed_hulls := PackedFloat64Array()
var _core: Object = null
var _world_signals: WorldFrame = null


## The capital ship of catalogue type `type`, for `p_faction`, called `display_name`, holding `velocity` (World frame). Null
## when the type is unknown or its asset is not generated. Add it to the tree with `WorldFrame.spawn`. `spec_override` flies
## other numbers on the type's hull (tests: the same hull with another drive).
static func create(type: StringName, p_faction: StringName, display_name: String, velocity: Vector3,
		spec_override: ShipSpec = null) -> CapitalShip:
	var catalog: ShipCatalogData = ShipCatalog.data()
	var loaded: ShipSpec = load(catalog.spec_path(type)) as ShipSpec if catalog.has(type) and catalog.role(type) == &"capital" else null
	if loaded != null and spec_override != null:
		loaded = spec_override
	if loaded == null:
		push_warning("CapitalShip: %s is not a capital in the catalogue" % type)
		return null
	var cap := CapitalShip.new()
	cap.type_id = type
	cap.capital_class = StringName(ShipCatalog.entry_text(type, "capital_class"))
	cap.faction = p_faction
	cap.cruise_velocity = velocity
	cap.linear_velocity = velocity
	cap.name = display_name.replace(" ", "_")
	if not cap._build(loaded, display_name):
		cap.free()
		return null
	return cap


## The capital ship whose body is `body_id`, or null.
static func of_body(body_id: int) -> CapitalShip:
	var found: CapitalShip = _by_body.get(body_id)
	return found if found != null and is_instance_valid(found) else null


func _enter_tree() -> void:
	add_to_group(GROUP)
	_by_body[get_instance_id()] = self


func _ready() -> void:
	for rotor: CapitalRotor in rotors:
		rotor.snap()
	_world_signals = WorldFrame.of(self)
	if world == null:
		world = _world_signals
	if _world_signals != null and not _world_signals.rebased.is_connected(_on_rebased):
		_world_signals.rebased.connect(_on_rebased)
	_register_surfaces()
	if _world_signals != null:
		CapitalFlight.attach(_world_signals).join(self)


func _exit_tree() -> void:
	_by_body.erase(get_instance_id())
	if _world_signals != null and is_instance_valid(_world_signals):
		if _world_signals.rebased.is_connected(_on_rebased):
			_world_signals.rebased.disconnect(_on_rebased)
		var flight: CapitalFlight = CapitalFlight.of(_world_signals)
		if flight != null:
			flight.leave(self)
	_world_signals = null
	if _core != null and is_instance_valid(_core):
		_core.clear_surface(get_instance_id())
		for rotor: CapitalRotor in rotors:
			_core.clear_surface(rotor.get_instance_id())
	_core = null


func _process(_delta: float) -> void:
	var fraction: float = Engine.get_physics_interpolation_fraction()
	for rotor: CapitalRotor in rotors:
		rotor.visual_pivot.transform = Transform3D(Basis(rotor.axis, rotor.visual_angle(fraction)), rotor.pivot)


func half_extents() -> Vector3:
	return _half


func drawn_mesh() -> Mesh:
	return hull_piece.mesh() if hull_piece != null else null


func set_faction(p_faction: StringName) -> void:
	super.set_faction(p_faction)
	for rotor: CapitalRotor in rotors:
		rotor.hull.faction = p_faction


## Sets the helm: the bow toward `heading` (World; zero holds the bow where it is) and `velocity` to hold (World frame).
func set_course(heading: Vector3, velocity: Vector3) -> void:
	helm.heading = heading.normalized() if heading.length_squared() > 1e-12 else Vector3.ZERO
	cruise_velocity = velocity


## This tick's command for the flight step (the helm on `cruise_velocity`).
func flight_command() -> FlightCommand:
	helm.velocity = cruise_velocity
	return helm.command(global_basis, linear_velocity)


## The force its engines applied on the last tick, World frame (the ram resolver takes it off a contact's velocity change).
func applied_force() -> Vector3:
	var flight: CapitalFlight = CapitalFlight.of(_world_signals) if _world_signals != null else null
	var row: int = flight.row_of(self) if flight != null else -1
	return flight.out_vectors[row * FlightBatch.OUT_VECTORS + FlightBatch.Out.FORCE] if row >= 0 else Vector3.ZERO


## One tick of its rotating sections (`CapitalFlight` calls it before Jolt's step).
func step_rotors(delta: float) -> void:
	for rotor: CapitalRotor in rotors:
		rotor.step(delta)


func unpark_from_tier(xform: Transform3D, velocity: Vector3, spin: Vector3) -> void:
	super.unpark_from_tier(xform, velocity, spin)
	for rotor: CapitalRotor in rotors:
		rotor.snap()


## Opens its own jump point at its anchor from `pool` (`direction` arrival or departure) and holds it; null when it cannot
## (not jump-capable, its drive recharging, no anchor or no free point).
func open_own_point(pool: JumpPointPool, direction: JumpVortex.Direction = JumpVortex.Direction.DEPARTURE) -> JumpVortex:
	if pool == null or jump_anchor.is_empty():
		return null
	var fwd: Vector3 = -global_basis.z
	var mouth: Vector3 = global_transform * (jump_anchor["position"] as Vector3)
	var r: float = maxf(float(jump_anchor["mouth_radius_m"]), VortexFit.POINT_RADII_PER_SHIP * cross_radius_m())
	var xform := Transform3D(Basis.looking_at(-fwd, global_basis.y), mouth)  # its way out faces the ship
	return pool.open_with(xform, VortexFit.new(r, r * VortexFit.POINT_DEPTH_RATIO), direction, VortexTiming.DEFAULT_HOLD_S, self)


## The break-up chunk `chunk_name`'s mesh, drawn with its own piece's maps (a rotor's chunk with the rotor's); null when missing.
func chunk_mesh(chunk_name: String) -> Mesh:
	for raw: Variant in _hardpoints.get("chunks", []):
		var chunk: Dictionary = raw
		if str(chunk.get("name", "")) != chunk_name:
			continue
		var piece: Dictionary = (_manifest.get("pieces", {}) as Dictionary).get(str(chunk.get("piece", CapitalSections.HULL)), {})
		return MeshAssets.chunk_mesh(_dir, str(chunk.get("mesh", "")), piece.get("mesh", {}) as Dictionary)
	return null


## How many collision shapes the hull body has (the rotors' are their own).
func hull_shape_count() -> int:
	return _hull_shapes


## Whether the native core holds its sections as surfaces.
func surfaces_held() -> bool:
	return _core != null and is_instance_valid(_core) and int(_core.surface_volume_count(get_instance_id())) > 0


func _build(loaded: ShipSpec, display_name: String) -> bool:
	_manifest = MeshAssets.read_manifest(loaded.asset_id)
	sections = CapitalSections.from_manifest(_manifest)
	var text: String = FileAccess.get_file_as_string(loaded.hardpoints_path())
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	_hardpoints = parsed if parsed is Dictionary else {}
	layout = CapitalPropulsion.layout(_hardpoints)
	var pieces: Dictionary = _manifest.get("pieces", {}) if _manifest.get("pieces") is Dictionary else {}
	if not sections.valid or not layout.valid or not pieces.has(CapitalSections.HULL):
		push_warning("CapitalShip: %s is not generated or is broken (%s %s); run scripts/gen_assets.sh, then import" % [
				loaded.asset_id, sections.error, layout.error])
		return false
	spec = loaded
	_dir = ShipSpec.ASSET_ROOT.path_join(loaded.asset_id)
	flight_spec = CapitalPropulsion.flight_spec(spec, CapitalPropulsion.main_count(layout))
	helm = CapitalHelm.make(flight_spec, layout)
	helm.velocity = cruise_velocity
	mass = spec.mass
	inertia = spec.inertia
	max_contacts_reported = CONTACTS_REPORTED
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = layout.center_of_mass
	var dims: Dictionary = _manifest.get("dimensions_m", {})
	_half = 0.5 * Vector3(float(dims.get("span", 0.0)), float(dims.get("height", 0.0)), float(dims.get("length", 0.0)))
	jump_drive.recharge_s = CapitalData.jump_recharge_s(capital_class)
	_read_jump_anchor()
	skin_variant = HullSheenMaterial.variant_of_mesh((pieces[CapitalSections.HULL] as Dictionary).get("mesh", {}), display_name)
	_build_hull(pieces[CapitalSections.HULL], display_name)
	for piece_name: String in sections.bodies():
		if piece_name != CapitalSections.HULL and pieces.has(piece_name):
			_build_rotor(piece_name, pieces[piece_name])
	return true


func _build_hull(entry: Dictionary, display_name: String) -> void:
	var shapes: Array[Dictionary] = sections.shapes_of(CapitalSections.HULL)
	for shape: Dictionary in shapes:
		var node := CollisionShape3D.new()
		node.name = str(shape["name"]).to_pascal_case().validate_node_name()
		node.shape = shape["shape"]
		node.transform = shape["transform"]
		add_child(node, true)
	_hull_shapes = shapes.size()
	hull_piece = RenderPiece.new()
	hull_piece.name = "Hull"
	hull_piece.build(_dir, entry)
	hull_piece.set_skin_variant(skin_variant)
	add_child(hull_piece)
	targetable = Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = display_name
	targetable.faction = faction
	targetable.kind = Targetable.Kind.CAPITAL
	targetable.broadcast_range_m = CapitalData.broadcast_range_m(capital_class)
	add_child(targetable)
	damageable = Damageable.new()
	damageable.name = "Damageable"
	damageable.ram_safe_dv_mps = spec.ram_safe_dv_mps
	damageable.ram_lethal_dv_mps = spec.ram_lethal_dv_mps
	add_child(damageable)
	var volumes: Array[HitShape] = sections.volumes_of(CapitalSections.HULL)
	var entries: Array[Dictionary] = []
	for v: HitShape in volumes:
		entries.append(Station.volume_entry(v))
	damageable.setup(entries, spec.hull_max, faction)
	damageable.hit_taken.connect(_on_hit)
	_packed_volumes = Station.pack_volumes(volumes)
	_packed_hulls = Station.pack_hulls(shapes, volumes)


func _build_rotor(piece_name: String, entry: Dictionary) -> void:
	var rotor := CapitalRotor.make(self, piece_name, entry, sections.shapes_of(piece_name), sections.volumes_of(piece_name))
	rotor.visual_pivot = Node3D.new()
	rotor.visual_pivot.name = "%sPivot" % piece_name.to_pascal_case()
	rotor.visual_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # turned each frame, not each tick
	rotor.visual_pivot.position = rotor.pivot
	add_child(rotor.visual_pivot)
	var picture := RenderPiece.new()
	picture.name = piece_name.to_pascal_case()
	picture.build(_dir, entry)
	picture.set_skin_variant(skin_variant)
	rotor.visual_pivot.add_child(picture)
	add_child(rotor)
	rotors.append(rotor)


func _read_jump_anchor() -> void:
	var anchor: Variant = _hardpoints.get("jump_point")
	if anchor is Dictionary and (anchor as Dictionary).get("position") is Array and ((anchor as Dictionary)["position"] as Array).size() == 3:
		var at: Array = (anchor as Dictionary)["position"]
		jump_anchor = {"position": Vector3(float(at[0]), float(at[1]), float(at[2])),
				"mouth_radius_m": float((anchor as Dictionary).get("mouth_radius_m", 0.0))}


# The sections' hit volumes to the native core, as the body's surface and each rotor's (named by this hull).
func _register_surfaces() -> void:
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null or sim.core == null:
		return
	_core = sim.core
	_core.set_surface(get_instance_id(), _packed_volumes, _packed_hulls, 0.0)
	_core.set_surface_owner(get_instance_id(), 0, false)
	for rotor: CapitalRotor in rotors:
		# No spin in the core: a ram on the rotor takes the rotor's own motion (the hull's) instead of its skin's turn alone.
		_core.set_surface(rotor.get_instance_id(), rotor.packed_volumes, rotor.packed_hulls, 0.0)
		_core.set_surface_owner(rotor.get_instance_id(), get_instance_id(), false)


# A hit or ram on the hull or a rotor (which says which) is named by the section it landed in.
func _on_hit(info: HitInfo) -> void:
	var piece: String = str(info.get_meta(PIECE_META, CapitalSections.HULL))
	var node: Node3D = self
	for rotor: CapitalRotor in rotors:
		if rotor.piece_name == piece:
			node = rotor
	var local: Vector3 = node.global_transform.affine_inverse() * info.point if node.is_inside_tree() else info.point
	last_section = sections.section_at(piece, local)
	section_hits[last_section] = int(section_hits.get(last_section, 0)) + 1
	section_hit.emit(last_section, info)


# After a rebase moved the hull, the rotors are put beside it at once (they are not in the shifted group).
func _on_rebased(_offset: Vector3) -> void:
	for rotor: CapitalRotor in rotors:
		rotor.snap()
