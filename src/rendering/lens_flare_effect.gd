class_name SceneLensFlareEffect
extends LensFlareEffect
## The vendored add-on's lens flare, with its files unedited and two differences at start-up. Its shader is compiled then
## (`RuntimeShader`) instead of read from the import cache, which a headless import leaves empty for a shader that uses
## Godot's built-in includes. And its source is patched in memory: the flare's colour is the star's alone (Q30), and it stays a
## lens effect, with no haze or shafts, because space has nothing to scatter light (Q31).

## What the add-on's shader says, and what it should say. A re-vendor that moves these fails `test_post_effects`.
const SHADER_PATCHES: Dictionary[String, String] = {
	# Q30: it pushes the lens ghosts toward blue.
	"""    float yellow = min(lensflare.r, lensflare.g); // amount of yellow
    lensflare.r -= yellow * 0.5;
    lensflare.g -= yellow * 0.5;""": "    lensflare = desaturate(lensflare, 1.0);",
	# Q31: a flat veil over the whole picture.
	"vec3 always_on_flare = sun_color.rgb * mix(0.02, always_on_strength, pow(always_on_weight, 0.1));":
			"vec3 always_on_flare = vec3(0.0);",
	# Q31: the glare's long tail reads as a glow in the air; a tight one stays on the lens.
	"f0 = pow(f0, 2.0);": "f0 = pow(f0, 4.0);",
	# Q31: three broad lobes that wash over the middle of the picture; the hard-edged ghosts stay.
	"max(1.0 / (1.0 + 32.0 * length_squared(uvd + 0.8 * pos)), .0) * 00.25;": "0.0;",
	"max(1.0 / (1.0 + 32.0 * length_squared(uvd + 0.85 * pos)), .0) * 00.23;": "0.0;",
	"max(1.0 / (1.0 + 32.0 * length_squared(uvd + 0.9 * pos)), .0) * 00.21;": "0.0;",
	# Q31: god rays are shafts through a medium that is not there, and marching them costs 64 depth reads per pixel.
	"    col *= godrays;": "",
	"for (int i = 0; i < int(sample_count); i++) {": "for (int i = 0; i < 0; i++) {",
}


## False once the shader failed: the flare then stays off whatever the setting says (`PostEffects.apply_settings`).
var usable: bool = true


func create_shader(p_file_path: String) -> RID:
	var text: String = patched_source(p_file_path)
	var shader := RID()
	if not text.is_empty() and rd != null:
		shader = RuntimeShader.compile_text(rd, text, p_file_path)
	if not shader.is_valid():
		# The add-on would retry and fail on every frame.
		push_warning("SceneLensFlareEffect: %s did not compile; the lens flare stays off" % p_file_path)
		usable = false
		enabled = false
		return shader
	add_rid_to_free(shader, "shader: %s" % p_file_path)
	return shader


## The add-on's shader source with the patches applied.
static func patched_source(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return text
	for old: String in SHADER_PATCHES:
		if not text.contains(old):
			push_warning("SceneLensFlareEffect: %s has changed: a patch no longer applies" % path)
		text = text.replace(old, SHADER_PATCHES[old])
	return text
