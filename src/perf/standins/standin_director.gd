class_name StandinDirector
extends Node3D
## The battle's stand-ins in play (M4-T07, architecture §17.6): `World/Standins`, an identity container `Main` makes for the
## bench runner. It holds the capitals, the asteroid field, the mine belts and the moon, steps every capital's engines, guns,
## interceptors and beam lasers once per tick (priority -5: after the core's first sync and the AI drivers, before anything
## moves), keeps `missile_target` missiles in flight (M4-T12), steps the mines, runs the carriers' launch cycle through the
## runner's `launcher`, and counts the battle per entity type for the `perf` probe. Bench-only: no scenario spawns stand-ins.
##
## Interceptors find what is in reach through the hit broad phase's grid (one query a tick for every interceptor due), and so
## do the mines. Missiles and beams fire at each capital's strike target: its nearest hostile fighter within the missile's
## reach, looked up again when older than `STRIKE_RETARGET_TICKS`.
##
## The guns, interceptors, beams, strike targets, missile launches and mine triggers are decided by `NativeWeapons` over the
## core's rows in one call a tick (M4-T20, §17.13), and this node does what they decide (bolts, kills, beams, launches,
## blasts). M4-T37 removed the GDScript stand-ins' own stepping, the reference until then (`tests/fixtures/parity/`).
##
## `last_us` is the stand-ins' own cost in the latest tick (wall clock, profiling only); it sits inside the `flight` stage.
## `part_us` splits it by part (`PART_NAMES`), summed since `restart_weapon_counters`, with `ticks` the ticks it covers.

enum Count { FIGHTERS_NEAR, FIGHTERS_FAR, CAPITALS, TURRETS, INTERCEPTORS, BEAMS, MISSILES, MINES, ASTEROIDS, LAUNCHES, SIDES,
		TIER_FIGHTERS, TIER_CAPITALS }
const COUNT_NAMES: Array[StringName] = [&"fighters_near", &"fighters_far", &"capitals", &"turrets", &"interceptors", &"beams",
		&"missiles", &"mines", &"asteroids", &"launches", &"sides", &"tier_fighters", &"tier_capitals"]

const PRIORITY: int = -5
## Fighters within this of the player are the near set (the tier's radius to come, M4-T21), m.
const NEAR_RADIUS_M: float = 10000.0
## A carrier releases one fighter of its side and takes it back at its bay this often (N holds), s.
const LAUNCH_PERIOD_S: float = 5.0
## A capital's strike target is looked up again when older than this, ticks.
const STRIKE_RETARGET_TICKS: int = 30
## At most this many missiles leave in one tick, so a gap in the count fills over a few ticks.
const MAX_MISSILE_LAUNCHES_PER_TICK: int = 2
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
## The far capitals' fire (M4-T22): group rolls run (one a second per tier capital) and their hits landed since `clear`.
var tier_group_rolls: int = 0
var tier_hits_landed: int = 0
# Each far missile in the air: the hull life of its target at launch (fix round 1).
var _tier_missile_lives: Dictionary[int, int] = {}
## The latest tick's counts, by `Count`.
var counts: PackedInt64Array = PackedInt64Array()
var last_us: int = 0
## Each part's cost summed over `ticks` active ticks since `clear`, by `Part` (profiling only).
var part_us: PackedInt64Array = PackedInt64Array()
var ticks: int = 0

var _capitals: Array[CapitalStandin] = []
var _field: AsteroidField = null
var _mines: MineStandin = null
var _strike: Dictionary = {}  # capital -> [target body id, tick it was looked up]
var _capital_turn: int = 0


var _missiles_flying: int = 0
var _gravity: GravityStandin = null
var _tick: int = 0
var _next_launch: Dictionary = {}  # carrier -> sim time of its next launch
var _last_frame: int = -1
var _native: NativeWeapons = null  # bound while the native rows step the weapons
var _native_dirty: bool = true  # the capitals or mines changed since the rows were bound
var _path: StringName = &"none"


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
	step(delta, SimClock.now())


## One tick of every stand-in at sim time `now_s`, over the core's rows; then the counts.
func step(delta: float, now_s: float) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only
	_tick += 1
	ticks += 1
	var native: NativeWeapons = _native_weapons()
	_path = &"native" if native != null else &"none"
	if native != null:
		_step_native(native, delta, now_s, started_us)


# The carriers' launches, the cost and the counts: the end of a tick on either path.
func _finish(now_s: float, mark_us: int, started_us: int) -> void:
	var launched: int = 0
	for cap: CapitalStandin in _capitals:
		if _flying(cap) and cap.is_carrier() and launcher.is_valid() and now_s >= float(_next_launch.get(cap, INF)):
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
		if _flying(cap):
			cap.step_engines(delta)
	var intercept_ticks: int = maxi(1, roundi(TurretStandin.INTERCEPT_INTERVAL_S * Engine.physics_ticks_per_second))
	var beam_ticks: int = maxi(1, roundi(BeamStandin.INTERVAL_S * Engine.physics_ticks_per_second))
	var out: Array = native.rows.step(_tick, now_s, delta, intercept_ticks, beam_ticks, missile_target,
			MAX_MISSILE_LAUNCHES_PER_TICK, Engine.physics_ticks_per_second)
	var gun_rows: PackedInt32Array = out[0]
	var bolt_at: PackedVector3Array = out[1]
	var bolt_velocity: PackedVector3Array = out[2]
	for k: int in gun_rows.size():
		var gun := native.turrets[gun_rows[k]] as TurretStandin
		TurretStandin.launch_bolt(gun.capital, bolt_at[k], bolt_velocity[k], now_s)
	mark_us = _mark(Part.ENGINES_GUNS, mark_us)
	var spent: PackedInt64Array = out[3]
	var spent_missile: PackedByteArray = out[4]
	for k: int in spent.size():
		if spent[k] < 0:
			native.sim.spend_bolt(spent[k])  # an owned bolt row (M4-T35)
		else:
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
	# The far capitals (M4-T22): their rolled hits land through each target's Damageable; their launches were resolved, and
	# a far missile lands only on the life of the target it was launched at (fix round 1).
	if out.size() >= 21:
		var launched: PackedInt64Array = out[17]
		var launched_targets: PackedInt64Array = out[18]
		for k: int in launched.size():
			_tier_missile_lives[launched[k]] = _life_of(launched_targets[k])
		var targets: PackedInt64Array = out[10]
		if not targets.is_empty():
			var missile_ids: PackedInt64Array = out[16]
			var keep := PackedByteArray()
			keep.resize(targets.size())
			for k: int in targets.size():
				var id: int = missile_ids[k]
				keep[k] = 1 if id == 0 or int(_tier_missile_lives.get(id, -2)) == _life_of(targets[k]) else 0
			tier_hits_landed += TierDirector.land_hits(_kept_i(targets, keep), _kept_i(out[11], keep), _kept_f(out[12], keep),
					_kept_v(out[13], keep))
		for id: int in (out[19] as PackedInt64Array):
			_tier_missile_lives.erase(id)
		missile_launches += int(out[14])
		missile_intercepts += int(out[20])
		tier_group_rolls = int(out[15])
	mark_us = _mark(Part.MISSILES, mark_us)
	if native.mines != null and is_instance_valid(native.mines):
		detonations += native.mines.step_native(_tick, now_s)
	mark_us = _mark(Part.MINES, mark_us)
	_finish(now_s, mark_us, started_us)


## Which code stepped the weapons in the latest tick: &"native" (the rows), or &"none" when no core was there to step them.
func weapons_path() -> StringName:
	return _path


## Copies the native rows' state into the stand-ins' nodes (turrets, strike targets, the launch turn), so a reader of the
## nodes sees the rows' state; the rows keep stepping. Nothing without the rows.
func pull_native_state() -> void:
	if _native == null:
		return
	_native.pull_turrets()
	_capital_turn = _native.pull_strike(_strike)


# The native rows over this tick's core (its first sync made, a body touched since read again), bound afresh when the
# capitals or mines changed; null without a core, with any state the rows held handed back to the nodes.
func _native_weapons() -> NativeWeapons:
	var sim: SimCore = SimCore.for_tree(get_tree())
	var ready: bool = sim != null and sim.ensure_synced()
	if ready and int(sim.core.touched_count()) > 0:
		sim.core.resync_touched_now()  # a ship moved or parked since the first sync is read where it is now
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
	SimCore.attach(world)  # the core steps the capitals' engines and guns (M4-T42)
	var cap: CapitalStandin = CapitalStandin.create(cls, faction, display_name, velocity)
	cap.world = world
	world.spawn(cap, at, basis, self)
	cap.linear_velocity = velocity
	for gun: TurretStandin in cap.guns():
		gun.axis = -cap.global_basis.z
	_capitals.append(cap)
	_native_dirty = true
	var destruction: DestructionDirector = DestructionDirector.current()
	if destruction != null:
		destruction.watch_capital(cap)  # its death is drawn and leaves play (M4-T23)
	return cap


## The mine belts: `rows` (`offset` m from `anchor`, `faction` the layer's).
func add_mines(rows: Array[Dictionary], anchor: UniversePos) -> MineStandin:
	remove_mines()
	SimCore.attach(world)  # the core steps the mines (M4-T42)
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
	_tier_missile_lives.clear()
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


func capitals() -> Array[CapitalStandin]:
	return _capitals


## The moon, or null without one.
func gravity() -> GravityStandin:
	return _gravity if _gravity != null and is_instance_valid(_gravity) else null


## Capitals in play, on their bodies or as tier rows: not the destroyed ones (M4-T23 fix round 1: capitals can die now).
func capitals_in_play() -> int:
	var n: int = 0
	for cap: CapitalStandin in _capitals:
		n += 1 if _in_play(cap) else 0
	return n


# A capital not freed and not destroyed (its body may be parked in the tier).
static func _in_play(cap: CapitalStandin) -> bool:
	return is_instance_valid(cap) and not cap.damageable.hull.destroyed


# A capital in play on its body: not freed, in the tree and not parked in the low-attention tier (M4-T21).
static func _flying(cap: CapitalStandin) -> bool:
	return is_instance_valid(cap) and cap.is_inside_tree() and cap.can_process()


func asteroid_count() -> int:
	return _field.count() if _field != null and is_instance_valid(_field) else 0


func turret_count() -> int:
	var n: int = 0
	for cap: CapitalStandin in _capitals:
		n += cap.guns().size() if _in_play(cap) else 0
	return n


func interceptor_count() -> int:
	var n: int = 0
	for cap: CapitalStandin in _capitals:
		n += cap.interceptors().size() if _in_play(cap) else 0
	return n


func beam_count() -> int:
	var n: int = 0
	for cap: CapitalStandin in _capitals:
		n += cap.beams().size() if _in_play(cap) else 0
	return n


## Starts the weapons' counts and the parts' costs over (a bench's measured window).
func restart_weapon_counters() -> void:
	tier_hits_landed = 0
	var tier: TierDirector = TierDirector.current()
	if tier != null:
		tier.reset_costs()
	missile_intercepts = 0
	missile_launches = 0
	beam_shots = 0
	detonations = 0
	ticks = 0
	part_us.fill(0)


# A target's hull life now (-1 when it is gone), so a far missile lands only on the life it was launched at.
static func _life_of(body_id: int) -> int:
	if not is_instance_id_valid(body_id):
		return -1
	var d: Damageable = Damageable.of(instance_from_id(body_id) as Node)
	return d.life if d != null else -1


static func _kept_i(a: PackedInt64Array, keep: PackedByteArray) -> PackedInt64Array:
	var out := PackedInt64Array()
	for k: int in a.size():
		if keep[k] == 1:
			out.append(a[k])
	return out


static func _kept_f(a: PackedFloat64Array, keep: PackedByteArray) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k: int in a.size():
		if keep[k] == 1:
			out.append(a[k])
	return out


static func _kept_v(a: PackedVector3Array, keep: PackedByteArray) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k: int in a.size():
		if keep[k] == 1:
			out.append(a[k])
	return out


## The far capitals' rolls in the last tick, us (wall clock, a readout; M4-T22).
func tier_fire_us() -> float:
	return float(_native.rows.tier_us()) if _native != null and is_instance_valid(_native) and _native.rows != null else 0.0


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


# Each carrier's first launch, spread over one period so they do not all launch in the same tick.
func _plan_launches(now_s: float) -> void:
	var carriers: Array[CapitalStandin] = []
	for cap: CapitalStandin in _capitals:
		if cap.is_carrier() and not _next_launch.has(cap):
			carriers.append(cap)
	for i: int in carriers.size():
		_next_launch[carriers[i]] = now_s + LAUNCH_PERIOD_S * float(i + 1) / float(carriers.size() + 1)


func _count(launched: int) -> void:
	counts[Count.CAPITALS] = capitals_in_play()
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
	var tier: TierDirector = TierDirector.current()
	if ships != null and player != null and is_instance_valid(player):
		var centre: Vector3 = player.global_position
		var reach_sq: float = NEAR_RADIUS_M * NEAR_RADIUS_M
		for c: Combatant in ships.alive():
			if c.ship.is_tier_parked():
				far += 1  # a tier row (M4-T21): far by definition, its parked node's place is stale
			elif c.ship.global_position.distance_squared_to(centre) <= reach_sq:
				near += 1
			else:
				far += 1
	counts[Count.FIGHTERS_NEAR] = near
	counts[Count.FIGHTERS_FAR] = far
	counts[Count.TIER_FIGHTERS] = tier.tier_fighters() if tier != null else 0
	counts[Count.TIER_CAPITALS] = tier.tier_capitals() if tier != null else 0
