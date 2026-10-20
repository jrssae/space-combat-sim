class_name SplatStatus
extends Node
## Which GDGS backend draws the splats, and the switch to the mesh fallback (architecture §7.4, §6.4).
##
## `active_backend()` reads GDGS's backend selector (resolved once per session) and returns one of:
## - `compute` / `raster`: a backend initialised; splats render (whether they look right is (H)).
## - `headless`: no display server (`--headless`: import, CI, GUT). GDGS deliberately skips backend selection there,
##   so there is no backend, but there is also nothing to draw: this is not a failure and does NOT turn the
##   fallback on. That keeps headless runs on the real splat path (the GDGS nodes exist and stay visible; only the
##   GPU work is missing), which is what the integration tests assert.
## - `none`: a display exists but neither backend initialised. Only this turns the fallback on automatically.
##
## The fallback can also be forced (console `fallback on`, Main's F4 toggle; T16 adds a CLI flag and a setting).
## Nodes that can draw without splats opt in through groups, and this node calls them whenever the state changes
## and once when they join while the fallback is active:
## - `MESH_GROUP`: `use_fallback_mesh(enabled: bool)` (Ship, NavBuoy): show the OBJ, hide the splats.
## - `SKY_GROUP`: `use_fallback_sky(enabled: bool)` (SpaceEnvironment): panorama sky instead of sky splats.
## A Ship also checks `active_backend()` itself in `_ready`, so it shows its mesh when nothing renders splats even
## without a SplatStatus in the scene.
##
## Main (M1-T15) adds one SplatStatus outside `World`. Console: provider `render` (`splat_backend`, `fallback` (w),
## `fps`, `gpu`) and command `fallback [on|off]`.

## The fallback state changed (forced or not); `active` is `is_fallback_active()`.
signal fallback_changed(active: bool)

const SELECTOR := preload("res://addons/gdgs/runtime/render/backend/gaussian_backend_selector.gd")

const BACKEND_COMPUTE: StringName = &"compute"
const BACKEND_RASTER: StringName = &"raster"
const BACKEND_HEADLESS: StringName = &"headless"
const BACKEND_NONE: StringName = &"none"

const MESH_GROUP: StringName = &"splat_fallback_mesh"
const SKY_GROUP: StringName = &"splat_fallback_sky"
const MESH_METHOD: StringName = &"use_fallback_mesh"
const SKY_METHOD: StringName = &"use_fallback_sky"

var _forced: bool = false
var _applied: bool = false


## The active GDGS backend as a lower-case id (`compute`, `raster`), or `headless` / `none` when there is none.
static func active_backend() -> StringName:
	var backend: RefCounted = SELECTOR.get_backend(null)
	if backend != null and backend.has_method(&"get_display_name"):
		return backend_id(str(backend.call(&"get_display_name")))
	if DisplayServer.get_name() == "headless":
		return BACKEND_HEADLESS
	return BACKEND_NONE


## GDGS display name ("Compute", "Raster") -> backend id (`compute`, `raster`).
static func backend_id(display_name: String) -> StringName:
	return StringName(display_name.strip_edges().to_lower())


## Whether a backend id means splats cannot be drawn on a screen that exists (only `none`).
static func needs_fallback(backend: StringName) -> bool:
	return backend == BACKEND_NONE


func _ready() -> void:
	_applied = is_fallback_active()
	if _applied:
		_apply_all()
	get_tree().node_added.connect(_on_node_added)
	DebugConsole.registry.register_provider(&"render", ConsoleVars.new({
		&"splat_backend": {"get": func() -> StringName: return active_backend(),
				"doc": "GDGS backend: compute, raster, headless (nothing renders) or none (fallback on)"},
		&"fallback": {"get": is_fallback_active, "set": _console_set_fallback, "type": TYPE_BOOL,
				"doc": "Fallback meshes and panorama sky instead of splats"},
		&"fps": {"get": func() -> float: return Engine.get_frames_per_second(), "doc": "Frames per second"},
		&"gpu": {"get": _gpu_name, "doc": "Video adapter name"},
	}), self)
	DebugConsole.registry.register_command(ConsoleCommand.new(&"fallback",
			"Show the fallback meshes and panorama sky instead of splats; with no argument, toggle",
			[ConsoleArg.bool_optional(&"state")]), _cmd_fallback, self)


func _exit_tree() -> void:
	DebugConsole.registry.unregister_owner(self)
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


## True when the fallback is forced or no backend can draw splats.
func is_fallback_active() -> bool:
	return _forced or needs_fallback(active_backend())


func is_fallback_forced() -> bool:
	return _forced


## Forces the fallback on, or releases it. Releasing cannot turn splats on when no backend exists: then it returns
## the reason and the fallback stays on. Returns "" on success.
func set_fallback(enabled: bool) -> String:
	_forced = enabled
	var active: bool = is_fallback_active()
	if active != _applied:
		_applied = active
		_apply_all()
		fallback_changed.emit(active)
	if not enabled and active:
		return "no splat backend (%s); the fallback stays on" % active_backend()
	return ""


## Main's F4 toggle.
func toggle_fallback() -> String:
	return set_fallback(not is_fallback_active())


func _apply_all() -> void:
	for group: StringName in [MESH_GROUP, SKY_GROUP]:
		for node: Node in get_tree().get_nodes_in_group(group):
			_apply_to(node)


# Calls the node's fallback method with the current state; a node that is not ready yet (a sibling later in the
# tree, or one just added) gets it when it is.
func _apply_to(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if not node.is_node_ready():
		var deferred: Callable = _apply_to.bind(node)
		if not node.ready.is_connected(deferred):
			node.ready.connect(deferred, CONNECT_ONE_SHOT)
		return
	var active: bool = is_fallback_active()
	if node.is_in_group(MESH_GROUP) and node.has_method(MESH_METHOD):
		node.call(MESH_METHOD, active)
	if node.is_in_group(SKY_GROUP) and node.has_method(SKY_METHOD):
		node.call(SKY_METHOD, active)


# Everything defaults to splats, so a node joining later only needs telling while the fallback is on.
func _on_node_added(node: Node) -> void:
	if _applied and (node.is_in_group(MESH_GROUP) or node.is_in_group(SKY_GROUP)):
		_apply_to(node)


func _console_set_fallback(value: Variant) -> String:
	return set_fallback(bool(value))


func _cmd_fallback(args: Dictionary) -> ConsoleResult:
	return DebugConsole.registry.toggle("render.fallback", args[&"state"])


static func _gpu_name() -> String:
	var adapter: String = RenderingServer.get_video_adapter_name()
	return adapter if not adapter.is_empty() else "none"
