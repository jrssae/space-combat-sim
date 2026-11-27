extends GutTest
## RenderDriverReport (M9-T08): the start-up line and the warning when the driver in use is not the configured one.


func test_the_line_names_the_method_and_the_driver() -> void:
	assert_eq(RenderDriverReport.line("forward_plus", "vulkan"), "RenderStatus: rendering method forward_plus, driver vulkan")


func test_the_configured_driver_in_use_gives_no_warning() -> void:
	assert_eq(RenderDriverReport.warning("vulkan", "vulkan"), "")
	assert_eq(RenderDriverReport.warning("d3d12", "d3d12"), "")


func test_the_fallback_driver_warns_naming_both() -> void:
	var text: String = RenderDriverReport.warning("vulkan", "d3d12")
	assert_string_contains(text, "vulkan")
	assert_string_contains(text, "d3d12")


func test_nothing_drawn_or_nothing_configured_gives_no_warning() -> void:
	assert_eq(RenderDriverReport.warning("vulkan", "headless"), "", "headless draws nothing")
	assert_eq(RenderDriverReport.warning("vulkan", ""), "", "no driver reported")
	assert_eq(RenderDriverReport.warning("", "d3d12"), "", "no driver configured")


func test_the_setting_key_follows_the_os() -> void:
	assert_eq(RenderDriverReport.setting_key("Windows"), "rendering/rendering_device/driver.windows")
	assert_eq(RenderDriverReport.setting_key("Linux"), "rendering/rendering_device/driver.linuxbsd")
	assert_eq(RenderDriverReport.setting_key("Web"), "")


func test_the_project_asks_for_vulkan_with_the_d3d12_fallback_on_windows() -> void:
	assert_eq(String(ProjectSettings.get_setting("rendering/rendering_device/driver.windows", "")), "vulkan")
	assert_true(bool(ProjectSettings.get_setting("rendering/rendering_device/fallback_to_d3d12", false)))


func test_the_render_provider_reports_the_driver() -> void:
	# GUT runs headless, so nothing is drawn.
	assert_eq(String(RenderStatus.driver()), "headless")
	assert_ne(RenderStatus.configured_driver(), "", "Linux and Windows configure one")
