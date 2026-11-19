extends GutTest
## CinematicKeyLight (M8-T29, shared with the launches): a key light on the sun's side of a shot's subject ship and a rim from
## behind, following the ship while the shots play, gone when they end; the strength is data.

var ship: Node3D


func before_each() -> void:
	ship = Node3D.new()
	add_child_autofree(ship)
	ship.global_position = Vector3(100.0, 0.0, 0.0)


func test_it_lights_the_ship_from_the_sun_and_goes_when_detached() -> void:
	var light := CinematicKeyLight.new()
	assert_false(light.is_attached())
	light.attach(ship, Vector3(0.0, 0.0, 1.0))
	assert_true(light.is_attached())
	assert_eq(light.subject(), ship)
	var key := ship.get_node_or_null(^"CinematicKey") as OmniLight3D
	var rim := ship.get_node_or_null(^"CinematicRim") as OmniLight3D
	assert_not_null(key)
	assert_not_null(rim, "the data turns the rim on")
	assert_gt(key.global_position.z - ship.global_position.z, 10.0, "the key sits toward the sun")
	assert_lt(rim.global_position.z - ship.global_position.z, -10.0, "the rim behind")
	assert_almost_eq(key.light_energy, float(CinematicKeyLight.load_settings()["key"]["energy"]), 1e-6, "the data's strength")
	ship.global_position = Vector3(500.0, 0.0, 0.0)
	light.update(Vector3(1.0, 0.0, 0.0))
	assert_gt(key.global_position.x, 510.0, "it follows the ship and the sun")
	light.detach()
	assert_false(light.is_attached())
	await get_tree().process_frame
	assert_null(ship.get_node_or_null(^"CinematicKey"), "gone with the shots")
	assert_null(ship.get_node_or_null(^"CinematicRim"))


func test_attaching_again_or_to_another_ship_keeps_one_pair_of_lights() -> void:
	var light := CinematicKeyLight.new({"key": {"energy": 2.0}, "rim": {"enabled": false}})
	light.attach(ship)
	light.attach(ship)
	assert_eq(ship.get_children().size(), 1, "one key, no rim when the data turns it off")
	var other := Node3D.new()
	add_child_autofree(other)
	light.attach(other)
	await get_tree().process_frame
	assert_eq(ship.get_children().size(), 0, "moved to the new subject")
	assert_eq(light.subject(), other)
	light.detach()
