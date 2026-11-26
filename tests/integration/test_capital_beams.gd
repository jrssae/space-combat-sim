extends GutTest
## Capital beams on the native rows in the real main scene (M10-T12, D12.9, AC9's beam clause), on the Omega's six sustained
## particle beams: an Omega beams a hostile hull ahead section by section, only from the emitters whose arcs cover it; a lost
## mount stops its beam while its sister fires on; a disabled ship stops them all; an Omega leaves a disguised renegade alone
## until the renegade's own beam gives it away; the lines are drawn in one batch per kind; the console fires a test beam.

const TYPE: StringName = &"ea_omega"
const SPEED_UP: float = 4.0
const RENEGADES: StringName = &"renegades"

var main: Main
var _rate_backup: int = 60
var _scale_backup: float = 1.0
var _steps_backup: int = 8


func before_each() -> void:
	get_tree().paused = false
	_rate_backup = Engine.physics_ticks_per_second
	_scale_backup = Engine.time_scale
	_steps_backup = Engine.max_physics_steps_per_frame
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup
	DebugConsole.flags.invulnerable = false


# An Omega for `faction` `ahead_m` along the player's nose, bow along the player's (or toward the player with `facing_back`),
# holding still.
func _spawn(display_name: String, faction: StringName, ahead_m: float, facing_back: bool = false) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, display_name, rest)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	if cap == null:
		return null
	var basis: Basis = main.ship.global_basis
	if facing_back:
		basis = basis.rotated(basis.y, PI)
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position - main.ship.global_basis.z * ahead_m), basis)
	cap.set_course(-basis.z, rest)
	return cap


func _fly(seconds: float, done: Callable = Callable()) -> void:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED_UP)
	Engine.time_scale = SPEED_UP
	Engine.max_physics_steps_per_frame = maxi(_steps_backup, roundi(SPEED_UP))
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame
		if done.is_valid() and bool(done.call()):
			break
	Engine.physics_ticks_per_second = _rate_backup
	Engine.time_scale = _scale_backup
	Engine.max_physics_steps_per_frame = _steps_backup


func _run(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute_tokens(line.split(" ", false))


func _beams() -> CapitalBeams:
	return CapitalBeams.of(main.world)


# Every beam hit `target` takes, logged as [the shooter, the section, the damage], from each tick's summary (M10-T75: the
# beams land in one native batch a tick; each of its hits names its section, and every hit here carries the same share).
func _log_beams(target: CapitalShip) -> Array:
	var log: Array = []
	target.damageable.hits_landed.connect(func(summary: HitSummary) -> void:
		for slot: int in summary.sections:
			log.append([summary.last_shooter, target.damage.section_name(slot), summary.damage / float(summary.hits)]))
	return log


# The mounts of `ship`'s emitters that were firing on the last tick (phase 2).
func _firing(ship: CapitalShip) -> PackedStringArray:
	var out := PackedStringArray()
	for k: int in _beams().beams_of(ship):
		var s: Dictionary = _beams().state(k)
		if int(s["phase"]) == 2:
			out.append(str((s["mount"] as Dictionary)["name"]))
	return out


func test_an_omega_beams_a_hostile_hull_ahead_from_its_fore_emitters_by_section() -> void:
	var omega: CapitalShip = _spawn("EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var enemy: CapitalShip = _spawn("Renegade", RENEGADES, 7000.0, true)
	if omega == null or enemy == null:
		return
	enemy.damageable.invulnerable = true
	var log: Array = _log_beams(enemy)
	await wait_physics_frames(2)
	assert_eq(_beams().beams_of(omega).size(), 6, "the Omega's six particle beams are on the rows")
	var seen_firing: Dictionary = {}
	await _fly(4.0, func() -> bool:
		for m: String in _firing(omega):
			seen_firing[m] = true
		return false)
	assert_gt(log.size(), 60, "a sustained beam lands every tick it is on (%d hits)" % log.size())
	var shooters: Dictionary = {}
	var sections: Dictionary = {}
	var total: float = 0.0
	for e: Array in log:
		shooters[e[0]] = true
		sections[e[1]] = true
		total += float(e[2])
	assert_eq(shooters.keys(), [omega.get_instance_id()], "the Omega is the shooter")
	assert_false(sections.has(""), "every hit named by its section")
	# Its brain sweeps them onto a vital spot they can reach (M10-T16), else the nearest part: here the bridge, else the bow.
	assert_true(sections.has("bridge") or sections.has("bow"), "the beams land on the bridge or the bow it faces: %s" % [sections.keys()])
	assert_eq(seen_firing.keys().size(), 2, "only the fore emitters cover a hull dead ahead: %s" % [seen_firing.keys()])
	assert_true(seen_firing.has("beam_fore_r") and seen_firing.has("beam_fore_l"))
	# 40 dps an emitter while on, landed a tick's share at a time (the sped-up ticks are still 1/60 s of sim time).
	assert_almost_eq(total / float(log.size()), 40.0 / 60.0, 1e-6, "each tick's share of 40 dps")
	assert_gte(_beams().hits, log.size(), "its hits are counted (the enemy's aft beams on the Omega too)")
	assert_gt(BeamDraw.of(main.world).sustained_shown + _beams().lines_last, 0, "the lines are drawn")


func test_a_lost_mount_stops_its_beam_while_its_sister_fires_on_and_a_disabled_ship_stops_all() -> void:
	var omega: CapitalShip = _spawn("EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var enemy: CapitalShip = _spawn("Renegade", RENEGADES, 7000.0)
	if omega == null or enemy == null:
		return
	enemy.damageable.invulnerable = true
	await wait_physics_frames(2)
	assert_true(_run("capital focus %s" % String(omega.name)).ok)
	omega.damage.mounts["beam_fore_r"].hp = 1.0  # one point left, so a small hit takes the mount and spares its section
	assert_true(_run("capital damage beam_fore_r 1").ok, "the mount takes its last point")
	assert_false(omega.mount_works("beam_fore_r"), "lost")
	assert_true(omega.mount_works("beam_fore_l"), "its sister on the same section works")
	var seen: Dictionary = {}
	await _fly(4.0, func() -> bool:
		for m: String in _firing(omega):
			seen[m] = true
		return false)
	assert_false(seen.has("beam_fore_r"), "the lost mount never fires")
	assert_true(seen.has("beam_fore_l"), "its sister does")
	var index: int = _beams().beams_of(omega)[0]
	assert_false(bool(_beams().state(index)["works"]), "the rows know it is lost")
	assert_true(_run("capital disable").ok)
	await _fly(0.2)
	var log: Array = _log_beams(enemy)
	assert_true(_run("beam fire Renegade").ok, "the console's test shot is refused by nothing but the dead mounts")
	await _fly(4.0)
	assert_eq(log.size(), 0, "a disabled ship's beams are silent")
	assert_eq(_firing(omega).size(), 0)


func test_an_omega_leaves_a_disguised_renegade_alone_until_its_beam_gives_it_away() -> void:
	var omega: CapitalShip = _spawn("EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var renegade: CapitalShip = _spawn("Renegade", RENEGADES, 7000.0, true)
	if omega == null or renegade == null:
		return
	omega.damageable.invulnerable = true
	renegade.damageable.invulnerable = true
	renegade.targetable.disguise_as(Factions.EARTH_ALLIANCE)
	await wait_physics_frames(2)
	assert_true(renegade.targetable.is_disguised())
	var on_renegade: Array = _log_beams(renegade)
	var on_omega: Array = _log_beams(omega)
	# Only beams here: neither ship's guns fire (M10-T14), so the renegade's beam is what gives it away.
	for ship: CapitalShip in [omega, renegade]:
		CapitalGuns.of(main.world).hold(ship, true)
	# The renegade holds its fire first: the Omega takes it for a friend.
	_beams().hold(renegade, true)
	await _fly(4.0)
	assert_eq(on_renegade.size(), 0, "the Omega leaves the hull broadcasting Earth Alliance alone")
	_beams().hold(renegade, false)
	await _fly(4.0, func() -> bool: return not on_omega.is_empty())
	assert_false(on_omega.is_empty(), "the renegade, seeing an enemy, beams the Omega")
	assert_false(renegade.targetable.is_disguised(), "and its hit on Earth Alliance gives it away")
	await _fly(4.0, func() -> bool: return not on_renegade.is_empty())
	assert_false(on_renegade.is_empty(), "now the Omega beams it back")


func test_the_console_lists_emitters_and_fires_a_test_beam() -> void:
	var omega: CapitalShip = _spawn("EAS Agamemnon", Factions.EARTH_ALLIANCE, 3000.0)
	var enemy: CapitalShip = _spawn("Renegade", RENEGADES, 6000.0)
	if omega == null or enemy == null:
		return
	enemy.damageable.invulnerable = true
	await wait_physics_frames(2)
	assert_true(_run("capital focus %s" % String(omega.name)).ok)
	var info: ConsoleResult = _run("beam")
	assert_true(info.ok, info.error)
	assert_eq(info.lines.size(), 6, "one line an emitter")
	var fired: ConsoleResult = _run("beam fire Renegade")
	assert_true(fired.ok, fired.error)
	await _fly(2.5, func() -> bool: return _beams().hits > 0)
	assert_gt(_beams().hits, 0, "the test beam lands")
	assert_eq(int(DebugConsole.registry.read("beams.emitters")["value"]), 12, "two Omegas' emitters on the rows")
	assert_false(_run("beam fire nobody").ok, "an unknown target is refused")
	assert_true(_run("beam clear").ok)
