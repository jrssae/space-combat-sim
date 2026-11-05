class_name WeaponRowsScene
extends RefCounted
## Test fixture (M4-T20): a seeded battle in miniature for the weapon kernels' differential tests. Capitals of three sides
## turn and drift, fighters (some with a marker, some hull-only drones) fly seeded loops through their turrets' reach and
## through a mine belt, hostile bolts and missiles are laid near the capitals for the interceptors, and the director fires
## guns, beams and missiles and steps the mines once per tick, all moved by hand so a run is the same every time. A run
## logs every turret's state, every projectile the director made, every interceptor kill and every hit the mines dealt,
## tick by tick, with bodies named by their place in the scene (instance ids differ between runs). Run once on the
## GDScript stand-ins and once on the native rows, the two logs must be equal byte for byte.

const DT: float = 1.0 / 60.0
const SIDES: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS, Factions.NEUTRAL]
const CLASSES: Array[StringName] = [&"cruiser", &"destroyer", &"carrier"]
const SETTINGS: Array[StringName] = [&"perf_native", &"perf_native_core", &"perf_native_weapons"]

var world: WorldFrame
var projectiles: Node3D
var director: StandinDirector
var core: SimCore
var capitals: Array[CapitalStandin] = []
var fighters: Array[TargetDrone] = []
var now_s: float = 0.0
var tick: int = 0
## A rebase this many ticks in, between the tick's sync and the director's step (0 for none).
var rebase_at: int = 0
## The log, one entry per tick, each a Dictionary of plain values.
var log: Array = []

var _rng := RandomNumberGenerator.new()
var _loops: Array[Dictionary] = []  # per fighter: centre, radius, rate, phase, tilt
var _cap_motion: Array[Dictionary] = []  # per capital: start, velocity, yaw rate, pitch
var _laid: Array[Projectile] = []  # bolts and missiles laid for the interceptors, in order
var _made: int = 0  # projectiles under `projectiles` already logged
var _hits: Array = []  # this tick's hits from the mines
var _rebased: Vector3 = Vector3.ZERO  # what the rebases moved the World frame by


## Builds the scene under `test` (a GutTest, which frees it), seeded, with the native weapon rows on or off.
static func build(test: Node, seed_value: int, native: bool) -> WeaponRowsScene:
	var scene := WeaponRowsScene.new()
	scene._build(test, seed_value, native)
	return scene


func _build(test: Node, seed_value: int, native: bool) -> void:
	_rng.seed = seed_value
	Settings.set_value(&"perf_native", true)
	Settings.set_value(&"perf_native_core", true)
	Settings.set_value(&"perf_native_weapons", native)
	Factions.reset()
	ContactScan.invalidate()
	StaticRows.clear()
	world = WorldFrame.new()
	world.name = "World"
	test.add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	director = StandinDirector.new()
	director.name = "Standins"
	director.world = world
	director.projectiles = projectiles
	world.add_child(director)
	director.set_physics_process(false)  # stepped by hand
	director.active = true
	now_s = SimClock.now() + 100.0  # ahead of the clock projectiles expire by
	for i: int in 6:
		var at := Vector3(_rng.randf_range(-3000.0, 3000.0), _rng.randf_range(-800.0, 800.0), _rng.randf_range(-3000.0, 3000.0))
		var basis := Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-PI, PI), _rng.randf_range(-0.2, 0.2)))
		var velocity := Vector3(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-5.0, 5.0), _rng.randf_range(-30.0, 30.0))
		var cap: CapitalStandin = director.add_capital(CLASSES[i % CLASSES.size()], SIDES[i % 2], "CAP %d" % i,
				world.to_universe(at), basis, velocity)
		cap.freeze = true
		capitals.append(cap)
		_cap_motion.append({"start": at, "basis": basis, "velocity": velocity, "yaw": _rng.randf_range(-0.05, 0.05)})
	# Fighters loop through the capitals' reach: most within 4 km of some capital, a few far out, of every side.
	for i: int in 40:
		var drone := (load("res://tests/fixtures/target_drone.tscn") as PackedScene).instantiate() as TargetDrone
		drone.faction = SIDES[i % SIDES.size()]
		drone.set_physics_process(false)
		drone.freeze = true
		var anchor: Vector3 = _cap_motion[i % _cap_motion.size()]["start"]
		var centre: Vector3 = anchor + Vector3(_rng.randf_range(-3500.0, 3500.0), _rng.randf_range(-1500.0, 1500.0),
				_rng.randf_range(-3500.0, 3500.0))
		_loops.append({"centre": centre, "radius": _rng.randf_range(200.0, 1500.0), "rate": _rng.randf_range(0.05, 0.4),
				"phase": _rng.randf_range(0.0, TAU), "tilt": _rng.randf_range(-1.0, 1.0)})
		world.spawn(drone, world.to_universe(centre))
		if i % 3 != 0:
			var marker := Targetable.new()
			marker.name = "Targetable"
			marker.display_name = "FTR %d" % i
			marker.faction = drone.faction
			drone.add_child(marker)
		drone.damageable.hit_taken.connect(_on_hit.bind(i))
		fighters.append(drone)
	# A belt along the first fighters' loops, laid by the side hostile to each loop's fighter (a neutral's loop by Earth
	# Alliance, which never sets them off); the first mine of each loop where its fighter is half a second in.
	var mines: Array[Dictionary] = []
	for i: int in 90:
		var k: int = i % 12
		var loop: Dictionary = _loops[k]
		var angle: float = float(loop["phase"]) + float(loop["rate"]) * 0.5 if i < 12 else _rng.randf_range(0.0, TAU)
		var r: float = float(loop["radius"])
		var offset := Vector3(cos(angle) * r, sin(angle) * r * float(loop["tilt"]), sin(angle) * r) \
				+ Vector3(_rng.randf_range(-30.0, 30.0), _rng.randf_range(-30.0, 30.0), _rng.randf_range(-30.0, 30.0))
		var layer: StringName = Factions.RAIDERS if k % 3 == 0 else Factions.EARTH_ALLIANCE
		mines.append({"offset": (loop["centre"] as Vector3) + offset, "faction": layer})
	director.add_mines(mines, world.to_universe(Vector3.ZERO))
	director.missile_target = 5
	core = SimCore.attach(world)
	_move(0.0)


## One tick: the bodies move, the core syncs, an optional rebase, interceptor quarry is laid, the director steps; then the
## tick is logged.
func step() -> void:
	tick += 1
	now_s += DT
	_move(float(tick) * DT)
	if tick % 7 == 1:
		_lay_quarry()
	if core != null:
		core.sync_now()
	if rebase_at > 0 and tick == rebase_at:
		var offset := Vector3(1234.5, -321.25, 777.0)
		world.rebase(offset)
		_rebased -= offset
	_hits.clear()
	director.step(DT, now_s, ContactScan.from_tree(world.get_tree()))
	director.pull_native_state()
	log.append(_entry())


## Takes the scene out of the tree and frees it (the log stays), so the next scene's core and scan see only their own.
func dispose() -> void:
	if is_instance_valid(world):
		world.get_parent().remove_child(world)
		world.free()


## Runs `ticks` ticks.
func run(ticks: int) -> void:
	for i: int in ticks:
		step()


# Every body where its seeded path has it at time `t`.
func _move(t: float) -> void:
	for i: int in capitals.size():
		var m: Dictionary = _cap_motion[i]
		var basis: Basis = (m["basis"] as Basis).rotated(Vector3.UP, float(m["yaw"]) * t)
		var at: Vector3 = (m["start"] as Vector3) + (m["velocity"] as Vector3) * t
		capitals[i].global_transform = Transform3D(basis, _here(at))
		capitals[i].linear_velocity = m["velocity"]
	for i: int in fighters.size():
		var l: Dictionary = _loops[i]
		var a: float = float(l["phase"]) + float(l["rate"]) * t
		var r: float = float(l["radius"])
		var tilt: float = float(l["tilt"])
		var offset := Vector3(cos(a) * r, sin(a) * r * tilt, sin(a) * r)
		var velocity := Vector3(-sin(a), cos(a) * tilt, cos(a)) * (r * float(l["rate"]))
		fighters[i].global_position = _here((l["centre"] as Vector3) + offset)
		fighters[i].linear_velocity = velocity
		fighters[i].velocity = velocity


# A scene position (as built, before any rebase) in the World's frame now.
func _here(at: Vector3) -> Vector3:
	return at + _rebased


# Hostile bolts and missiles near the capitals, for the interceptors (laid in a seeded order, never moved).
func _lay_quarry() -> void:
	for i: int in 3:
		var cap: CapitalStandin = capitals[_rng.randi_range(0, capitals.size() - 1)]
		var shot := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
		projectiles.add_child(shot)
		shot.configure(WeaponSpec.new())
		if i == 2:
			shot.set_kind(Projectile.KIND_MISSILE)
		shot.faction = SIDES[_rng.randi_range(0, SIDES.size() - 1)]
		var at: Vector3 = cap.global_position + Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1),
				_rng.randf_range(-1, 1)).normalized() * _rng.randf_range(100.0, 2200.0)
		shot.launch(at, Vector3(_rng.randf_range(-300.0, 300.0), 0.0, _rng.randf_range(-300.0, 300.0)), now_s)
		shot.set_physics_process(false)
		_laid.append(shot)
	_made = projectiles.get_child_count()


func _on_hit(info: HitInfo, fighter: int) -> void:
	_hits.append([fighter, String(info.cause), info.damage, info.point, info.normal])


# Names a body by its place in the scene: "f<i>" a fighter, "c<i>" a capital, "" none, "?" anything else.
func _name_of(body_id: int) -> String:
	if body_id == 0:
		return ""
	for i: int in fighters.size():
		if fighters[i].get_instance_id() == body_id:
			return "f%d" % i
	for i: int in capitals.size():
		if capitals[i].get_instance_id() == body_id:
			return "c%d" % i
	return "?"


# This tick's entry: every turret's state, the projectiles the director made, the laid quarry still alive, the counts and
# the mines' hits in the order they landed.
func _entry() -> Dictionary:
	var turrets: Array = []
	for cap: CapitalStandin in capitals:
		for gun: TurretStandin in cap.guns():
			turrets.append([var_to_bytes(gun.axis), _name_of(gun.target_id), gun.aim_error_rad(), gun.shots,
					gun.gate._ready_at_s])
		for icp: TurretStandin in cap.interceptors():
			turrets.append([icp.shots, icp.missile_shots])
	var made: Array = []
	var children: Array[Node] = projectiles.get_children()
	for k: int in range(_made, children.size()):
		var p := children[k] as Projectile
		if p == null:
			continue
		var target: String = _name_of(director.missile_target_of(p))
		made.append([String(p.kind), var_to_bytes(p.global_position), var_to_bytes(p.velocity), var_to_bytes(p.last_step),
				_name_of(p.shooter_id), String(p.faction), target])
	_made = children.size()
	var alive: Array = []
	for k: int in _laid.size():
		alive.append(1 if is_instance_valid(_laid[k]) and not _laid[k].is_spent() else 0)
	var hits: Array = _hits.duplicate()  # in the order the blasts landed
	var mines: MineStandin = director.mines()
	var mine_alive := PackedByteArray()
	for i: int in mines.count():
		mine_alive.append(1 if mines.is_alive(i) else 0)
	return {"tick": tick, "turrets": turrets, "made": made, "alive": alive, "hits": var_to_bytes(hits),
			"mines": mine_alive, "checked": mines.checked_last_tick,
			"counts": [director.intercepts, director.missile_intercepts, director.beam_shots, director.missile_launches,
					director.detonations]}
