extends GutTest
## The project's Newtonian physics settings (architecture §5.4), read without a scene: the quick tier's damping check. The
## damping guard itself (`test_ship_physics`: these settings, the ship's body and a measured coast in Jolt) runs in the
## standard tier; M6-T18 turned `test_smoke` into this file.


func test_newtonian_project_settings() -> void:
	# Any non-zero default silently bleeds momentum.
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.0)
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_linear_damp")), 0.0)
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_angular_damp")), 0.0)
