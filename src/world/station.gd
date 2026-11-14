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
##   a ram at the skin's speed (Q9). Each piece also carries a `Damageable` (the frame's on this node, beside the `Targetable`)
##   whose hits go to the damage sections (`StationSections`, Q5); the hull itself never falls.
## - **Visuals** are the pieces' `RenderPiece`s, with the drum's on a pivot turned each frame to the body's angle.
## - No lights: M7-T18 lights the station, and nothing here takes a `LightPicker` slot.
## - **The defence grid** (M7-T07, D75) is a `StationGrid` child: its mounts hang from the visuals and bind to the frame and drum
##   bodies in the core. A bolt of the station's own side stops on its hull without harm (maintainer).
##
## Console: provider and command `station`.

## A damage section took a hit: its index, name and health left.
signal section_damaged(index: int, section_name: String, health: float)
## A damage section reached zero (once per loss): a mission can fail on it (Q5). The station goes on.
signal section_lost(index: int, section_name: String)

const ASSET_ID: String = "babylon5_station"
const DISPLAY_NAME: String = "BABYLON 5"
## The station's beacon is heard 1 000 km out, as a nav buoy's and the gate's (M3-T17, D69).
const BROADCAST_RANGE_M: float = 1.0e6
## Before the core's sync (-11), so the rows and Jolt see the drum at this tick's angle; after the frame's sample (-100).
const SPIN_PRIORITY: int = -50
## The bodies' collision kind (`CollisionLayers`): ships hit it, rocks do not, as the jumpgate.
const COLLISION_KIND: StringName = &"rock"
## The hull number behind the sections; never reduced (the `Damageable`s are invulnerable).
const HULL_MAX: float = 1.0e9
const PROVIDER: StringName = &"station"
const ACTIONS: Array[StringName] = [&"info", &"section", &"spin", &"goto", &"heal"]

var hardpoints: StationHardpoints = null
var sections: StationSections = null
var spin: StationSpin = StationSpin.new()
## False holds the drum still (`station spin off`, captures).
var spinning: bool = true
var frame_body: AnimatableBody3D = null
var drum_body: AnimatableBody3D = null
var frame_hull: Damageable = null
var drum_hull: Damageable = null
var targetable: Targetable = null
## The defence grid (M7-T07).
var grid: StationGrid = null
## The maintenance bots (M7-T11, Q11): ambient drones on loops round the hull, in the frame's and the drum's visuals.
var bots: BotFleet = null
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


func _init() -> void:
	add_to_group(WorldFrame.SHIFTABLE_GROUP)
	add_to_group(WorldFrame.ANCHORED_GROUP)
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
	grid = StationGrid.new()
	grid.build(self)
	add_child(grid)
	bots = BotFleet.new()
	if bots.build(self):
		add_child(bots)
	else:
		bots.free()
		bots = null
	return true


## The visuals `FarProp` shrinks and fades into its dot (`FarPropHost.dress_station`).
func far_visuals() -> Array[Node3D]:
	return [frame_piece, drum_pivot] as Array[Node3D]


func _ready() -> void:
	_register_surfaces()
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


## Takes `amount` off the damage section `index` as a hit would; true when that lost it.
func damage_section(index: int, amount: float) -> bool:
	if sections == null or index < 0 or index >= sections.count():
		return false
	var was_lost: bool = sections.is_lost(index)
	var lost_now: bool = sections.damage(index, amount)
	if frame_hull != null and not was_lost:
		frame_hull.zones.record_zone(index, amount)
	section_damaged.emit(index, String(sections.sections[index]["name"]), sections.health[index])
	return lost_now


## Every section whole again.
func heal() -> void:
	if sections != null:
		sections.restore()
	if frame_hull != null:
		frame_hull.zones.set_capacities(sections.max_health)


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
	frame_hull.hit_taken.connect(_on_hit.bind(StationHardpoints.FRAME))
	drum_hull.hit_taken.connect(_on_hit.bind(StationHardpoints.DRUM))
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
	var drawn: Array[Dictionary] = []
	for i: int in sections.count():
		var box: AABB = sections.sections[i]["aabb"]
		if sections.sections[i]["body"] == StationHardpoints.DRUM:
			box.position += drum_origin
		drawn.append({"zone": i, "aabb": box})
	Silhouette.set_station_sections(drawn)


# A piece's hull: its hit volumes, the station's faction, never falling (hits go to the sections).
func _hull(volumes: Array[HitShape], layout: StringName) -> Damageable:
	var entries: Array[Dictionary] = []
	for v: HitShape in volumes:
		entries.append(_entry(v))
	var hull := Damageable.new()
	hull.setup(entries, HULL_MAX, Factions.EARTH_ALLIANCE, false, false, layout)
	hull.invulnerable = true
	hull.stops_friendly_bolts = true
	return hull


# A hit volume back in `Hardpoints.collision`'s form, for `Damageable.setup`.
static func _entry(v: HitShape) -> Dictionary:
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


# A hit on one piece goes to the damage section it landed in.
func _on_hit(info: HitInfo, body: String) -> void:
	var node: Node3D = drum_body if body == StationHardpoints.DRUM else self
	if node == null or not node.is_inside_tree():
		return
	var local: Vector3 = node.global_transform.affine_inverse() * info.point
	var index: int = sections.section_at(body, local)
	if index >= 0:
		damage_section(index, info.damage)
	if grid != null:
		grid.take_hit(body, local, info.damage)  # the grid's mounts near the hit wear down too (M7-T07)


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
			return ConsoleResult.line("%s %.0f/%.0f%s" % [a, sections.health[index], sections.max_health[index],
					" (lost)" if lost else ""])
		&"heal":
			heal()
			return ConsoleResult.line("station sections whole")
		&"spin":
			if a != "on" and a != "off":
				return ConsoleResult.failure("station spin on|off")
			set_spinning(a == "on")
			return ConsoleResult.line("drum %s at %.1f deg" % ["turning" if spinning else "held", rad_to_deg(drum_angle)])
		&"goto":
			return _goto(a)
	return ConsoleResult.line("%s: %s; drum %.1f deg%s; %s; %s" % [DISPLAY_NAME, universe_position(), rad_to_deg(drum_angle),
			"" if spinning else " (held)", sections.describe(), _collision_text()])


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
	var body: String = String(point["body"])
	var at: Vector3 = to_world(point["position"], body)
	var look: Vector3 = to_world(point["look_at"], body)
	var up: Vector3 = Vector3.UP if absf((look - at).normalized().dot(Vector3.UP)) < 0.98 else Vector3.BACK
	main.ship.reset_to(Transform3D(Basis.looking_at((look - at).normalized(), up), at))
	var world: WorldFrame = WorldFrame.of(self)
	main.ship.linear_velocity = world.rest_velocity() if world != null else Vector3.ZERO
	main.ship.angular_velocity = Vector3.ZERO
	return ConsoleResult.line("at tour point %s" % point_name)
