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
## The hulls and bolts come as columns from the native core's rows (M4-T15, `SimCore`; the bolts read again at this
## priority, since they moved at 0) and the broad phase pairs them natively from the same rows; the resolver then looks up
## only the nodes the pairs name. Every world has a core (M4-T42); a tree with no world has nothing to resolve.
## With the core owning the bolts (M4-T35), a bolt's shooter, faction, damage and tint are columns
## of the table and a hit spends the row in the core; a projectile that still has a node (a beam, a missile, the player's
## bolts) is spent through its node as before.
## Every projectile kind (bolt, beam, missile, mine) is swept alike, with its own hit radius; a beam (M4-T12) lives for one
## resolve, so its first hull along the segment takes the hit and it is retired whether it hit or not. Rocks (M4-T29, §17.16)
## are `StaticRows` with no node: they stay in a grid of their own between ticks, rebuilt only when a rock changes, and a bolt
## that reaches one first is spent there (rocks never break; any bolt of another faction stops on one). The bolt is spent,
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
## Hulls gathered on the last tick, and projectile and rock pairs the rocks' grid tested (work counts, M4-T29).
var hulls_last_tick: int = 0
var static_pairs_visited: int = 0
## Wall-clock microseconds of the last tick's gather of hulls and bolts (a readout only).
var gather_us: int = 0
## Finds the pairs that pass the bounding-sphere test (M4-T08), natively over the core's rows.
var broad_phase: HitBroadPhase = HitBroadPhase.new()

# This tick's hulls (columns, index j) and projectiles (columns, index i), refilled every tick from the native core's rows
# (M4-T15). Nodes are looked up only for the pairs the broad phase gives.
var _hull_count: int = 0
var _body_ids := PackedInt64Array()
var _hull_ids := PackedInt64Array()
var _starts := PackedVector3Array()
var _velocities := PackedVector3Array()
var _bases := PackedVector3Array()  # three columns (the x, y and z axes) a hull
var _damageables: Array[Damageable] = []  # per hull, looked up when first needed (null until then)
var _to_body: Dictionary = {}  # hull -> Basis, transposed when first needed
var _bolt_ids := PackedInt64Array()
# The bolts in launch order (the core's, M4-T35).
var _bolt_order := PackedInt32Array()
var _hull_first := PackedInt32Array()
var _hull_next := PackedInt32Array()
var _rock_first := PackedInt32Array()
var _rock_next := PackedInt32Array()
var _bolt_starts := PackedVector3Array()
var _bolt_ends := PackedVector3Array()
var _bolt_radii := PackedFloat64Array()
var _beams := PackedInt32Array()
# What a hit lands with, per bolt (M4-T35), from the core's columns.
var _bolt_shooters := PackedInt64Array()
var _bolt_factions: Array = []
var _bolt_damage := PackedFloat64Array()
var _bolt_colors := PackedColorArray()
var _bolt_owned: int = 0  # rows at the front the core owns (spent in the core, not through a node)
var _sim: SimCore = null
var _delta: float = 0.0
var _source: StringName = &"none"
var _gather_frame: int = -1
# The rocks (M4-T29): their grid, kept until a rock changes, and the earliest rock hit `_earliest_rock` found.
var _rocks: HitBroadPhase = HitBroadPhase.new()
var _solid: StaticRows.Solid = null
var _rock_t: float = INF
var _rock_a := Vector3.ZERO
var _rock_b := Vector3.ZERO
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
		&"projectiles": {"get": func() -> int: return projectiles_last_tick, "doc": "Bolts in flight at the last tick's resolve"},
		&"hits": {"get": func() -> int: return hits_total, "doc": "Hits resolved this session"},
		&"last_hit": {"get": func() -> String: return last_hit, "doc": "The last hit: shooter -> target, damage"},
		&"pairs_tested": {"get": func() -> int: return pairs_tested, "doc": "Bolt and ship pairs swept on the last tick (past the distance cull)"},
		&"pairs_visited": {"get": func() -> int: return pairs_visited,
				"doc": "Bolt and ship pairs the broad phase put to the distance cull on the last tick (the work)"},
		&"hit_path": {"get": func() -> String: return String(broad_phase.path()),
				"doc": "Which code finds the pairs worth sweeping: native, or none without the library"},
		&"source": {"get": func() -> String: return String(_source),
				"doc": "Where the last tick's hulls and bolts came from: core (the native core's rows, M4-T15), or none with no core in the tree"},
		&"gather_us": {"get": func() -> int: return gather_us, "unit": "us",
				"doc": "Cost of the last tick's gather of hulls and bolts (profiling only, wall clock)"},
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
	pairs_tested = 0
	pairs_visited = 0
	friendly_fire = bool(Settings.get_value(&"friendly_fire"))
	var sim: SimCore = _gather(delta)
	gather_us = Time.get_ticks_usec() - started_us
	hulls_last_tick = _hull_count
	projectiles_last_tick = _bolt_ids.size()
	if sim == null:
		resolve_us = Time.get_ticks_usec() - started_us
		return
	var hull_count: int = _hull_count
	var keys: PackedInt64Array = broad_phase.pairs_core(sim.core, delta)
	pairs_visited = broad_phase.visited
	var rock_keys: PackedInt64Array = _rock_pairs(sim)
	var rock_count: int = _solid.ids.size()
	# Bolts come in table order on both lists; each bolt with a pair on either takes the earliest of its hull and rock
	# hits. The hits land in launch order (`_bolt_order`), the order the bolt nodes' group had, so an owned row and the
	# player's node bolt reaching one hull in the same tick give the kill to the one fired first.
	_pair_ranges(keys, hull_count, _hull_first, _hull_next)
	_pair_ranges(rock_keys, rock_count, _rock_first, _rock_next)
	for k: int in _bolt_ids.size():
		var i: int = _bolt_order[k] if k < _bolt_order.size() else k
		var first: int = _hull_first[i]
		var next: int = _hull_next[i]
		var rock_first: int = _rock_first[i]
		var rock_next: int = _rock_next[i]
		if next == first and rock_next == rock_first:
			continue
		# A hit handler may have retired a bolt later in the list, as the per-bolt checks before the broad phase allowed.
		if not _bolt_live(i):
			continue
		var hull_hit: bool = next > first and _earliest_hit(i, keys, first, next, hull_count)
		var rock: int = _earliest_rock(i, rock_keys, rock_first, rock_next, rock_count) if rock_next > rock_first else -1
		if rock >= 0 and (not hull_hit or _rock_t < _best_t):
			_land_on_rock(i, rock, delta)
		elif hull_hit:
			_land(i, delta)
	for i: int in _beams:
		_spend(i)
	resolve_us = Time.get_ticks_usec() - started_us


# Each bolt's run of pair keys `[first, next)` in `keys` (sorted by bolt index, `key / count` the bolt), empty for a bolt
# with no pair.
func _pair_ranges(keys: PackedInt64Array, count: int, first_out: PackedInt32Array, next_out: PackedInt32Array) -> void:
	var n: int = _bolt_ids.size()
	first_out.resize(n)
	next_out.resize(n)
	first_out.fill(0)
	next_out.fill(0)
	var at: int = 0
	while at < keys.size():
		@warning_ignore("integer_division")
		var i: int = keys[at] / count
		var start: int = at
		while at < keys.size() and keys[at] / count == i:
			at += 1
		first_out[i] = start
		next_out[i] = at


## Where the last gather came from: &"core" (the native core's rows, M4-T15), or &"none" with no core in the tree.
func source() -> StringName:
	return _source


## The broad phase alone, for the parity tests (M4-T15): `[keys, visited]`, the keys as `resolve` sees them.
func broad_phase_pairs(delta: float) -> Array:
	var sim: SimCore = _gather(delta)
	if sim == null:
		return [PackedInt64Array(), 0]
	return [broad_phase.pairs_core(sim.core, delta), broad_phase.visited]


# This tick's hulls and bolts from the core's rows (the core it read, returned); none, and null, with no core in the tree.
func _gather(delta: float) -> SimCore:
	_delta = delta
	_damageables.clear()
	_to_body.clear()
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim != null and _synced(sim):
		_source = &"core"
		var hulls: Array = sim.core.sweep_columns()
		_body_ids = hulls[0]
		_hull_ids = hulls[1]
		_starts = hulls[3]
		_velocities = hulls[4]
		_bases = hulls[6]
		_hull_count = _body_ids.size()
		var bolts: Array = sim.core.bolt_columns()
		_bolt_ids = bolts[0]
		_bolt_starts = bolts[1]
		_bolt_ends = bolts[2]
		_bolt_radii = bolts[3]
		_beams = bolts[5]
		_bolt_shooters = bolts[6]
		_bolt_factions = bolts[7]
		_bolt_damage = bolts[8]
		_bolt_colors = bolts[9]
		_bolt_owned = int(bolts[11])
		_bolt_order = bolts[14]
	else:
		_source = &"none"
		sim = null
		_hull_count = 0
		_bolt_ids.clear()
		_bolt_order.clear()
		_beams.clear()
		_bolt_owned = 0
	_sim = sim
	_damageables.resize(_hull_count)
	return sim


# The core's rows as of now: the tick's sync points in play; a second gather inside one physics frame (a test stepping
# the resolver by hand) reads everything again, since anything may have moved between.
func _synced(sim: SimCore) -> bool:
	var frame: int = Engine.get_physics_frames()
	var again: bool = _gather_frame == frame
	_gather_frame = frame
	if again:
		return sim.sync_now() and sim.sync_bolts_now()
	return sim.ensure_bolts_synced()


# Bolt `i`'s node, or null when it is gone or the bolt is a row the core owns.
func _bolt(i: int) -> Projectile:
	if i < _bolt_owned:
		return null
	return instance_from_id(_bolt_ids[i]) as Projectile if is_instance_id_valid(_bolt_ids[i]) else null


# Whether bolt `i` can still hit: an owned row not spent, or a node still live in the tree.
func _bolt_live(i: int) -> bool:
	if i < _bolt_owned:
		return _sim != null and bool(_sim.core.bolt_live(i))
	var bolt: Projectile = _bolt(i)
	return bolt != null and not bolt.is_spent() and not bolt.is_queued_for_deletion() and bolt.is_inside_tree()


# Retires bolt `i` after a hit: the row in the core, or the node.
func _spend(i: int) -> void:
	if i < _bolt_owned:
		if _sim != null:
			_sim.core.spend_bolt_row(i)
		return
	var bolt: Projectile = _bolt(i)
	if bolt != null:
		bolt.spend()


# Hull `j`'s `Damageable`, looked up when first needed.
func _damageable(j: int) -> Damageable:
	var found: Damageable = _damageables[j]
	if found == null:
		found = instance_from_id(_hull_ids[j]) as Damageable
		_damageables[j] = found
	return found


# Hull `j`'s basis (its body's `global_basis` at the gather) and its transpose, the latter made when first needed.
func _basis(j: int) -> Basis:
	return Basis(_bases[j * 3], _bases[j * 3 + 1], _bases[j * 3 + 2])


func _to_body_of(j: int) -> Basis:
	var found: Variant = _to_body.get(j)
	if found == null:
		found = _basis(j).transposed()
		_to_body[j] = found
	return found


# This tick's projectile and rock pairs that pass the sphere test, as `bolt * rocks + rock`, ascending; the rocks' grid is
# built again only when a rock changed.
func _rock_pairs(sim: SimCore) -> PackedInt64Array:
	var solid: StaticRows.Solid = StaticRows.solid()
	if solid != _solid:
		_solid = solid
		_rocks.keep(solid.positions, solid.radii)
	static_pairs_visited = 0
	if solid.ids.is_empty():
		return PackedInt64Array()
	var keys: PackedInt64Array = _rocks.kept_pairs_core(sim.core)
	static_pairs_visited = _rocks.visited
	return keys


# The earliest rock bolt `i` reaches among its pairs `keys[first..next)` (its index in `_solid`, with `_rock_*` set), or -1.
func _earliest_rock(i: int, keys: PackedInt64Array, first: int, next: int, rock_count: int) -> int:
	var best: int = -1
	_rock_t = INF
	var start: Vector3 = _bolt_starts[i]
	var p1: Vector3 = _bolt_ends[i]
	var bolt_faction: StringName = _bolt_factions[i]
	var hit_radius: float = _bolt_radii[i]
	for k: int in range(first, next):
		var s: int = keys[k] - i * rock_count
		if not friendly_fire and bolt_faction == _solid.factions[s]:
			continue  # a rock's own faction passes it, as a buoy's does
		var centre: Vector3 = _solid.positions[s]
		var a: Vector3 = start - centre
		var b: Vector3 = p1 - centre
		var t: float = SweepMath.segment_sphere(a, b, Vector3.ZERO, _solid.radii[s] + hit_radius)
		if t >= 0.0 and t < _rock_t:
			_rock_t = t
			_rock_a = a
			_rock_b = b
			best = s
	return best


# A bolt stopped by rock `s`: spent, sparks, and `hit_resolved` with the rock's row id as the target (nothing breaks).
func _land_on_rock(i: int, s: int, delta: float) -> void:
	var centre: Vector3 = _solid.positions[s]
	var local_point: Vector3 = _rock_a + _rock_t * (_rock_b - _rock_a)
	var relative: Vector3 = _rock_b - _rock_a
	var info := HitInfo.new(_solid.ids[s], _bolt_shooters[i], _bolt_factions[i], _bolt_damage[i], centre + local_point,
			-relative.normalized() if relative.length_squared() > 1e-12 else Vector3.ZERO,
			relative.length() / maxf(delta, 1e-6))
	_spend(i)
	hits_total += 1
	last_hit = "%s -> %s, 0.0 of %.1f applied" % [name_of(info.shooter_id), name_of(info.target_id), info.damage]
	if fx != null:
		_throw_sparks(info, centre, Vector3.ZERO)
	hit_resolved.emit(info)


# The earliest hit of bolt `i` among its pairs `keys[first..next)`, kept in `_best_*`; false when it hits nothing.
func _earliest_hit(i: int, keys: PackedInt64Array, first: int, next: int, hull_count: int) -> bool:
	var best_t: float = INF
	_best = -1
	var start: Vector3 = _bolt_starts[i]
	var p1: Vector3 = _bolt_ends[i]
	var shooter_id: int = _bolt_shooters[i]
	var bolt_faction: StringName = _bolt_factions[i]
	var hit_radius: float = _bolt_radii[i]
	for k: int in range(first, next):
		var j: int = keys[k] - i * hull_count
		var damageable: Damageable = _damageable(j)
		# Already destroyed this tick by another bolt (or gone since the gather).
		if damageable == null or damageable.hull.destroyed or _body_ids[j] == shooter_id \
				or not damageable.can_be_hit_by(bolt_faction, friendly_fire):
			continue
		pairs_tested += 1
		var to_body: Basis = _to_body_of(j)
		var t0: Vector3 = _starts[j]
		var a: Vector3 = to_body * (start - t0)
		var b: Vector3 = to_body * (p1 - (t0 + _velocities[j] * _delta))
		if SweepMath.segment_sphere(a, b, Vector3.ZERO, damageable.bounding_radius + hit_radius) < 0.0:
			continue
		var t: float = INF
		for shape: HitShape in damageable.shapes:
			var shape_t: float = shape.sweep(a, b, hit_radius)
			if shape_t >= 0.0 and shape_t < t:
				t = shape_t
		if t < best_t:
			best_t = t
			_best = j
			_best_t = t
			_best_a = a
			_best_b = b
	return _best >= 0


func _land(i: int, delta: float) -> void:
	var j: int = _best
	var damageable: Damageable = _damageable(j)
	var basis: Basis = _basis(j)
	var t: float = _best_t
	var a: Vector3 = _best_a
	var b: Vector3 = _best_b
	var move: Vector3 = _velocities[j] * _delta
	var t0: Vector3 = _starts[j]
	var local_point: Vector3 = a + t * (b - a)
	var relative: Vector3 = basis * (b - a)
	var shooter_id: int = _bolt_shooters[i]
	var info := HitInfo.new(_body_ids[j], shooter_id, _bolt_factions[i], _bolt_damage[i],
			t0 + move * t + basis * local_point,
			-relative.normalized() if relative.length_squared() > 1e-12 else Vector3.ZERO,
			relative.length() / maxf(delta, 1e-6))
	_spend(i)
	var sim: SimCore = SimCore.for_tree(get_tree())
	if sim != null:
		sim.note_hit(info.target_id, shooter_id)  # the turrets' attacker memory, in the sweep's order (M5-T21)
	_apply(damageable, info)
	# A destroyed hull is hidden and the explosion replaces the flash; a flash on a parked ship would never be processed.
	var body := instance_from_id(_body_ids[j]) as Node3D
	if body != null and body.is_visible_in_tree():
		var flash := ImpactFlash.create(_bolt_colors[i], hash([shooter_id, info.target_id, Engine.get_physics_frames()]))
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


## The display name of the body with this instance id (its `Targetable`'s, else the node name), "static <id>" for a row with
## no node (a rock), or "nobody".
static func name_of(body_id: int) -> String:
	if body_id == 0 or not is_instance_id_valid(body_id):
		return "static %d" % body_id if body_id != 0 and StaticRows.has(body_id) else "nobody"
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
