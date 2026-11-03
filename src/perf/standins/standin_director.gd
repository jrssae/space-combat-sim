class_name StandinDirector
extends Node3D
## The battle's stand-ins in play (M4-T07, architecture §17.6): `World/Standins`, an identity container `Main` makes for the
## bench runner. It holds the capitals, the asteroid field and the moon, steps every capital's engines, guns and interceptors
## once per tick (priority -5: after the AI drivers built the tick's contact scan, before anything moves), runs the carriers'
## launch cycle through the runner's `launcher`, and counts the battle per entity type for the `perf` probe. Bench-only:
## no scenario spawns stand-ins.
##
## `last_us` is the stand-ins' own cost in the latest tick (wall clock, profiling only); it sits inside the `flight` stage.

enum Count { FIGHTERS_NEAR, FIGHTERS_FAR, CAPITALS, TURRETS, INTERCEPTORS, BEAMS, MISSILES, MINES, ASTEROIDS, LAUNCHES, SIDES }
const COUNT_NAMES: Array[StringName] = [&"fighters_near", &"fighters_far", &"capitals", &"turrets", &"interceptors", &"beams",
		&"missiles", &"mines", &"asteroids", &"launches", &"sides"]

const PRIORITY: int = -5
## Fighters within this of the player are the near set (the tier's radius to come, M4-T21), m.
const NEAR_RADIUS_M: float = 10000.0
## A carrier releases one fighter of its side and takes it back at its bay this often (N holds), s.
const LAUNCH_PERIOD_S: float = 5.0

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
## The latest tick's counts, by `Count`.
var counts: PackedInt64Array = PackedInt64Array()
var last_us: int = 0

var _capitals: Array[CapitalStandin] = []
var _field: AsteroidField = null
var _gravity: GravityStandin = null
var _tick: int = 0
var _next_launch: Dictionary = {}  # carrier -> sim time of its next launch
var _last_frame: int = -1


func _init() -> void:
	process_physics_priority = PRIORITY
	counts.resize(COUNT_NAMES.size())


func _physics_process(delta: float) -> void:
	if not active:
		return
	step(delta, SimClock.now(), ContactScan.shared(get_tree()))


## One tick of every stand-in at sim time `now_s`, the guns choosing from `scan`; then the counts.
func step(delta: float, now_s: float, scan: ContactScan) -> void:
	var started_us: int = Time.get_ticks_usec()  # profiling readout only
	_tick += 1
	var bolts: Array[Projectile] = []
	var bolts_gathered: bool = false
	var hostile: Dictionary = {}  # capital faction -> {bolt faction -> hostile}
	var launched: int = 0
	var gun_index: int = 0
	var interceptor_index: int = 0
	var intercept_ticks: int = maxi(1, roundi(TurretStandin.INTERCEPT_INTERVAL_S * Engine.physics_ticks_per_second))
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
		for icp: TurretStandin in cap.interceptors():
			interceptor_index += 1
			if (_tick + interceptor_index) % intercept_ticks != 0:
				continue
			if not bolts_gathered:
				bolts = _live_bolts()
				bolts_gathered = true
			if not hostile.has(cap.faction):
				hostile[cap.faction] = _hostile_to(cap.faction, bolts)
			if icp.step_interceptor(bolts, hostile[cap.faction]):
				intercepts += 1
		if cap.is_carrier() and launcher.is_valid() and now_s >= float(_next_launch.get(cap, INF)):
			_next_launch[cap] = float(_next_launch[cap]) + LAUNCH_PERIOD_S
			if bool(launcher.call(cap)):
				launched += 1
	launches += launched
	last_us = Time.get_ticks_usec() - started_us
	_last_frame = Engine.get_physics_frames()
	_count(launched)


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
	return cap


## The asteroid field: `rocks` (`offset` m from `anchor`, `radius` m), built into this world's physics space.
func add_asteroids(rocks: Array[Dictionary], anchor: UniversePos) -> AsteroidField:
	remove_asteroids()
	_field = AsteroidField.new()
	_field.name = "Asteroids"
	world.spawn(_field, anchor, Basis.IDENTITY, self)
	_field.build(rocks, world.get_world_3d().space)
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
	for cap: CapitalStandin in _capitals:
		if is_instance_valid(cap):
			remove_child(cap)
			cap.queue_free()
	_capitals.clear()
	remove_asteroids()
	remove_gravity()
	_next_launch.clear()
	launcher = Callable()
	sides = 0
	intercepts = 0
	launches = 0
	counts.fill(0)


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


# Each carrier's first launch, spread over one period so they do not all launch in the same tick.
func _plan_launches(now_s: float) -> void:
	var carriers: Array[CapitalStandin] = []
	for cap: CapitalStandin in _capitals:
		if cap.is_carrier() and not _next_launch.has(cap):
			carriers.append(cap)
	for i: int in carriers.size():
		_next_launch[carriers[i]] = now_s + LAUNCH_PERIOD_S * float(i + 1) / float(carriers.size() + 1)


func _live_bolts() -> Array[Projectile]:
	var out: Array[Projectile] = []
	for node: Node in get_tree().get_nodes_in_group(Projectile.GROUP):
		var bolt := node as Projectile
		if bolt != null and not bolt.is_spent() and bolt.is_inside_tree():
			out.append(bolt)
	return out


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
	counts[Count.BEAMS] = 0  # beams, missiles and mines are M4-T12's stand-ins
	counts[Count.MISSILES] = 0
	counts[Count.MINES] = 0
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
