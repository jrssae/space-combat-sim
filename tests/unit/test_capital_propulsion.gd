extends GutTest
## A capital's drive as the flight step's nozzles (M10-T07, Q51): the engines become mains with stand-in retros at their places;
## a reaction hull keeps its spec, a gravitic one gets a fraction of its forward thrust backward and sideways; the broadcast
## range per class comes from the capitals' data.


func _engine(name: String, x: float) -> Dictionary:
	return {"name": name, "section": "engine", "position": [x, 0.0, 150.0], "thrust": [0.0, 0.0, -1.0],
			"exhaust": [0.0, 0.0, 1.0], "share": 0.25}


func _hardpoints(xs: Array[float]) -> Dictionary:
	var engines: Array = []
	for i: int in xs.size():
		engines.append(_engine("engine_%d" % i, xs[i]))
	return {"center_of_mass": [0.0, 1.0, 0.0], "engines": engines}


func _spec(propulsion: StringName, retro: float = 0.0, fraction: float = 0.0) -> ShipSpec:
	var spec := ShipSpec.new()
	spec.pod_main_thrust = 6.0e6
	spec.pod_retro_thrust = retro
	spec.rcs_force_max = Vector3(1.0e6, 1.0e6, 0.0)
	spec.propulsion = propulsion
	spec.gravitic_fraction = fraction
	return spec


func test_every_engine_is_a_main_with_a_stand_in_retro_at_its_place() -> void:
	var layout: ThrusterLayout = CapitalPropulsion.layout(_hardpoints([25.0, 25.0, -25.0, -25.0]))
	assert_true(layout.valid, layout.error)
	assert_eq(CapitalPropulsion.main_count(layout), 4)
	assert_eq(layout.nozzle_count(), 8, "four mains and four retros")
	assert_eq(layout.center_of_mass, Vector3(0.0, 1.0, 0.0), "about the hardpoints' centre of mass")
	for i: int in 4:
		assert_eq(layout.nozzle_positions[i + 4], layout.nozzle_positions[i], "each retro sits at its main")
		assert_eq(layout.nozzle_exhausts[i + 4], -layout.nozzle_exhausts[i], "pointing the other way")
	assert_almost_eq(layout.thrust_axis(ThrusterLayout.Group.R_MAIN).z, -2.0, 1e-6, "the mains push forward")
	assert_almost_eq(layout.thrust_axis(ThrusterLayout.Group.R_RETRO).z, 2.0, 1e-6, "the retros push aft")


func test_an_engine_on_the_centre_line_serves_both_sides() -> void:
	var layout: ThrusterLayout = CapitalPropulsion.layout(_hardpoints([0.0]))
	assert_true(layout.valid, layout.error)
	assert_eq(CapitalPropulsion.main_count(layout), 2, "listed right and left, so the step's two sides both have it")


func test_a_hull_with_no_engines_gives_no_layout() -> void:
	var layout: ThrusterLayout = CapitalPropulsion.layout({"center_of_mass": [0.0, 0.0, 0.0]})
	assert_false(layout.valid)
	assert_string_contains(layout.error, "engines")


func test_a_reaction_hull_flies_its_spec_as_it_is() -> void:
	var with_retros: ShipSpec = _spec(CapitalPropulsion.REACTION, 3.0e6)
	assert_same(CapitalPropulsion.flight_spec(with_retros, 4), with_retros)
	assert_true(CapitalPropulsion.has_retros(with_retros))
	assert_false(CapitalPropulsion.has_retros(_spec(CapitalPropulsion.REACTION, 0.0)), "no room for retros: it flips")
	assert_false(CapitalPropulsion.is_gravitic(with_retros))


func test_a_gravitic_hull_pushes_a_fraction_of_its_forward_thrust_along_every_other_axis() -> void:
	var spec: ShipSpec = _spec(CapitalPropulsion.GRAVITIC, 0.0, 0.4)
	var flown: ShipSpec = CapitalPropulsion.flight_spec(spec, 4)
	assert_ne(flown, spec, "a copy: the shared resource is untouched")
	assert_eq(spec.pod_retro_thrust, 0.0)
	assert_almost_eq(flown.pod_retro_thrust, 0.4 * 6.0e6, 1.0, "backward: the fraction of each main")
	assert_almost_eq(flown.rcs_force_max.x, 0.4 * 4.0 * 6.0e6, 1.0, "sideways: the fraction of the whole forward thrust")
	assert_almost_eq(flown.rcs_force_max.y, 0.4 * 4.0 * 6.0e6, 1.0)
	assert_true(CapitalPropulsion.has_retros(spec), "it never needs to flip")


func test_broadcast_range_by_class_from_the_data() -> void:
	CapitalData.reload()
	assert_almost_eq(CapitalData.broadcast_range_m(&"cruiser"), 2.0e5, 1e-3, "cruisers 200 km (Q51)")
	assert_almost_eq(CapitalData.broadcast_range_m(&"capital"), 5.0e5, 1e-3, "capitals 500 km")
	assert_almost_eq(CapitalData.broadcast_range_m(&"dreadnought"), 1.0e6, 1e-3, "dreadnoughts 1 000 km")
	assert_almost_eq(CapitalData.broadcast_range_m(&"destroyer"), 5.0e5, 1e-3, "a class the file does not name is a capital")
