extends GutTest
## `InteriorLight` and `InteriorZones.volumes` (M7): a ship inside a station's hall or bay is drawn on the interior layer, which
## the key star's light leaves out, and comes back out on the first layer.


func _ship() -> Node3D:
	var root := Node3D.new()
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	var pod := MeshInstance3D.new()
	pod.name = "Pod"
	pod.layers = 1 | 8  # a layer of its own beside the first
	hull.add_child(pod)
	var marker := MeshInstance3D.new()
	marker.name = "Marker"
	marker.layers = 16  # not on the first layer: left alone
	root.add_child(marker)
	add_child_autofree(root)
	return root


func test_the_first_layer_is_swapped_for_the_interior_one_and_back() -> void:
	assert_eq(InteriorLight.moved(1, true), LightRig.INTERIOR_LAYER)
	assert_eq(InteriorLight.moved(LightRig.INTERIOR_LAYER, false), 1)
	assert_eq(InteriorLight.moved(1 | 8, true), LightRig.INTERIOR_LAYER | 8, "its other layers stay")
	assert_eq(InteriorLight.moved(16, true), 16, "what is not on the first layer stays where it is")
	assert_eq(InteriorLight.moved(1, false), 1, "already outside")
	assert_eq(InteriorLight.moved(LightRig.INTERIOR_LAYER, true), LightRig.INTERIOR_LAYER, "already inside")


func test_every_mesh_of_a_ship_goes_in_and_comes_out() -> void:
	var ship: Node3D = _ship()
	assert_false(InteriorLight.is_inside(ship))
	InteriorLight.set_inside(ship, true)
	assert_true(InteriorLight.is_inside(ship))
	assert_eq((ship.get_node(^"Hull") as MeshInstance3D).layers, LightRig.INTERIOR_LAYER)
	assert_eq((ship.get_node(^"Hull/Pod") as MeshInstance3D).layers, LightRig.INTERIOR_LAYER | 8)
	assert_eq((ship.get_node(^"Marker") as MeshInstance3D).layers, 16)
	InteriorLight.set_inside(ship, true)
	assert_eq((ship.get_node(^"Hull") as MeshInstance3D).layers, LightRig.INTERIOR_LAYER, "twice is once")
	InteriorLight.set_inside(ship, false)
	assert_false(InteriorLight.is_inside(ship))
	assert_eq((ship.get_node(^"Hull") as MeshInstance3D).layers, 1)
	assert_eq((ship.get_node(^"Hull/Pod") as MeshInstance3D).layers, 1 | 8)


func test_the_bays_volumes_come_from_the_stations_hardpoints() -> void:
	var manifest: Dictionary = {"pieces": {"drum": {"pivot": [0.0, 0.0, -1000.0]}}, "hardpoints": {
		"main_docking_bay": {"main_docking_bay_mouth": [0.0, 0.0, -2550.0], "main_docking_bay_airlock": [0.0, 0.0, -2360.0],
				"main_docking_bay_clear_half_m": [47.0, 17.0]},
		"cargo_bay": {"cargo_bay_clear_min": [-32.0, 327.0, -3580.0], "cargo_bay_clear_max": [32.0, 355.0, -3512.0]}}}
	var volumes: Array[Dictionary] = InteriorZones.volumes(manifest)
	assert_eq(volumes.size(), 2)
	var tunnel: Dictionary = volumes[0]
	assert_eq(tunnel["name"], "main_docking_bay")
	assert_eq(tunnel["kind"], "cylinder")
	var from_z: float = (tunnel["centre"] as Vector3).z - 0.5 * float(tunnel["length"])
	assert_almost_eq(from_z, -3550.0 + InteriorZones.MOUTH_INSET_M, 1e-3, "it starts in past the mouth, in the asset's frame")
	assert_almost_eq(from_z + float(tunnel["length"]), -3360.0, 1e-3, "and ends at the airlock")
	assert_gt(float(tunnel["radius"]), 47.0, "the clear passage and room round it")
	var cargo: Dictionary = volumes[1]
	assert_eq(cargo["kind"], "box")
	assert_almost_eq((cargo["centre"] as Vector3).y, 341.0, 1e-3)
	assert_gt((cargo["size"] as Vector3).x, 64.0)
	assert_eq(InteriorZones.volumes({}).size(), 0, "a station without bays has no volumes")
	assert_null(InteriorZones.for_manifest({}))
