class_name HullDepthProxy
extends MeshInstance3D
## Depth-only stand-in for a splat body (architecture §7.2). GDGS composites splats before the transparent pass and
## splats write no depth, so effects drawn with depth testing (thruster plumes, muzzle flash, projectiles, the buoy
## beacon) behind a hull would show through it. This node draws the body's fallback mesh in opaque black with every
## vertex pulled `inset_m` inward along its normal (`hull_depth_proxy.gdshader`): it writes depth just inside the splat
## surface, so it hides what is behind the hull and never covers the splats.
##
## The owner (`Ship`, `NavBuoy`) gives it the mesh the fallback uses (`mesh = fallback.mesh`, whatever is loaded) and
## shows it exactly when the splats are shown, i.e. opposite to the fallback mesh (`SplatStatus`). Shadows and GI
## ignore it. What it looks like is (H); an unlit black hull with splats on top is the intended picture.

const SHADER: Shader = preload("res://assets/shaders/hull_depth_proxy.gdshader")
const INSET_PARAMETER: StringName = &"inset_m"
## Default inset, m: beyond the splat sampling jitter, small enough that the silhouette stays inside the splats.
const DEFAULT_INSET_M: float = 0.04

## How far inside the surface the proxy sits, m.
@export_range(0.0, 0.5, 0.005, "suffix:m") var inset_m: float = DEFAULT_INSET_M:
	set(value):
		inset_m = value
		_sync_inset()

var _material: ShaderMaterial = null


func _init() -> void:
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_sync_inset()


func _sync_inset() -> void:
	if _material != null:
		_material.set_shader_parameter(INSET_PARAMETER, inset_m)
