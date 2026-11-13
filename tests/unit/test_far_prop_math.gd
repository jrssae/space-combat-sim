extends GutTest
## Far props' draw paths and hand-offs (M6-T15, D70, AC9), pure: the drawn size is continuous across the near-to-shrunk hand-off
## (exactly: the same angle) and across the mesh-to-dot one (the area covered on screen, within 0.5 % between frames beyond what
## the distance itself changes), the dot keeps M4's hysteresis, and every distance from 100 m to the broadcast range is drawn.
## The silhouette blends continuously between the table's directions (the gate's outline falls steeply toward its end-on view,
## and the blend keeps close to that slope). The real picture against these numbers is
## test_far_props_gpu.gd's.

const FAR_PLANE_M: float = 50000.0
## Pixels per radian of a 1080-line picture at the cockpit's 75 degrees, and of the 675-line capture window.
const K_1080: float = 703.74
const K_675: float = 439.84
## Between two frames, the covered area may change by what the distance's change explains and this much more.
const COVER_TOLERANCE: float = 0.005

var gate: FarPropMath
var station: FarPropMath


func before_all() -> void:
	gate = FarPropMath.from_section(MeshAssets.read_manifest(Jumpgate.ASSET_ID).get("far", {}))
	station = FarPropMath.from_section(MeshAssets.read_manifest(StationStandin.ASSET_ID).get("far", {}))


func test_both_assets_carry_their_silhouettes() -> void:
	assert_not_null(gate, "the jumpgate's manifest has its far section (generator v4)")
	assert_not_null(station, "the station's stand-in's manifest has its far section (generator v4)")
	assert_almost_eq(gate.radius_m, 1408.0, 5.0, "the gate's bounding radius from the middle of its box (T19 round 4: 1.55 wide)")
	assert_almost_eq(gate.centre.z, 605.0, 1.0, "half way down the arms")
	assert_almost_eq(station.radius_m, 4028.0, 5.0)
	assert_eq(gate.directions.size(), 3 + 3 * 4 * 8 + 128, "the axes, their rings and the spiral")
	assert_null(FarPropMath.from_section({}), "no section, no far prop")


func test_a_gate_seen_end_on_covers_a_fraction_of_its_side_view() -> void:
	var end_on: float = gate.area_toward(Vector3.FORWARD)
	var side: float = gate.area_toward(Vector3.RIGHT)
	assert_lt(end_on, side / 5.0, "four rails' ends against four rails and their fins")
	assert_almost_eq(end_on, gate.areas_m2[2], 1e-6, "the table's own value at its own direction")
	assert_almost_eq(gate.area_toward(Vector3.BACK), end_on, 1e-6, "the same from behind")
	assert_almost_eq(gate.area_toward(Vector3(-1.0, 0.5, 0.2)), gate.area_toward(Vector3(1.0, -0.5, -0.2)), 1e-6)


func test_the_silhouette_changes_smoothly_with_the_view() -> void:
	# Round a great circle through the gate's axis and its side, and one through the station's length, in 0.25 degree steps:
	# the gate's own outline grows 19 % in the first quarter degree off its end-on view (measured on the mesh), so no step may
	# go much past that.
	for model: FarPropMath in [gate, station]:
		for axis: Vector3 in [Vector3.UP, Vector3(1.0, 1.0, 0.3).normalized()]:
			var start: Vector3 = Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT
			var worst: float = _worst_step(model, start, axis, 0.25, 360.0)
			assert_lt(worst, 0.3, "no step in the area over a quarter degree of view (worst %.4f)" % worst)
	# And it is continuous: a hundredth of a degree changes it by a hundredth as much, even at the end-on dip.
	var fine: float = _worst_step(gate, Vector3.FORWARD, Vector3.UP, 0.01, 12.0)
	assert_lt(fine, 0.015, "no jump anywhere near the gate's end-on view (worst %.4f per 0.01 degree)" % fine)


func _worst_step(model: FarPropMath, start: Vector3, axis: Vector3, step_deg: float, span_deg: float) -> float:
	var last: float = model.area_toward(start)
	var worst: float = 0.0
	for step: int in range(1, int(span_deg / step_deg) + 1):
		var a: float = model.area_toward(start.rotated(axis, deg_to_rad(step * step_deg)))
		worst = maxf(worst, absf(a - last) / maxf(a, last))
		last = a
	return worst


func test_the_shrunk_prop_covers_the_same_angle_and_stays_inside_the_far_plane() -> void:
	for model: FarPropMath in [gate, station]:
		var pull: float = model.pull_m(FAR_PLANE_M)
		assert_between(pull, 40000.0, FAR_PLANE_M, "drawn where it is out to about the far plane")
		var d: float = pull * 0.9
		while d < pull * 1.1:
			var s: float = FarPropMath.shrink(d, pull)
			var drawn_angle: float = asin((model.radius_m * s) / (d * s))
			assert_almost_eq(drawn_angle, asin(model.radius_m / d), 1e-9, "the same angle at %.0f m" % d)
			assert_lte(d * s + model.radius_m * s, FAR_PLANE_M - FarPropMath.PULL_MARGIN_M + 1.0, "its far side inside the far plane")
			if d <= pull:
				assert_eq(s, 1.0, "drawn where it is inside %.0f m" % pull)
			d += 10.0
		assert_almost_eq(FarPropMath.shrink(1.0e6, pull), pull / 1.0e6, 1e-12)


func test_the_dot_takes_over_at_its_pixel_size_and_hands_back_a_tenth_inside() -> void:
	var out_at: float = gate.dot_distance_m(K_1080)
	assert_almost_eq(gate.bounding_px(out_at, K_1080), FarPropMath.DOT_PX, 0.01, "%.2f px bounding radius" % FarPropMath.DOT_PX)
	assert_between(out_at, 220000.0, 280000.0, "a 1080-line cockpit view: the gate turns into a dot about 248 km out")
	assert_between(station.dot_distance_m(K_1080), 650000.0, 750000.0, "the station about 709 km out")
	var dot: bool = false
	var switched_out: float = 0.0
	var d: float = out_at * 0.8
	while d < out_at * 1.2:
		var was: bool = dot
		dot = gate.is_dot(d, dot, K_1080)
		if dot and not was:
			switched_out = d
		d *= 1.001
	assert_almost_eq(switched_out, out_at, out_at * 0.002, "the dot takes over at the dot distance going out")
	var switched_in: float = 0.0
	while d > out_at * 0.7:
		var was_dot: bool = dot
		dot = gate.is_dot(d, dot, K_1080)
		if was_dot and not dot:
			switched_in = d
		d /= 1.001
	assert_almost_eq(switched_in, out_at * LodSwitcherMath.FAR_RETURN, out_at * 0.002, "the mesh comes back a tenth inside")
	# Jitter on the line never flaps it.
	var flips: int = 0
	dot = true
	for i: int in 200:
		var was2: bool = dot
		dot = gate.is_dot(out_at * (0.99 if i % 2 == 0 else 1.01), dot, K_1080)
		flips += 1 if dot != was2 else 0
	assert_eq(flips, 0, "1 % either side of the line keeps the dot")


func test_mesh_and_dot_cover_the_same_area_from_every_side() -> void:
	var d: float = gate.dot_distance_m(K_1080)
	for i: int in gate.directions.size():
		var to_eye: Vector3 = gate.directions[i]
		var mesh: float = gate.cover_px2(to_eye, d, 0.0, K_1080)
		var dot: float = gate.cover_px2(to_eye, d, 1.0, K_1080)
		assert_almost_eq(dot, mesh, mesh * 1e-6, "direction %d: %.3f px2" % [i, mesh])
	# Under the 1 px floor the dot keeps its floor and dims by the square: what it covers follows the same law.
	var tiny: float = FarPropMath.dot_cover_px2(FarPropMath.dot_radius_m(gate.area_toward(Vector3.FORWARD)), 1.0e6, K_675)
	var r_px: float = FarPropMath.dot_radius_m(gate.area_toward(Vector3.FORWARD)) * K_675 / 1.0e6
	assert_lt(r_px, 1.0, "end on at 1 000 km the dot is under a pixel")
	assert_almost_eq(tiny, 0.5 * PI * 1.0 * (r_px * r_px), 1e-9, "a 1 px dot dimmed by the square covers what the law says")


func test_flying_out_and_back_through_both_hand_offs_never_pops() -> void:
	# 60 frames a second, out from 100 m past the dot distance at 2 % of the distance a frame, then back; from three sides.
	for model: FarPropMath in [gate, station]:
		for to_eye: Vector3 in [Vector3.FORWARD, Vector3(1.0, 0.3, -0.6), Vector3.UP]:
			var far: float = maxf(model.dot_distance_m(K_675) * 1.5, 1.0e6)
			var fade: float = 0.0
			var dot: bool = false
			var d: float = 100.0
			var last_cover: float = model.cover_px2(to_eye, d, fade, K_675)
			var last_d: float = d
			var worst: float = 0.0
			for leg: int in 2:
				while (leg == 0 and d < far) or (leg == 1 and d > 100.0):
					d = d * 1.02 if leg == 0 else d / 1.02
					dot = model.is_dot(d, dot, K_675)
					fade = FarPropMath.step_fade(fade, dot, 1.0 / 60.0)
					var cover: float = model.cover_px2(to_eye, d, fade, K_675)
					# What the distance alone explains: the area falls with its square.
					var expected: float = last_cover * (last_d / d) * (last_d / d)
					worst = maxf(worst, absf(cover - expected) / maxf(expected, 1e-12))
					last_cover = cover
					last_d = d
			assert_lt(worst, COVER_TOLERANCE, "no jump in the area covered (worst %.5f)" % worst)
			assert_false(dot, "back near, the mesh")


func test_every_distance_from_100_m_to_the_range_is_drawn() -> void:
	for model: FarPropMath in [gate, station]:
		var pull: float = model.pull_m(FAR_PLANE_M)
		var d: float = 100.0
		var dot: bool = false
		while d <= 1.0e6:
			dot = model.is_dot(d, dot, K_675)
			var s: float = FarPropMath.shrink(d, pull)
			if not dot:
				assert_lte((d + model.radius_m) * s, FAR_PLANE_M, "the mesh lies inside the far plane at %.0f m" % d)
			assert_gt(model.cover_px2(Vector3.FORWARD, d, 1.0 if dot else 0.0, K_675), 0.0, "something drawn at %.0f m" % d)
			d *= 1.05


func test_the_dot_is_lit_as_a_sphere_would_be() -> void:
	assert_almost_eq(FarPropMath.lit_share(0.0, 1.0, 0.1), 1.0, 1e-6, "full sun behind the eye: all lit")
	assert_almost_eq(FarPropMath.lit_share(PI, 1.0, 0.1), 0.1, 1e-6, "seen from its night side: the ambient")
	assert_almost_eq(FarPropMath.lit_share(PI / 2.0, 1.0, 0.0), 1.0 / PI, 1e-6, "half lit: a Lambert sphere's 1/pi")
	assert_almost_eq(FarPropMath.lit_share(0.0, 0.0, 0.1), 0.1, 1e-6, "in the planet's shadow: the ambient")
	var last: float = 2.0
	for i: int in 19:
		var share: float = FarPropMath.lit_share(PI * i / 18.0, 1.0, 0.05)
		assert_lt(share, last + 1e-9, "darker as the sun goes round behind it")
		last = share


func test_pixels_per_radian() -> void:
	assert_almost_eq(FarPropMath.px_per_rad(1080.0, 75.0), K_1080, 0.1)
	assert_almost_eq(FarPropMath.px_per_rad(675.0, 75.0), K_675, 0.1)
	var fade: float = 0.0
	for i: int in 22:
		fade = FarPropMath.step_fade(fade, true, 1.0 / 60.0)
	assert_eq(fade, 1.0, "the cross-fade takes %.2f s" % FarPropMath.FADE_S)


func test_a_far_hull_keeps_its_light_past_quarter_phase_and_glints_against_the_sun() -> void:
	assert_almost_eq(FarPropMath.hull_phase(0.0), 1.0, 1e-6, "full phase")
	assert_almost_eq(FarPropMath.hull_phase(deg_to_rad(60.0)), 0.89, 0.03, "measured 0.88 of full phase")
	assert_almost_eq(FarPropMath.hull_phase(deg_to_rad(110.0)), 0.70, 0.03, "measured 0.71")
	assert_almost_eq(FarPropMath.hull_phase(deg_to_rad(160.0)), 5.6, 0.3, "measured 5.8: the sheen on the rims")
	var last: float = FarPropMath.hull_phase(0.0)
	var worst: float = 0.0
	for i: int in range(1, 181):
		var h: float = FarPropMath.hull_phase(deg_to_rad(i))
		worst = maxf(worst, absf(h - last))
		last = h
	assert_lt(worst, 0.5, "no step over a degree of phase (worst %.3f)" % worst)
