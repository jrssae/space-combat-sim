extends GutTest
## AC26, the slashing pass in Jolt (M3-T18, Q19): a veteran Starfury on the `ally_starfury` profile flies the slashing pass and
## chase against a straight-flying drone; the same pilot with the pass turned off (`AiProfile.slashing` false) flies the
## standard gun run on the same seed, 10 km away in the same world. Over 60 s the slashing pilot has the drone inside its fire
## gate (range, cone and miss distance, measured here from the ship's muzzles, nose and the intercept lead) at least 25 % longer,
## and it fires within 1 s of its first closest approach. Real ships, Jolt and the real drivers; sim time sped up.

const STARFURY_SPEC: String = "res://assets/ships/starfury_aurora.tres"
const RAIDER_SPEC: String = "res://assets/ships/raider_delta_v.tres"
const SPEED_UP: float = 2.0
const RUN_S: float = 60.0
const SEED: int = 1919
const APART_M: float = 10000.0

var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	ContactScan.invalidate()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	ContactScan.invalidate()


func _ship(world: WorldFrame, projectiles: Node3D, spec_path: String, faction: StringName, ship_name: String, at: Vector3,
		velocity: Vector3) -> Combatant:
	var c: Combatant = ShipAssembly.build(load(spec_path) as ShipSpec, world, projectiles, {
		ShipAssembly.OPT_FACTION: faction,
		ShipAssembly.OPT_DISPLAY_NAME: ship_name,
		ShipAssembly.OPT_FORCE_ASSIST: true,
		ShipAssembly.OPT_AI: true,
	})
	world.spawn(c.ship, world.to_universe(at))
	c.ship.linear_velocity = velocity
	c.damageable.hull = HullHealth.new(1.0e6)
	return c


## A veteran, balanced Starfury pilot 2 km behind a drone flying straight at 60 m/s; `slashing` false flies the standard run.
func _setup(world: WorldFrame, projectiles: Node3D, at: Vector3, slashing: bool, tag: String) -> Dictionary:
	var drone: Combatant = _ship(world, projectiles, RAIDER_SPEC, Factions.RAIDERS, "DRONE %s" % tag, at, Vector3(60.0, 0.0, 0.0))
	var hunter: Combatant = _ship(world, projectiles, STARFURY_SPEC, Factions.EARTH_ALLIANCE, "ALPHA %s" % tag,
			at + Vector3(0.0, 0.0, 2000.0), Vector3.ZERO)
	var profile := (AiProfile.load_named(&"ally_starfury") as AiProfile).duplicate() as AiProfile
	profile.slashing = slashing
	var pilot := AiPilot.new(profile, SEED, [] as Array[AiBehaviour], AiTemperament.new(0.7, 0.5))
	# Every run a slashing pass (a veteran flies 65 % of them) or, with slashing off, every run the standard one.
	var attack := pilot.behaviour(&"attack") as BehaviourAttack
	attack.slash_chance = 1.0 if slashing else 0.0
	attack.close_pass_chance = 0.0
	attack.reset()
	hunter.driver.brain = pilot
	return {"drone": drone, "hunter": hunter, "pilot": pilot, "gate_s": 0.0, "closest_m": INF, "closest_at_s": -1.0,
			"fire_times": [], "passed": false}


# The fire gate as the brains apply it, measured from the ship: the intercept lead from the mean muzzle, the nose's angle off
# it, the cone capped by the miss distance at this range, inside the fire range.
func _in_gate(run: Dictionary) -> bool:
	var hunter: Combatant = run["hunter"]
	var drone: Combatant = run["drone"]
	var tactics: RaiderTactics = (run["pilot"] as AiPilot).profile.tactics
	var muzzle := Vector3.ZERO
	var muzzles: Array[Transform3D] = hunter.ship.get_muzzle_transforms()  # a lean ship has no marker nodes (M4-T35)
	for m: Transform3D in muzzles:
		muzzle += hunter.ship.global_transform * m.origin
	muzzle /= float(muzzles.size())
	var lead: Dictionary = InterceptMath.solve(muzzle, hunter.ship.linear_velocity, drone.ship.global_position,
			drone.ship.linear_velocity, hunter.cannon.weapon.muzzle_speed_mps, hunter.cannon.weapon.lifetime_s)
	if not bool(lead["ok"]):
		return false
	var range_m: float = hunter.ship.global_position.distance_to(drone.ship.global_position)
	var off_deg: float = rad_to_deg(hunter.ship.forward().angle_to(lead["aim_dir"] as Vector3))
	var cone_deg: float = minf(tactics.fire_cone_deg, rad_to_deg(atan(tactics.fire_miss_m / range_m)))
	return range_m < tactics.fire_range_m and off_deg < cone_deg


func _sample(run: Dictionary, dt: float, t: float) -> void:
	if _in_gate(run):
		run["gate_s"] = float(run["gate_s"]) + dt
	var range_m: float = (run["hunter"] as Combatant).ship.global_position.distance_to((run["drone"] as Combatant).ship.global_position)
	if not bool(run["passed"]):
		if range_m < float(run["closest_m"]):
			run["closest_m"] = range_m
			run["closest_at_s"] = t
		elif range_m > float(run["closest_m"]) + 50.0:
			run["passed"] = true  # the first closest approach is behind it


func test_the_slashing_pass_keeps_the_drone_in_the_gate_at_least_25_percent_longer() -> void:
	var world := WorldFrame.new()
	world.name = "World"
	add_child_autofree(world)
	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var slashing: Dictionary = _setup(world, projectiles, Vector3(APART_M / 2.0, 0.0, 0.0), true, "S")
	var standard: Dictionary = _setup(world, projectiles, Vector3(-APART_M / 2.0, 0.0, 0.0), false, "N")
	assert_true(((slashing["pilot"] as AiPilot).behaviour(&"attack") as BehaviourAttack).uses_slash, "a veteran slashes")
	assert_false(((standard["pilot"] as AiPilot).behaviour(&"attack") as BehaviourAttack).uses_slash, "turned off: the standard run")
	(slashing["hunter"] as Combatant).cannon.shot_fired.connect(func(_i: int, _at: Vector3) -> void:  # on either bolt path (M4-T35)
		(slashing["fire_times"] as Array).append(SimClock.now()))  # an Array: a reference, unlike a packed array
	var t0: float = SimClock.now()
	var ticker := PhysicsTicker.new()
	ticker.on_tick = func() -> void:
		var dt: float = Engine.time_scale / float(Engine.physics_ticks_per_second)
		_sample(slashing, dt, SimClock.now())
		_sample(standard, dt, SimClock.now())

	add_child_autofree(ticker)
	Engine.time_scale = SPEED_UP
	while SimClock.now() - t0 < RUN_S:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	var slash := ((slashing["pilot"] as AiPilot).behaviour(&"attack") as BehaviourAttack).slash
	gut.p("slashing: %.1f s in the gate (%d passes, %s); standard: %.1f s; first closest approach %.0f m at %.1f s" % [
			slashing["gate_s"], slash.passes, slash.describe()["state"], standard["gate_s"], slashing["closest_m"],
			float(slashing["closest_at_s"]) - t0])
	assert_gt(float(standard["gate_s"]), 0.0, "the standard run gets on target too")
	assert_gte(float(slashing["gate_s"]), 1.25 * float(standard["gate_s"]), "at least 25 % longer in the gate")
	var near: bool = false
	for t: float in slashing["fire_times"] as Array:
		near = near or absf(t - float(slashing["closest_at_s"])) <= 1.0
	assert_true(near, "it fired within 1 s of its first closest approach")


func test_every_skill_slashes_rookies_always_and_profiles_may_opt_out() -> void:
	var rookie := AiPilot.new(AiProfile.load_named(&"raider"), 1, [] as Array[AiBehaviour], AiTemperament.new(0.2, 0.5))
	assert_eq((rookie.behaviour(&"attack") as BehaviourAttack).slash_chance, 1.0, "a rookie always slashes")
	var ace := AiPilot.new(AiProfile.load_named(&"raider"), 1, [] as Array[AiBehaviour], AiTemperament.new(0.95, 0.5))
	assert_almost_eq((ace.behaviour(&"attack") as BehaviourAttack).slash_chance, 0.5, 1e-9, "an ace half its runs")
	for profile_name: StringName in [&"instructor", &"civilian"]:
		var opted := AiPilot.new(AiProfile.load_named(profile_name), 1, [] as Array[AiBehaviour], AiTemperament.new(0.2, 1.0))
		assert_eq((opted.behaviour(&"attack") as BehaviourAttack).slash_chance, 0.0, "%s never slashes" % profile_name)
	# Runs are rolled: over many engagements an ace mixes both, seeded.
	var slashing: int = 0
	for s: int in 200:
		var pilot := AiPilot.new(AiProfile.load_named(&"raider"), s, [] as Array[AiBehaviour], AiTemperament.new(0.95, 0.5))
		slashing += 1 if (pilot.behaviour(&"attack") as BehaviourAttack).uses_slash else 0
	assert_between(slashing, 70, 130, "about half of an ace's runs are slashing passes (%d of 200)" % slashing)
	var live := AiPilot.new(AiProfile.load_named(&"ally_starfury"), 1)
	live.set_temperament(AiTemperament.new(0.2, 0.5))
	assert_eq((live.behaviour(&"attack") as BehaviourAttack).slash_chance, 1.0, "retuned live")
