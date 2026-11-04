class_name HitResolver
extends Node
## Swept hit detection for bolts (architecture §15.3, §15.5, D21). Once per physics tick, after every bolt has moved
## (`process_physics_priority` 200), it sweeps each bolt's flight this tick against every active `Damageable` hostile to it
## and not its shooter. With `settings.friendly_fire` (D31) every hull but the shooter's can be hit. Pure script maths
## (`SweepMath` through `HitShape`), no Jolt queries, so it is exact at any closing speed.
##
## Each bolt and target are compared in the target's body frame, using its start-of-tick pose (its body has not been
## stepped yet). A bounding-sphere test comes first, then each hit volume inflated by the bolt's hit radius; the earliest
## hit wins. The sphere test runs in `HitBroadPhase` (M4-T08, §17.7), which finds the pairs that pass it without testing every
## pair, natively when the library is loaded; the resolver sweeps only those, in the same order, so the hits are the same.
## Every projectile kind (bolt, beam, missile, mine) is swept alike, with its own hit radius. The bolt is spent,
## `Damageable.apply_hit` runs, an `ImpactFlash` is added and `hit_resolved` is emitted for the HUD and sound. Nothing is cached
## between ticks, so a `World.rebase()` changes nothing. The target's rotation during one
## tick is ignored.
##
## Console: provider `combat` (`projectiles`, `hits`, `last_hit`, `pairs_tested`, `pairs_visited`, `hit_path`, `resolve_us`)
## and commands `damage <amount> [player|target]` and `heal [player|target|all]`. `resolve_us` is wall clock, a profiling
## readout. It also registers the faction entries (`FactionConsole`), because `Factions` is static and has no node of its own.

## A bolt hit a ship; `info.applied` is set by then.
signal hit_resolved(info: HitInfo)

const LATE_PRIORITY: int = 200
const TARGET_CHOICES: Array[StringName] = [&"player", &"target"]
const HEAL_CHOICES: Array[StringName] = [&"player", &"target", &"all"]

## Bolts considered and ship pairs swept on the last tick, total hits, and the last tick's cost in microseconds.
var projectiles_last_tick: int = 0
var pairs_tested: int = 0
var hits_total: int = 0
var last_hit: String = "none"
var resolve_us: int = 0
## Projectile and hull pairs the broad phase put to the bounding-sphere test on the last tick (the work count).
var pairs_visited: int = 0
## Finds the pairs that pass the bounding-sphere test (M4-T08); a test may swap in its own.
var broad_phase: HitBroadPhase = HitBroadPhase.new()

# This tick's hulls (parallel arrays, index j) and projectiles (index i), refilled every tick.
var _damageables: Array[Damageable] = []
var _bodies: Array[Node3D] = []
var _body_ids := PackedInt64Array()
var _starts := PackedVector3Array()
var _bases: Array[Basis] = []
var _to_body: Array[Basis] = []
var _moves := PackedVector3Array()
var _mids := PackedVector3Array()
var _reach := PackedFloat64Array()
var _bolts: Array[Projectile] = []
var _bolt_starts := PackedVector3Array()
var _bolt_ends := PackedVector3Array()
var _bolt_mids := PackedVector3Array()
var _bolt_reach := PackedFloat64Array()
# The earliest hit `_earliest_hit` found: the hull, the time along the tick and the segment in the hull's frame.
var _best: int = -1
var _best_t: float = INF
var _best_a := Vector3.ZERO
var _best_b := Vector3.ZERO
## `settings.friendly_fire` as of the last tick.
var friendly_fire: bool = false
## Throws the sparks of a hull hit (`Main` sets it); none without it.
var fx: FxPool = null


func _init() -> void:
	process_physics_priority = LATE_PRIORITY


func _ready() -> void:
	DebugConsole.registry.register_provider(&"combat", ConsoleVars.new({
		&"projectiles": {"get": func() -> int: return projectiles_last_tick, "doc": "Bolts swept on the last tick"},
		&"hits": {"get": func() -> int: return hits_total, "doc": "Hits resolved this session"},
		&"last_hit": {"get": func() -> String: return last_hit, "doc": "The last hit: shooter -> target, damage"},
		&"pairs_tested": {"get": func() -> int: return pairs_tested, "doc": "Bolt and ship pairs swept on the last tick (past the distance cull)"},
		&"pairs_visited": {"get": func() -> int: return pairs_visited,
				"doc": "Bolt and ship pairs the broad phase put to the distance cull on the last tick (the work)"},
		&"hit_path": {"get": func() -> String: return String(broad_phase.path()),
				"doc": "Which code finds the pairs worth sweeping: native or gdscript"},
		&"resolve_us": {"get": func() -> int: return resolve_us, "unit": "us",
				"doc": "Cost of the last tick's resolve (profiling only, wall clock)"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"damage",
			"Hit the player or the selected target with no shooter (god mode applies to the player)",
			[ConsoleArg.float_required(&"amount", 0.0), ConsoleArg.enum_optional(&"who", TARGET_CHOICES, &"player")]),
			_cmd_damage, self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"heal", "Restore the player's, the target's or every hull",
			[ConsoleArg.enum_optional(&"who", HEAL_CHOICES, &"player")]), _cmd_heal, self)
	DebugConsole.registry.register_provider(&"factions", FactionConsole.provider(), self)
	DebugConsole.registry.register_command(FactionConsole.command(), FactionConsole.run, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func _physics_process(delta: float) -> void:
	resolve(delta)


## One tick of hit detection with time step `delta`. `_physics_process` calls it; public so tests can step it.
func resolve(delta: float) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only, never gameplay time
	projectiles_last_tick = 0
	pairs_tested = 0
	pairs_visited = 0
	friendly_fire = bool(Settings.get_value(&"friendly_fire"))
	_gather_targets(delta)
	_gather_bolts()
	var hull_count: int = _damageables.size()
	var keys: PackedInt64Array = broad_phase.pairs(_bolt_mids, _bolt_reach, _mids, _reach)
	pairs_visited = broad_phase.visited
	var next: int = 0  # the first pair not yet taken; pairs come in bolt order
	for i: int in _bolts.size():
		var first: int = next
		while next < keys.size() and keys[next] / hull_count == i:
			next += 1
		var bolt: Projectile = _bolts[i]
		# A hit handler may have retired a bolt later in the list, as the per-bolt checks before the broad phase allowed.
		if bolt.is_spent() or bolt.is_queued_for_deletion() or not bolt.is_inside_tree():
			continue
		projectiles_last_tick += 1
		if next > first and _earliest_hit(bolt, i, keys, first, next, hull_count):
			_land(bolt, delta)
	resolve_us = Time.get_ticks_usec() - started_us


# Everything about the active hulls that does not depend on the bolt, as of this tick's start.
func _gather_targets(delta: float) -> void:
	_damageables.clear()
	_bodies.clear()
	_body_ids.clear()
	_starts.clear()
	_bases.clear()
	_to_body.clear()
	_moves.clear()
	_mids.clear()
	_reach.clear()
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable == null or not damageable.is_active():
			continue
		var body: Node3D = damageable.body()
		var velocity: Vector3 = Vector3.ZERO
		if body is RigidBody3D:
			velocity = (body as RigidBody3D).linear_velocity
		var basis: Basis = body.global_basis
		_damageables.append(damageable)
		_bodies.append(body)
		_body_ids.append(body.get_instance_id())
		_starts.append(body.global_position)
		_bases.append(basis)
		_to_body.append(basis.transposed())
		_moves.append(velocity * delta)
		_mids.append(body.global_position + velocity * (0.5 * delta))
		_reach.append(damageable.bounding_radius + velocity.length() * delta * 0.5)


# Every live projectile and the sphere round the segment it flew this tick.
func _gather_bolts() -> void:
	_bolts.clear()
	_bolt_starts.clear()
	_bolt_ends.clear()
	_bolt_mids.clear()
	_bolt_reach.clear()
	for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
		var bolt := node as Projectile
		if bolt == null or bolt.is_spent() or bolt.is_queued_for_deletion() or not bolt.is_inside_tree():
			continue
		var p1: Vector3 = bolt.global_position
		var start: Vector3 = p1 - bolt.last_step
		_bolts.append(bolt)
		_bolt_starts.append(start)
		_bolt_ends.append(p1)
		_bolt_mids.append(start + bolt.last_step * 0.5)
		_bolt_reach.append(bolt.last_step.length() * 0.5 + bolt.hit_radius_m)


# The earliest hit of bolt `i` among its pairs `keys[first..next)`, kept in `_best_*`; false when it hits nothing.
func _earliest_hit(bolt: Projectile, i: int, keys: PackedInt64Array, first: int, next: int, hull_count: int) -> bool:
	var best_t: float = INF
	_best = -1
	var start: Vector3 = _bolt_starts[i]
	var p1: Vector3 = _bolt_ends[i]
	for k: int in range(first, next):
		var j: int = keys[k] - i * hull_count
		var damageable: Damageable = _damageables[j]
		# Already destroyed this tick by another bolt.
		if damageable.hull.destroyed or _body_ids[j] == bolt.shooter_id or not damageable.can_be_hit_by(bolt.faction, friendly_fire):
			continue
		pairs_tested += 1
		var to_body: Basis = _to_body[j]
		var t0: Vector3 = _starts[j]
		var a: Vector3 = to_body * (start - t0)
		var b: Vector3 = to_body * (p1 - (t0 + _moves[j]))
		if SweepMath.segment_sphere(a, b, Vector3.ZERO, damageable.bounding_radius + bolt.hit_radius_m) < 0.0:
			continue
		var t: float = INF
		for shape: HitShape in damageable.shapes:
			var shape_t: float = shape.sweep(a, b, bolt.hit_radius_m)
			if shape_t >= 0.0 and shape_t < t:
				t = shape_t
		if t < best_t:
			best_t = t
			_best = j
			_best_t = t
			_best_a = a
			_best_b = b
	return _best >= 0


func _land(bolt: Projectile, delta: float) -> void:
	var j: int = _best
	var damageable: Damageable = _damageables[j]
	var basis: Basis = _bases[j]
	var t: float = _best_t
	var a: Vector3 = _best_a
	var b: Vector3 = _best_b
	var move: Vector3 = _moves[j]
	var t0: Vector3 = _starts[j]
	var local_point: Vector3 = a + t * (b - a)
	var relative: Vector3 = basis * (b - a)
	var info := HitInfo.new(_body_ids[j], bolt.shooter_id, bolt.faction, bolt.damage,
			t0 + move * t + basis * local_point,
			-relative.normalized() if relative.length_squared() > 1e-12 else Vector3.ZERO,
			relative.length() / maxf(delta, 1e-6))
	bolt.spend()
	_apply(damageable, info)
	# A destroyed hull is hidden and the explosion replaces the flash; a flash on a parked ship would never be processed.
	var body: Node3D = _bodies[j]
	if body.is_visible_in_tree():
		var flash := ImpactFlash.create(bolt.color, hash([bolt.shooter_id, info.target_id, Engine.get_physics_frames()]))
		flash.position = local_point
		body.add_child(flash)
		flash.reset_physics_interpolation()
	if fx != null:
		_throw_sparks(info, t0 + move * t, move / maxf(delta, 1e-6))
	hit_resolved.emit(info)


# Sparks fly back off the hull, mirrored about the surface (taken as radial from the centre).
func _throw_sparks(info: HitInfo, hull_centre: Vector3, hull_velocity: Vector3) -> void:
	fx.burst(FxSpecs.HIT, info.point, FxSpecs.hit_direction(-info.normal, info.point - hull_centre), hull_velocity)


func _apply(damageable: Damageable, info: HitInfo) -> void:
	hits_total += 1
	damageable.apply_hit(info)
	last_hit = "%s -> %s, %.1f of %.1f applied" % [name_of(info.shooter_id), name_of(info.target_id), info.applied,
			info.damage]


## The display name of the body with this instance id (its `Targetable`'s, else the node name), or "nobody".
static func name_of(body_id: int) -> String:
	if body_id == 0 or not is_instance_id_valid(body_id):
		return "nobody"
	var body := instance_from_id(body_id) as Node
	if body == null:
		return "nobody"
	for child: Node in body.get_children():
		if child is Targetable and not (child as Targetable).display_name.is_empty():
			return (child as Targetable).display_name
	return String(body.name)


# --- console -----------------------------------------------------------------------------------------------------


# The player's hull (the one that respects god mode).
func _player_damageable() -> Damageable:
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable != null and damageable.respects_god_mode:
			return damageable
	return null


# The hull of the ship the player has selected, or null.
func _target_damageable() -> Damageable:
	var player: Damageable = _player_damageable()
	var ship := player.body() as Ship if player != null else null
	if ship == null or not ship.targeting.system.has_selection():
		return null
	var selected_id: int = ship.targeting.selected_id()
	if not is_instance_id_valid(selected_id):
		return null
	var targetable := instance_from_id(selected_id) as Targetable
	return Damageable.of(targetable.get_parent()) if targetable != null else null


func _cmd_damage(args: Dictionary) -> ConsoleResult:
	var who: StringName = StringName(args[&"who"])
	var damageable: Damageable = _player_damageable() if who == &"player" else _target_damageable()
	if damageable == null:
		return ConsoleResult.failure("no %s hull to damage" % who)
	var body: Node3D = damageable.body()
	var info := HitInfo.new(body.get_instance_id(), 0, &"", float(args[&"amount"]), body.global_position, Vector3.ZERO, 0.0,
			HitInfo.CAUSE_CONSOLE)
	_apply(damageable, info)
	hit_resolved.emit(info)
	return ConsoleResult.line("%s: %.1f applied of %.1f, hull %.1f / %.1f%s" % [who, info.applied, info.damage,
			damageable.hull.hp, damageable.hull.max_hp, " (destroyed)" if damageable.hull.destroyed else ""])


func _cmd_heal(args: Dictionary) -> ConsoleResult:
	var who: StringName = StringName(args[&"who"])
	var healed: Array[Damageable] = []
	match who:
		&"all":
			for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
				if node is Damageable:
					healed.append(node as Damageable)
		&"target":
			var target: Damageable = _target_damageable()
			if target != null:
				healed.append(target)
		_:
			var player: Damageable = _player_damageable()
			if player != null:
				healed.append(player)
	if healed.is_empty():
		return ConsoleResult.failure("no %s hull to heal" % who)
	for damageable: Damageable in healed:
		damageable.restore()
	return ConsoleResult.line("restored %d hull(s)" % healed.size())
