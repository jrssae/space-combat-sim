extends GutTest
## The beam hits' parity recording (M10-T75, Q70, Q85): beam hits moved from one GDScript landing per hit (`CapitalBeams._land`
## through each target's `Damageable`) into one native batch a tick on the damage store. Before the move this file recorded,
## from the GDScript landing, two hostile Omegas beaming each other across the seeded battle with their sections nearly spent
## (so sections fall, mounts go and a ship blows) and the fighters crossing their lines: every beam hit (the hull's place in the
## battle, the tick, damage, point), every damage event and the end state of every hull (`tests/fixtures/parity/
## beam_landing.json`). The native batch must land the same hits with the same outcomes, bit for bit; now its hits are read
## from the beams' native hit log, and no hit is left to GDScript.

const FILE: String = "beam_landing"
const TICKS: int = 600
const TYPE: StringName = &"ea_omega"
const GAP_M: float = 1600.0
## The share of its points each Omega section but the bridge starts with.
const SECTION_LEFT: float = 0.12
## Ticks per digest of the hit log.
const CHUNK_TICKS: int = 50

var _threads_backup: Variant = null


func before_all() -> void:
	CapitalHangar.stocked_on_spawn = false  # its capitals are alone here: their hangars stay empty (M10-T17)


func after_all() -> void:
	CapitalHangar.stocked_on_spawn = true


func before_each() -> void:
	_threads_backup = Settings.get_value(&"perf_threads")


func after_each() -> void:
	Settings.set_value(&"perf_threads", _threads_backup)


func test_beam_hits_and_their_outcomes_match_the_recorded_gdscript_landing() -> void:
	Settings.set_value(&"perf_threads", 6)
	var got: Dictionary = await _battle()
	assert_gt(int(got["hits"]), 300, "the beams land (%d hits)" % int(got["hits"]))
	gut.p("beam hits %d, events %d" % [int(got["hits"]), int(got["events"])])
	var expected: Variant = await ParityFixture.expected(FILE, "battle", func() -> Dictionary: return got)
	assert_not_null(expected, "the landing is recorded (%s.json)" % FILE)
	if expected == null:
		return
	var mine: Dictionary = ParityFixture.encode(got)
	var theirs: Dictionary = expected
	assert_eq(mine["hits"], theirs.get("hits"), "as many beam hits as recorded")
	var first_bad: int = -1
	var chunks: Array = mine["chunks"]
	var recorded: Array = theirs.get("chunks", [])
	for c: int in chunks.size():
		if c >= recorded.size() or chunks[c] != recorded[c]:
			first_bad = c * CHUNK_TICKS
			break
	assert_eq(first_bad, -1, "the hits tick by tick as recorded (first chunk off starts at tick %d)" % first_bad)
	assert_eq(mine["events"], theirs.get("events"), "as many damage events as recorded")
	assert_eq(mine["event_log"], theirs.get("event_log"), "the damage events as recorded")
	assert_eq(mine["end"], theirs.get("end"), "every hull's end state as recorded")
	assert_eq(int(got["deferred"]), 0, "every hit landed in the native batch")


# The seeded battle with an Earth Alliance and a raider Omega either side of its first fight, their sections nearly spent.
func _battle() -> Dictionary:
	var fight: Dictionary = await SeededBattle.start(self)
	var ships: Array[Combatant] = fight["ships"]
	var index_of: Dictionary = fight["index_of"]
	var world: WorldFrame = fight["world"]
	var centre: Vector3 = ships[0].ship.global_position
	var a: CapitalShip = _omega(world, Factions.EARTH_ALLIANCE, "Omega A", centre + Vector3(0.0, 0.0, GAP_M), Basis.IDENTITY)
	var b: CapitalShip = _omega(world, Factions.RAIDERS, "Omega B", centre - Vector3(0.0, 0.0, GAP_M), Basis(Vector3.UP, PI))
	var tick: Array[int] = [0]
	var hits: Array = []
	var events: Array = []
	CapitalBeams.of(world).set_hit_log(true)
	for c: Combatant in ships:
		var who: int = int(index_of.get(c.ship.get_instance_id(), -3))
		c.damageable.destroyed.connect(func(_info: HitInfo) -> void: events.append([tick[0], who, "destroyed"]))
	for pair: Array in [[a, -1], [b, -2]]:
		var cap: CapitalShip = pair[0]
		var who: int = pair[1]
		for name: String in cap.damage.sections:
			if cap.damage.sections[name].kind != CapitalSection.BRIDGE:
				cap.damage.sections[name].hp = cap.damage.sections[name].max_hp * SECTION_LEFT
		cap.damage.section_changed.connect(func(s: String, state: int) -> void: events.append([tick[0], who, "section", s, state]))
		cap.damage.mount_lost.connect(func(n: String) -> void: events.append([tick[0], who, "mount", n]))
		cap.damage.part_lost.connect(func(k: String) -> void: events.append([tick[0], who, "part", k]))
		cap.damage.disabled.connect(func() -> void: events.append([tick[0], who, "disabled"]))
		cap.damage.blew.connect(func(s: String) -> void: events.append([tick[0], who, "blew", s]))
		cap.damageable.destroyed.connect(func(_info: HitInfo) -> void: events.append([tick[0], who, "destroyed"]))
	var chunks: Array = []
	var chunk_from: int = 0
	for t: int in TICKS:
		tick[0] = t
		await get_tree().physics_frame
		_take_beam_hits(fight, [a, b], t, hits)
		if (t + 1) % CHUNK_TICKS == 0:
			chunks.append(ParityFixture.digest(hits.slice(chunk_from)))
			chunk_from = hits.size()
	var end: Array = []
	for c: Combatant in ships:
		end.append([c.damageable.hull.hp, c.damageable.hull.destroyed])
	for cap: CapitalShip in [a, b]:
		var state: Array = [cap.damageable.hull.hp, cap.damage.hull_hp, cap.damage.is_disabled, cap.damage.is_destroyed,
				cap.damage.blown]
		for name: String in cap.damage.sections:
			state.append([cap.damage.sections[name].hp, cap.damage.sections[name].state])
		for name: String in cap.damage.mounts:
			state.append([cap.damage.mounts[name].hp, cap.damage.mounts[name].alive])
		end.append(state)
	var deferred: int = CapitalBeams.of(world).deferred
	await SeededBattle.finish(fight)
	return {"hits": hits.size(), "chunks": chunks, "events": events.size(), "event_log": ParityFixture.digest(events),
			"end": ParityFixture.digest(end), "deferred": deferred}


# Each beam hit as [the hull's place in the battle (-1, -2 the Omegas), the tick, damage, point], in landing order, read from
# the beams' native hit log (M10-T75; before, from each hull's `hit_taken`): the hits of tick `tick` are those it logged since
# the last call.
func _take_beam_hits(fight: Dictionary, caps: Array[CapitalShip], tick: int, into: Array) -> void:
	var beams: CapitalBeams = CapitalBeams.of(fight["world"])
	var index_of: Dictionary = fight["index_of"]
	var who: Dictionary = {}
	for k: int in caps.size():
		who[caps[k].damageable.get_instance_id()] = -1 - k
		for rotor: CapitalRotor in caps[k].rotors:
			who[rotor.hull.get_instance_id()] = -1 - k
	for e: Array in beams.hit_log():
		var at: int = int(who.get(int(e[0]), index_of.get(int(e[1]), -3)))
		into.append([at, tick, e[3], e[5]])
	beams.set_hit_log(true)  # forgets what it read


func _omega(world: WorldFrame, faction: StringName, label: String, at: Vector3, basis: Basis) -> CapitalShip:
	var cap: CapitalShip = CapitalShip.create(TYPE, faction, label, Vector3.ZERO)
	assert_not_null(cap, "the Omega is generated (scripts/gen_assets.sh)")
	world.spawn(cap, world.to_universe(at), basis)
	cap.set_course(-basis.z, Vector3.ZERO)
	return cap
