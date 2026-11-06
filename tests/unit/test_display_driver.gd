extends GutTest
## The game asks for Godot's Wayland display driver on Linux (M4-T41): under GNOME's fractional scaling the X11 path made a
## fullscreen window larger than the panel, which the compositor then scaled down; Wayland gives the panel's own size.


func test_the_project_asks_for_the_wayland_driver_on_linux() -> void:
	assert_eq(String(ProjectSettings.get_setting("display/display_server/driver.linuxbsd", "")), "wayland",
		"project.godot sets display/display_server/driver.linuxbsd")


func test_the_render_provider_names_the_display_server() -> void:
	# GUT runs headless, so the display server is the headless one.
	assert_eq(String(RenderStatus.display_server()), "headless")


func test_the_render_provider_reports_the_window_size() -> void:
	var size: Vector2i = RenderStatus.window_size()
	assert_true(size.x >= 0 and size.y >= 0, "a size, zero when headless")
