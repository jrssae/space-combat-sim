extends GutTest
## A capital's bays out of the sun's light (M10-T72, Q68): the trigger volume of its halls, read from its `bays` hardpoints, and
## the lamps of its open bays, which light the interior layer alone.

const HARDPOINTS: Dictionary = {
	"bays": [
		{"name": "bay_fore", "kind": "bay", "position": [0.0, -1.0, -400.0], "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0],
				"exit": [0.0, -1.0, -470.0], "mouth_m": [62.0, 24.0], "depth_m": 140.0},
		{"name": "bay_side_r", "kind": "bay", "position": [8.0, 40.0, 70.0], "forward": [1.0, 0.0, 0.0], "up": [0.0, 1.0, 0.0],
				"exit": [16.0, 40.0, 70.0], "mouth_m": [22.0, 12.0], "depth_m": 16.0},
		{"name": "tube_r", "kind": "tube", "position": [20.0, -5.0, 60.0], "forward": [0.0, 0.0, -1.0], "up": [0.0, 1.0, 0.0],
				"exit": [20.0, -5.0, 50.0], "radius_m": 1.5, "length_m": 12.0},
	],
	"doors": [{"name": "bay_side_r_door", "position": [16.3, 40.0, 70.0], "forward": [1.0, 0.0, 0.0], "up": [0.0, 1.0, 0.0],
			"size_m": [22.4, 12.1, 0.2], "slats": 13}],
	"lights": [
		{"name": "bay_fore_light", "role": "bay", "position": [0.0, 3.0, -400.0], "colour": [0.75, 0.02, 0.01], "range_m": 172.0},
		{"name": "bay_side_r_light", "role": "bay", "position": [8.0, 40.0, 70.0], "colour": [0.75, 0.02, 0.01], "range_m": 68.0},
	],
}


func test_each_bays_hall_is_a_box_from_inside_its_mouth_to_its_back_wall() -> void:
	var volumes: Array[Dictionary] = InteriorZones.bay_volumes(HARDPOINTS)
	assert_eq(volumes.size(), 2, "the bays, not the tube")
	var fore: Dictionary = volumes[0]
	assert_eq(fore["name"], "bay_fore")
	assert_eq(fore["size"], Vector3(62.0, 24.0, 140.0 - InteriorZones.MOUTH_INSET_M))
	var basis: Basis = fore["basis"]
	assert_almost_eq(basis.determinant(), 1.0, 1e-5, "a turn, not a mirror")
	assert_almost_eq(basis.z.dot(Vector3.BACK), 1.0, 1e-5, "its depth runs into the hall, away from the mouth")
	var centre: Vector3 = fore["centre"]
	var mouth_z: float = -470.0
	assert_almost_eq(centre.z - 0.5 * (140.0 - InteriorZones.MOUTH_INSET_M), mouth_z + InteriorZones.MOUTH_INSET_M, 1e-3, "starts inside")
	assert_almost_eq(centre.z + 0.5 * (140.0 - InteriorZones.MOUTH_INSET_M), mouth_z + 140.0, 1e-3, "ends at the back wall")
	assert_almost_eq(centre.y, -1.0 + 4.0, 1e-4, "the hall's middle, a sixth of its height over the craft's start")
	var side: Dictionary = volumes[1]
	assert_eq((side["size"] as Vector3).z, 8.0, "a short hall's volume is its back half")
	assert_almost_eq((side["basis"] as Basis).z.dot(Vector3.LEFT), 1.0, 1e-5, "turned with its bay")
	assert_eq(InteriorZones.bay_volumes({}).size(), 0)
	assert_null(InteriorZones.for_bays({}), "a hull without bays has no zone")


func test_the_halls_are_one_trigger_volume_that_ignores_capitals() -> void:
	var zones: InteriorZones = InteriorZones.for_bays(HARDPOINTS)
	add_child_autofree(zones)
	var area: Area3D = zones.area(InteriorZones.BAYS)
	assert_not_null(area)
	assert_eq(area.get_child_count(), 2, "a shape per hall")
	assert_eq(area.collision_layer, 0)
	assert_eq(area.collision_mask, CollisionLayers.PLAYER | CollisionLayers.FIGHTER, "not its own hull, nor another capital's")
	assert_eq(zones.inside[InteriorZones.BAYS], 0)


func test_only_an_open_bay_gets_a_lamp_and_it_lights_the_interior_alone() -> void:
	var ship := Node3D.new()
	add_child_autofree(ship)
	var lamps: CapitalBayLamps = CapitalBayLamps.make(ship, HARDPOINTS)
	assert_not_null(lamps)
	assert_eq(lamps.emitters.size(), 1, "the doored bay lights its hall as its door opens")
	var lamp: LightEmitter = lamps.emitters[0]
	assert_eq(lamp.label, "bay_fore_light")
	assert_true(lamp.interior_only, "it never shows through the hull's walls")
	assert_eq(lamp.anchor, ship)
	assert_eq(lamp.offset, Vector3(0.0, 3.0, -400.0))
	assert_eq(lamp.omni_range, 172.0)
	assert_eq(lamp.energy, BayDoors.LIGHT_ENERGY)
	lamps.set_level(0.25)
	assert_almost_eq(lamp.energy, 0.25 * BayDoors.LIGHT_ENERGY, 1e-6, "dimmed with a disabled ship's glow")
	lamps.free()
	assert_null(CapitalBayLamps.make(ship, {"bays": HARDPOINTS["bays"], "lights": []}), "no light, no lamp")
