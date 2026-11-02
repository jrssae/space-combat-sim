extends GutTest
## The ram resolver at scale (M4-T03, cycle 2). The resolver's swept pass used to look at every pair of hulls every tick
## (N squared), though a pair can only ram in a tick when its two hulls come near each other in it. The work it does per tick in
## a spread-out fleet must grow with the ship count, not its square.
##
## The rest pins what may not change while it gets cheaper, among bystanders the resolver must leave out: a ram at speed lands,
## even when the hulls meet in the middle of a tick and are far apart at both its ends; a glancing pass lands at the overlap's
## edge and a hand's breadth outside it does not; a slow scrape is Jolt's contact and its pair stays touching while Jolt holds
## it, even when its bounding spheres are too small to bring it in; a pair that separates and comes back is rammed again, once
## per meeting.
##
## The ships fly in real physics ticks (Jolt, the real resolver at priority 210). Ships drift without input.

const STARFURY_PATH: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_PATH: String = "res://assets/ships/raider_delta_v.tres"
const FACING := Basis(Vector3.UP, PI)
## The spread-out fleet: a lattice of FLEET ships SPACING_M apart, half drifting still and half crossing at CROSSING_MPS, so
## the resolver sees both kinds of pair (the still ones below the tunnelling speed, the crossing ones above it).
const FLEET: int = 24
const COLUMNS: int = 6
const SPACING_M: float = 250.0
const CROSSING_MPS: float = 300.0
const MEASURED_TICKS: int = 10
## Pairs the resolver may look at per ship per tick: linear in N. The old full pass looks at (N - 1) / 2 per ship, 11.5 here.
const PAIRS_PER_SHIP: float = 2.0
## The two Starfuries' glancing pass at 600 m/s closing, abreast in x (found by sampling on the resolver before cycle 2; the
## overlap's edge lies between 15.45 and 15.50 m).
const GLANCING_X_M: float = 15.4
const CLEAR_X_M: float = 15.6
## A slow scrape: 20 m/s closing with the wings overlapping, below the tunnelling speed; Jolt bounces it.
const SCRAPE_MPS: float = 20.0
const SCRAPE_X_M: float = 8.0


## Counts the pairs the tracker is told to keep touching, and which ones.
class CountingTracker extends RamTracker:
	var keep_touching_calls: int = 0
	var kept: Dictionary[String, bool] = {}

	func keep_touching(a: int, b: int) -> void:
		keep_touching_calls += 1
		kept[RamTracker.pair_key(a, b)] = true
		super(a, b)


## Counts the pairs swept shape by shape.
class CountingResolver extends RamResolver:
	var sweeps: int = 0

	func _sweep_pair(first: Dictionary, second: Dictionary, deep: bool) -> Dictionary:
		sweeps += 1
		return super(first, second, deep)


var world: WorldFrame
var projectiles: Node3D
var rams: CountingResolver
var tracker: CountingTracker
## Each ram as it lands: the info and the resolver's `last_ram` line (which names how it was found).
var landed: Array[Array] = []
var ram_damage_backup: bool = true


func before_each() -> void:
	DebugConsole.flags.invulnerable = false
	ram_damage_backup = bool(Settings.get_value(&"ram_damage"))
	Settings.set_value(&"ram_damage", true)
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	rams = CountingResolver.new()
	rams.name = "RamResolver"
	rams.world = world
	tracker = CountingTracker.new()
	rams.tracker = tracker
	add_child_autofree(rams)
	landed.clear()
	rams.ram_resolved.connect(func(info: HitInfo) -> void: landed.append([info, rams.last_ram]))


func after_each() -> void:
	Settings.set_value(&"ram_damage", ram_damage_backup)


func _ship(path: String, at: Vector3, basis: Basis = Basis.IDENTITY) -> Combatant:
	var combatant: Combatant = ShipAssembly.build(load(path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: Factions.EARTH_ALLIANCE,
	})
	world.spawn(combatant.ship, world.to_universe(at), basis)
	return combatant


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _place(combatant: Combatant, position: Vector3, basis: Basis, velocity: Vector3) -> void:
	combatant.ship.reset_to(Transform3D(basis, position))
	combatant.ship.linear_velocity = velocity
	combatant.ship.angular_velocity = Vector3.ZERO


## Still bystanders on a ring of `radius` round the origin, well away from the encounter there.
func _bystanders(count: int, radius: float) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for i: int in count:
		var angle: float = TAU * float(i) / float(count)
		out.append(_ship(STARFURY_PATH if i % 2 == 0 else RAIDER_PATH, Vector3(cos(angle), 0.3, sin(angle)) * radius))
	return out


## Two Starfuries nose to nose on z, `gap` apart, `x` abreast, closing at `closing`.
func _head_on(a: Combatant, b: Combatant, closing: float, gap: float, x: float) -> void:
	_place(a, Vector3.ZERO, Basis.IDENTITY, Vector3(0.0, 0.0, -0.5 * closing))
	_place(b, Vector3(x, 0.0, -gap), FACING, Vector3(0.0, 0.0, 0.5 * closing))


func _rams_on(combatant: Combatant) -> int:
	var id: int = combatant.ship.get_instance_id()
	return landed.filter(func(entry: Array) -> bool: return (entry[0] as HitInfo).target_id == id).size()


func _kinds() -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Array in landed:
		var line: String = entry[1]
		out.append(line.get_slice(": ", 1).get_slice(",", 0))
	return out


# --- the work per tick ----------------------------------------------------------------------------------------------


func test_the_pairs_looked_at_per_tick_in_a_spread_out_fleet_grow_linearly() -> void:
	for i: int in FLEET:
		var at := Vector3(float(i % COLUMNS) * SPACING_M, 0.0, floorf(float(i) / COLUMNS) * SPACING_M)
		var crossing: bool = i % 2 == 1
		var combatant: Combatant = _ship(STARFURY_PATH if i % 4 < 2 else RAIDER_PATH, at)
		combatant.ship.linear_velocity = Vector3(CROSSING_MPS, 0.0, 0.0) if crossing else Vector3.ZERO
	await _ticks(2)
	rams.sweeps = 0
	tracker.keep_touching_calls = 0
	await _ticks(MEASURED_TICKS)
	var per_tick: float = float(rams.sweeps + tracker.keep_touching_calls) / float(MEASURED_TICKS)
	var bound: float = PAIRS_PER_SHIP * FLEET
	assert_lte(per_tick, bound, "pairs looked at per tick (%.1f swept, %.1f kept touching) against a linear bound of %.0f; all pairs: %.0f"
			% [float(rams.sweeps) / MEASURED_TICKS, float(tracker.keep_touching_calls) / MEASURED_TICKS, bound, FLEET * (FLEET - 1) / 2.0])
	assert_eq(landed.size(), 0, "nobody met")


# --- what stays the same ---------------------------------------------------------------------------------------------


func test_a_ram_at_speed_lands_among_bystanders() -> void:
	_bystanders(8, 400.0)
	var a: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, 600.0))
	var b: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, -600.0))
	await _ticks(2)
	_head_on(a, b, 600.0, 45.0, 0.0)  # 10 m per tick
	await _ticks(12)
	assert_true(a.damageable.hull.destroyed and b.damageable.hull.destroyed, "both destroyed at 600 m/s closing")
	assert_eq(_rams_on(a), 1)
	assert_eq(_rams_on(b), 1)
	assert_eq(_kinds(), PackedStringArray(["tunnelling", "tunnelling"]))


func test_a_ram_lands_when_the_hulls_are_far_apart_at_both_ends_of_the_tick() -> void:
	# 3 000 m/s closing is 50 m per tick: on the tick of the hit the two origins start about 25 m apart and end about 25 m past
	# each other, beyond the two bounding spheres (20.5 m together) at both ends. Only the sweep through the tick sees them meet.
	_bystanders(8, 400.0)
	var a: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, 600.0))
	var b: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, -600.0))
	await _ticks(2)
	_head_on(a, b, 3000.0, 175.0, 2.0)
	await _ticks(8)
	assert_true(a.damageable.hull.destroyed and b.damageable.hull.destroyed, "both destroyed at 3 000 m/s closing")
	assert_eq(_kinds(), PackedStringArray(["tunnelling", "tunnelling"]))


func test_a_glancing_pass_lands_at_the_overlaps_edge_and_not_outside_it() -> void:
	_bystanders(8, 400.0)
	var a: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, 600.0))
	var b: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, -600.0))
	await _ticks(2)
	_head_on(a, b, 600.0, 45.0, GLANCING_X_M)
	await _ticks(12)
	assert_eq(_kinds(), PackedStringArray(["tunnelling", "tunnelling"]), "the wing tips meet %.2f m abreast" % GLANCING_X_M)
	landed.clear()
	a.damageable.restore()
	b.damageable.restore()
	rams.tracker.reset()
	_head_on(a, b, 600.0, 45.0, CLEAR_X_M)
	await _ticks(12)
	assert_eq(landed.size(), 0, "%.2f m abreast passes clear" % CLEAR_X_M)


func test_a_slow_scrape_is_a_jolt_contact_and_its_pair_stays_touching() -> void:
	_bystanders(8, 400.0)
	var a: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, 600.0))
	var b: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, -600.0))
	await _ticks(2)
	assert_false(RamMath.is_tunnelling(SCRAPE_MPS, 1.0 / 60.0, a.damageable.core_radius, b.damageable.core_radius),
			"below the tunnelling speed")
	_head_on(a, b, SCRAPE_MPS, 14.0, SCRAPE_X_M)
	var key: String = RamTracker.pair_key(a.ship.get_instance_id(), b.ship.get_instance_id())
	var touched: bool = false
	for i: int in 60:
		await _ticks(1)
		touched = touched or tracker.in_contact(a.ship.get_instance_id(), b.ship.get_instance_id())
	assert_true(touched, "Jolt reported the scrape")
	assert_true(tracker.kept.has(key), "the resolver kept the pair touching while Jolt held it")
	assert_eq(_kinds(), PackedStringArray(["contact", "contact"]), "a scrape is a contact ram, one on each hull")


func test_a_pair_jolt_holds_in_contact_is_kept_touching_whatever_its_bounding_spheres() -> void:
	# The bounding spheres shrunk to half a metre: the scrape's two origins stay metres apart, so only Jolt's report of the
	# contact can bring the pair to the resolver.
	_bystanders(8, 400.0)
	var a: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, 600.0))
	var b: Combatant = _ship(STARFURY_PATH, Vector3(0.0, 0.0, -600.0))
	await _ticks(2)
	a.damageable.bounding_radius = 0.5
	b.damageable.bounding_radius = 0.5
	_head_on(a, b, SCRAPE_MPS, 14.0, SCRAPE_X_M)
	var touched: bool = false
	for i: int in 60:
		await _ticks(1)
		touched = touched or tracker.in_contact(a.ship.get_instance_id(), b.ship.get_instance_id())
	assert_true(touched, "Jolt reported the scrape")
	assert_true(tracker.kept.has(RamTracker.pair_key(a.ship.get_instance_id(), b.ship.get_instance_id())),
			"the resolver kept the pair touching while Jolt held it")


func test_a_pair_that_separates_and_comes_back_is_rammed_once_per_meeting() -> void:
	# Two raiders, one dropping belly first onto the other at 29 m/s: a swept ram each (14.5 m/s, under the raider's lethal 15),
	# then Jolt holds them together. Pulled apart, far out of each other's reach, and sent back: a second meeting, a second ram.
	_bystanders(8, 400.0)
	var lower: Combatant = _ship(RAIDER_PATH, Vector3(0.0, 0.0, 0.0))
	var upper: Combatant = _ship(RAIDER_PATH, Vector3(0.0, 3.0, 0.0))
	await _ticks(2)
	lower.ship.linear_velocity = Vector3(0.0, 14.5, 0.0)
	upper.ship.linear_velocity = Vector3(0.0, -14.5, 0.0)
	await _ticks(40)
	assert_eq(_kinds(), PackedStringArray(["tunnelling", "tunnelling"]), "one ram each, the bounce is the same collision")
	lower.damageable.restore()
	upper.damageable.restore()
	_place(lower, Vector3(0.0, -150.0, 0.0), Basis.IDENTITY, Vector3.ZERO)
	_place(upper, Vector3(0.0, 150.0, 0.0), Basis.IDENTITY, Vector3.ZERO)
	await _ticks(10)
	assert_eq(landed.size(), 2, "nothing while apart")
	_place(lower, Vector3(0.0, 0.0, 0.0), Basis.IDENTITY, Vector3(0.0, 14.5, 0.0))
	_place(upper, Vector3(0.0, 3.0, 0.0), Basis.IDENTITY, Vector3(0.0, -14.5, 0.0))
	await _ticks(40)
	assert_eq(_kinds(), PackedStringArray(["tunnelling", "tunnelling", "tunnelling", "tunnelling"]), "a second meeting, a second ram each")
	assert_eq(_rams_on(lower), 2)
	assert_eq(_rams_on(upper), 2)
