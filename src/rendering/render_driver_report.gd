class_name RenderDriverReport
extends RefCounted
## What the start-up log says about the graphics driver (M9-T08): one line naming the rendering method and the driver, and a
## warning when the driver in use is not the one project.godot asks for (Vulkan asked for, Direct3D 12 running: Godot's
## fallback on a Windows machine whose Vulkan driver fails). Pure functions; `RenderStatus` reads the engine and logs.

## The driver a platform's project setting names when project.godot does not set it.
const DEFAULT_DRIVER: String = "vulkan"


## The ProjectSettings key holding the configured driver for `os_name` (`OS.get_name()`), or "" for an OS the game does not
## configure.
static func setting_key(os_name: String) -> String:
	match os_name:
		"Windows":
			return "rendering/rendering_device/driver.windows"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return "rendering/rendering_device/driver.linuxbsd"
	return ""


## The start-up line: the rendering method and the driver in use.
static func line(method: String, driver: String) -> String:
	return "RenderStatus: rendering method %s, driver %s" % [method, driver]


## The warning to log, or "" when there is none: nothing is configured, nothing is drawn (headless, no driver) or the driver in
## use is the configured one.
static func warning(configured: String, driver: String) -> String:
	if configured.is_empty() or driver.is_empty() or driver == RenderStatus.RENDERER_HEADLESS:
		return ""
	if driver == configured:
		return ""
	return "RenderStatus: the %s driver is configured but %s is in use (the configured one failed to start, or was overridden)" % [
			configured, driver]
