class_name CockpitScreens
extends Node3D
## The screens in the Starfury's console and the indicator row above them (M3-T29, Q29), on the player's ship only. Each screen is a 2D-only
## `SubViewport` painted by the HUD's own `HudPainter` from the frame `Hud` hands over, shown on a mesh the hardpoints place, so the game's
## screens sit where the interior's rims expect them. The viewports draw only for a new frame and only while the interior shows.
##
## The screens are lit by nothing but themselves, and no `Light3D` comes with them (AC30). The lamps are surfaces of the interior mesh, relit when
## their state changes.

## A screen's texels per metre: about one texel per pixel at 1080p from the eye, a little over so that text stays sharp.
const PIXELS_PER_M: float = 1200.0
const BACKGROUND: Color = Color(0.008, 0.012, 0.012)
## A dark lamp keeps this share of its lit colour, so the row reads as lamps.
const LAMP_DARK_SHARE: float = 0.10
const LAMP_SURFACE_PREFIX: String = "ef_cockpit_ind_"

var _views: Dictionary = {}
var _interior: MeshInstance3D = null
var _lamp_surfaces: Dictionary = {}
var _lamp_lit: Dictionary = {}
var _lit_materials: Dictionary = {}
var _dark_materials: Dictionary = {}
var _shown: bool = false
var _powered: bool = true


## One screen: its viewport, what paints it, and the mesh it shows on.
class ScreenView extends RefCounted:
	var viewport: SubViewport = null
	var canvas: ScreenCanvas = null
	var mesh: MeshInstance3D = null


## The control a screen's viewport draws: it holds that screen's painter and last frame.
class ScreenCanvas extends Control:
	var painter: HudPainter = null
	var frame: HudFrame = null
	var surface: HudSurface = null
	## How many times this screen has been painted (tests read it).
	var paints: int = 0

	func _ready() -> void:
		painter = HudPainter.new(self)

	func _draw() -> void:
		if frame == null or surface == null or painter == null:
			return
		draw_rect(Rect2(Vector2.ZERO, surface.size), CockpitScreens.BACKGROUND, true)
		painter.paint(frame, surface)
		paints += 1


## Builds the screens from the hardpoints' `screens` and finds the lamps on `interior`. Calling it again places what is already built.
func setup(screens: Dictionary, interior: MeshInstance3D) -> void:
	_interior = interior
	for id: String in screens:
		var entry: Dictionary = screens[id]
		var key := StringName(id)
		var view: ScreenView = _views.get(key, null)
		if view == null:
			view = _make_view(key, entry)
			_views[key] = view
		view.mesh.transform = entry["transform"]
	_find_lamps()
	_apply_visibility()


## Each screen's size in pixels by id: what `HudLayout` lays them out for.
func sizes() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in _views:
		out[id] = Vector2((_views[id] as ScreenView).viewport.size)
	return out


## Paints `f` on the screens, and lights the lamps by it. Does nothing while they are hidden.
func show_frame(f: HudFrame) -> void:
	_apply_lamps(f.lamps)
	if not _shown or not _powered:
		return
	for id: StringName in f.screens:
		var view: ScreenView = _views.get(id, null)
		if view == null:
			continue
		view.canvas.frame = f
		view.canvas.surface = f.screens[id]
		view.canvas.queue_redraw()
		view.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The screens show with the interior.
func set_shown(shown: bool) -> void:
	_shown = shown
	_apply_visibility()


## Off goes dark: the HUD switched off takes its instruments with it.
func set_powered(powered: bool) -> void:
	_powered = powered
	_apply_visibility()


## What each screen was given last, for tests: `{"frame": HudFrame, "surface": HudSurface, "paints": int, "painted": Array[StringName]}`.
func screen_state(id: StringName) -> Dictionary:
	var view: ScreenView = _views[id]
	return {"frame": view.canvas.frame, "surface": view.canvas.surface, "paints": view.canvas.paints, "painted": view.canvas.painter.painted}


## The viewport of a screen (tests read how it is set up).
func viewport(id: StringName) -> SubViewport:
	return (_views[id] as ScreenView).viewport


## The mesh a screen shows on.
func screen_mesh(id: StringName) -> MeshInstance3D:
	return (_views[id] as ScreenView).mesh


## Whether a lamp is lit now.
func lamp_lit(id: StringName) -> bool:
	return bool(_lamp_lit.get(id, false))


## Lamp ids found on the interior, in surface order.
func lamp_ids() -> Array:
	return _lamp_surfaces.keys()


func _make_view(id: StringName, entry: Dictionary) -> ScreenView:
	var view := ScreenView.new()
	view.viewport = SubViewport.new()
	view.viewport.name = "%sViewport" % String(id).to_pascal_case()
	view.viewport.disable_3d = true
	view.viewport.transparent_bg = false
	view.viewport.gui_disable_input = true
	view.viewport.handle_input_locally = false
	view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var world_size: Vector2 = entry["size"]
	view.viewport.size = Vector2i((world_size * PIXELS_PER_M).round())
	view.canvas = ScreenCanvas.new()
	view.canvas.name = "Canvas"
	view.canvas.size = Vector2(view.viewport.size)
	view.canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.viewport.add_child(view.canvas)
	add_child(view.viewport)
	view.mesh = MeshInstance3D.new()
	view.mesh.name = "%sScreen" % String(id).to_pascal_case()
	view.mesh.mesh = screen_outline_mesh(world_size, float(entry["corner"]))
	view.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	view.mesh.material_override = _screen_material(view.viewport)
	add_child(view.mesh)
	return view


## A flat screen in its local XY plane, facing +Z: a rectangle, or an octagon with `corner` metres cut off each corner along both edges.
static func screen_outline_mesh(size: Vector2, corner: float) -> ArrayMesh:
	var half: Vector2 = size * 0.5
	var outline := PackedVector2Array()
	if corner > 0.0:
		outline = PackedVector2Array([Vector2(-half.x + corner, half.y), Vector2(half.x - corner, half.y), Vector2(half.x, half.y - corner),
				Vector2(half.x, -half.y + corner), Vector2(half.x - corner, -half.y), Vector2(-half.x + corner, -half.y),
				Vector2(-half.x, -half.y + corner), Vector2(-half.x, half.y - corner)])
	else:
		outline = PackedVector2Array([Vector2(-half.x, half.y), Vector2(half.x, half.y), Vector2(half.x, -half.y), Vector2(-half.x, -half.y)])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for point: Vector2 in outline:
		vertices.append(Vector3(point.x, point.y, 0.0))
		normals.append(Vector3.BACK)
		uvs.append(Vector2(point.x / size.x + 0.5, 0.5 - point.y / size.y))
	for i: int in range(1, outline.size() - 1):
		indices.append_array(PackedInt32Array([0, i, i + 1]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# Unshaded and without mipmaps: nothing in the cabin may dim the instruments, and a mip level would blur their text.
func _screen_material(viewport_node: SubViewport) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.albedo_texture = viewport_node.get_texture()
	return material


# The lamps are named surfaces of the interior mesh.
func _find_lamps() -> void:
	_lamp_surfaces.clear()
	if _interior == null or _interior.mesh == null:
		return
	for i: int in _interior.mesh.get_surface_count():
		var material: Material = _interior.mesh.surface_get_material(i)
		if material != null and String(material.resource_name).begins_with(LAMP_SURFACE_PREFIX):
			_lamp_surfaces[StringName(String(material.resource_name).trim_prefix(LAMP_SURFACE_PREFIX))] = i
	for lamp: StringName in _lamp_surfaces:
		if not _lit_materials.has(lamp):
			var color: Color = HudLayout.LAMP_COLORS.get(lamp, Color.WHITE)
			_lit_materials[lamp] = _lamp_material(color)
			_dark_materials[lamp] = _lamp_material(Color(color.r * LAMP_DARK_SHARE, color.g * LAMP_DARK_SHARE, color.b * LAMP_DARK_SHARE))
		_interior.set_surface_override_material(_lamp_surfaces[lamp], _dark_materials[lamp])
	_lamp_lit.clear()


static func _lamp_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material


# Only a change touches the mesh.
func _apply_lamps(lamps: Dictionary) -> void:
	for lamp: StringName in lamps:
		var lit: bool = bool(lamps[lamp])
		if _lamp_lit.get(lamp, null) == lit or not _lamp_surfaces.has(lamp):
			continue
		_lamp_lit[lamp] = lit
		_interior.set_surface_override_material(_lamp_surfaces[lamp], _lit_materials[lamp] if lit else _dark_materials[lamp])


func _apply_visibility() -> void:
	for id: StringName in _views:
		var view: ScreenView = _views[id]
		view.mesh.visible = _shown and _powered
		if not view.mesh.visible:
			view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
