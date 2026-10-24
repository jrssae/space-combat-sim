extends GutTest
## ContactScan (M3-T05, architecture §16 D33, §16.3): one list per physics tick, shared by every AI driver, of the active
## `Targetable`s and `Damageable`s in the tree; each ship gets the ones within 5 km but itself, with its relation to them,
## and a count of the hostile bolts about to pass within 15 m. Real ships from `ShipAssembly`, a nav buoy, a drone without
## a `Targetable` and real bolts; nothing is stepped.

const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const DRONE_SCENE: String = "res://tests/fixtures/target_drone.tscn"

var world: WorldFrame
var projectiles: Node3D
var own: Combatant
var wingman: Combatant
var enemy: Combatant
var far_enemy: Combatant
var parked: Combatant
var buoy: NavBuoy
var drone: TargetDrone


func before_each() -> void:
	Factions.reset()
	ContactScan.invalidate()
	world = WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	projectiles = Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	own = _ship(RAIDER_SPEC, "RAIDER 1", Factions.RAIDERS, Vector3.ZERO)
	wingman = _ship(RAIDER_SPEC, "RAIDER 2", Factions.RAIDERS, Vector3(100.0, 0.0, 0.0))
	enemy = _ship(STARFURY_SPEC, "ALPHA 1", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -800.0),
			Basis.looking_at(Vector3.RIGHT, Vector3.UP))
	far_enemy = _ship(STARFURY_SPEC, "ALPHA 2", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -6000.0))
	parked = _ship(STARFURY_SPEC, "ALPHA 3", Factions.EARTH_ALLIANCE, Vector3(0.0, 0.0, -300.0))
	parked.ship.visible = false
	parked.ship.process_mode = Node.PROCESS_MODE_DISABLED
	buoy = NavBuoy.create("NAV ALPHA")
	world.spawn(buoy, world.to_universe(Vector3(0.0, 50.0, -200.0)))
	drone = (load(DRONE_SCENE) as PackedScene).instantiate() as TargetDrone
	world.spawn(drone, world.to_universe(Vector3(-300.0, 0.0, 0.0)))
	wingman.ship.linear_velocity = Vector3(0.0, 0.0, -10.0)


func after_each() -> void:
	ContactScan.invalidate()
	Factions.reset()


func _ship(spec_path: String, display_name: String, faction: StringName, at: Vector3, basis: Basis = Basis.IDENTITY) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(spec_path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: display_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at), basis)
	return c


func _bolt(at: Vector3, velocity: Vector3, faction: StringName, shooter_id: int = 0) -> Projectile:
	var bolt := (load(Projectile.SCENE_PATH) as PackedScene).instantiate() as Projectile
	projectiles.add_child(bolt)
	bolt.faction = faction
	bolt.shooter_id = shooter_id
	bolt.launch(at, velocity, SimClock.now())
	return bolt


func _seen_by(c: Combatant, scan: ContactScan = null) -> Dictionary:
	var s: ContactScan = scan if scan != null else ContactScan.from_tree(get_tree())
	var by_name: Dictionary = {}
	for contact: Contact in s.contacts_for(c.ship.get_instance_id(), c.ship.global_position, c.faction):
		by_name[contact.name if not contact.name.is_empty() else "<%d>" % contact.id] = contact
	return by_name


func test_a_ship_sees_everything_active_within_5_km_but_itself() -> void:
	var seen: Dictionary = _seen_by(own)
	assert_false(seen.has("RAIDER 1"), "not itself")
	assert_true(seen.has("RAIDER 2"), "a wingman")
	assert_true(seen.has("ALPHA 1"), "an enemy 800 m out")
	assert_true(seen.has("NAV ALPHA"), "a buoy")
	assert_true(seen.has("<%d>" % drone.get_instance_id()), "a hull without a Targetable, by its body id")
	assert_false(seen.has("ALPHA 2"), "not one 6 km out (sensor range %.0f m)" % ContactScan.SENSOR_RANGE_M)
	assert_false(seen.has("ALPHA 3"), "not a parked (hidden, disabled) ship")
	assert_eq(seen.size(), 4)


func test_contacts_carry_identity_motion_and_hull() -> void:
	enemy.damageable.hull.apply(enemy.damageable.hull.max_hp * 0.25)
	var seen: Dictionary = _seen_by(own)
	var e: Contact = seen["ALPHA 1"]
	assert_eq(e.id, enemy.targetable.get_instance_id(), "the Targetable's id, as TargetInfo")
	assert_eq(e.faction, Factions.EARTH_ALLIANCE)
	assert_almost_eq(e.position, enemy.ship.global_position, Vector3.ONE * 1e-4)
	assert_almost_eq(e.forward, Vector3.RIGHT, Vector3.ONE * 1e-4, "its nose")
	assert_almost_eq(e.bounding_radius, enemy.damageable.bounding_radius, 1e-6)
	assert_gt(e.bounding_radius, 1.0)
	assert_true(e.is_ship)
	assert_almost_eq(e.hull_fraction, 0.75, 1e-6)
	var w: Contact = seen["RAIDER 2"]
	assert_almost_eq(w.velocity, Vector3(0.0, 0.0, -10.0), Vector3.ONE * 1e-4, "a body's linear velocity")
	var b: Contact = seen["NAV ALPHA"]
	assert_false(b.is_ship, "a prop")
	assert_eq(b.velocity, Vector3.ZERO, "a static prop")
	assert_eq(b.faction, Factions.NEUTRAL)
	assert_almost_eq(b.hull_fraction, 1.0, 1e-6)
	var d: Contact = seen["<%d>" % drone.get_instance_id()]
	assert_eq(d.faction, drone.damageable.faction, "the hull's faction when there is no Targetable")
	assert_true(d.is_ship)


func test_relations_are_from_the_perceiving_ship() -> void:
	var by_raider: Dictionary = _seen_by(own)
	assert_eq((by_raider["RAIDER 2"] as Contact).relation, Factions.Relation.FRIENDLY)
	assert_eq((by_raider["ALPHA 1"] as Contact).relation, Factions.Relation.HOSTILE)
	assert_eq((by_raider["NAV ALPHA"] as Contact).relation, Factions.Relation.NEUTRAL)
	var by_alliance: Dictionary = _seen_by(enemy)
	assert_eq((by_alliance["RAIDER 1"] as Contact).relation, Factions.Relation.HOSTILE)
	assert_false(by_alliance.has("ALPHA 3"), "parked: unseen from any side")


func test_target_id_is_whom_a_ship_has_selected() -> void:
	assert_true(wingman.ship.targeting.select_nearest_hostile())
	var seen: Dictionary = _seen_by(own)
	assert_eq((seen["RAIDER 2"] as Contact).target_id, enemy.targetable.get_instance_id())
	assert_eq((seen["ALPHA 1"] as Contact).target_id, -1, "nothing selected")
	assert_eq((seen["NAV ALPHA"] as Contact).target_id, -1, "no targeting computer")


func test_one_scan_per_physics_frame_shared_by_every_driver() -> void:
	var first: ContactScan = ContactScan.shared(get_tree())
	assert_same(ContactScan.shared(get_tree()), first, "the same frame: the same scan")
	wingman.ship.global_position = Vector3(200.0, 0.0, 0.0)
	assert_almost_eq((_seen_by(own, ContactScan.shared(get_tree()))["RAIDER 2"] as Contact).position.x, 100.0, 1e-4,
			"positions as of the scan")
	await get_tree().physics_frame
	var next: ContactScan = ContactScan.shared(get_tree())
	assert_not_same(next, first, "a new frame: a new scan")
	assert_almost_eq((_seen_by(own, next)["RAIDER 2"] as Contact).position.x, 200.0, 5.0, "current again")


func test_a_scan_of_freed_bodies_is_rebuilt_within_the_frame() -> void:
	var first: ContactScan = ContactScan.shared(get_tree())
	drone.free()
	assert_not_same(ContactScan.shared(get_tree()), first)


func test_ships_of_one_faction_share_contact_objects() -> void:
	var scan: ContactScan = ContactScan.from_tree(get_tree())
	var by_own: Array[Contact] = scan.contacts_for(own.ship.get_instance_id(), own.ship.global_position, own.faction)
	var by_wingman: Array[Contact] = scan.contacts_for(wingman.ship.get_instance_id(), wingman.ship.global_position, wingman.faction)
	var enemy_a: Contact = null
	var enemy_b: Contact = null
	for c: Contact in by_own:
		if c.name == "ALPHA 1":
			enemy_a = c
	for c: Contact in by_wingman:
		if c.name == "ALPHA 1":
			enemy_b = c
	assert_same(enemy_a, enemy_b, "one object per faction, not one per ship")


func test_in_a_fight_a_ship_sees_every_body_but_itself_in_the_same_order_as_the_loop() -> void:
	far_enemy.ship.global_position = Vector3(0.0, 0.0, -1500.0)  # every body within 5 km of every other: the copy path
	var scan: ContactScan = ContactScan.from_tree(get_tree())
	var seen: Array[Contact] = scan.contacts_for(own.ship.get_instance_id(), own.ship.global_position, own.faction)
	# A body id the scan does not know takes the range loop; without the ship itself that is what the loop gives the ship.
	var looped: Array[Contact] = []
	for c: Contact in scan.contacts_for(-1, own.ship.global_position, own.faction):
		if c.name != "RAIDER 1":
			looped.append(c)
	assert_eq(seen.size(), 5, "the wingman, both enemies, the buoy and the drone")
	assert_eq(seen.size(), looped.size(), "the same contacts as the loop")
	for i: int in mini(seen.size(), looped.size()):
		assert_same(seen[i], looped[i], "the same contact object, in the same place (%d)" % i)


func test_incoming_fire_counts_hostile_bolts_passing_within_15_m_in_2_s() -> void:
	_bolt(Vector3(0.0, 0.0, -500.0), Vector3(0.0, 0.0, 400.0), Factions.EARTH_ALLIANCE)  # dead on, 1.25 s out: counts
	_bolt(Vector3(5.0, 8.0, -300.0), Vector3(0.0, 0.0, 400.0), Factions.EARTH_ALLIANCE)  # 9.4 m off, 0.75 s: counts
	_bolt(Vector3(20.0, 0.0, -500.0), Vector3(0.0, 0.0, 400.0), Factions.EARTH_ALLIANCE)  # 20 m off: no
	_bolt(Vector3(0.0, 0.0, -1000.0), Vector3(0.0, 0.0, 400.0), Factions.EARTH_ALLIANCE)  # 2.5 s out: no
	_bolt(Vector3(0.0, 0.0, 100.0), Vector3(0.0, 0.0, 400.0), Factions.EARTH_ALLIANCE)  # already past, flying away: no
	_bolt(Vector3(0.0, 0.0, -500.0), Vector3(0.0, 0.0, 400.0), Factions.RAIDERS)  # a friend's: no
	var scan: ContactScan = ContactScan.from_tree(get_tree())
	assert_eq(scan.incoming_fire(own.ship.get_instance_id(), Vector3.ZERO, Vector3.ZERO, own.faction), 2)
	assert_eq(scan.incoming_fire(own.ship.get_instance_id(), Vector3.ZERO, Vector3(0.0, 0.0, -400.0), own.faction), 3,
			"own motion counts: flying into them, the one 2.5 s out arrives in 1.25 s")
