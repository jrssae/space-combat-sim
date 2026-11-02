@tool
extends RefCounted
class_name GaussianOwnLights
## [space-combat-sim patch] Lights one splat node carries for itself (PATCHES.md, patch 6): they light that node's splats alone and
## use no slot of the scene's 8. Each is two vec4 in the instance's own frame, so the shader needs no matrix per light:
##
##   position xyz, 1 / range
##   colour * energy, view range
##
## A view range of 0 makes a surface light, summed with the scene's lights. Above 0 it makes a glow: light seen through glass, so it
## is added to the colour whichever way the splat faces and only where the paint is dark, as glass and its frames are; it is gone
## once the camera is that far from the splat.
##
## `evaluate` and `glow_on_paint` are the CPU copy of the shaders' sums, for the tests; keep the three in parity.

const MAX_OWN_LIGHTS := 2
const FLOATS_PER_LIGHT := 8
## A glow starts to fade at this share of its view range.
const VIEW_FADE_START := 0.8
## A glow shows fully on paint up to the first level (its brightest channel) and not at all from the second.
const GLOW_PAINT_FULL := 0.1
const GLOW_PAINT_NONE := 0.25


## A light that falls on the surfaces facing it. `position` is in the instance's frame (`to_instance_frame`).
static func surface(position: Vector3, color: Color, energy: float, range_m: float) -> PackedFloat32Array:
	return _pack(position, color, energy, range_m, 0.0)


## A soft glow around `position`, seen only from within `view_range_m` of the camera.
static func glow(position: Vector3, color: Color, level: float, range_m: float, view_range_m: float) -> PackedFloat32Array:
	return _pack(position, color, level, range_m, view_range_m)


## A point given relative to a node's parent, in that node's own frame. `node_pose` is the node's pose relative to the same parent.
static func to_instance_frame(point: Vector3, node_pose: Transform3D) -> Vector3:
	return node_pose.affine_inverse() * point


## What `lights` give a splat at `local_position` with `local_normal`, both in the instance's frame, seen from `camera_distance`:
## `direct` joins the scene lights' sum, `glow` is added to the colour.
static func evaluate(lights: PackedFloat32Array, local_position: Vector3, local_normal: Vector3, camera_distance: float) -> Dictionary:
	var direct := Vector3.ZERO
	var added := Vector3.ZERO
	for i: int in lights.size() / FLOATS_PER_LIGHT:
		var at: int = i * FLOATS_PER_LIGHT
		var relative: Vector3 = Vector3(lights[at], lights[at + 1], lights[at + 2]) - local_position
		var tint := Vector3(lights[at + 4], lights[at + 5], lights[at + 6])
		var inverse_range: float = lights[at + 3]
		var view_range: float = lights[at + 7]
		var dist: float = relative.length()
		if view_range > 0.0:
			var window: float = maxf(1.0 - pow(dist * inverse_range, 2.0), 0.0)
			var fade: float = 1.0 - smoothstep(VIEW_FADE_START * view_range, view_range, camera_distance)
			added += tint * window * window * fade
		elif dist >= 1e-6:
			var falloff: float = maxf(1.0 - pow(dist * inverse_range, 4.0), 0.0)
			direct += tint * falloff * falloff / maxf(dist, 0.0001) * maxf(local_normal.dot(relative / dist), 0.0)
	return {"direct": direct, "glow": added}


## What `glow` (from `evaluate`) adds to a splat with this paint, before lighting.
static func glow_on_paint(glow_term: Vector3, paint: Vector3) -> Vector3:
	var brightest: float = maxf(paint.x, maxf(paint.y, paint.z))
	return glow_term * (1.0 - smoothstep(GLOW_PAINT_FULL, GLOW_PAINT_NONE, brightest))


static func _pack(position: Vector3, color: Color, energy: float, range_m: float, view_range_m: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		position.x, position.y, position.z, 1.0 / maxf(range_m, 0.001),
		color.r * energy, color.g * energy, color.b * energy, view_range_m,
	])
