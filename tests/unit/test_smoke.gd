extends GutTest
## Proves the GUT runner path works end to end (headless, -gexit, exit code).


func test_runner_works() -> void:
	assert_true(true, "GUT runs")


func test_newtonian_project_settings() -> void:
	# The damping/gravity guard from architecture §5.4: any non-zero default silently bleeds momentum.
	assert_eq(ProjectSettings.get_setting("physics/3d/physics_engine"), "Jolt Physics")
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_gravity")), 0.0)
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_linear_damp")), 0.0)
	assert_eq(float(ProjectSettings.get_setting("physics/3d/default_angular_damp")), 0.0)
