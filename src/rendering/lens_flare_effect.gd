class_name SceneLensFlareEffect
extends LensFlareEffect
## The vendored add-on's lens flare, with its files unedited and two differences at start-up. Its shader is compiled then
## (`RuntimeShader`) instead of read from the import cache, which a headless import leaves empty for a shader that uses
## Godot's built-in includes. And its source is patched in memory so the flare's colour is the star's alone (Q30): the add-on
## pushes its lens ghosts toward blue and applies the tint twice to its always-on glow.

## What the add-on's shader says, and what it should say. A re-vendor that moves these fails `test_post_effects`.
const COLOUR_PATCHES: Dictionary[String, String] = {
	"""    float yellow = min(lensflare.r, lensflare.g); // amount of yellow
    lensflare.r -= yellow * 0.5;
    lensflare.g -= yellow * 0.5;""": "    lensflare = desaturate(lensflare, 1.0);",
	"vec3 always_on_flare = sun_color.rgb * mix(0.02,": "vec3 always_on_flare = vec3(0.39) * mix(0.02,",
}


func create_shader(p_file_path: String) -> RID:
	var shader: RID = RuntimeShader.compile_text(rd, patched_source(p_file_path), p_file_path)
	if not shader.is_valid():
		# The add-on would retry and fail on every frame.
		push_warning("SceneLensFlareEffect: %s did not compile; the lens flare stays off" % p_file_path)
		enabled = false
		return shader
	add_rid_to_free(shader, "shader: %s" % p_file_path)
	return shader


## The add-on's shader source with the colour patches applied.
static func patched_source(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	for old: String in COLOUR_PATCHES:
		if not text.contains(old):
			push_warning("SceneLensFlareEffect: %s has changed: a colour patch no longer applies" % path)
		text = text.replace(old, COLOUR_PATCHES[old])
	return text
