extends GutTest
## A capital's bays out of the sun's light in the real main scene (M10-T72, Q68), on T05's test cruiser: its hall's faces drawn
## on the interior layer under the hull's mesh, the halls' trigger volume flying and turning with the ship, a fighter in a hall
## lit as the hall is and back out as it leaves, and a bay's lamp lighting the interior layer alone.

const TYPE: StringName = &"capital_test_cruiser"
const AHEAD := Vector3(0.0, 0.0, -2500.0)

var main: Main


func before_each() -> void:
	get_tree().paused = false
	main = (load("res://src/game/main.tscn") as PackedScene).instantiate() as Main
	main.input_source = FakeInputSource.new()
	main.scenario_path = ScenarioLoader.FREE_FLIGHT_PATH
	main.scenario_seed = 3
	add_child_autofree(main)
	await wait_physics_frames(2)
	DebugConsole.flags.invulnerable = true


func after_each() -> void:
	DebugConsole.flags.invulnerable = false


func _spawn(basis: Basis = Basis.IDENTITY) -> CapitalShip:
	var rest: Vector3 = main.world.rest_velocity()
	var cap: CapitalShip = CapitalShip.create(TYPE, Factions.EARTH_ALLIANCE, "TEST CRUISER", rest)
	assert_not_null(cap, "the test cruiser is generated (scripts/gen_assets.sh)")
	main.world.spawn(cap, main.world.to_universe(main.ship.global_position + AHEAD), basis)
	cap.set_course(-basis.z, rest)
	return cap


func _bay(cap: CapitalShip) -> Dictionary:
	for bay: Dictionary in cap.hardpoints().get("bays", []):
		if str(bay.get("kind", "")) == "bay":
			return bay
	return {}


func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func test_the_halls_faces_are_drawn_on_the_interior_layer_with_the_hulls_materials() -> void:
	var cap: CapitalShip = _spawn()
	if cap == null:
		return
	var node: MeshInstance3D = cap.hull_piece.interior_node(RenderPiece.WHOLE)
	assert_not_null(node, "the hall has its own mesh")
	assert_not_null(node.mesh)
	assert_eq(node.layers, LightRig.INTERIOR_LAYER, "the sun's light leaves it out")
	assert_eq(node.get_parent().name, "HullMesh", "it moves with the hull")
	assert_eq(node.mesh.surface_get_material(0), cap.drawn_mesh().surface_get_material(0), "the hull's own paint and texture set")
	assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_the_halls_volume_flies_and_turns_with_the_ship() -> void:
	var turned := Basis(Vector3.UP, 0.5 * PI)
	var cap: CapitalShip = _spawn(turned)
	if cap == null:
		return
	assert_not_null(cap.bay_zones, "a hull with a bay has its halls' volume")
	assert_eq(cap.bay_zones.get_parent(), cap, "a child of the ship")
	var area: Area3D = cap.bay_zones.area(InteriorZones.BAYS)
	var shape: CollisionShape3D = area.get_child(0) as CollisionShape3D
	var bay: Dictionary = _bay(cap)
	var volume: Dictionary = InteriorZones.bay_volumes(cap.hardpoints())[0]
	assert_almost_eq(shape.global_position, cap.global_transform * (volume["centre"] as Vector3), Vector3.ONE * 1e-3, "in the hall")
	assert_almost_eq(shape.global_basis.z.dot(-(cap.global_basis * _vec(bay["forward"]))), 1.0, 1e-4, "turned with the hull")
	assert_null(cap.bay_lamps, "the test cruiser's bay is unlit")


func test_a_fighter_in_a_hall_is_lit_as_the_hall_and_comes_back_out() -> void:
	var cap: CapitalShip = _spawn(Basis(Vector3.UP, 0.3 * PI))
	if cap == null:
		return
	await wait_physics_frames(2)
	var bay: Dictionary = _bay(cap)
	var start: Vector3 = cap.global_transform * _vec(bay["position"])
	var ship: Ship = main.ship
	ship.global_transform = Transform3D(cap.global_basis, start)
	ship.linear_velocity = cap.linear_velocity
	await wait_physics_frames(4)
	assert_true(InteriorLight.is_inside(ship), "in the hall, out of the sun's light")
	assert_eq(int(cap.bay_zones.inside[InteriorZones.BAYS]), 1)
	assert_eq((cap.hull_piece.get_node(^"HullMesh") as MeshInstance3D).layers & 1, 1, "the hull itself stays in the sun")
	ship.global_position = start + cap.global_basis * _vec(bay["forward"]) * 400.0
	await wait_physics_frames(4)
	assert_false(InteriorLight.is_inside(ship), "back in the sun outside")
	assert_eq(int(cap.bay_zones.inside[InteriorZones.BAYS]), 0)


func test_a_bays_lamp_lights_the_interior_layer_alone() -> void:
	var rig: LightRig = LightRig.of(main)
	var camera: Vector3 = get_viewport().get_camera_3d().global_position
	var hall := LightEmitter.new("hall", LightEmitter.PRIORITY_PLAYER_OWN, Color.RED, 3.0, 50.0)
	hall.position = camera + Vector3(0.0, 0.0, -5.0)
	hall.interior_only = true
	var open := LightEmitter.new("open", LightEmitter.PRIORITY_PLAYER_OWN, Color.WHITE, 3.0, 50.0)
	open.position = camera + Vector3(0.0, 0.0, -6.0)
	rig.add_emitter(hall)
	rig.add_emitter(open)
	rig.update(camera)
	var masks: Dictionary = {}
	for k: int in LightPicker.SLOT_COUNT:
		if rig.picked()[k] != null:
			masks[rig.picked()[k].label] = rig.slots()[k + 1].light_cull_mask
	assert_eq(masks.get("hall"), LightRig.INTERIOR_LAYER, "a hall's lamp never shows through the hull")
	assert_eq(masks.get("open"), LightRig.SLOT_CULL_MASK, "any other light lights both layers")
	rig.remove_emitter(hall)
	rig.remove_emitter(open)
