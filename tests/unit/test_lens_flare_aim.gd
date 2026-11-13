extends GutTest
## `LensFlareAim`: where the star is on screen and whether the camera faces it, in the terms the lens flare effect
## expects (the add-on's convention: a point just in front of the camera, along the direction to the star).

var camera: Camera3D


func before_each() -> void:
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.current = true


func test_facing_is_one_looking_at_the_star_and_minus_one_looking_away() -> void:
	var to_sun := Vector3(0.0, 0.0, -1.0)
	assert_almost_eq(LensFlareAim.facing(Vector3(0.0, 0.0, -1.0), to_sun), 1.0, 0.0001)
	assert_almost_eq(LensFlareAim.facing(Vector3(0.0, 0.0, 1.0), to_sun), -1.0, 0.0001)
	assert_almost_eq(LensFlareAim.facing(Vector3(1.0, 0.0, 0.0), to_sun), 0.0, 0.0001, "side on")


func test_facing_ignores_vector_lengths() -> void:
	assert_almost_eq(LensFlareAim.facing(Vector3(0.0, 0.0, -5.0), Vector3(0.0, 0.0, -0.1)), 1.0, 0.0001)


func test_the_probe_point_is_at_least_one_metre_out_along_the_star_direction() -> void:
	var p: Vector3 = LensFlareAim.probe_point(Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, 2.0), 0.05)
	assert_eq(p, Vector3(10.0, 0.0, 1.0), "near plane under 1 m: 1 m")
	p = LensFlareAim.probe_point(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), 4.0)
	assert_eq(p, Vector3(4.0, 0.0, 0.0), "near plane over 1 m: the near plane")


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
