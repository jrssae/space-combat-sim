extends GutTest
## Destructible nav buoys: any bolt hurts one, at zero hull it blows up (explosion and shards) and leaves play hidden but not
## freed, nothing targets it afterwards, and the player's respawn brings it back.

var main: Main
var source: FakeInputSource


func before_each() -> void:
	get_tree().paused = false
	DebugConsole.flags.invulnerable = true
	source = FakeInputSource.new()
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = source
	main.waves_auto_start = false
	add_child_autofree(main)
	await _ticks(2)


func after_each() -> void:
	DebugConsole.flags.invulnerable = false
	get_tree().paused = false


func _ticks(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


# Puts the first buoy on the line of the first gun, 200 m ahead, standing still.
func _buoy_in_the_sights() -> NavBuoy:
	var buoy: NavBuoy = main.buoys[0]
	buoy.velocity = Vector3.ZERO
	var muzzle: Node3D = main.ship.get_muzzles()[0]
	buoy.global_position = muzzle.global_position + main.ship.forward() * 200.0
	return buoy


func test_a_buoy_has_a_hull_and_is_hit_by_anyones_bolts() -> void:
	var buoy: NavBuoy = main.buoys[0]
	assert_not_null(buoy.damageable)
	assert_eq(buoy.damageable.hull.max_hp, NavBuoy.HULL_MAX)
	assert_true(buoy.damageable.can_be_hit_by(Factions.EARTH_ALLIANCE))
	assert_true(buoy.damageable.can_be_hit_by(Factions.RAIDERS))
	assert_false(buoy.damageable.can_be_hit_by(Factions.NEUTRAL), "its own faction passes through")
	assert_gt(buoy.damageable.shapes.size(), 0, "hit volumes come from its hardpoints")


func test_shooting_a_buoy_destroys_it_with_effects_and_takes_it_out_of_play() -> void:
	var buoy: NavBuoy = _buoy_in_the_sights()
	var destroyed: Array[bool] = [false]
	main.director.buoy_destroyed.connect(func(_b: NavBuoy, _i: HitInfo) -> void: destroyed[0] = true)
	var effects_before: int = main.effects.get_child_count()
	assert_true(main.ship.targeting.select_by_name(buoy.display_name), "targetable before")
	source.hold(InputAdapter.FIRE)
	var low_point: float = 1.0
	for i: int in 600:
		await _ticks(1)
		low_point = minf(low_point, buoy.damageable.hull.fraction())
		if destroyed[0]:
			break
	source.release(InputAdapter.FIRE)
	assert_lt(low_point, 1.0, "it took damage on the way")
	assert_true(destroyed[0], "destroyed")
	assert_true(buoy.is_destroyed())
	assert_false(buoy.visible, "hidden")
	assert_true(buoy.is_inside_tree(), "but never freed: no splat node leaves the tree during play")
	await _ticks(2)
	assert_gt(main.effects.get_child_count(), effects_before, "an explosion appeared")
	assert_false(buoy.targetable.is_active(), "nothing can target it any more")
	assert_false(buoy.damageable.is_active(), "or hit it")


func test_the_players_respawn_restores_the_buoys() -> void:
	var buoy: NavBuoy = main.buoys[0]
	buoy.damageable.kill()
	assert_true(buoy.is_destroyed())
	main.respawn()
	assert_false(buoy.is_destroyed())
	assert_true(buoy.visible)
	assert_eq(buoy.damageable.hull.fraction(), 1.0)
	await _ticks(2)
	assert_true(buoy.targetable.is_active(), "targetable again")
