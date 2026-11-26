class_name CapitalWrecks
extends Node3D
## Plays every capital's staged break-up (M10-T11, D12.8; architecture §22.4): a `CapitalBreakup` each, from the death on.
## Every physics tick its wreck moves on, the held sections are placed on it, and each section whose time has come lets go:
## its `CapitalChunk` flies on its own motion (the wreck's at its centre, a kick outward, its own tumble), its blast is set off
## through `BlastResolver` (a D12.6 blast in the native batch, in the plan's order: hurting and pushing what is near, setting
## off mines and the deaths it causes) and drawn at its level of detail (an explosion from the pool, or a far flash with its
## energy), and its fires start. A death in the low-attention tier plays its blasts on the wreck's motion with no bodies.
##
## The chunks stay as wreckage; past `breakup.chunks_max` (`data/capitals/capitals.json`) the oldest wreck's are freed. A
## child of `World` at its origin (`attach`); its chunks are shiftable bodies, and the wrecks move with a rebase and keep
## their universe velocity through a boost.
##
## Console: `wrecks [clear]` lists the break-ups or frees every wreck's chunks; provider `breakups` (`info.md`).

## A break-up blast went off at `at` (World frame), with `spec` (for sounds).
signal blast_set_off(at: Vector3, spec: BlastSpec)

const NODE_NAME: String = "CapitalWrecks"
## After the hit resolver (200), before the rams (210): a tick's break-up blasts land after its hits.
const PHYSICS_PRIORITY: int = 205
const DEFAULT_CHUNKS_MAX: int = 96

## Who draws the blasts and fires (`DestructionDirector.attach_wrecks` sets it); none drawn without one.
var director: DestructionDirector = null
## Readouts: break-ups started, blasts set off, fires drawn.
var started: int = 0
var blasts: int = 0
var fires: int = 0
var last: String = ""

var _playing: Array[CapitalBreakup] = []
var _bodies: Dictionary = {}  # CapitalBreakup -> Array[CapitalChunk] (index by section; null for none), oldest first


## The world's wrecks, or null before the first break-up.
static func of(world: Node) -> CapitalWrecks:
	if world == null or not is_instance_valid(world):
		return null
	return world.get_node_or_null(NodePath(NODE_NAME)) as CapitalWrecks


## The world's wrecks, made on first use.
static func attach(world: Node) -> CapitalWrecks:
	var found: CapitalWrecks = of(world)
	if found != null or world == null or not is_instance_valid(world):
		return found
	var made := CapitalWrecks.new()
	world.add_child(made)
	return made


func _init() -> void:
	name = NODE_NAME
	process_physics_priority = PHYSICS_PRIORITY


func _ready() -> void:
	var world := get_parent() as WorldFrame
	if world != null and not world.rebased.is_connected(_on_rebased):
		world.rebased.connect(_on_rebased)
		world.boosted.connect(_on_boosted)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"wrecks",
			"List the capitals' break-ups and their wreckage, or free every wreck's chunks (clear)",
			[ConsoleArg.enum_optional(&"action", [&"list", &"clear"] as Array[StringName], &"list")]), _cmd_wrecks, self)
	DebugConsole.registry.register_provider(&"breakups", ConsoleVars.new({
		&"playing": {"get": func() -> int: return _playing.size(), "doc": "Break-ups still playing (sections or fires left)"},
		&"wrecks": {"get": func() -> int: return _bodies.size(), "doc": "Wrecks with chunks in the world"},
		&"chunks": {"get": func() -> int: return chunk_count(), "doc": "Capital chunks in the world"},
		&"started": {"get": func() -> int: return started, "doc": "Break-ups started"},
		&"blasts": {"get": func() -> int: return blasts, "doc": "Break-up blasts set off"},
		&"fires": {"get": func() -> int: return fires, "doc": "Fires drawn on loose chunks"},
		&"last": {"get": func() -> String: return last, "doc": "The last section to let go"},
	}), self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	for b: CapitalBreakup in _playing.duplicate():
		play(b, delta)


## Starts break-up `b`: its sections as held chunks when `with_bodies` (a death in play), then its first step at once (the
## section that blew lets go and sets off its blast in this tick).
func start(b: CapitalBreakup, with_bodies: bool) -> void:
	started += 1
	if with_bodies:
		_bodies[b] = _build(b)
		_trim()
	_playing.append(b)
	play(b, 0.0)


## Plays `b` `delta` seconds on: the wreck moves, held chunks follow it, due sections let go, due fires are drawn.
func play(b: CapitalBreakup, delta: float) -> void:
	var due: PackedInt32Array = b.wreck.advance(delta, WorldFrame.of(self))
	var bodies: Array = _bodies.get(b, [])
	for i: int in bodies.size():
		var chunk: CapitalChunk = bodies[i]
		if chunk != null and is_instance_valid(chunk) and not b.wreck.is_released(i):
			chunk.hold(b.wreck.chunk_transform(i))
	for i: int in due:
		_let_go(b, i, bodies)
	for fire: Array in b.fires_due():
		_fire(b, int(fire[0]), fire[1] as Vector3, bodies)
	if b.finished():
		_playing.erase(b)


## The break-ups still playing.
func playing() -> Array[CapitalBreakup]:
	return _playing


## The chunks of break-up `b` (index by section; null where a section has none), empty when it has none in the world.
func bodies_of(b: CapitalBreakup) -> Array:
	return _bodies.get(b, [])


## Capital chunks in the world.
func chunk_count() -> int:
	var n: int = 0
	for list: Array in _bodies.values():
		for chunk: Variant in list:
			n += 1 if chunk != null and is_instance_valid(chunk) else 0
	return n


## Frees every wreck's chunks (the plans still playing go on with no bodies).
func clear() -> void:
	for b: Variant in _bodies.keys():
		_free(b as CapitalBreakup)


# Section `index` lets go: its chunk flies, its blast goes off, its fires start.
func _let_go(b: CapitalBreakup, index: int, bodies: Array) -> void:
	last = "%s %s at %.1f s" % [b.label, b.names[index], b.wreck.age_s]
	var chunk: CapitalChunk = bodies[index] if index < bodies.size() else null
	if chunk != null and is_instance_valid(chunk):
		chunk.hold(b.wreck.chunk_transform(index))
		chunk.release(b.wreck.release_velocity(index), b.wreck.release_spin(index))
	b.light_fires(index)
	var spec: BlastSpec = b.blast_of(index)
	var at: Vector3 = b.blast_point(index)
	var velocity: Vector3 = b.wreck.point_velocity(b.wreck.offset_of(index))
	if director != null and is_instance_valid(director):
		director.draw_explosion(b.fireball_radius(index, spec), at, velocity, spec.energy_j() if spec != null else 0.0)
	if spec == null:
		return
	if b.blasts == 0:
		b.first_spec = spec
		b.first_at = at
	b.blasts += 1
	blasts += 1
	blast_set_off.emit(at, spec)
	BlastResolver.set_off(spec, at, b.faction)


# A fire on section `index`'s chunk at `local` (its frame): drawn only, where its body is (or its place on the wreck).
func _fire(b: CapitalBreakup, index: int, local: Vector3, bodies: Array) -> void:
	if director == null or not is_instance_valid(director):
		return
	var chunk: CapitalChunk = bodies[index] if index < bodies.size() else null
	if chunk == null or not is_instance_valid(chunk):
		return  # a wreck with no bodies (in the tier, or freed) burns unseen
	var at: Vector3 = chunk.global_transform * local
	var velocity: Vector3 = chunk.linear_velocity + chunk.angular_velocity.cross(at - chunk.global_position)
	if director.draw_explosion(float(b.numbers.get("fire_radius_m", 0.0)), at, velocity, 0.0, false):
		fires += 1


# The held chunks of `b`, one per section with a mesh or shapes, kept from colliding with each other.
func _build(b: CapitalBreakup) -> Array:
	var out: Array = []
	var layer: int = CollisionLayers.layer_of(&"capital")
	var mask: int = CollisionLayers.mask_of(&"capital")
	var made: Array[CapitalChunk] = []
	for i: int in b.names.size():
		var mesh: Mesh = b.meshes[i] if i < b.meshes.size() else null
		var shapes: Array[Dictionary] = []
		for shape: Variant in b.shapes[i]:
			shapes.append(shape as Dictionary)
		if mesh == null and shapes.is_empty():
			out.append(null)
			continue
		var chunk: CapitalChunk = CapitalChunk.create(b.names[i], mesh, b.skin_variant, shapes, b.to_chunk[i], b.mass_kg[i],
				layer, mask)
		chunk.ship_name = b.label
		chunk.box = b.boxes[i]
		chunk.transform = b.wreck.chunk_transform(i)
		add_child(chunk)
		chunk.reset_physics_interpolation()
		for other: CapitalChunk in made:
			chunk.add_collision_exception_with(other)
			other.add_collision_exception_with(chunk)
		made.append(chunk)
		out.append(chunk)
	return out


# Frees the oldest wrecks' chunks while there are more than the table allows.
func _trim() -> void:
	var cap: int = int(CapitalData.table("breakup").get("chunks_max", DEFAULT_CHUNKS_MAX))
	while chunk_count() > cap and _bodies.size() > 1:
		_free(_bodies.keys()[0] as CapitalBreakup)


func _free(b: CapitalBreakup) -> void:
	for chunk: Variant in _bodies.get(b, []):
		if chunk != null and is_instance_valid(chunk):
			(chunk as CapitalChunk).queue_free()
	_bodies.erase(b)


# A rebase moved the chunks with the world; the wrecks' held poses go with them.
func _on_rebased(offset: Vector3) -> void:
	for b: CapitalBreakup in _playing:
		b.wreck.shift(offset)


# A velocity rebase: the wrecks keep their universe velocity (their loose chunks are bodies and take it themselves).
func _on_boosted(dv: Vector3) -> void:
	for b: CapitalBreakup in _playing:
		b.wreck.boost(dv)


func _cmd_wrecks(args: Dictionary) -> ConsoleResult:
	if StringName(args[&"action"]) == &"clear":
		var n: int = chunk_count()
		clear()
		return ConsoleResult.line("freed %d chunk(s)" % n)
	var lines: PackedStringArray = []
	for b: CapitalBreakup in _bodies.keys():
		lines.append("%s: %d chunk(s), %d blast(s)%s" % [b.label, (_bodies[b] as Array).filter(func(c: Variant) -> bool:
				return c != null and is_instance_valid(c)).size(), b.blasts, ", playing" if _playing.has(b) else ""])
	for b: CapitalBreakup in _playing:
		if not _bodies.has(b):
			lines.append("%s: no bodies (in the tier), %d blast(s), playing" % [b.label, b.blasts])
	if lines.is_empty():
		return ConsoleResult.line("no break-ups")
	return ConsoleResult.line("\n".join(lines))
