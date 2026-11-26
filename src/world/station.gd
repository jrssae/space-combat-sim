class_name Station
extends Node3D
## Babylon 5 in the game (M7-T06, D74, AC5): the generated `babylon5_station` (M7-T04, T05, T19) as a body ships fly around and
## into, placed where the system data puts the station (M6) and riding the free-falling frame with its anchor (D65), so it
## stays where it is across rebases and drifts. It replaces M4's `StationStandin` in the game; `FarPropHost` places and
## dresses it for the far field.
##
## - **The frame** is a kinematic body (`AnimatableBody3D`) that never moves in the station's frame; **the drum** is a second
##   one turned in `_physics_process` from the system's clock (`StationSpin`), so Jolt gives its skin the drum's speed. The
##   drum's body is a node of the World beside the station, shiftable and tied to the anchor in its own right (a group member
##   may not sit inside another), so a rebase or the frame's drift moves it once, and its motion against the anchor is only
##   its turn: a velocity rebase changes nothing of it in universe terms. A rebase teleports both bodies in Jolt
##   (`_teleport_bodies`): moved as kinematic bodies they would sweep the shift in one step, about 240 km/s at a 4 km
##   rebase, and ram whatever touched them. Both
##   are built from the manifest's `collision.pieces` (`CollisionBodies`) on the rock layer: ships collide with them, rocks
##   and bolts do not (bolts have no body; the hit sweep lands them).
## - **Hit volumes** go to the native core as the big hulls' surfaces (`ScsSimCore.set_surface`), with the convex hulls they
##   are fitted to, so the hit sweep lands bolts on the shape Jolt collides with, avoidance and the fire lane go round its skin and a ship that scrapes the turning drum takes
##   a ram at the skin's speed (Q9). Each piece also carries a `Damageable` (the frame's on this node, beside the `Targetable`),
##   the two sharing one hull, whose hits go by what they strike (`StationDamage`, M10-T65, Q72): a grid mount or the command or
##   reactor section in full and the hull half, anything else off its damage section (`StationSections`, Q5) and the hull.
## - **Always destructible** (Q72): the reactor at 0 or the hull at 0 destroys it (its death blast, `DestructionDirector`; a mission
##   that needs it fails), the command section at 0 or the hull below a tenth leaves a hulk. With no power its lights go out
##   (`StationLights`, the bays' and grid's lamps, the hull's glow) and its grid, launches and docking stop (`has_power`). The
##   wreck stays where it is (no break-up yet).
## - **Visuals** are the pieces' `RenderPiece`s, with the drum's on a pivot turned each frame to the body's angle.
## - Lights: the bays' red lamps (two down the main docking bay's mouth, two in the cargo bay) take `LightPicker` slots
##   (`BayLights`, M7-T25, M7-T32); M7-T18 lights the rest of the station.
## - **The defense grid** (M7-T07, D75) is a `StationGrid` child: its mounts hang from the visuals and bind to the frame and drum
##   bodies in the core. A bolt of the station's own side stops on its hull without harm (maintainer).
##
## Console: provider and command `station`.

## A damage section took a hit: its index, name and health left.
signal section_damaged(index: int, section_name: String, health: float)
## A damage section reached zero (once per loss): a mission can fail on it (Q5).
signal section_lost(index: int, section_name: String)
## It became a hulk (M10-T65): no power from now on.
signal disabled
## It was destroyed (M10-T65): the section that blew, or "" when the hull ran out. The destruction director draws its blast.
signal station_destroyed(section: String)
## A lost section repaired above zero, or a damaged one made whole, by the maintenance bots (M7-T35).
signal section_repaired(index: int, section_name: String, health: float)

const ASSET_ID: String = "babylon5_station"
const DISPLAY_NAME: String = "BABYLON 5"
## The id fighters name as their home dock (`Combatant.home`, M8-T06): the scenario's `home: "babylon5"`.
const HOME_ID: StringName = &"babylon5"
## Every station in the tree, for a ship that keeps clear of a hostile one's guns (M8-T08: a raider carrier).
const GROUP: StringName = &"stations"
## The station's beacon is heard 1 000 km out, as a nav buoy's and the gate's (M3-T17, D69).
const BROADCAST_RANGE_M: float = 1.0e6
## Before the core's sync (-11), so the rows and Jolt see the drum at this tick's angle; after the frame's sample (-100).
const SPIN_PRIORITY: int = -50
## The bodies' collision kind (`CollisionLayers`): ships hit it, rocks do not, as the jumpgate.
const COLLISION_KIND: StringName = &"rock"
## The id its damage rules go by (`data/capitals/capitals.json` `station_damage`).
const DAMAGE_ID: String = "babylon5"
const PROVIDER: StringName = &"station"
const ACTIONS: Array[StringName] = [&"info", &"section", &"spin", &"goto", &"heal"]
## The bays as navigation targets (M7-T27): what the pilot reads, and what a hold of X will do there once missions fill it in.
const DOCKING_BAY_NAME: String = "BABYLON 5 DOCKING BAY"
const CARGO_BAY_NAME: String = "BABYLON 5 CARGO BAY"
## How close to a bay's mouth the hold is offered, m: the gate's 2 km request range, so every interaction reads alike.
const BAY_REACH_M: float = 2000.0

var hardpoints: StationHardpoints = null
var sections: StationSections = null
## Its damage by what is hit (M10-T65): the sections', the grid mounts' and the hull's points, and whether it has power.
var damage: StationDamage = null
## The one hull both pieces' `Damageable`s share.
var hull: HullHealth = null
var spin: StationSpin = StationSpin.new()
## False holds the drum still (`station spin off`, captures).
var spinning: bool = true
var frame_body: AnimatableBody3D = null
var drum_body: AnimatableBody3D = null
var frame_hull: Damageable = null
var drum_hull: Damageable = null
var targetable: Targetable = null
## The main docking bay's and the cargo bay's navigation targets (M7-T27), at the bay mouths; placeholders until missions fill
## their interactions (docking, loading, unloading).
var docking_bay: NavPoint = null
## Whose home this station is: its docking bay takes only the fighters that name it (M8-T06).
var home_id: StringName = HOME_ID
var cargo_bay: NavPoint = null
## The defense grid (M7-T07).
var grid: StationGrid = null
## The main docking bay's inner doors, and its red lamps (M7-T25).
var airlock: StationAirlock = null
var bay_lights: BayLights = null
var grid_lights: StationGridLights = null
## The exterior lights (M7-T18): beacons, navigation lights, bay lamps and the floods on the hull.
var station_lights: StationLights = null
## The maintenance bots (M7-T11, Q11): ambient drones on loops round the hull, in the frame's and the drum's visuals.
var bots: BotFleet = null
## The cargo pods (M7-T34): every freighter's cargo carried between it and the cargo bay, on the frame.
var cargo_pods: CargoPodFleet = null
## The pieces' visuals; the drum's turns on `drum_pivot`.
var frame_piece: RenderPiece = null
var drum_piece: RenderPiece = null
var drum_pivot: Node3D = null
## Where the drum's axis meets the station's frame (the manifest's `pivot`).
var drum_origin: Vector3 = Vector3.ZERO
var length_m: float = 0.0
## The drum's turn as last set, radians.
var drum_angle: float = 0.0
## The scene that knows the player (FarPropHost sets it), for `station goto`; null in a bare test.
var main: Main = null
## Shapes and hit volumes per piece, for the console and tests.
var frame_shapes: int = 0
var drum_shapes: int = 0

var _frame_volumes := PackedFloat64Array()
var _drum_volumes := PackedFloat64Array()
var _frame_hulls := PackedFloat64Array()
var _drum_hulls := PackedFloat64Array()
var _core: Object = null  # the native core the surfaces were given to
var _held_angle: float = 0.0
var _phase: float = 0.0  # added to the clock's angle, so a drum started again goes on from where it was held
var _world: WorldFrame = null  # whose rebases teleport the bodies
var _goto_after_launch: String = ""  # the tour point a `station goto` during a launch waits to place the player at
var _glow: CapitalHulkLights = null  # the hull's own glow on materials of its own, dark while it has no power


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_to_group(WorldFrame.ANCHORED_GROUP)
	add_to_group(GROUP)
	process_physics_priority = SPIN_PRIORITY


## Builds the bodies, hulls, marker and visuals from the generated asset; false (nothing built) when it is missing or broken.
func build() -> bool:
	var manifest: Dictionary = MeshAssets.read_manifest(ASSET_ID)
	var pieces: Dictionary = manifest.get("pieces", {})
	var collision: CollisionPieces = CollisionPieces.from_manifest(manifest)
	hardpoints = StationHardpoints.from_manifest(manifest)
	if not pieces.has("drum") or not pieces.has("frame") or not collision.valid or not hardpoints.valid:
		push_warning("Station: %s is not generated or is broken (%s %s); run scripts/gen_assets.sh, then import" % [ASSET_ID,
				collision.error, hardpoints.error])
		return false
	length_m = float(manifest.get("length_m", 8000.0))
	var drum_entry: Dictionary = pieces["drum"]
	var pivot: Array = drum_entry.get("pivot", [0.0, 0.0, 0.0])
	drum_origin = Vector3(float(pivot[0]), float(pivot[1]), float(pivot[2]))
	spin = StationSpin.new(float(drum_entry.get("spin_rad_s", hardpoints.spin_rad_s)))
	sections = StationSections.from_hardpoints(hardpoints)
	sections.lost.connect(_on_section_lost)
	_build_visuals(pieces)
	_build_bodies(collision)
	_build_hulls(collision)
	_build_nav_points()
	grid = StationGrid.new()
	grid.build(self)
	add_child(grid)
	_build_damage()
	airlock = StationAirlock.make(self)
	if airlock != null:
		add_child(airlock)
	bay_lights = BayLights.make(self)
	if bay_lights != null:
		add_child(bay_lights)
	grid_lights = StationGridLights.make(self)
	if grid_lights != null:
		add_child(grid_lights)
	station_lights = StationLights.make(self)
	if station_lights != null:
		add_child(station_lights)
	bots = BotFleet.new()
	if bots.build(self):
		add_child(bots)
	else:
		bots.free()
		bots = null
	cargo_pods = CargoPodFleet.new()
	cargo_pods.build(self)
	add_child(cargo_pods)
	return true


## The visuals `FarProp` shrinks and fades into its dot (`FarPropHost.dress_station`).
func far_visuals() -> Array[Node3D]:
	return [frame_piece, drum_pivot] as Array[Node3D]


func _ready() -> void:
	add_to_group(TargetCategories.LAUNCH_BASES)  # the fighters it launches name it home; the target menu pins it in ALLIES
	_register_surfaces()
	var destruction: DestructionDirector = DestructionDirector.current()
	if destruction != null:
		destruction.watch_station(self)  # its death blast, and a mission that needs it fails (M10-T65)
	_register_console()
	_world = WorldFrame.of(self)
	if _world != null and not _world.rebased.is_connected(_teleport_bodies):
		_world.rebased.connect(_teleport_bodies)
	# The drum's body joins the World beside the station: at once when the spawner calls `place_drum_body`, else once the
	# World is free to take a child.
	place_drum_body.call_deferred()


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if _world != null and is_instance_valid(_world) and _world.rebased.is_connected(_teleport_bodies):
		_world.rebased.disconnect(_teleport_bodies)
	_world = null
	if _core != null and is_instance_valid(_core):
		_core.clear_surface(get_instance_id())
		if drum_body != null:
			_core.clear_surface(drum_body.get_instance_id())
	_core = null
	if drum_body != null and is_instance_valid(drum_body) and drum_body.is_inside_tree():
		drum_body.queue_free()


func _notification(what: int) -> void:
	# A station freed before it was ever placed takes its drum's body with it.
	if what == NOTIFICATION_PREDELETE and drum_body != null and is_instance_valid(drum_body) and not drum_body.is_inside_tree():
		drum_body.free()


## Puts the drum's body in the World beside the station (call after spawning it; `_ready` does it a frame late otherwise).
func place_drum_body() -> void:
	var parent: Node = get_parent()
	if not is_inside_tree() or parent == null or drum_body == null or drum_body.is_inside_tree():
		return
	# Placed before it joins, so Jolt first sees it where it belongs, never across whatever lies at its local pivot.
	drum_angle = _angle_now()
	drum_body.transform = transform * Transform3D(Basis(Vector3.BACK, drum_angle), drum_origin)
	parent.add_child(drum_body, true)
	set_drum_angle(drum_angle)
	drum_body.reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	set_drum_angle(_angle_now())


func _process(_delta: float) -> void:
	if drum_pivot == null:
		return
	drum_pivot.transform = Transform3D(Basis(Vector3.BACK, visual_angle(Engine.get_physics_interpolation_fraction())), drum_origin)


## The drum's angle as drawn `fraction` of the way through the frame's tick: between the body's last two angles, as the
## interpolated ships beside it and riding it are drawn (M7-T08: a launching fighter rides the drum).
func visual_angle(fraction: float) -> float:
	if not spinning:
		return drum_angle
	return fposmod(drum_angle + spin.rate_rad_s * (fraction - 1.0) / float(Engine.physics_ticks_per_second), TAU)


## Turns the drum's body (and its picture) to `angle` radians about +Z.
func set_drum_angle(angle: float) -> void:
	drum_angle = angle
	if drum_body != null and drum_body.is_inside_tree() and is_inside_tree():
		drum_body.global_transform = global_transform * Transform3D(Basis(Vector3.BACK, angle), drum_origin)
	if drum_pivot != null:
		drum_pivot.transform = Transform3D(Basis(Vector3.BACK, angle), drum_origin)


## After a rebase moved the nodes by `-offset`: each body is put in Jolt where its last step left it, moved by the shift, as
## a teleport (static for the moment it is placed), then given the pose its node now asks for as its kinematic target. So
## the shift adds no velocity: the drum's skin keeps its spin and the frame stays at rest against the anchor.
func _teleport_bodies(offset: Vector3) -> void:
	for body: AnimatableBody3D in [frame_body, drum_body]:
		if body == null or not body.is_inside_tree():
			continue
		var rid: RID = body.get_rid()
		var was: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
		PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(was.basis, was.origin - offset))
		PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_KINEMATIC)
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)


## Starts or stops the drum (`station spin`); stopped, its skin is still to a ship that touches it.
func set_spinning(on: bool) -> void:
	if on == spinning:
		return
	_held_angle = drum_angle
	if on:
		_phase = drum_angle - spin.angle_at(_system_time())
	spinning = on
	if _core != null and is_instance_valid(_core) and drum_body != null:
		_core.set_surface(drum_body.get_instance_id(), _drum_volumes, _drum_hulls, spin.rate_rad_s if on else 0.0)


## A point given in `body`'s frame (`drum` or `frame`, as the hardpoints name them), in the World now.
func to_world(point: Vector3, body: String) -> Vector3:
	return global_transform * StationHardpoints.to_station(point, body, drum_origin, drum_angle)


## The station's centre in the universe frame.
func universe_position() -> UniversePos:
	var world: WorldFrame = WorldFrame.of(self)
	return world.to_universe(global_position) if world != null else UniversePos.new()


## A hit of `amount` on damage section `index` itself (the console's, no mount struck), by the rules a shot's takes (Q72): the
## command or reactor section in full and the hull half, any other off the section and the hull. True when it lost the section.
func damage_section(index: int, amount: float) -> bool:
	if damage == null or index < 0 or index >= sections.count():
		return false
	var was_lost: bool = sections.is_lost(index)
	var before: float = sections.health[index]
	_take_hull(damage.hit_section(index, amount))
	_note_section(index, before)
	return not was_lost and sections.is_lost(index)


## Whether it has power: neither a hulk nor destroyed (Q72). Without it nothing fires, launches or docks, and its lights are out.
func has_power() -> bool:
	return damage == null or damage.has_power()


func is_destroyed() -> bool:
	return damage != null and damage.is_destroyed


## Adds `amount` to damage section `index` (a maintenance bot's work, M7-T35); a lost section comes back above zero and can be
## lost again.
func repair_section(index: int, amount: float) -> void:
	if sections == null or index < 0 or index >= sections.count() or sections.is_whole(index):
		return
	var came_back: bool = sections.repair(index, amount)
	if frame_hull != null and index < frame_hull.zones.totals.size():
		frame_hull.zones.totals[index] = minf(frame_hull.zones.totals[index], sections.max_health[index] - sections.health[index])
	if came_back or sections.is_whole(index):
		section_repaired.emit(index, String(sections.sections[index]["name"]), sections.health[index])


## Every section, the hull and its power whole again (the console's heal).
func heal() -> void:
	if damage != null:
		damage.restore()
	elif sections != null:
		sections.restore()
	if frame_hull != null:
		frame_hull.restore()
		frame_hull.zones.set_capacities(sections.max_health)
	_set_power(true)


func _angle_now() -> float:
	return fposmod(spin.angle_at(_system_time()) + _phase, TAU) if spinning else _held_angle


# The system's clock (M6-T09: the scenario's epoch plus sim time), or sim time alone outside a world.
func _system_time() -> float:
	var world: WorldFrame = WorldFrame.of(self) if is_inside_tree() else null
	return world.system_time() if world != null else SimClock.now()


func _build_visuals(pieces: Dictionary) -> void:
	var dir: String = ShipSpec.ASSET_ROOT.path_join(ASSET_ID)
	frame_piece = RenderPiece.new()
	frame_piece.name = "Frame"
	frame_piece.build(dir, pieces["frame"])
	add_child(frame_piece)
	drum_pivot = Node3D.new()
	drum_pivot.name = "DrumPivot"
	drum_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # turned each frame, not each tick
	drum_pivot.position = drum_origin
	add_child(drum_pivot)
	drum_piece = RenderPiece.new()
	drum_piece.name = "Drum"
	drum_piece.build(dir, pieces["drum"])
	drum_pivot.add_child(drum_piece)


func _build_bodies(collision: CollisionPieces) -> void:
	var frame_entry: Dictionary = collision.piece("frame")
	var drum_entry: Dictionary = collision.piece("drum")
	frame_body = CollisionBodies.build(frame_entry, true) as AnimatableBody3D
	frame_body.name = "FrameBody"
	drum_body = CollisionBodies.build(drum_entry, true) as AnimatableBody3D
	drum_body.name = "DrumBody"
	drum_body.position = drum_origin
	drum_body.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	drum_body.add_to_group(WorldFrame.ANCHORED_GROUP)
	for body: AnimatableBody3D in [frame_body, drum_body]:
		# The script places them each tick: what it sets is where Jolt moves them, with the speed that takes.
		body.sync_to_physics = false
		body.collision_layer = CollisionLayers.layer_of(COLLISION_KIND)
		body.collision_mask = CollisionLayers.mask_of(COLLISION_KIND)
	add_child(frame_body)
	frame_shapes = (frame_entry["shapes"] as Array).size()
	drum_shapes = (drum_entry["shapes"] as Array).size()


func _build_hulls(collision: CollisionPieces) -> void:
	var frame_volumes: Array[HitShape] = collision.piece("frame")["hit_volumes"]
	var drum_volumes: Array[HitShape] = collision.piece("drum")["hit_volumes"]
	frame_hull = _hull(frame_volumes, &"station")
	frame_hull.name = "Hull"
	add_child(frame_hull)
	drum_hull = _hull(drum_volumes, &"")
	drum_hull.name = "Hull"
	drum_body.add_child(drum_hull)
	frame_hull.zones.set_capacities(sections.max_health)
	frame_hull.hit_router = _route_hit.bind(StationHardpoints.FRAME)
	drum_hull.hit_router = _route_hit.bind(StationHardpoints.DRUM)
	_frame_volumes = pack_volumes(frame_volumes)
	_drum_volumes = pack_volumes(drum_volumes)
	_frame_hulls = pack_hulls(collision.piece("frame")["shapes"], frame_volumes)
	_drum_hulls = pack_hulls(collision.piece("drum")["shapes"], drum_volumes)
	targetable = Targetable.new()
	targetable.name = "Targetable"
	targetable.display_name = DISPLAY_NAME
	targetable.faction = Factions.EARTH_ALLIANCE
	targetable.kind = Targetable.Kind.PROP
	targetable.broadcast_range_m = BROADCAST_RANGE_M
	add_child(targetable)
	drum_body.set_meta(Targetable.SPEAKS_FOR, targetable)  # the drum's guns fire for the station (M7-T10)
	var drawn: Array[Dictionary] = []
	for i: int in sections.count():
		var box: AABB = sections.sections[i]["aabb"]
		if sections.sections[i]["body"] == StationHardpoints.DRUM:
			box.position += drum_origin
		drawn.append({"zone": i, "aabb": box})
	Silhouette.set_station_sections(drawn)


# The bays' navigation targets, at their mouths: the docking bay's on the drum's axis, so the drum's turn never moves it.
func _build_nav_points() -> void:
	var dock: Dictionary = hardpoints.main_docking_bay
	var cargo: Dictionary = hardpoints.cargo_bay
	docking_bay = NavPoint.make(DOCKING_BAY_NAME, TargetInteraction.new(&"dock", "DOCK", Callable(), Callable(), BAY_REACH_M),
			BROADCAST_RANGE_M)
	docking_bay.position = (dock.get("main_docking_bay_mouth", Vector3.ZERO) as Vector3) + drum_origin
	docking_bay.class_text = "Docking bay"
	docking_bay.home_id = home_id
	add_child(docking_bay)
	cargo_bay = NavPoint.make(CARGO_BAY_NAME, TargetInteraction.new(&"cargo", "CARGO", Callable(), Callable(), BAY_REACH_M),
			BROADCAST_RANGE_M)
	cargo_bay.position = cargo.get("cargo_bay_entry", Vector3.ZERO) as Vector3
	cargo_bay.class_text = "Cargo bay"
	add_child(cargo_bay)


# A piece's hull: its hit volumes and the station's faction; its points are set with the damage model (`_build_damage`).
func _hull(volumes: Array[HitShape], layout: StringName) -> Damageable:
	var entries: Array[Dictionary] = []
	for v: HitShape in volumes:
		entries.append(volume_entry(v))
	var piece := Damageable.new()
	piece.setup(entries, 1.0, Factions.EARTH_ALLIANCE, false, false, layout)
	piece.stops_friendly_bolts = true
	return piece


# Its damage by what is hit (M10-T65): the sections and the grid's mounts under one hull, which both pieces share.
func _build_damage() -> void:
	var rules: Dictionary = CapitalData.station_rules(DAMAGE_ID)
	damage = StationDamage.make(sections, grid.health if grid != null else null, rules.get("section_kinds", {}) as Dictionary)
	if grid != null:
		damage.mount_out = grid.knock_out
	damage.disabled.connect(_on_disabled)
	damage.destroyed.connect(_on_destroyed)
	hull = HullHealth.new(damage.hull_max)
	if frame_hull != null:
		frame_hull.hull = hull
	if drum_hull != null:
		drum_hull.hull = hull


## Its death blast and where it goes off (World frame), `[BlastSpec, Vector3]`: the table's row for its class and kind
## (`station_damage`), from its reactor section's centre (the section that blew, else the reactor, else the station's centre).
func death_blast() -> Array:
	var rule: Array = CapitalData.station_rules(DAMAGE_ID).get("blast", ["dreadnought", CapitalSection.REACTOR]) as Array
	var spec: BlastSpec = BlastTable.section(StringName(str(rule[0])), str(rule[1]))
	var index: int = sections.index_of(damage.blown) if damage != null and not damage.blown.is_empty() else -1
	if index < 0 and damage != null:
		index = damage.kinds.find(CapitalSection.REACTOR)
	var centre: Vector3 = global_position
	if index >= 0:
		var box: AABB = sections.sections[index]["aabb"]
		centre = to_world(box.get_center(), String(sections.sections[index]["body"]))
	return [spec, centre]


## A hit volume back in `Hardpoints.collision`'s form, for `Damageable.setup`.
static func volume_entry(v: HitShape) -> Dictionary:
	if v.kind == HitShape.Kind.CAPSULE:
		var capsule := CapsuleShape3D.new()
		capsule.radius = v.radius
		capsule.height = 2.0 * (v.half_segment + v.radius)
		return {"name": v.shape_name, "shape": capsule, "transform": v.transform}
	var box := BoxShape3D.new()
	box.size = v.half_extents * 2.0
	return {"name": v.shape_name, "shape": box, "transform": v.transform}


## Hit volumes as the core's surfaces take them (`surface::VOLUME_LEN` numbers each): capsule flag, the volume's x, y and z
## axes, its centre, its size (a box's half extents; a capsule's half segment, radius, 0).
static func pack_volumes(volumes: Array[HitShape]) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for v: HitShape in volumes:
		var b: Basis = v.transform.basis
		var o: Vector3 = v.transform.origin
		var capsule: bool = v.kind == HitShape.Kind.CAPSULE
		out.append_array([1.0 if capsule else 0.0, b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z])
		if capsule:
			out.append_array([v.half_segment, v.radius, 0.0])
		else:
			out.append_array([v.half_extents.x, v.half_extents.y, v.half_extents.z])
	return out


## The convex hulls behind the hit volumes, as the core's surfaces take them (`surface::add_hulls`): per hull shape its
## volume's index, its point count and its points. A volume is fitted to the shape of the same place and name (M7-T03), so
## a bolt stops on the shape Jolt collides with; a shape whose name does not match its volume is left to the box.
static func pack_hulls(shapes: Array[Dictionary], volumes: Array[HitShape]) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i: int in mini(shapes.size(), volumes.size()):
		var shape: Dictionary = shapes[i]
		var hull := shape["shape"] as ConvexPolygonShape3D
		if hull == null or str(shape["name"]) != volumes[i].shape_name:
			continue
		var xform: Transform3D = shape["transform"]
		out.append_array([float(i), float(hull.points.size())])
		for p: Vector3 in hull.points:
			var q: Vector3 = xform * p
			out.append_array([q.x, q.y, q.z])
	return out


func _register_surfaces() -> void:
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim == null or sim.core == null:
		return
	_core = sim.core
	_core.set_surface(get_instance_id(), _frame_volumes, _frame_hulls, 0.0)
	_core.set_surface(drum_body.get_instance_id(), _drum_volumes, _drum_hulls, spin.rate_rad_s if spinning else 0.0)
	# A neutral port: any people's fleeing civilians shelter here (M7-T55); the drum goes by the station's name.
	_core.set_surface_owner(get_instance_id(), 0, true)
	_core.set_surface_owner(drum_body.get_instance_id(), get_instance_id(), true)


# A hit on one piece (its `Damageable`'s router) lands by what it strikes there: a mount, the command or reactor section, or
# the hull in its section. Returns the hull points it removed.
func _route_hit(info: HitInfo, body: String) -> float:
	var node: Node3D = drum_body if body == StationHardpoints.DRUM else self
	if damage == null or node == null or not node.is_inside_tree():
		return 0.0
	var local: Vector3 = node.global_transform.affine_inverse() * info.point
	var index: int = sections.section_at(body, local)
	var before: float = sections.health[index] if index >= 0 else 0.0
	var removed: float = _take_hull(damage.hit(body, local, info.damage))
	if index >= 0:
		_note_section(index, before)
	return removed


# The hull's share of a hit off the shared hull; all of it once the station is destroyed.
func _take_hull(amount: float) -> float:
	if hull == null:
		return 0.0
	return hull.apply(hull.hp if damage.is_destroyed else amount)


# A section's points fell from `before`: the HUD's zone and the signal.
func _note_section(index: int, before: float) -> void:
	var lost: float = before - sections.health[index]
	if lost <= 0.0:
		return
	if frame_hull != null:
		frame_hull.zones.record_zone(index, lost)
	section_damaged.emit(index, String(sections.sections[index]["name"]), sections.health[index])


func _on_disabled() -> void:
	_set_power(false)
	disabled.emit()


func _on_destroyed(section: String) -> void:
	_set_power(false)
	station_destroyed.emit(section)


# Power on or off: the grid, every light (the points and floods, the bays' and the grid's lamps, the hull's own glow) and, through
# `has_power`, its launches and docking.
func _set_power(on: bool) -> void:
	if grid != null:
		grid.set_powered(on)
	if station_lights != null:
		station_lights.set_shown(on)
	var lamps: Array[LightEmitter] = []
	if bay_lights != null:
		lamps.append_array(bay_lights.emitters)
	if grid_lights != null:
		lamps.append_array(grid_lights.emitters)
	for emitter: LightEmitter in lamps:
		if not on:
			emitter.set_meta(&"_powered_energy", emitter.energy)
			emitter.energy = 0.0
		elif emitter.has_meta(&"_powered_energy"):
			emitter.energy = float(emitter.get_meta(&"_powered_energy"))
	if not on and _glow == null:
		_glow = CapitalHulkLights.collect([frame_piece, drum_pivot] as Array[Node])
		_glow.apply(0.0)
	elif on and _glow != null:
		_glow.release()
		_glow = null


func _on_section_lost(index: int) -> void:
	section_lost.emit(index, String(sections.sections[index]["name"]))


# --- console -----------------------------------------------------------------------------------------------------


func _register_console() -> void:
	DebugConsole.registry.register_provider(PROVIDER, ConsoleVars.new({
		&"place": {"get": func() -> String: return str(universe_position()),
				"doc": "Where the station stands: its centre in the universe frame (the system data's point, M6)"},
		&"drum_deg": {"get": func() -> float: return rad_to_deg(drum_angle), "type": TYPE_FLOAT,
				"doc": "The drum's turn now, degrees (from the system's clock, 0.148 rad/s)"},
		&"spinning": {"get": func() -> bool: return spinning, "type": TYPE_BOOL, "doc": "The drum turns (station spin on|off)"},
		&"sections": {"get": func() -> String: return sections.describe() if sections != null else "",
				"doc": "Each damage section's health (Q5); a lost one says LOST"},
		&"state": {"get": func() -> String: return damage.describe() if damage != null else "",
				"doc": "fighting, hulk or destroyed (M10-T65, Q72), and the hull's points"},
		&"hull": {"get": func() -> float: return hull.fraction() if hull != null else 1.0, "type": TYPE_FLOAT,
				"doc": "Hull points left, 0 to 1 (below 0.1 a hulk, at 0 destroyed)"},
		&"powered": {"get": has_power, "type": TYPE_BOOL,
				"doc": "It has power: its lights, grid, launches and docking work (a hulk or a wreck has none)"},
		&"broadcast_km": {"get": func() -> float: return BROADCAST_RANGE_M / 1000.0, "type": TYPE_FLOAT,
				"doc": "How far the station's beacon is heard, km"},
		&"collision": {"get": _collision_text,
				"doc": "Jolt shapes and hit volumes per piece, and whether the core holds the surfaces"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(PROVIDER,
			"The station (M7-T06): info, section <name> damage <n>, heal, spin on|off, goto <tour point>",
			[ConsoleArg.enum_optional(&"action", ACTIONS, &"info"), ConsoleArg.string_optional(&"a"),
					ConsoleArg.string_optional(&"b"), ConsoleArg.float_optional(&"amount", null, 0.0)]), _cmd_station, self)


func _collision_text() -> String:
	var held: bool = _core != null and is_instance_valid(_core) and int(_core.surface_volume_count(get_instance_id())) > 0
	return "frame %d shapes %d volumes, drum %d shapes %d volumes, surfaces %s" % [frame_shapes,
			frame_hull.shapes.size() if frame_hull != null else 0, drum_shapes, drum_hull.shapes.size() if drum_hull != null else 0,
			"in the core" if held else "not in a core"]


func _cmd_station(args: Dictionary) -> ConsoleResult:
	var a: String = str(args[&"a"]) if args[&"a"] != null else ""
	var b: String = str(args[&"b"]) if args[&"b"] != null else ""
	match StringName(args[&"action"]):
		&"section":
			var index: int = sections.index_of(a)
			if index < 0 or b != "damage" or args[&"amount"] == null:
				return ConsoleResult.failure("station section <name> damage <n>; sections: %s" % _section_names())
			var lost: bool = damage_section(index, float(args[&"amount"]))
			return ConsoleResult.line("%s %.0f/%.0f%s; %s" % [a, sections.health[index], sections.max_health[index],
					" (lost)" if lost else "", damage.describe()])
		&"heal":
			heal()
			return ConsoleResult.line("station sections, hull and power whole")
		&"spin":
			if a != "on" and a != "off":
				return ConsoleResult.failure("station spin on|off")
			set_spinning(a == "on")
			return ConsoleResult.line("drum %s at %.1f deg" % ["turning" if spinning else "held", rad_to_deg(drum_angle)])
		&"goto":
			return _goto(a)
	return ConsoleResult.line("%s: %s; drum %.1f deg%s; %s; %s; %s" % [DISPLAY_NAME, universe_position(), rad_to_deg(drum_angle),
			"" if spinning else " (held)", damage.describe(), sections.describe(), _collision_text()])


func _section_names() -> String:
	var names := PackedStringArray()
	for entry: Dictionary in sections.sections:
		names.append(String(entry["name"]))
	return ", ".join(names)


# Puts the player at tour point `point_name` (M7-T05's), at rest against the station, looking where the point looks.
func _goto(point_name: String) -> ConsoleResult:
	var point: Dictionary = hardpoints.tour(point_name)
	if point.is_empty():
		var names := PackedStringArray()
		for entry: Dictionary in hardpoints.tour_points:
			names.append(String(entry["name"]))
		return ConsoleResult.failure("station goto <%s>" % "|".join(names))
	if main == null or not main.player_alive:
		return ConsoleResult.failure("station goto: no player to move")
	# A launch in progress still carries the player with the drum: end it first, then place the player once it lets go.
	if main.launches != null and main.launches.locks_controls():
		main.launches.skip()
		_goto_after_launch = point_name  # the last goto asked wins
		if not main.launches.player_released.is_connected(_place_after_launch):
			main.launches.player_released.connect(_place_after_launch)
			main.player_died.connect(_forget_goto)
		return ConsoleResult.line("launch skipped; at tour point %s once the player is away" % point_name)
	_place_at_tour_point(point_name)
	return ConsoleResult.line("at tour point %s" % point_name)


# The launch let the player go: on to the tour point asked for during it.
func _place_after_launch() -> void:
	var point_name: String = _goto_after_launch
	_forget_goto()
	_place_at_tour_point(point_name)


# A goto waiting on a launch is dropped once it is done, or when the player dies first, so no later launch carries it out.
func _forget_goto() -> void:
	_goto_after_launch = ""
	if main.launches.player_released.is_connected(_place_after_launch):
		main.launches.player_released.disconnect(_place_after_launch)
	if main.player_died.is_connected(_forget_goto):
		main.player_died.disconnect(_forget_goto)


# Rests the player at the tour point against what is near it: on the drum, the drum's own motion there.
func _place_at_tour_point(point_name: String) -> void:
	var point: Dictionary = hardpoints.tour(point_name)
	if point.is_empty() or main == null or not main.player_alive:
		return
	main.world.return_home()  # the frame back on the station's rail first (M7-T71)
	var body: String = String(point["body"])
	var at: Vector3 = to_world(point["position"], body)
	var look: Vector3 = to_world(point["look_at"], body)
	var up: Vector3 = Vector3.UP if absf((look - at).normalized().dot(Vector3.UP)) < 0.98 else Vector3.BACK
	main.ship.reset_to(Transform3D(Basis.looking_at((look - at).normalized(), up), at))
	var world: WorldFrame = WorldFrame.of(self)
	var rest: Vector3 = world.rest_velocity() if world != null else Vector3.ZERO
	if body == StationHardpoints.DRUM and spinning:
		var radius: Vector3 = Vector3.BACK.cross(StationHardpoints.to_station(point["position"], body, drum_origin, drum_angle) - drum_origin)
		rest += global_transform.basis * (radius * spin.rate_rad_s)
	main.ship.linear_velocity = rest
	main.ship.angular_velocity = Vector3.ZERO
