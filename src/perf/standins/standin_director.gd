class_name StandinDirector
extends Node3D
## The battle's stand-ins in play (M4-T07, architecture §17.6): `World/Standins`, an identity container `Main` makes for the
## bench runner. It holds the capitals, the asteroid field, the mine belts and the moon, steps every capital's engines, guns,
## interceptors and beam lasers once per tick (priority -5: after the AI drivers built the tick's contact scan, before anything
## moves), keeps `missile_target` missiles in flight (M4-T12), steps the mines, runs the carriers' launch cycle through the
## runner's `launcher`, and counts the battle per entity type for the `perf` probe. Bench-only: no scenario spawns stand-ins.
##
## Interceptors find what is in reach through the hit broad phase's grid (one query a tick for every interceptor due), and so
## do the mines. Missiles and beams fire at each capital's strike target: its nearest hostile fighter within the missile's
## reach, looked up again when older than `STRIKE_RETARGET_TICKS`.
##
## With the core on and `perf_native_weapons` set (M4-T20, §17.13), the guns, interceptors, beams, strike targets, missile
## launches and mine triggers are decided by `NativeWeapons` over the core's rows in one call a tick, and this node does
## what they decide (bolts, kills, beams, launches, blasts); the GDScript below is the reference, and either path carries
## on from the other's state.
##
## `last_us` is the stand-ins' own cost in the latest tick (wall clock, profiling only); it sits inside the `flight` stage.
## `part_us` splits it by part (`PART_NAMES`), summed since `restart_weapon_counters`, with `ticks` the ticks it covers.

enum Count { FIGHTERS_NEAR, FIGHTERS_FAR, CAPITALS, TURRETS, INTERCEPTORS, BEAMS, MISSILES, MINES, ASTEROIDS, LAUNCHES, SIDES }
const COUNT_NAMES: Array[StringName] = [&"fighters_near", &"fighters_far", &"capitals", &"turrets", &"interceptors", &"beams",
		&"missiles", &"mines", &"asteroids", &"launches", &"sides"]

const PRIORITY: int = -5
## Fighters within this of the player are the near set (the tier's radius to come, M4-T21), m.
const NEAR_RADIUS_M: float = 10000.0
## A carrier releases one fighter of its side and takes it back at its bay this often (N holds), s.
const LAUNCH_PERIOD_S: float = 5.0
## A capital's strike target is looked up again when older than this, ticks.
const STRIKE_RETARGET_TICKS: int = 30
## At most this many missiles leave in one tick, so a gap in the count fills over a few ticks.
const MAX_MISSILE_LAUNCHES_PER_TICK: int = 2
## Hulls larger than this are capitals, not fighters, m.
const FIGHTER_RADIUS_MAX_M: float = TurretStandin.FIGHTER_RADIUS_MAX_M
enum Part { GATHER, ENGINES_GUNS, INTERCEPTORS, BEAMS, MISSILES, MINES, LAUNCHES }
const PART_NAMES: Array[StringName] = [&"gather", &"engines_guns", &"interceptors", &"beams", &"missiles", &"mines", &"launches"]

var world: WorldFrame = null
var projectiles: Node3D = null
## For the near and far fighter counts.
var ships: ShipPool = null
var player: Node3D = null
## Counts and steps only while active (the bench runner turns it on for a battle).
var active: bool = false
## How many sides fly (the per-entity counter).
var sides: int = 0
## `func(carrier: CapitalStandin) -> bool`: a launch is due; true when a fighter left the bay.
var launcher: Callable = Callable()
## Bolts the interceptors shot down, and fighters launched, since `clear`.
var intercepts: int = 0
var launches: int = 0
## How many missiles to keep in flight (the mix's; 0 for none), and what the weapons did since `clear` (M4-T12).
var missile_target: int = 0
var missile_intercepts: int = 0
var missile_launches: int = 0
var beam_shots: int = 0
var detonations: int = 0
## The latest tick's counts, by `Count`.
var counts: PackedInt64Array = PackedInt64Array()
var last_us: int = 0
## Each part's cost summed over `ticks` active ticks since `clear`, by `Part` (profiling only).
var part_us: PackedInt64Array = PackedInt64Array()
var ticks: int = 0
## False forces the GDScript stand-ins (a test pairing them with the native rows).
var use_native_weapons: bool = true

var _capitals: Array[CapitalStandin] = []
var _field: AsteroidField = null
var _mines: MineStandin = null
var _grid: HitBroadPhase = HitBroadPhase.new()
var _strike: Dictionary = {}  # capital -> [target body id, tick it was looked up]
var _capital_turn: int = 0
# This tick's hulls that fly (fighters, capitals, the player): parallel arrays.
var _hulls: Array[Damageable] = []
var _hull_at := PackedVector3Array()
var _hull_reach := PackedFloat64Array()
var _hull_factions: Array[StringName] = []
# This tick's projectiles in flight but beams, with their places.
var _shots: Array[Projectile] = []
var _shot_at := PackedVector3Array()
var _missiles_flying: int = 0
var _gravity: GravityStandin = null
var _tick: int = 0
var _next_launch: Dictionary = {}  # carrier -> sim time of its next launch
var _last_frame: int = -1
var _native: NativeWeapons = null  # bound while the native rows step the weapons
var _native_dirty: bool = true  # the capitals or mines changed since the rows were bound
var _path: StringName = &"gdscript"


func _init() -> void:
	process_physics_priority = PRIORITY
	counts.resize(COUNT_NAMES.size())
	part_us.resize(PART_NAMES.size())


func _exit_tree() -> void:
	_leave_native()


func _physics_process(delta: float) -> void:
	if not active:
		_leave_native()
		return
	step(delta, SimClock.now(), ContactScan.shared(get_tree()))


## One tick of every stand-in at sim time `now_s`, the guns choosing from `scan`; then the counts.
func step(delta: float, now_s: float, scan: ContactScan) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only
	_tick += 1
	ticks += 1
	var native: NativeWeapons = _native_weapons()
	_path = &"native" if native != null else &"gdscript"
	if native != null:
		_step_native(native, delta, now_s, started_us)
		return
	_gather_hulls()
	_gather_shots()
	var mark_us: int = _mark(Part.GATHER, started_us)
	var gun_index: int = 0
	_plan_launches(now_s)
	for cap: CapitalStandin in _capitals:
		if not is_instance_valid(cap) or not cap.is_inside_tree():
			continue
		cap.step_engines(delta)
		for gun: TurretStandin in cap.guns():
			if (_tick + gun_index) % TurretStandin.RETARGET_TICKS == 0:
				gun.retarget(scan)
			gun.step_gun(delta, now_s, projectiles)
			gun_index += 1
	mark_us = _mark(Part.ENGINES_GUNS, mark_us)
	_step_interceptors()
	mark_us = _mark(Part.INTERCEPTORS, mark_us)
	_step_beams(now_s)
	mark_us = _mark(Part.BEAMS, mark_us)
	_launch_missiles(now_s)
	mark_us = _mark(Part.MISSILES, mark_us)
	if _mines != null and is_instance_valid(_mines):
		detonations += _mines.step(_tick, now_s, _hulls, _hull_at, _hull_reach, _hull_factions)
	mark_us = _mark(Part.MINES, mark_us)
	_finish(now_s, mark_us, started_us)


# The carriers' launches, the cost and the counts: the end of a tick on either path.
func _finish(now_s: float, mark_us: int, started_us: int) -> void:
	var launched: int = 0
	for cap: CapitalStandin in _capitals:
		if is_instance_valid(cap) and cap.is_carrier() and launcher.is_valid() and now_s >= float(_next_launch.get(cap, INF)):
			_next_launch[cap] = float(_next_launch[cap]) + LAUNCH_PERIOD_S
			if bool(launcher.call(cap)):
				launched += 1
	_mark(Part.LAUNCHES, mark_us)
	launches += launched
	last_us = Time.get_ticks_usec() - started_us
	_last_frame = Engine.get_physics_frames()
	_count(launched)


# One tick on the native rows: they decide the guns' shots, the interceptors' kills, the beams, the launches and the
# mines' triggers in one call; this does what they decided, in the GDScript's order.
func _step_native(native: NativeWeapons, delta: float, now_s: float, started_us: int) -> void:
	native.refresh_relations()
	var mark_us: int = _mark(Part.GATHER, started_us)
	_plan_launches(now_s)
	for cap: CapitalStandin in _capitals:
		if is_instance_valid(cap) and cap.is_inside_tree():
			cap.step_engines(delta)
	var intercept_ticks: int = maxi(1, roundi(TurretStandin.INTERCEPT_INTERVAL_S * Engine.physics_ticks_per_second))
	var beam_ticks: int = maxi(1, roundi(BeamStandin.INTERVAL_S * Engine.physics_ticks_per_second))
	var out: Array = native.rows.step(_tick, now_s, delta, intercept_ticks, beam_ticks, missile_target,
			MAX_MISSILE_LAUNCHES_PER_TICK)
	var gun_rows: PackedInt32Array = out[0]
	var bolt_at: PackedVector3Array = out[1]
	var bolt_velocity: PackedVector3Array = out[2]
	for k: int in gun_rows.size():
		var gun := native.turrets[gun_rows[k]] as TurretStandin
		TurretStandin.launch_bolt(gun.capital, bolt_at[k], bolt_velocity[k], now_s, projectiles)
	mark_us = _mark(Part.ENGINES_GUNS, mark_us)
	var spent: PackedInt64Array = out[3]
	var spent_missile: PackedByteArray = out[4]
	for k: int in spent.size():
		var shot := instance_from_id(spent[k]) as Projectile
		if shot != null:
			shot.spend()
		intercepts += 1
		missile_intercepts += spent_missile[k]
	mark_us = _mark(Part.INTERCEPTORS, mark_us)
	var beam_rows: PackedInt32Array = out[5]
	var beam_targets: PackedVector3Array = out[6]
	for k: int in beam_rows.size():
		(native.turrets[beam_rows[k]] as BeamStandin).fire(beam_targets[k], now_s, projectiles)
		beam_shots += 1
	mark_us = _mark(Part.BEAMS, mark_us)
	var launch_caps: PackedInt32Array = out[7]
	var launch_targets: PackedInt64Array = out[8]
	for k: int in launch_caps.size():
		var cap: CapitalStandin = native.capitals[launch_caps[k]]
		var target := instance_from_id(launch_targets[k]) as Node3D
		var bow: Vector3 = cap.global_position - cap.global_basis.z * (cap.length_m() * 0.5 + 10.0)
		MissileStandin.launch(projectiles, bow, target, cap.get_instance_id(), cap.faction, now_s)
		missile_launches += 1
	_missiles_flying = out[9]
	mark_us = _mark(Part.MISSILES, mark_us)
	if native.mines != null and is_instance_valid(native.mines):
		detonations += native.mines.step_native(_tick, now_s, _walked_hulls)
	mark_us = _mark(Part.MINES, mark_us)
	_finish(now_s, mark_us, started_us)


# The hulls the GDScript's mines would walk this tick, in its order (gathered only when a mine goes off).
func _walked_hulls() -> Array:
	_gather_hulls()
	return _hulls


## Which code stepped the weapons in the latest tick: &"native" (the rows) or &"gdscript" (the stand-ins).
func weapons_path() -> StringName:
	return _path


## Copies the native rows' state into the stand-ins' nodes (turrets, strike targets, the launch turn), so a reader of the
## nodes sees the rows' state; the rows keep stepping. Nothing without the rows.
func pull_native_state() -> void:
	if _native == null:
		return
	_native.pull_turrets()
	_capital_turn = _native.pull_strike(_strike)


# The native rows when they may step this tick (the setting, the library, a core synced this frame with no body touched
# since), bound afresh when the capitals or mines changed; else null, with any state they held handed back to the nodes.
func _native_weapons() -> NativeWeapons:
	var sim: SimCore = null
	if use_native_weapons and bool(Settings.get_value(&"perf_native_weapons")) and NativeWeapons.available():
		sim = SimCore.for_tree(get_tree())
	var ready: bool = sim != null and sim.synced_frame == Engine.get_physics_frames() and int(sim.core.touched_count()) == 0
	if not ready or (_native != null and (_native_dirty or _native.sim != sim)):
		_leave_native()
	if not ready:
		MissileStandin.native_rows = null
		return null
	if _native == null:
		_native = NativeWeapons.bind(sim, _capitals, mines())
		_native.push_strike(_strike, _capital_turn)
		_native_dirty = false
	MissileStandin.native_rows = _native.rows
	return _native


# Hands the rows' state back to the nodes and lets go of them.
func _leave_native() -> void:
	if _native == null:
		return
	pull_native_state()
	_native.unbind_mines()
	_native = null
	if MissileStandin.native_rows != null:
		MissileStandin.native_rows = null


## The stand-ins' cost in the current tick, us (0 when they did not run in it).
func us_this_tick() -> int:
	return last_us if _last_frame == Engine.get_physics_frames() else 0


## A capital of `cls` for `faction` at `at` (universe), facing `basis`, cruising at `velocity`, its guns along its nose.
func add_capital(cls: StringName, faction: StringName, display_name: String, at: UniversePos, basis: Basis,
		velocity: Vector3) -> CapitalStandin:
	var cap: CapitalStandin = CapitalStandin.create(cls, faction, display_name, velocity)
	cap.world = world
	world.spawn(cap, at, basis, self)
	cap.linear_velocity = velocity
	for gun: TurretStandin in cap.guns():
		gun.axis = -cap.global_basis.z
	_capitals.append(cap)
	_native_dirty = true
	return cap


## The mine belts: `rows` (`offset` m from `anchor`, `faction` the layer's).
func add_mines(rows: Array[Dictionary], anchor: UniversePos) -> MineStandin:
	remove_mines()
	_native_dirty = true
	_mines = MineStandin.new()
	_mines.name = "Mines"
	_mines.world = world
	world.spawn(_mines, anchor, Basis.IDENTITY, self)
	_mines.build(rows)
	return _mines


func remove_mines() -> void:
	_native_dirty = true
	if _mines != null and is_instance_valid(_mines):
		remove_child(_mines)  # its rows leave `StaticRows` as it leaves the tree
		_mines.queue_free()
	_mines = null


func mines() -> MineStandin:
	return _mines if _mines != null and is_instance_valid(_mines) else null


## The body a missile flies at (instance id), 0 for none or for a projectile that is not a guided missile.
func missile_target_of(missile: Projectile) -> int:
	var guide: MissileStandin = MissileStandin.of(missile)
	return guide.target_id if guide != null else 0


## The asteroid field: `rocks` (`offset` m from `anchor`, `radius` m), built into this world's physics space.
func add_asteroids(rocks: Array[Dictionary], anchor: UniversePos) -> AsteroidField:
	remove_asteroids()
	_field = AsteroidField.new()
	_field.name = "Asteroids"
	world.spawn(_field, anchor, Basis.IDENTITY, self)
	_field.build(rocks, world.get_world_3d().space, world)
	world.rebased.connect(_field.on_rebased)
	return _field


## The moon: a point source at `at` (universe) with parameter `gm` (m^3/s^2), installed as the world's environment field.
func add_gravity(at: UniversePos, gm: float) -> GravityStandin:
	remove_gravity()
	_gravity = GravityStandin.new()
	_gravity.name = "Gravity"
	add_child(_gravity)
	_gravity.install(world, at, gm)
	return _gravity


func remove_gravity() -> void:
	if _gravity != null and is_instance_valid(_gravity):
		_gravity.uninstall()
		remove_child(_gravity)
		_gravity.queue_free()
	_gravity = null


func remove_asteroids() -> void:
	if _field != null and is_instance_valid(_field):
		if world.rebased.is_connected(_field.on_rebased):
			world.rebased.disconnect(_field.on_rebased)
		_field.free_bodies()
		remove_child(_field)
		_field.queue_free()
	_field = null


## Removes every stand-in and stops; the counters start over.
func clear() -> void:
	active = false
	_leave_native()
	for cap: CapitalStandin in _capitals:
		if is_instance_valid(cap):
			remove_child(cap)
			cap.queue_free()
	_capitals.clear()
	remove_asteroids()
	remove_mines()
	remove_gravity()
	_next_launch.clear()
	_strike.clear()
	launcher = Callable()
	sides = 0
	intercepts = 0
	launches = 0
	missile_target = 0
	restart_weapon_counters()
	counts.fill(0)
	_hulls.clear()
	_shots.clear()


func capitals() -> Array[CapitalStandin]:
	return _capitals


func asteroid_count() -> int:
	return _field.count() if _field != null and is_instance_valid(_field) else 0


func turret_count() -> int:
	var n: int = 0
	for cap: CapitalStandin in _capitals:
		n += cap.guns().size()
	return n


func interceptor_count() -> int:
	var n: int = 0
	for cap: CapitalStandin in _capitals:
		n += cap.interceptors().size()
	return n


func beam_count() -> int:
	var n: int = 0
	for cap: CapitalStandin in _capitals:
		n += cap.beams().size()
	return n


## Starts the weapons' counts and the parts' costs over (a bench's measured window).
func restart_weapon_counters() -> void:
	missile_intercepts = 0
	missile_launches = 0
	beam_shots = 0
	detonations = 0
	ticks = 0
	part_us.fill(0)


## Each part's mean cost per active tick since `clear`, us, by name (profiling only).
func part_means_us() -> Dictionary:
	var out: Dictionary = {}
	for i: int in PART_NAMES.size():
		out[String(PART_NAMES[i])] = float(part_us[i]) / float(maxi(ticks, 1))
	return out


# Adds the time since `since_us` to `part`; returns now.
func _mark(part: Part, since_us: int) -> int:
	var now_us: int = Time.get_ticks_usec()
	part_us[part] += now_us - since_us
	return now_us


# Every hull that flies this tick (the pool's fighters, the capitals and the player; in a test, every rigid body's hull).
func _gather_hulls() -> void:
	_hulls.clear()
	_hull_at.clear()
	_hull_reach.clear()
	_hull_factions.clear()
	if ships != null and is_instance_valid(ships):
		for c: Combatant in ships.alive():
			_add_hull(c.damageable)
		for cap: CapitalStandin in _capitals:
			if is_instance_valid(cap):
				_add_hull(cap.damageable)
		if player != null and is_instance_valid(player):
			_add_hull(Damageable.of(player))
		return
	for node: Node in get_tree().get_nodes_in_group(Damageable.GROUP):
		var damageable := node as Damageable
		if damageable != null and damageable.body() is RigidBody3D:
			_add_hull(damageable)


func _add_hull(damageable: Damageable) -> void:
	if damageable == null or not damageable.is_active():
		return
	_hulls.append(damageable)
	_hull_at.append(damageable.body().global_position)
	_hull_reach.append(damageable.bounding_radius)
	_hull_factions.append(damageable.faction)


# Every projectile in flight but beams (an interceptor's quarry, the missile count).
func _gather_shots() -> void:
	_shots.clear()
	_shot_at.clear()
	_missiles_flying = 0
	for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
		var shot := node as Projectile
		if shot == null or shot.is_spent() or shot.is_queued_for_deletion() or not shot.is_inside_tree() \
				or shot.kind == Projectile.KIND_BEAM:
			continue
		_shots.append(shot)
		_shot_at.append(shot.global_position)
		if shot.kind == Projectile.KIND_MISSILE:
			_missiles_flying += 1


# The interceptors due this tick, each given the projectiles within its reach from one grid query.
func _step_interceptors() -> void:
	var intercept_ticks: int = maxi(1, roundi(TurretStandin.INTERCEPT_INTERVAL_S * Engine.physics_ticks_per_second))
	var due: Array[TurretStandin] = []
	var due_at := PackedVector3Array()
	var index: int = 0
	for cap: CapitalStandin in _capitals:
		if not is_instance_valid(cap) or not cap.is_inside_tree():
			continue
		for icp: TurretStandin in cap.interceptors():
			index += 1
			if (_tick + index) % intercept_ticks == 0:
				due.append(icp)
				due_at.append(icp.global_position)
	if due.is_empty() or _shots.is_empty():
		return
	var reach := PackedFloat64Array()
	reach.resize(due.size())
	reach.fill(TurretStandin.INTERCEPT_RANGE_M)
	var no_reach := PackedFloat64Array()
	no_reach.resize(_shots.size())
	var due_count: int = due.size()
	var candidates: Array[Array] = []  # per interceptor due, the shots in its reach
	for k: int in due_count:
		candidates.append([])
	for key: int in _grid.pairs(_shot_at, no_reach, due_at, reach):
		var p: int = key / due_count
		candidates[key - p * due_count].append(p)
	var hostile: Dictionary = {}  # capital faction -> {shot faction -> hostile}
	for k: int in due_count:
		if candidates[k].is_empty():
			continue
		var faction: StringName = due[k].capital.faction
		if not hostile.has(faction):
			hostile[faction] = _hostile_to(faction, _shots)
		var missiles_before: int = due[k].missile_shots
		if due[k].step_interceptor(candidates[k], _shots, _shot_at, hostile[faction]):
			intercepts += 1
			missile_intercepts += due[k].missile_shots - missiles_before


# The beam emitters due this tick fire at their capital's strike target when it is within a beam's reach.
func _step_beams(now_s: float) -> void:
	var beam_ticks: int = maxi(1, roundi(BeamStandin.INTERVAL_S * Engine.physics_ticks_per_second))
	var index: int = 0
	for cap: CapitalStandin in _capitals:
		if not is_instance_valid(cap) or not cap.is_inside_tree():
			continue
		for emitter: BeamStandin in cap.beams():
			index += 1
			if (_tick + index) % beam_ticks != 0:
				continue
			var target: Node3D = _strike_target(cap)
			if target == null:
				continue
			var reach: float = BeamStandin.RANGE_M
			if target.global_position.distance_squared_to(emitter.global_position) > reach * reach:
				continue
			emitter.fire(target.global_position, now_s, projectiles)
			beam_shots += 1


# Tops the missiles in flight up to `missile_target`, from the capitals in turn that have a strike target.
func _launch_missiles(now_s: float) -> void:
	if missile_target <= 0 or _capitals.is_empty():
		return
	var launched: int = 0
	var tried: int = 0
	while _missiles_flying < missile_target and launched < MAX_MISSILE_LAUNCHES_PER_TICK and tried < _capitals.size():
		var cap: CapitalStandin = _capitals[_capital_turn % _capitals.size()]
		_capital_turn += 1
		tried += 1
		if not is_instance_valid(cap) or not cap.is_inside_tree():
			continue
		var target: Node3D = _strike_target(cap)
		if target == null:
			continue
		var bow: Vector3 = cap.global_position - cap.global_basis.z * (cap.length_m() * 0.5 + 10.0)
		MissileStandin.launch(projectiles, bow, target, cap.get_instance_id(), cap.faction, now_s)
		_missiles_flying += 1
		missile_launches += 1
		launched += 1


# The capital's nearest hostile fighter within a missile's reach, looked up again when stale; null for none.
func _strike_target(cap: CapitalStandin) -> Node3D:
	var held: Array = _strike.get(cap, [])
	if held.is_empty() or _tick - int(held[1]) >= STRIKE_RETARGET_TICKS:
		held = [_nearest_hostile_fighter(cap), _tick]
		_strike[cap] = held
	var id: int = int(held[0])
	var body := instance_from_id(id) as Node3D if id != 0 and is_instance_id_valid(id) else null
	if body == null or not body.is_inside_tree() or not body.is_visible_in_tree():
		return null
	var reach: float = MissileStandin.RANGE_M
	return body if body.global_position.distance_squared_to(cap.global_position) <= reach * reach else null


func _nearest_hostile_fighter(cap: CapitalStandin) -> int:
	var at: Vector3 = cap.global_position
	var best_sq: float = MissileStandin.RANGE_M * MissileStandin.RANGE_M
	var best: int = 0
	var hostile: Dictionary = {}
	for j: int in _hulls.size():
		if _hull_reach[j] > FIGHTER_RADIUS_MAX_M:
			continue
		var d_sq: float = _hull_at[j].distance_squared_to(at)
		if d_sq > best_sq:
			continue
		var faction: StringName = _hull_factions[j]
		if not hostile.has(faction):
			hostile[faction] = Factions.is_hostile(cap.faction, faction)
		if hostile[faction]:
			best_sq = d_sq
			best = _hulls[j].body().get_instance_id()
	return best


# Each carrier's first launch, spread over one period so they do not all launch in the same tick.
func _plan_launches(now_s: float) -> void:
	var carriers: Array[CapitalStandin] = []
	for cap: CapitalStandin in _capitals:
		if cap.is_carrier() and not _next_launch.has(cap):
			carriers.append(cap)
	for i: int in carriers.size():
		_next_launch[carriers[i]] = now_s + LAUNCH_PERIOD_S * float(i + 1) / float(carriers.size() + 1)


static func _hostile_to(faction: StringName, bolts: Array[Projectile]) -> Dictionary:
	var out: Dictionary = {}
	for bolt: Projectile in bolts:
		if not out.has(bolt.faction):
			out[bolt.faction] = Factions.is_hostile(bolt.faction, faction)
	return out


func _count(launched: int) -> void:
	counts[Count.CAPITALS] = _capitals.size()
	counts[Count.TURRETS] = turret_count()
	counts[Count.INTERCEPTORS] = interceptor_count()
	counts[Count.ASTEROIDS] = asteroid_count()
	counts[Count.LAUNCHES] = launched
	counts[Count.SIDES] = sides
	counts[Count.BEAMS] = beam_count()
	counts[Count.MISSILES] = _missiles_flying
	counts[Count.MINES] = _mines.alive_count() if _mines != null and is_instance_valid(_mines) else 0
	var near: int = 0
	var far: int = 0
	if ships != null and player != null and is_instance_valid(player):
		var centre: Vector3 = player.global_position
		var reach_sq: float = NEAR_RADIUS_M * NEAR_RADIUS_M
		for c: Combatant in ships.alive():
			if c.ship.global_position.distance_squared_to(centre) <= reach_sq:
				near += 1
			else:
				far += 1
	counts[Count.FIGHTERS_NEAR] = near
	counts[Count.FIGHTERS_FAR] = far
