extends GutTest
## M3 end to end (M3-T12): one headless build runs the sandbox's fight with orders, lights, deaths and a replacement wingman, and the
## node counts the design promises stay fixed through it. The dogfight records AC13's AI time (Q10) and holds its resolver budget.

const SPEED_UP: float = 4.0
const DOGFIGHT_PATH: String = "res://data/scenarios/dogfight.json"
const DOGFIGHT_SECONDS: float = 45.0
## AC13: the hit and ram resolvers together, per tick. A kill's effects run inside the resolve and a busy machine doubles the worst tick
## (see test_m2_run), so the 99th percentile is what is asserted and the worst is recorded.
const RESOLVER_BUDGET_US: int = 2000
const MAX_LIGHTS: int = 8

var main: Main
var source: FakeInputSource
var _scale_backup: float = 1.0


func before_each() -> void:
	_scale_backup = Engine.time_scale
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	source = FakeInputSource.new()


func after_each() -> void:
	Engine.time_scale = _scale_backup
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _start(scenario_path: String = "") -> void:
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	if not scenario_path.is_empty():
		main.scenario_path = scenario_path
	add_child_autofree(main)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _exec(line: String) -> ConsoleResult:
	return DebugConsole.registry.execute(line)[0]


func _count(node: Node, kind: Variant) -> int:
	var n: int = 1 if is_instance_of(node, kind) else 0
	for child: Node in node.get_children():
		n += _count(child, kind)
	return n


func _ticks(seconds: float) -> void:
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < seconds:
		await get_tree().physics_frame


static func _percentile(values: PackedInt64Array, share: float) -> int:
	var sorted: PackedInt64Array = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(share * float(sorted.size())))] if not sorted.is_empty() else 0


func test_the_sandbox_plays_a_whole_fight_with_every_system_on() -> void:
	await _start()
	var splat_nodes: int = _count(get_tree().root, GaussianSplatNode)
	var particles: int = _count(get_tree().root, GPUParticles3D)
	assert_gt(splat_nodes, 0)
	assert_gt(particles, 0)
	assert_eq(main.wings.player_wing().members().size(), 3, "the wing is on the player at load")
	source.hold(InputAdapter.FIRE)
	assert_true(_exec("wing order engage").ok)
	assert_true(_exec("wave start 3").ok)
	Engine.time_scale = SPEED_UP
	# Wave 3 comes in from 4 km after a countdown; the fight has started once the first bolt lands.
	var resolver: HitResolver = main.get_node("Combat/HitResolver") as HitResolver
	var lights_most: int = 0
	var t_wave: float = SimClock.now()
	while resolver.hits_total == 0 and SimClock.now() - t_wave < 90.0:
		await get_tree().physics_frame
		lights_most = maxi(lights_most, int(DebugConsole.registry.read("lights.active")["value"]))
	assert_gt(resolver.hits_total, 0, "bolts hit")
	# Every order, then the lights: the wing follows the player's.
	for order: String in ["form", "cover", "engage"]:
		assert_true(_exec("wing order %s" % order).ok)
		await _ticks(1.0)
	assert_true(_exec("running_lights off").ok)
	await _ticks(1.0)
	for member: Combatant in main.wings.player_wing().members():
		assert_false(member.ship.running_lights, "%s follows the player's lights" % member.display_name)
	assert_true(_exec("running_lights on").ok)
	# Lose a wingman, and the player: the wave goes on, the player comes back, and the next wave brings the replacement.
	assert_true(_exec("kill allies").ok)
	await get_tree().physics_frame
	assert_eq(main.wings.player_wing().members().size(), 0, "a downed wingman leaves the wing")
	assert_true(_exec("kill player").ok)
	await _ticks(4.0)
	assert_true(main.player_alive, "the player respawned")
	assert_true(_exec("kill all").ok)
	assert_true(_exec("wave next").ok)
	var t0: float = SimClock.now()
	while main.wings.player_wing().members().size() < 3 and SimClock.now() - t0 < 30.0:
		await get_tree().physics_frame
	assert_eq(main.wings.player_wing().members().size(), 3, "the next wave brought the wing back")
	var t_end: float = SimClock.now()
	while SimClock.now() - t_end < 3.0:
		await get_tree().physics_frame
		lights_most = maxi(lights_most, int(DebugConsole.registry.read("lights.active")["value"]))
	source.release(InputAdapter.FIRE)
	Engine.time_scale = 1.0
	assert_eq(_count(get_tree().root, GaussianSplatNode), splat_nodes, "no splat node entered or left the tree")
	assert_eq(_count(get_tree().root, GPUParticles3D), particles, "no particle node entered or left the tree")
	assert_between(lights_most, 1, MAX_LIGHTS, "the picker lit something and never more than its slots")
	gut.p("M3 run: %d splat nodes, %d particle nodes, %d kills, %d hits, %d lights at most" % [splat_nodes, particles, main.waves.kills,
			resolver.hits_total, lights_most])


func test_the_dogfight_records_the_ai_time_and_holds_the_resolver_budget() -> void:
	await _start(DOGFIGHT_PATH)
	var hit_resolver: HitResolver = main.get_node("Combat/HitResolver") as HitResolver
	var think := PackedInt64Array()
	var resolvers := PackedInt64Array()
	var ships_at_start: int = main.ships.alive().size()
	Engine.time_scale = SPEED_UP
	var t0: float = SimClock.now()
	while SimClock.now() - t0 < DOGFIGHT_SECONDS:
		await get_tree().physics_frame
		think.append(AiPilotDriver.think_us())
		resolvers.append(hit_resolver.resolve_us + main.rams.resolve_us)
	Engine.time_scale = 1.0
	assert_eq(ships_at_start, 10, "four allies and six raiders")
	assert_gt(hit_resolver.hits_total, 0, "the sides met")
	var resolve_p99: int = _percentile(resolvers, 0.99)
	gut.p("M3 dogfight, %d ticks: ai.think_us median %d p99 %d worst %d; hit + ram resolve median %d p99 %d worst %d" % [think.size(),
			_percentile(think, 0.5), _percentile(think, 0.99), _percentile(think, 1.0), _percentile(resolvers, 0.5), resolve_p99, _percentile(resolvers, 1.0)])
	assert_lt(resolve_p99, RESOLVER_BUDGET_US, "AC13: the hit and ram resolvers stay under 2 ms a tick")
