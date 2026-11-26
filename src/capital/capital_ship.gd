class_name CapitalShip
extends CapitalBody
## A capital ship in the game (M10-T07, D12.4, AC7), built from its catalogue entry and its generated asset (T05's framework):
##
## - **Flight.** Its numbers are a capital-scale `ShipSpec` (mass, inertia, slow turn rates, thrust per engine, propulsion,
##   `can_open_jump_point`). Its engines are the flight step's nozzles (`CapitalPropulsion`) and `CapitalFlight` flies it through
##   the native flight step each tick from its helm's command (the core's native helm, M10-T16: a heading and the velocity
##   `cruise_velocity` mirrors). No damping; forces are re-applied every tick.
## - **Brain** (M10-T16, D12.10): its native `capital` brain (`CapitalBrains`) steers the helm and names its weapons' target,
##   until `set_course` gives it orders (Hold); `release_helm` hands the helm back.
## - **Collision.** The hull piece's sections are compound shapes on this body (Jolt's compound); each rotating piece is a
##   `CapitalRotor`, a kinematic body turned about its pivot. Every section's hit volumes, with the convex hulls they are fitted
##   to, go to the native core as the body's surface (`ScsSimCore.set_surface`), so the hit sweep, the rams and the turrets' line
##   of fire see the real shape; a hit or ram is named by its section (`section_hit`), by the volume the core's sweep entered.
## - **Damage by what is hit** (M10-T08, D12.5; M10-T65, Q72). Its `Damageable` routes every hit to `damage` (`CapitalDamage`):
##   a subsystem struck takes it in full and the hull half, any other hit is hull damage. An engine lost or the reactor's power
##   down a stage refits the drive (the live engines' nozzles at the power left); a magazine, fuel or reactor section at 0 blows
##   it up, a hulk or not; the bridge at 0, the reactor at a tenth (Q78) or the hull below a tenth makes it a hulk.
##   `mount_works`, `bay_works` and `damage.fire_rate()` are what its weapons and launches read (T12 to T17).
## - **Beams** (M10-T12, D12.9): its beam mounts are emitters on the native beam rows (`CapitalBeams`), from its `_ready` until
##   it leaves the tree; a lost mount or section, a disabled or destroyed ship stops them.
## - **Guns and launchers** (M10-T14, D12.9): its turret, fixed gun and missile mounts are rows of `CapitalGuns`, the same way.
## - **Disguise** (M10-T02, Q55): a faction that broadcasts another's transponder (the renegades) does so from its capitals too,
##   until a hostile shot or hit gives the ship away.
## - **Disabled** (M10-T10, D12.7), it winds down in stages (`hulk_stages`): power first (weapons, bays, doors; its lights die,
##   `CapitalHulkLights`, its bay lamps with them), then control (the helm stops steering), then thrust (the mains' last setting winds down to cold), and
##   then it drifts on its last motion with no force, still a target whose sections can be hit and blow. In the tier it is a
##   hulk row. There is no cap on hulks; `scuttle()` is the crew's silent way to make one.
## - **In play.** `Targetable` of kind capital, heard as far as its class broadcasts (`CapitalData.broadcast_range_m`); in the
##   low-attention tier it is a capital row (`CapitalBody`); it opens and holds its own jump point at its anchor when its type
##   can (`open_own_point`). Destroyed, the `DestructionDirector` draws its blast and it leaves play (`leave_play`).
##
## Console: provider and command `capital` (`CapitalConsole`).

## A hit or a ram landed: the section it landed on ("" when none was found) and the hit.
signal section_hit(section: String, info: HitInfo)
## A section changed state (`CapitalSection.State`), a weapon mount was lost, power or control is gone (M10-T08).
signal section_changed(section: String, state: int)
signal mount_lost(mount: String)
signal ship_disabled
## Its drive is cold: from now it drifts with no force (M10-T10).
signal hulk_cold

const GROUP: StringName = &"capital_ships"
## Contact points Jolt keeps for the hull, which the ram tracker reads by body RID (as a ship's, `Ship.CONTACTS_REPORTED`).
const CONTACTS_REPORTED: int = 16
## Set on a hit a rotor passes on: the piece it landed on (none: the hull).
const PIECE_META: StringName = &"capital_piece"
## Set on every hit it takes: the section it landed on and where, in the body frame with the rotating pieces at rest.
const SECTION_META: StringName = &"capital_section"
const REST_POINT_META: StringName = &"capital_rest_point"

## The catalogue type it was built from and its capital class (`capital_class` there: what its broadcast and drive read).
var type_id: StringName = &""
var capital_class: StringName = &""
## The sections as its collision knows them, the engines as nozzles and the spec the flight step flies (its helm is native).
var sections: CapitalSections = null
var layout: ThrusterLayout = null
var flight_spec: ShipSpec = null
var rotors: Array[CapitalRotor] = []
var hull_piece: RenderPiece = null
## The bays' roll-up doors (M10-T22), by bay name; shut until a launch or a docking opens one.
var bay_doors: Dictionary = {}
## Its bays' halls as trigger volumes (a ship inside is lit as the hall is) and its open bays' lamps; null without (M10-T72).
var bay_zones: InteriorZones = null
var bay_lamps: CapitalBayLamps = null
## Its hangar (M10-T17): the craft its bays launch and recover; null for a hull whose bays take none. Empty until stocked.
var hangar: CapitalHangar = null
## Its docking collars (M10-T53): where small craft mate with it; null for a hull without `docking_ports`.
var dock: ShipDock = null
## 1 when this ship wears its style's second colouring (M10-T06: about a fifth of the Vorlons are red-based), else 0: drawn from
## the ship's own name, the same in every run. Its break-up chunks take the same value (`HullSheenMaterial.set_variant`).
var skin_variant: float = 0.0
## The section the last hit or ram landed on, and how many landed per section (a readout for T08 and the console).
var last_section: String = ""
var section_hits: Dictionary = {}
## The flight step's slot (set by `CapitalFlight`; -1 when not registered).
var flight_slot: int = -1
## Its damage by section (M10-T08): states, mounts, engines and bays that still work.
var damage: CapitalDamage = null
## How it winds down once disabled (M10-T10).
var hulk_stages: HulkStages = null

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
var _volume_sections: Dictionary[String, PackedStringArray] = {}  # per body: each surface volume's section, as the core holds them
var _full_layout: ThrusterLayout = null  # every engine's nozzles, as built
var _drive_power: float = 1.0  # the power the drive last had; kept while a disabled hull winds down
var _lights: CapitalHulkLights = null  # its own glow, dimming, while disabled
var _orders: Array = []  # [heading, velocity] given before its helm joined the core


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
	if damage != null and damage.is_disabled:
		SimCore.set_disabled(get_instance_id(), true)  # back in play still disabled


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
		_join_brain()
		CapitalFlight.attach(_world_signals).join(self)
		CapitalBeams.attach(_world_signals).join(self)  # its beam emitters on the native rows (M10-T12)
		CapitalGuns.attach(_world_signals).join(self)  # its guns and launchers on the native rows (M10-T14)
		MineLayers.join_ship(self, _world_signals)  # its mine mounts, laid by the core (M10-T15)
	var destruction: DestructionDirector = DestructionDirector.current()
	if destruction != null:
		destruction.watch_capital(self)  # its death is drawn and takes it out of play (M10-T21)


func _exit_tree() -> void:
	_by_body.erase(get_instance_id())
	SimCore.set_disabled(get_instance_id(), false)
	if _world_signals != null and is_instance_valid(_world_signals):
		if _world_signals.rebased.is_connected(_on_rebased):
			_world_signals.rebased.disconnect(_on_rebased)
		var flight: CapitalFlight = CapitalFlight.of(_world_signals)
		if flight != null:
			flight.leave(self)
		var brains: CapitalBrains = CapitalBrains.of(_world_signals)
		if brains != null:
			brains.leave(self)
		var beams: CapitalBeams = CapitalBeams.of(_world_signals)
		if beams != null:
			beams.leave(self)
		var guns: CapitalGuns = CapitalGuns.of(_world_signals)
		if guns != null:
			guns.leave(self)
		var layers: MineLayers = MineLayers.of(_world_signals)
		if layers != null:
			layers.leave(self)
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
	if _lights != null and hulk_stages.lights_fading():
		_lights.apply(hulk_stages.lights_level())
		_set_lamps(hulk_stages.lights_level())


func half_extents() -> Vector3:
	return _half


func drawn_mesh() -> Mesh:
	return hull_piece.mesh() if hull_piece != null else null


func set_faction(p_faction: StringName) -> void:
	super.set_faction(p_faction)
	for rotor: CapitalRotor in rotors:
		rotor.hull.faction = p_faction
	_show_marks_for_faction()
	if targetable != null:
		targetable.disguise_as(Factions.table().transponder(p_faction))


## Orders for the helm: the bow toward `heading` (World; zero holds the bow where it is) and `velocity` to hold (World
## frame). Its brain holds (it still names its weapons' target) until `release_helm`. A disabled hull takes no orders.
func set_course(heading: Vector3, velocity: Vector3) -> void:
	if is_hulk():
		return
	cruise_velocity = velocity
	_orders = [heading, velocity]
	if _core != null and is_instance_valid(_core):
		_core.capital_set_course(get_instance_id(), heading, velocity)


## Its brain steers the helm again (after `set_course`'s orders).
func release_helm() -> void:
	_orders = []
	if _core != null and is_instance_valid(_core):
		_core.capital_release(get_instance_id())


## Its helm as the core holds it: `{heading, velocity, flipping}` (empty before it joined).
func helm_state() -> Dictionary:
	var raw: Array = _core.capital_helm_state(get_instance_id()) if _core != null and is_instance_valid(_core) else []
	if raw.size() < 3:
		return {}
	return {"heading": raw[0], "velocity": raw[1], "flipping": raw[2]}


## Whether its helm is mid-flip (a reaction hull with no retros turned to burn against its motion).
func helm_flipping() -> bool:
	return bool(helm_state().get("flipping", false))


## The command a disabled hull flies this tick: its helm's `asked`, shaped by the stage it has reached (`HulkStages.shape`);
## none for a destroyed or cold hull, which drifts. A fighting hull flies its helm's command as it is.
func hulk_command(asked: FlightCommand) -> FlightCommand:
	if damage.is_destroyed or hulk_stages.is_cold():
		return FlightCommand.new()
	return hulk_stages.shape(asked if hulk_stages.has_control() else null)


## The command it flew on the last tick (a readout for the console and tests).
func flight_command() -> FlightCommand:
	var flight: CapitalFlight = CapitalFlight.of(_world_signals) if _world_signals != null else null
	return flight.last_command(self) if flight != null else FlightCommand.new()


## Whether its helm's command needs `hulk_command` this tick (a disabled or destroyed hull).
func needs_hulk_command() -> bool:
	return damage.is_disabled or damage.is_destroyed or hulk_stages.is_cold()


## Whether the flight step flies its assist this tick: the helm's, gone with control.
func flight_assist() -> bool:
	return hulk_stages.assist_on()


## One tick of a disabled hull's wind-down (`CapitalFlight` calls it before the command); cold, the drive is refitted to none.
func advance_hulk(delta: float) -> void:
	if hulk_stages.advance(delta) and hulk_stages.is_cold():
		_refit_drive()
		hulk_cold.emit()


func is_hulk() -> bool:
	return damage != null and damage.is_disabled and not damage.is_destroyed and not damageable.hull.destroyed


func settle_as_hulk() -> void:
	if hulk_stages.is_cold():
		return
	hulk_stages.finish()
	_refit_drive()
	if _lights != null:
		_lights.apply(0.0)
	_set_lamps(0.0)
	hulk_cold.emit()


## The crew scuttles the ship (M10-T10, D12.7): silent, no blast; it stops firing and winds down into a hulk. A ship that never
## becomes a hulk (`CapitalData.never_hulk`) explodes instead. For the AI and the missions; false when it is already disabled.
func scuttle() -> bool:
	if damage.is_disabled or damage.is_destroyed:
		return false
	return damage.scuttle()


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
	if _core != null and is_instance_valid(_core):
		_core.capital_set_helm_velocity(get_instance_id(), cruise_velocity)  # the tier held its cruise
	for rotor: CapitalRotor in rotors:
		rotor.snap()


## Out of play for good once destroyed: its sections leave the core too, so no bolt or ram meets the wreck before T11's break-up.
func leave_play() -> void:
	super.leave_play()
	if _core != null and is_instance_valid(_core):
		_core.clear_surface(get_instance_id())
		for rotor: CapitalRotor in rotors:
			_core.clear_surface(rotor.get_instance_id())
	_core = null


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
		var piece_mesh: Dictionary = piece.get("mesh", {}) as Dictionary
		# The manifest is already read: `MeshAssets.chunk_mesh` would parse it again for every chunk (M10-T11: a break-up's).
		if not piece_mesh.is_empty() and piece_mesh != _manifest.get("mesh", {}):
			return MeshAssets.section_mesh(_dir, piece_mesh, str(chunk.get("mesh", "")))
		return MeshAssets.chunk_mesh(_dir, str(chunk.get("mesh", "")))
	return null


## Whether weapon mount `mount` can fire, and bay `bay` launch (M10-T08: alive, its section standing, the ship fighting).
## Its hardpoints as generated (`hardpoints.json`): weapons, bays, engines, ... Shared and read-only to the caller.
func hardpoints() -> Dictionary:
	return _hardpoints


func mount_works(mount: String) -> bool:
	return damage.mount_works(mount)


func bay_works(bay: String) -> bool:
	return damage.bay_works(bay)


## Takes hit `info` by what it struck (its `Damageable`'s and each rotor's `hit_router`, Q72): a subsystem in full and the hull
## half, else the section it landed on and the hull's total; a section that blows takes the rest of the hull. Returns the hull
## points removed.
func route_hit(info: HitInfo) -> float:
	if not info.has_meta(SECTION_META):
		_name_hit(info)
	var removed: float = damage.hit(str(info.get_meta(SECTION_META)), info.get_meta(REST_POINT_META) as Vector3, info.damage)
	var hull: HullHealth = damageable.hull
	return hull.apply(hull.hp if damage.is_destroyed else removed)


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
	_full_layout = layout
	var pieces: Dictionary = _manifest.get("pieces", {}) if _manifest.get("pieces") is Dictionary else {}
	if not sections.valid or not layout.valid or not pieces.has(CapitalSections.HULL):
		push_warning("CapitalShip: %s is not generated or is broken (%s %s); run scripts/gen_assets.sh, then import" % [
				loaded.asset_id, sections.error, layout.error])
		return false
	spec = loaded
	_dir = ShipSpec.ASSET_ROOT.path_join(loaded.asset_id)
	flight_spec = CapitalPropulsion.flight_spec(spec, CapitalPropulsion.main_count(layout))
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
		_volume_sections[piece_name] = sections.volume_sections(piece_name)
		if piece_name != CapitalSections.HULL and pieces.has(piece_name):
			_build_rotor(piece_name, pieces[piece_name])
	damage = CapitalDamage.build(sections, _hardpoints, spec.hull_max)
	damage.section_changed.connect(section_changed.emit)
	damage.mount_lost.connect(mount_lost.emit)
	hulk_stages = HulkStages.from_rules(hash(display_name))
	damage.disabled.connect(_on_disabled)  # before the signal, so its listeners see the wind-down started
	damage.disabled.connect(ship_disabled.emit)
	damage.drive_changed.connect(_refit_drive)
	damageable.hit_router = route_hit
	damageable.restored.connect(_on_restored)
	for raw: Variant in _hardpoints.get("chunks", []):
		chunk_mesh(str((raw as Dictionary).get("name", "")))  # loaded once a type at spawn, not in the frame it dies (M10-T11)
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
	_add_marks(display_name)
	_add_doors()
	_add_bay_interiors()
	hangar = CapitalHangar.make(self)
	if hangar != null:
		add_child(hangar)
	targetable = Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = display_name
	targetable.faction = faction
	targetable.kind = Targetable.Kind.CAPITAL
	targetable.broadcast_range_m = CapitalData.broadcast_range_m(capital_class)
	add_child(targetable)
	targetable.disguise_as(Factions.table().transponder(faction))  # capitals broadcast it too (Q55)
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
	damageable.hits_landed.connect(_on_hits_landed)
	dock = ShipDock.make(self)
	if dock != null:
		add_child(dock)
	_packed_volumes = Station.pack_volumes(volumes)
	_packed_hulls = Station.pack_hulls(shapes, volumes)


## Opens (true) or shuts a bay's door; false when the hull has no door for that bay or no power to move it (the hangar calls
## this around a launch or a docking, M10-T17).
func set_bay_door(bay: String, open: bool, instant: bool = false) -> bool:
	var door: BayDoorNode = bay_doors.get(bay) as BayDoorNode
	if door == null or not damage.has_power():
		return false
	if instant:
		door.snap(open)
	else:
		door.set_open(open)
	return true


## Whether a bay's door is open or opening; false for a shut door or an unknown bay.
func bay_door_open(bay: String) -> bool:
	var door: BayDoorNode = bay_doors.get(bay) as BayDoorNode
	return door != null and door.is_open()


## The roll-up doors the hull carries, all shut.
func _add_doors() -> void:
	for door: Dictionary in BayDoors.doors_of(_hardpoints):
		var node: BayDoorNode = BayDoorNode.create(door, BayDoors.light_of(_hardpoints, BayDoors.bay_of(str(door.get("name", "")))))
		bay_doors[node.bay] = node
		hull_piece.add_child(node)


## The bays' halls, out of the sun's light (Q68): a ship flying into one goes into the interior light, and an open bay's lamp
## lights it. The halls' own faces are on the interior layer already (`RenderPiece`).
func _add_bay_interiors() -> void:
	bay_zones = InteriorZones.for_bays(_hardpoints)
	if bay_zones != null:
		add_child(bay_zones)
	bay_lamps = CapitalBayLamps.make(self, _hardpoints)
	if bay_lamps != null:
		add_child(bay_lamps)


## The painted lettering the hull carries (an Omega's name letter on each shield), chosen by the name it spawns under. A type with
## no name list has no name of its own to letter.
func _add_marks(display_name: String) -> void:
	if ShipNames.names_for(type_id).is_empty() or not _hardpoints.get("mark_atlas") is Dictionary:
		return
	for node: HullMarkNode in HullMarkNode.build_all(HullMarks.marks_of(_hardpoints), _hardpoints["mark_atlas"], _dir, display_name):
		hull_piece.add_child(node)
	_show_marks_for_faction()


## Shows the marks painted for this ship's faction only (the renegades' red X) and hides the rest.
func _show_marks_for_faction() -> void:
	if hull_piece == null:
		return
	for node: Node in hull_piece.get_children():
		if node is HullMarkNode:
			var mark := node as HullMarkNode
			mark.visible = HullMarks.shown_for({"only_faction": String(mark.only_faction)}, faction)


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


# Its helm and brain join the core's capital table: the helm holds what it was told (its velocity at least).
func _join_brain() -> void:
	CapitalBrains.attach(_world_signals).join(self)
	if _core == null or not is_instance_valid(_core):
		return
	_core.capital_set_helm_velocity(get_instance_id(), cruise_velocity)
	if not _orders.is_empty():
		_core.capital_set_course(get_instance_id(), _orders[0], _orders[1])


# The sections' hit volumes to the native core, as the body's surface and each rotor's (named by this hull).
func _register_surfaces() -> void:
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null or sim.core == null:
		return
	_core = sim.core
	_core.set_surface(get_instance_id(), _packed_volumes, _packed_hulls, 0.0)
	_core.set_surface_owner(get_instance_id(), 0, false)
	_check_volume_count(CapitalSections.HULL, get_instance_id())
	for rotor: CapitalRotor in rotors:
		# No spin in the core: a ram on the rotor takes the rotor's own motion (the hull's) instead of its skin's turn alone.
		_core.set_surface(rotor.get_instance_id(), rotor.packed_volumes, rotor.packed_hulls, 0.0)
		_core.set_surface_owner(rotor.get_instance_id(), get_instance_id(), false)
		_check_volume_count(rotor.piece_name, rotor.get_instance_id())
	_set_landing()


# How the beams' batch lands on the hull and each rotor (M10-T75): by this ship's sections, each piece's surface volumes named
# by their sections' slots, a rotor's hits at its pivot (a rotor passes its summaries on to the hull's, as every signal).
func _set_landing() -> void:
	damageable.set_landing(Damageable.LANDING_CAPITAL, damage.ledger, 0, _volume_slots(CapitalSections.HULL))
	for rotor: CapitalRotor in rotors:
		if rotor.hull != null:
			rotor.hull.set_landing(Damageable.LANDING_CAPITAL, damage.ledger, 0, _volume_slots(rotor.piece_name), rotor.pivot)


func _volume_slots(piece: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for section: String in _volume_sections.get(piece, PackedStringArray()):
		out.append(damage.section_slot(section))
	return out


# The core drops a volume that is not finite, which would shift the sweep's volume numbers: that body's hits are then named by
# their point instead.
func _check_volume_count(piece: String, body_id: int) -> void:
	if int(_core.surface_volume_count(body_id)) != _volume_sections.get(piece, PackedStringArray()).size():
		push_warning("CapitalShip %s: the core holds a different count of %s volumes; hits there are named by point" % [name, piece])
		_volume_sections[piece] = PackedStringArray()


# A hit or ram on the hull or a rotor (which says which) is named by the section it landed in.
func _on_hit(info: HitInfo) -> void:
	if not info.has_meta(SECTION_META):
		_name_hit(info)
	last_section = str(info.get_meta(SECTION_META))
	section_hits[last_section] = int(section_hits.get(last_section, 0)) + 1
	section_hit.emit(last_section, info)


# A tick's beam hits (M10-T75): each counted on its section, as `_on_hit` counts a hit.
func _on_hits_landed(summary: HitSummary) -> void:
	for slot: int in summary.sections:
		last_section = damage.section_name(slot)
		section_hits[last_section] = int(section_hits.get(last_section, 0)) + 1


# Names the section a hit landed on, by the surface volume the core's sweep entered when it gives one (a bolt), else by the
# point (a ram, the console), and where it landed with the rotating pieces at rest, where the mounts are listed.
func _name_hit(info: HitInfo) -> void:
	var piece: String = str(info.get_meta(PIECE_META, CapitalSections.HULL))
	var node: Node3D = self
	var rest_offset := Vector3.ZERO
	for rotor: CapitalRotor in rotors:
		if rotor.piece_name == piece:
			node = rotor
			rest_offset = rotor.pivot
	var local: Vector3 = node.global_transform.affine_inverse() * info.point if node.is_inside_tree() else info.point
	var by_volume: PackedStringArray = _volume_sections.get(piece, PackedStringArray())
	var section: String = by_volume[info.volume] if info.volume >= 0 and info.volume < by_volume.size() else sections.section_at(piece, local)
	info.set_meta(SECTION_META, section)
	info.set_meta(REST_POINT_META, local + rest_offset)


# An engine lost or the reactor's power changed: the flight step flies the live engines' nozzles, each at the thrust it had as
# built, scaled by the power left (every engine's nozzles at no thrust with none left), the helm keeping its course.
func _refit_drive() -> void:
	var live: Dictionary = CapitalPropulsion.live_layout(_hardpoints, damage.live_engines())
	var refit: ThrusterLayout = live["layout"] if (live["layout"] as ThrusterLayout).valid else _full_layout
	var base: ShipSpec = CapitalPropulsion.flight_spec(spec, CapitalPropulsion.main_count(_full_layout))
	var power: float = _power_for_drive()
	var per_nozzle: float = power * float(live["nozzle_scale"])
	var scaled: ShipSpec = base.duplicate() as ShipSpec
	scaled.pod_main_thrust = base.pod_main_thrust * per_nozzle
	scaled.pod_retro_thrust = base.pod_retro_thrust * per_nozzle
	# A gravitic drive's sideways push is its engines'; a reaction hull's thrusters only need power.
	var side: float = power * (damage.engine_share() if CapitalPropulsion.is_gravitic(spec) else 1.0)
	scaled.rcs_force_max = base.rcs_force_max * side
	scaled.rcs_torque_max = base.rcs_torque_max * power
	layout = refit
	flight_spec = scaled
	var brains: CapitalBrains = CapitalBrains.of(_world_signals) if _world_signals != null else null
	if brains != null and brains.ships().has(self):
		brains.join(self)  # the helm's numbers again, its course, memory and orders kept
	var flight: CapitalFlight = CapitalFlight.of(_world_signals) if _world_signals != null else null
	if flight != null and flight.ships().has(self):
		flight.join(self)


# The power the drive flies with: the reactors' while it fights; while a disabled hull winds down, what it had before the loss
# (its thrust then falls by the stage's share of the command); none once cold or destroyed.
func _power_for_drive() -> float:
	if damage.is_destroyed:
		return 0.0
	var power: float = damage.power()
	if not damage.is_disabled and power > 0.0:
		_drive_power = power
		return power
	return 0.0 if hulk_stages.is_cold() else _drive_power


# Disabled: the wind-down starts, its lights get their own materials to dim; a hull already in the tier is a hulk row at once.
func _on_disabled() -> void:
	SimCore.set_disabled(get_instance_id(), true)
	if CapitalData.never_hulk(faction, type_id):
		_blow_instead.call_deferred()  # not inside the hit that disabled it
		return
	hulk_stages.start()
	var roots: Array[Node] = [hull_piece]
	for rotor: CapitalRotor in rotors:
		roots.append(rotor.visual_pivot)
	if _lights == null:
		_lights = CapitalHulkLights.collect(roots)
	_refit_drive()
	if is_tier_parked():
		var tier: TierDirector = TierDirector.current()
		if tier != null:
			tier.mark_hulk(self, true)
		settle_as_hulk()


# A ship that never becomes a hulk blows up the moment it is disabled, as any ship of its kind is destroyed.
func _blow_instead() -> void:
	if is_instance_valid(self) and damage != null and damage.is_disabled and not damage.is_destroyed:
		damageable.kill(HitInfo.CAUSE_NO_HULK)


# Whole again (the console's heal, a rebuild): every section and mount, the drive as built, its lights back on.
func _on_restored() -> void:
	var was_hulk: bool = is_hulk()
	damage.restore()
	SimCore.set_disabled(get_instance_id(), false)
	hulk_stages.reset()
	_drive_power = 1.0
	if _lights != null:
		_lights.release()
		_lights = null
	_set_lamps(1.0)
	_refit_drive()
	if was_hulk and is_tier_parked() and TierDirector.current() != null:
		TierDirector.current().mark_hulk(self, false)


# Its bays' lamps (the open halls' and the doors') at `level` of their strength: out with a hulk's other lights.
func _set_lamps(level: float) -> void:
	if bay_lamps != null:
		bay_lamps.set_level(level)
	for door: Variant in bay_doors.values():
		(door as BayDoorNode).set_power(level)


# After a rebase moved the hull, the rotors are put beside it at once (they are not in the shifted group).
func _on_rebased(_offset: Vector3) -> void:
	for rotor: CapitalRotor in rotors:
		rotor.snap()
