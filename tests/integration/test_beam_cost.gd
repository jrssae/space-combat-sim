extends GutTest
## The beams' landing cost with 32 sustained beams on (M10-T75, Q70): eight Earth Alliance and eight raider Omegas in pairs
## 3.2 km apart, bow to bow, beaming each other beside the seeded battle's fighters (192 emitters, the two fore ones of each
## bearing). Reports
## the native step and the landing a tick and per hit (wall clock, a readout: T75 measured 302 us a tick, about 9 us a hit,
## before the batch). A slow file.

const TICKS: int = 300
const TYPE: StringName = &"ea_omega"
const PAIRS: int = 8
const GAP_M: float = 1600.0
const SPACING_M: float = 2500.0


# A slow file (M4-T36, Q58): runs with GUT_SLOW=1 (the full run and CI), skipped in focused runs.
func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


@warning_ignore("untyped_declaration")  # GutTest declares it untyped
func should_skip_script():
	return SlowTests.skip_reason()


func test_thirty_two_sustained_beams_land_and_report_their_cost() -> void:
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var world: WorldFrame = fight["world"]
	var centre: Vector3 = ships[0].ship.global_position + Vector3(0.0, 4000.0, 0.0)
	for p: int in PAIRS:
		var side := Vector3(SPACING_M * (p - 3.5), 0.0, 0.0)
		_omega(world, Factions.EARTH_ALLIANCE, "Omega A%d" % p, centre + side + Vector3(0.0, 0.0, GAP_M), Basis.IDENTITY)
		_omega(world, Factions.RAIDERS, "Omega B%d" % p, centre + side - Vector3(0.0, 0.0, GAP_M), Basis(Vector3.UP, PI))
	var beams: CapitalBeams = CapitalBeams.of(world)
	var land: Array[float] = []
	var step: Array[float] = []
	var per_hit: Array[float] = []
	var lines: Array[int] = []
	var hits_before: int = beams.hits
	for t: int in TICKS:
		await get_tree().physics_frame
		var landed: int = beams.hits - hits_before
		hits_before = beams.hits
		lines.append(beams.lines_last)
		if landed >= 28:
			land.append(float(beams.land_us))
			step.append(beams.step_us)
			per_hit.append(float(beams.land_us) / float(landed))
	await SeededBattle.finish(fight)
	assert_gt(land.size(), 50, "ticks with about 32 beams landing (%d)" % land.size())
	if land.is_empty():
		return
	for list: Array[float] in [land, step, per_hit]:
		list.sort()
	lines.sort()
	gut.p("32 sustained beams (%d ticks, lines drawn median %d): landing median %.1f us (p90 %.1f), %.2f us a hit; native step %.1f us"
			% [land.size(), lines[lines.size() / 2], land[land.size() / 2], land[int(land.size() * 0.9)],
			per_hit[per_hit.size() / 2], step[step.size() / 2]])


func _omega(world: WorldFrame, faction: StringName, label: String, at: Vector3, basis: Basis) -> CapitalShip:
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, label, Vector3.ZERO)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	world.spawn(cap, world.to_universe(at), basis)
	cap.set_course(-basis.z, Vector3.ZERO)
	return cap
