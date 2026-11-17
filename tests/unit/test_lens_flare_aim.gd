extends GutTest
## `LensFlareAim`: where the star is on screen and whether the camera faces it, in the terms the lens flare effect
## expects, from the camera's turn alone so that it holds however far from the origin the camera is (M7-T72).

var camera: Camera3D


func before_each() -> void:
	camera = Camera3D.new()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autofree(camera)
	camera.current = true


func test_facing_is_one_looking_at_the_star_and_minus_one_looking_away() -> void:
	var to_sun := Vector3(0.0, 0.0, -1.0)
	assert_almost_eq(LensFlareAim.facing(Vector3(0.0, 0.0, -1.0), to_sun), 1.0, 0.0001)
	assert_almost_eq(LensFlareAim.facing(Vector3(0.0, 0.0, 1.0), to_sun), -1.0, 0.0001)
	assert_almost_eq(LensFlareAim.facing(Vector3(1.0, 0.0, 0.0), to_sun), 0.0, 0.0001, "side on")


func test_facing_ignores_vector_lengths() -> void:
	assert_almost_eq(LensFlareAim.facing(Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, -0.1)), 1.0, 0.0001)


func test_a_camera_thousands_of_km_out_puts_the_star_where_one_at_the_origin_does() -> void:
	# M7-T72: `far view station 10000` holds the camera 10 000 km from the World's origin; a probe point a metre in front of
	# it was lost to float rounding and drew the flare's core 2.6 degrees off the star.
	var to_sun := Vector3(0.45, 0.2, -1.0).normalized()
	camera.global_basis = Basis.looking_at(Vector3(0.2, -0.1, -1.0), Vector3.UP)
	var at_origin: Vector2 = LensFlareAim.sun_uv(camera, to_sun)
	for km: float in [1000.0, 10_000.0, 27_000.0]:
		camera.global_position = FarPropHost.VIEW_BEARING.normalized() * km * 1000.0
		var uv: Vector2 = LensFlareAim.sun_uv(camera, to_sun)
		assert_almost_eq(uv, at_origin, Vector2.ONE * 1.0e-5, "%s km out" % km)
		var ray: Vector3 = camera.project_ray_normal(uv * camera.get_viewport().get_visible_rect().size)
		assert_lt(rad_to_deg(ray.angle_to(to_sun)), 0.01, "%s km out: the flare's core is on the star" % km)


func test_a_star_dead_ahead_projects_to_the_screen_centre() -> void:
	# A camera with no rotation looks down -Z; the star lies the same way.
	var uv: Vector2 = LensFlareAim.sun_uv(camera, Vector3(0.0, 0.0, -1.0))
	assert_almost_eq(uv.x, 0.5, 0.001)
	assert_almost_eq(uv.y, 0.5, 0.001)


func test_a_star_to_the_right_projects_right_of_centre_and_one_above_projects_above() -> void:
	var right: Vector2 = LensFlareAim.sun_uv(camera, Vector3(0.2, 0.0, -1.0).normalized())
	assert_gt(right.x, 0.5)
	assert_almost_eq(right.y, 0.5, 0.001)
	var above: Vector2 = LensFlareAim.sun_uv(camera, Vector3(0.0, 0.2, -1.0).normalized())
	assert_lt(above.y, 0.5, "screen y runs down")


func test_a_star_square_to_the_view_projects_off_screen_without_an_error() -> void:
	# M6-T09: the sun lies in the game's XZ plane, so a camera looking along -Z can have it exactly to its side.
	var uv: Vector2 = LensFlareAim.sun_uv(camera, Vector3(-1.0, 0.0, 0.0))
	assert_true(is_finite(uv.x) and is_finite(uv.y))
	assert_lt(uv.x, -1.0, "far off the left edge")
