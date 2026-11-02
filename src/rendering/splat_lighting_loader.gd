class_name SplatLightingLoader
extends RefCounted
## Gives a splat node the lighting records its generator wrote (architecture §7.3). A `.light` file already is GDGS's
## `GaussianLightingResource` format 1 data, so loading is wrapping the bytes: there is no per-splat work, and one resource per file
## is shared by every node drawing that file.
##
## GDGS re-merges every splat in the scene when a node in the tree gets new records, so `attach` belongs before the node enters it.

## Every node with records, so a change of setting can reach them all.
const GROUP: StringName = &"relit_splats"
## The settings `apply_settings` reads.
const SETTINGS: Array[StringName] = [&"splat_relight", &"relight_ambient", &"relight_unlit_level", &"relight_light_gain"]

# File path -> its resource, or null when it could not be used (so that is reported once).
static var _cache: Dictionary[String, GaussianLightingResource] = {}


## The resource of a generator's records, or null when the bytes are not a whole number of records.
static func from_bytes(bytes: PackedByteArray) -> GaussianLightingResource:
	if bytes.is_empty() or bytes.size() % GaussianLightingResource.BYTES_PER_SPLAT != 0:
		return null
	var lighting := GaussianLightingResource.new()
	lighting.source_point_count = bytes.size() / GaussianLightingResource.BYTES_PER_SPLAT
	lighting.splat_data = bytes
	lighting.bake_settings = {"source": "tools/procgen"}
	return lighting


## The shared resource of a `.light` file, or null (with one warning) when it is missing or damaged.
static func load_file(path: String) -> GaussianLightingResource:
	if _cache.has(path):
		return _cache[path]
	var lighting: GaussianLightingResource = from_bytes(FileAccess.get_file_as_bytes(path))
	if lighting == null:
		push_warning("SplatLightingLoader: %s is missing or damaged (run scripts/gen_assets.sh); those splats stay unlit" % path)
	_cache[path] = lighting
	return lighting


## Forgets the loaded files (tests).
static func clear_cache() -> void:
	_cache.clear()


## Gives `node` (with its `gaussian` already set) the records at `path` and the relight settings. An empty path means the asset has
## none. Records for another splat count are refused: they would light the wrong splats.
static func attach(node: GaussianSplatNode, path: String) -> void:
	node.relight_cast_shadows = false  # nothing mesh-like receives a splat's shadow in M3
	var lighting: GaussianLightingResource = null if path.is_empty() else load_file(path)
	if lighting != null and node.gaussian != null and not lighting.matches_source(node.gaussian):
		push_warning("SplatLightingLoader: %s is for %d splats, the node has %d (run scripts/gen_assets.sh); those splats stay unlit"
				% [path, lighting.source_point_count, node.gaussian.point_count])
		lighting = null
	node.lighting = lighting
	if lighting != null:
		node.add_to_group(GROUP)
	apply_settings(node)


## Brings `node` in line with the relight settings. A node without records is never lit.
static func apply_settings(node: GaussianSplatNode) -> void:
	var ambient: float = Settings.get_value(&"relight_ambient")
	node.relight_enabled = node.lighting != null and bool(Settings.get_value(&"splat_relight"))
	node.relight_ambient = Color(ambient, ambient, ambient)
	node.relight_unlit_level = Settings.get_value(&"relight_unlit_level")
	node.relight_light_gain = Settings.get_value(&"relight_light_gain")
