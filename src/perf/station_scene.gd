class_name StationScene
extends Node
## The render comparison's second scene (M4-T27, Q24): the Babylon 5 station stand-in, 10 capital ships holding station around it,
## 80 fighters in a fight beside it (40 Earth Alliance Starfuries, 40 raiders, invulnerable like the bench's) and a planet 40 km off,
## drawn only: a 12 km body pulls nothing (D66, M6-T07). Bench-only: nothing in a scenario builds it.
##
## Every hull is drawn as its textured mesh. The player's ship is moved to a viewpoint near the station or 11 km off it, nose on the station, at rest.
##
## Console: `station <near|far|off>`.

const FIGHTERS_PER_SIDE: int = 40
const FIGHT_BALL_M: float = 500.0
## The capitals: class, faction, offset from the station's centre (m), all at rest.
const CAPITALS: Array[Dictionary] = [
	{"cls": &"carrier", "side": 0, "at": Vector3(-2600.0, 700.0, 1800.0)},
	{"cls": &"carrier", "side": 1, "at": Vector3(3200.0, -900.0, -2600.0)},
	{"cls": &"destroyer", "side": 0, "at": Vector3(-1900.0, -600.0, -1200.0)},
	{"cls": &"destroyer", "side": 0, "at": Vector3(2100.0, 1300.0, 2600.0)},
	{"cls": &"destroyer", "side": 1, "at": Vector3(3400.0, 500.0, 400.0)},
	{"cls": &"cruiser", "side": 0, "at": Vector3(-1500.0, 1400.0, 300.0)},
	{"cls": &"cruiser", "side": 0, "at": Vector3(1700.0, -1300.0, 1200.0)},
	{"cls": &"cruiser", "side": 0, "at": Vector3(-2400.0, -1500.0, 3200.0)},
	{"cls": &"cruiser", "side": 1, "at": Vector3(2600.0, 1800.0, -800.0)},
	{"cls": &"cruiser", "side": 1, "at": Vector3(1500.0, -400.0, -3600.0)},
]
const FIGHT_CENTRE: Vector3 = Vector3(800.0, 150.0, -300.0)
const VIEWS: Dictionary = {
	&"near": {"at": Vector3(1300.0, 250.0, 600.0), "look": Vector3(0.0, 0.0, -1200.0)},
	&"far": {"at": Vector3(9000.0, 3000.0, 6000.0), "look": Vector3(0.0, 0.0, 0.0)},
}
const PLANET_OFFSET: Vector3 = Vector3(-26000.0, -16000.0, -24000.0)
const PLANET_RADIUS_M: float = 12000.0
const SIDES: Array[Dictionary] = [
	{"type": ShipPool.ALLY_TYPE, "profile": "ally_starfury", "faction": Factions.EARTH_ALLIANCE},
	{"type": ShipPool.DEFAULT_TYPE, "profile": "raider", "faction": Factions.RAIDERS},
]

var main: Main = null
var station: StationStandin = null
var planet: MeshInstance3D = null
var fighters: Array[Combatant] = []
## The station's centre, universe frame (null while the scene is closed).
var centre: UniversePos = null


func _ready() -> void:
	DebugConsole.registry.register_command(ConsoleCommand.new(&"station",
			"Open the render comparison's station scene and put the player near it or far from it, or close it",
			[ConsoleArg.enum_required(&"view", [&"near", &"far", &"off"])]), _cmd_station, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)


func is_open() -> bool:
	return centre != null


## Builds the scene around a point 3 km ahead of the player (once), then moves the player to `view`. False when the station asset
## is missing.
func open(view: StringName) -> bool:
	if not is_open() and not _build():
		return false
	place_player(view)
	return true


## Takes everything down again and gives the fighters back to the pool.
func close() -> void:
	for c: Combatant in fighters:
		if is_instance_valid(c) and c.ship.is_inside_tree():
			main.ships.release(c)
	fighters.clear()
	if main.bench.standins != null:
		main.bench.standins.clear()
	for node: Node3D in [station, planet]:
		if node != null and is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	station = null
	planet = null
	centre = null


## Puts the player's ship at the view's place, at rest, nose on the view's target.
func place_player(view: StringName) -> void:
	if not is_open() or not main.player_alive or not VIEWS.has(view):
		return
	var spec: Dictionary = VIEWS[view]
	var at: Vector3 = main.world.universe_to_local(centre.plus_local(spec["at"]))
	var target: Vector3 = main.world.universe_to_local(centre.plus_local(spec["look"]))
	main.ship.reset_to(Transform3D(Basis.looking_at((target - at).normalized(), Vector3.UP), at))
	main.ship.linear_velocity = Vector3.ZERO
	main.ship.angular_velocity = Vector3.ZERO


func _build() -> bool:
	var anchor: UniversePos = main.world.to_universe(main.ship.global_position - main.ship.global_basis.z * 3000.0)
	station = StationStandin.new()
	station.name = "Station"
	if not station.build():
		station.free()
		station = null
		return false
	centre = anchor
	main.world.spawn(station, centre, Basis.IDENTITY, main.world)
	planet = _make_planet()
	main.world.spawn(planet, centre.plus_local(PLANET_OFFSET), Basis.IDENTITY, main.world)
	var standins: StandinDirector = main.bench.standins
	standins.clear()
	var faction_of: Array[StringName] = [Factions.EARTH_ALLIANCE, Factions.RAIDERS]
	var index: int = 0
	for row: Dictionary in CAPITALS:
		var cap: CapitalStandin = standins.add_capital(row["cls"], faction_of[int(row["side"])], "STATION CAPITAL %d" % (index + 1),
				centre.plus_local(row["at"]), Basis.IDENTITY, Vector3.ZERO)
		cap.damageable.invulnerable = true
		index += 1
	standins.sides = 2
	standins.active = true
	_spawn_fighters()
	_apply_look()
	return true


func _spawn_fighters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 27
	for side: int in SIDES.size():
		var row: Dictionary = SIDES[side]
		main.ensure_pool(row["type"], FIGHTERS_PER_SIDE + main.ships.alive(row["type"]).size())
		var side_centre: Vector3 = FIGHT_CENTRE + Vector3(0.0, 0.0, -350.0 if side == 0 else 350.0)
		for i: int in FIGHTERS_PER_SIDE:
			var offset: Vector3 = side_centre + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * FIGHT_BALL_M
			var at: UniversePos = centre.plus_local(offset)
			var made: Dictionary = BrainFactory.from_behaviour({"type": "ai", "profile": row["profile"]}, at, 2700 + side * 100 + i)
			if not bool(made["ok"]):
				continue
			var facing: Vector3 = (FIGHT_CENTRE - offset).normalized()
			var prefix: String = ShipPool.ALLY_NAME_PREFIX if row["type"] == ShipPool.ALLY_TYPE else ShipPool.NAME_PREFIX
			var first: int = ShipPool.ALLY_FIRST_NUMBER if row["type"] == ShipPool.ALLY_TYPE else 1
			var placed: Combatant = main.ships.acquire(main.ships.next_name(prefix, first), at, Basis.looking_at(facing, Vector3.UP),
					Vector3.ZERO, made["brain"] as PilotBrain, row["type"])
			if placed == null:
				continue
			placed.damageable.invulnerable = true
			if placed.faction != StringName(row["faction"]):
				BenchRunner.set_faction(placed, row["faction"])
			fighters.append(placed)


func _make_planet() -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = PLANET_RADIUS_M
	sphere.height = 2.0 * PLANET_RADIUS_M
	sphere.radial_segments = 128
	sphere.rings = 64
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.62, 0.36, 0.22)
	material.roughness = 1.0
	sphere.material = material
	var node := MeshInstance3D.new()
	node.name = "Planet"
	node.mesh = sphere
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_to_group(WorldFrame.SHIFTABLE_GROUP)
	node.add_to_group(WorldFrame.ANCHORED_GROUP)
	return node


# The capitals draw their textured hulls (the station's pieces always do).
func _apply_look() -> void:
	if not is_open():
		return
	for cap: CapitalStandin in main.bench.standins.capitals():
		if is_instance_valid(cap):
			cap.set_look(CapitalStandin.LOOK_MESH)


func _cmd_station(args: Dictionary) -> ConsoleResult:
	var view: StringName = StringName(args[&"view"])
	if view == &"off":
		close()
		return ConsoleResult.line("station scene closed")
	if not open(view):
		return ConsoleResult.failure("the b5_station asset is not generated (run scripts/gen_assets.sh, then import)")
	return ConsoleResult.line("station scene: %s view, %d fighters, %d capitals" % [view, fighters.size(),
			main.bench.standins.capitals().size()])
