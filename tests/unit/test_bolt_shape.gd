extends GutTest
## M7-T52: the bolts' teardrop (`BoltShape`): a round head at the bolt's place, a tail tapering behind it along the flight and
## fading toward its tip, and a core brighter than the envelope round it, in the additive draw and the opaque one (TAA).

const LENGTH: float = 1.5
const RADIUS: float = 0.05

var mesh: ArrayMesh
var verts: PackedVector3Array
var colors: PackedColorArray
var forward: Vector3


func before_each() -> void:
	mesh = BoltShape.mesh(LENGTH, RADIUS)
	var arrays: Array = mesh.surface_get_arrays(0)
	verts = arrays[Mesh.ARRAY_VERTEX]
	colors = arrays[Mesh.ARRAY_COLOR]
	var bolts := BoltMesh.new(null)
	forward = bolts.flight_axis()
	bolts.free()


# How far ahead along the flight a vertex lies, and how far off the axis.
func _along(v: Vector3) -> float:
	return v.dot(forward)


func _off(v: Vector3) -> float:
	return (v - forward * _along(v)).length()


# The envelope's vertices: the first drop built (the core follows it).
func _envelope_count() -> int:
	return 1 + (BoltShape.HEAD_RINGS + BoltShape.TAIL_RINGS - 1) * BoltShape.SIDES + 1


func test_the_head_leads_along_the_flight_and_the_tail_trails_behind() -> void:
	var front: float = -INF
	var back: float = INF
	for v: Vector3 in verts:
		front = maxf(front, _along(v))
		back = minf(back, _along(v))
	var head: float = BoltShape.head_radius(RADIUS)
	assert_almost_eq(front, head, 1e-5, "the nose is one head radius ahead of the bolt's place")
	assert_almost_eq(back, head - BoltShape.total_length(LENGTH, RADIUS), 1e-5, "the tail tip trails behind")
	assert_lt(back, -2.0 * head, "the tail is longer than the head")


func test_the_head_is_wider_than_the_tail() -> void:
	var head: float = BoltShape.head_radius(RADIUS)
	var tail: float = BoltShape.total_length(LENGTH, RADIUS) - head
	var widest_head: float = 0.0
	var widest_back_half: float = 0.0
	for i: int in _envelope_count():
		var v: Vector3 = verts[i]
		if _along(v) >= -head:
			widest_head = maxf(widest_head, _off(v))
		elif _along(v) <= -0.5 * tail:
			widest_back_half = maxf(widest_back_half, _off(v))
	assert_almost_eq(widest_head, head, 1e-5)
	assert_lt(widest_back_half, 0.5 * head, "the tail narrows to a point")
	for k: int in 10:
		var y: float = -tail * float(k) / 10.0
		assert_gt(BoltShape.radius_at(y, head, tail), BoltShape.radius_at(y - 0.1 * tail, head, tail), "narrower further back")


func test_the_tail_is_darker_than_the_head() -> void:
	var head_glow: float = 0.0
	var tip_glow: float = 1.0
	var tip_along: float = INF
	for i: int in _envelope_count():
		if _along(verts[i]) >= 0.0:
			head_glow = maxf(head_glow, colors[i].r)
		if _along(verts[i]) < tip_along:
			tip_along = _along(verts[i])
			tip_glow = colors[i].r
	assert_gt(head_glow, 0.0)
	assert_almost_eq(tip_glow, 0.0, 1e-6, "the glow fades out at the tip")
	var tail: float = 1.0
	for k: int in 10:
		var y: float = -tail * float(k) / 10.0
		assert_gt(BoltShape.fade_at(y, tail), BoltShape.fade_at(y - 0.1, tail), "dimmer further back")


func test_the_core_is_brighter_than_the_envelope_in_both_draws() -> void:
	var envelope: Color = BoltShape.color_at(0.0, 1.0, false)
	var core: Color = BoltShape.color_at(0.0, 1.0, true)
	# Opaque (TAA): a pixel shows one wall, the core's inside the envelope.
	assert_gt(core.r, envelope.r, "opaque: the core outshines the envelope")
	# Additive: the envelope plus the core weighted by its alpha, the same as the opaque core.
	assert_almost_eq(envelope.r + core.r * core.a, core.r, 1e-6, "additive and opaque cores alike")
	assert_almost_eq(core.r * BoltShape.PEAK, BoltShape.PEAK, 1e-6, "the head at the full peak")
	assert_almost_eq(envelope.r * BoltShape.PEAK, BoltShape.ENVELOPE_BRIGHTNESS, 1e-6)
	for k: int in 20:
		var y: float = -float(k) / 20.0
		var e: Color = BoltShape.color_at(y, 1.0, false)
		var c: Color = BoltShape.color_at(y, 1.0, true)
		assert_gte(c.r, e.r, "never darker than the envelope round it, at %.2f" % y)
		assert_almost_eq(e.r + c.r * c.a, c.r, 1e-5, "both draws alike at %.2f" % y)


func test_the_core_sits_inside_the_envelope() -> void:
	var head: float = BoltShape.head_radius(RADIUS)
	var tail: float = BoltShape.total_length(LENGTH, RADIUS) - head
	for i: int in range(_envelope_count(), verts.size()):
		var v: Vector3 = verts[i]
		var y: float = _along(v)
		assert_lte(_off(v), BoltShape.radius_at(y, head, tail) + 1e-5, "core vertex %d inside the envelope" % i)


func test_its_faces_point_outward() -> void:
	# The bolt materials cull front faces to draw the far walls; that needs outward front faces (Godot's wind clockwise).
	var arrays: Array = mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# The head's triangles (the nose's fan and the rings round it), whose outside is away from the head's centre at the origin.
	for t: int in range(0, 3 * BoltShape.SIDES * 4, 3):
		var a: Vector3 = verts[indices[t]]
		var b: Vector3 = verts[indices[t + 1]]
		var c: Vector3 = verts[indices[t + 2]]
		var centre: Vector3 = (a + b + c) / 3.0
		# Clockwise seen from outside: the counter-clockwise normal points inward.
		var ccw_normal: Vector3 = (b - a).cross(c - a)
		assert_lt(ccw_normal.dot(centre), 0.0, "triangle at index %d" % t)


func test_the_bolt_materials_draw_it_as_intended() -> void:
	var specs: Array[String] = ["res://assets/weapons/pulse_cannon_ef.tres", "res://assets/weapons/raider_plasma.tres",
			"res://assets/weapons/grid_light_pulse.tres", "res://assets/weapons/turret_light.tres",
			"res://assets/weapons/grid_interceptor.tres", "res://assets/weapons/grid_heavy_cannon.tres",
			"res://assets/weapons/turret_light_brakiri.tres"]
	for path: String in specs:
		var spec := load(path) as WeaponSpec
		var material := spec.bolt_material as StandardMaterial3D
		assert_not_null(material, "%s has its own bolt material" % path)
		if material == null:
			continue
		assert_true(material.vertex_color_use_as_albedo, "%s: the vertex colour carries the glow" % path)
		assert_eq(material.cull_mode, BaseMaterial3D.CULL_FRONT, "%s: the far walls, so the core shows" % path)
		assert_eq(material.depth_draw_mode, BaseMaterial3D.DEPTH_DRAW_ALWAYS, "%s: writes depth, so the blur leaves it sharp" % path)
		assert_eq(material.render_priority, Material.RENDER_PRIORITY_MAX, "%s: after the other see-through effects" % path)
		var peak := Color(material.emission.r * BoltShape.PEAK, material.emission.g * BoltShape.PEAK,
				material.emission.b * BoltShape.PEAK, 1.0)
		assert_true(material.albedo_color.is_equal_approx(peak), "%s: albedo is the bolt's colour at its peak" % path)


func test_the_station_light_guns_fire_orange_bolts_in_their_flash_colour() -> void:
	for path: String in ["res://assets/weapons/grid_light_pulse.tres", "res://assets/weapons/turret_light.tres"]:
		var spec := load(path) as WeaponSpec
		var material := spec.bolt_material as StandardMaterial3D
		assert_ne(material, Projectile.DEFAULT_MATERIAL, "%s: not the Starfury's blue" % path)
		assert_true(material.emission.is_equal_approx(spec.bolt_color), "%s: the impact flash's colour" % path)
		assert_gt(material.emission.r, material.emission.b, "%s: orange" % path)


func test_the_brakiri_turret_fires_bolts_in_its_own_green() -> void:
	# M7-T52 fix round: it had no bolt material and drew the Starfury's blue.
	var spec := load("res://assets/weapons/turret_light_brakiri.tres") as WeaponSpec
	var material := spec.bolt_material as StandardMaterial3D
	assert_not_null(material)
	if material == null:
		return
	assert_ne(material, Projectile.DEFAULT_MATERIAL, "not the Starfury's blue")
	assert_true(material.emission.is_equal_approx(spec.bolt_color), "the impact flash's colour")
	assert_gt(material.emission.g, maxf(material.emission.r, material.emission.b), "green")
