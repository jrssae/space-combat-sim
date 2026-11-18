extends GutTest
## The jump vortex's data (M7-T23): `data/jump/vortex_look.json` is there, holds every timing and colour the code reads, and the
## code takes its values from it.

const TIMING_KEYS: Array[String] = ["flash_s", "grow_s", "close_s", "end_flash_s", "hold_s"]
const GATE_KEYS: Array[String] = ["lead_s", "chase_s", "lamp_rise_s", "lamp_pulse_s", "lamp_hold_level", "lamp_steady_level",
		"tip_pulses", "tip_pulse_depth", "lamp_glow_m", "tip_glow_m", "flash_peak", "flash_size", "flash_spread",
		"flash_bloom_from", "flash_halo", "flash_ring", "flare_level", "eye_share", "shallow"]
const POINT_KEYS: Array[String] = ["spark_rise_s", "spark_level", "flash_peak", "flash_size", "flash_spread", "flash_bloom_from",
		"flash_halo", "flash_ring", "flare_level", "ring_start", "eye_share", "shallow"]


func test_the_file_is_there_with_every_section() -> void:
	assert_true(FileAccess.file_exists(VortexLook.PATH))
	for name: String in ["timing", "gate", "point", "colours", "look"]:
		assert_false(VortexLook.section(name).is_empty(), "section %s" % name)
	for key: String in TIMING_KEYS:
		assert_gt(VortexLook.number("timing", key, -1.0), 0.0, "timing.%s" % key)
	for key: String in GATE_KEYS:
		assert_gt(VortexLook.number("gate", key, -1.0), 0.0, "gate.%s" % key)
	for key: String in POINT_KEYS:
		assert_gt(VortexLook.number("point", key, -1.0), 0.0, "point.%s" % key)
	assert_true(VortexLook.data().has("hyperspace_side"), "the amber side is recorded for M11, not built")


func test_both_directions_have_their_colours() -> void:
	var grey: Array = [Color.GRAY, Color.GRAY]
	for way: String in ["arrival", "departure"]:
		var pair: Array = VortexLook.funnel_colours(way, grey)
		assert_ne(pair[0], Color.GRAY, "%s colour" % way)
		assert_ne(pair[1], Color.GRAY, "%s highlight" % way)
		assert_gt(VortexLook.brightness(way, -1.0), 0.0)
	var arrival: Color = VortexLook.funnel_colours("arrival", grey)[0]
	var departure: Color = VortexLook.funnel_colours("departure", grey)[0]
	assert_gt(arrival.b, arrival.r, "blue coming out of hyperspace")
	assert_gt(departure.r, departure.b, "amber going in")


func test_the_code_takes_its_values_from_the_file() -> void:
	assert_eq(VortexTiming.FLASH_S, VortexLook.number("timing", "flash_s", -1.0))
	assert_eq(VortexTiming.GROW_S, VortexLook.number("timing", "grow_s", -1.0))
	assert_eq(VortexTiming.POINT_LEAD_S, VortexLook.number("point", "lead_s", -1.0))
	assert_eq(GateActivation.DURATION_S, VortexLook.number("gate", "lead_s", -1.0))
	assert_eq(GateActivation.CHASE_S, VortexLook.number("gate", "chase_s", -1.0))
	assert_eq(JumpVortex.DEFAULT_COLOURS[&"arrival"], VortexLook.funnel_colours("arrival", [Color.GRAY, Color.GRAY]))


func test_every_look_value_is_a_uniform_of_the_funnel() -> void:
	var names: Dictionary = {}
	for uniform: Dictionary in JumpVortex.FUNNEL_SHADER.get_shader_uniform_list():
		names[String(uniform["name"])] = true
	for key: String in VortexLook.section("look"):
		assert_true(names.has(key), "look.%s is a uniform of the funnel's shader" % key)


func test_a_point_and_a_gate_open_in_their_own_way() -> void:
	var point: JumpVortex = autofree(JumpVortex.create({}, true, false))
	var gate: JumpVortex = autofree(JumpVortex.create({}, false, false))
	assert_true(point.own_point)
	assert_false(gate.own_point)
	point.open(JumpVortex.Direction.ARRIVAL)
	assert_true(point.timing.spark, "a ship's own point starts as a star")
	assert_almost_eq(point.timing.lead_s, VortexTiming.POINT_LEAD_S, 1e-4)
	assert_eq(VortexLook.number("point", "lead_s", -1.0), 0.0, "and does not pause (the maintainer)")
	gate.open(JumpVortex.Direction.ARRIVAL, 4.0, GateActivation.DURATION_S)
	assert_false(gate.timing.spark)
	assert_gt(point.eye_share, gate.eye_share, "a point opens as a ring, a gate's as a disc")
	assert_lt(point.shallow, 1.0, "a point opens wide and shallow, then deepens")
	assert_gt(gate.flash_size, point.flash_size, "a gate's flash fills its centre")
	# The GIF's colours: a gate's glows and spark pink-red, a point's star blue-purple. No flash whites out the view (the maintainer).
	assert_gt(gate.centre_colour.r, gate.centre_colour.b)
	assert_gt(gate.centre_colour.b, gate.centre_colour.g)
	assert_gt(point.centre_colour.b, point.centre_colour.r)
	assert_gt(point.centre_colour.r, point.centre_colour.g)
	assert_eq(gate.flash_bloom, 0.0, "a round flash, no white-out")
	assert_eq(point.flash_bloom, 0.0)
	# Round flashes with a lens flare, no star rays (the maintainer).
	assert_eq(gate.flash_rays, 0.0)
	assert_eq(point.flash_rays, 0.0)
	assert_gt(gate.flare_level, 0.0)
	assert_gt(point.flare_level, 0.0)
	# A point's funnel springs out as a visible ring, and is at its full size, depth and eye once open.
	var from: Vector3 = Vector3(0.0, 0.0, -2000.0)
	point.advance(point.timing.lead_s + VortexTiming.FLASH_S + VortexTiming.GROW_S * 0.2)
	point.update_visuals_for(from, 0.0)
	assert_true(point.funnel.visible)
	var state: Vector4 = point.funnel.get_instance_shader_parameter(&"vortex_state")
	assert_gt(state.x, point.ring_start, "already a ring a good share of the mouth across")
	assert_lt(state.w, state.x * 0.75, "with a band of blue round its eye")
	assert_lt(point.funnel.scale.z, point.fit.depth_m * 0.7, "wide and shallow")
	point.advance(point.timing.open_at_s - point.age_s + 0.1)
	point.update_visuals_for(from, 0.0)
	state = point.funnel.get_instance_shader_parameter(&"vortex_state")
	assert_almost_eq(state.x, 1.0, 1e-4)
	assert_almost_eq(point.funnel.scale.z, point.fit.depth_m, 0.01)
