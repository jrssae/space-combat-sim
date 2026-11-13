class_name PlanetLook
extends RefCounted
## How a planet with generated maps is drawn on the scaled-space layer (M6-T11, D68): its maps and tints from the generator's
## manifest, its atmosphere's height from the star system's data, which way its maps face against the ephemeris, and the
## numbers its two shaders need (the surface and the haze shell). Pure: reads a manifest, never touches the scene tree. A body
## without built maps is not fatal: `valid` is false and `error` says why, so the layer draws its plain stand-in instead.

const MANIFEST_PATH: String = "res://assets/generated/%s/manifest.json"
## The stand-in mesh's sphere: coarse, because the shaders find the true limb per pixel.
const SEGMENTS: int = 64
const RINGS: int = 32
## The haze fades out over this many scale heights below the atmosphere's top.
const SCALE_HEIGHTS: float = 5.0

## The maps' resource paths, beside the manifest.
var albedo_path: String = ""
var normal_path: String = ""
var wisp_path: String = ""
## The body's radius, m, as the star system's data gives it.
var radius_m: float = 0.0
## Where the atmosphere stops, m above the surface; 0 for none.
var atmosphere_top_m: float = 0.0
## The haze on the lit limb and the wisps, sRGB as the manifest gives them.
var haze_srgb: Color = Color.BLACK
var wisp_srgb: Color = Color.WHITE
## The maps' mean albedo, linear: the planet's far dot is painted with it (M6-T15).
var mean_albedo: Color = Color(0.2, 0.15, 0.1)
var valid: bool = false
## Why `valid` is false. Empty when valid.
var error: String = ""


## The look of body `id` from its built maps and `info` (the star system's `info(id)`).
static func load_body(id: StringName, info: Dictionary) -> PlanetLook:
	var path: String = MANIFEST_PATH % id
	if not FileAccess.file_exists(path):
		var missing := PlanetLook.new()
		missing.error = "no maps at %s; run scripts/gen_assets.sh" % path
		return missing
	return from_json_text(FileAccess.get_file_as_string(path), path.get_base_dir(), info)


static func from_json_text(text: String, directory: String, info: Dictionary) -> PlanetLook:
	var look := PlanetLook.new()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		look.error = "the planet's manifest is not a JSON object"
		return look
	var planet: Variant = (json.data as Dictionary).get("planet")
	if not (planet is Dictionary) or not ((planet as Dictionary).get("maps") is Dictionary):
		look.error = "the manifest has no planet maps (not a planet asset?)"
		return look
	var maps: Dictionary = (planet as Dictionary)["maps"]
	for key: String in ["albedo", "normal", "clouds"]:
		if not (maps.get(key) is Dictionary) or not ((maps[key] as Dictionary).get("file") is String):
			look.error = "the manifest has no %s map" % key
			return look
	if (planet as Dictionary).get("projection") != "equirectangular":
		look.error = "the maps are not equirectangular"
		return look
	look.albedo_path = directory.path_join(maps["albedo"]["file"])
	look.normal_path = directory.path_join(maps["normal"]["file"])
	look.wisp_path = directory.path_join(maps["clouds"]["file"])
	look.wisp_srgb = _colour8(maps["clouds"].get("tint_srgb"), Color.WHITE)
	var mean: Variant = (planet as Dictionary).get("mean_albedo")
	if mean is Array and (mean as Array).size() == 3:
		look.mean_albedo = Color(float(mean[0]), float(mean[1]), float(mean[2]))
	var atmosphere: Variant = (planet as Dictionary).get("atmosphere")
	look.haze_srgb = _colour8((atmosphere as Dictionary).get("limb_srgb") if atmosphere is Dictionary else null, Color.BLACK)
	look.radius_m = float(info.get("radius_m", (planet as Dictionary).get("radius_m", 0.0)))
	look.atmosphere_top_m = maxf(float(info.get("atmosphere_top_m", 0.0)), 0.0)
	if look.radius_m <= 0.0:
		look.error = "the body has no radius"
		return look
	look.valid = true
	return look


## The haze shell's outer radius, in planet radii.
func shell_radius() -> float:
	return 1.0 + atmosphere_top_m / radius_m


## The haze's scale height, in planet radii.
func scale_height() -> float:
	return atmosphere_top_m / radius_m / SCALE_HEIGHTS


## How much the stand-in mesh's vertices are pushed out so its flat faces still enclose the true sphere, for a sphere of
## `segments` round and `rings` from pole to pole. A face's plane sits nearest the centre at its middle.
static func mesh_inflate(segments: int = SEGMENTS, rings: int = RINGS) -> float:
	return 1.0 / (cos(PI / segments) * cos(PI / (2.0 * rings))) * 1.001


## Planet frame to game axes. The maps' frame (`manifest.planet.uv`): +Y the north pole, +Z where u = 0 (the prime meridian),
## +X east. The pole and the meridian are given in the ephemeris's axes (z north); by default the planet spins about the
## ephemeris's z with its prime meridian toward +x, so its equator lies in the plane its orbits are measured in.
static func orientation(pole_kernel: Vector3 = Vector3(0.0, 0.0, 1.0),
		meridian_kernel: Vector3 = Vector3(1.0, 0.0, 0.0)) -> Basis:
	var north: Vector3 = to_game(pole_kernel).normalized()
	var meridian: Vector3 = to_game(meridian_kernel)
	meridian = (meridian - north * meridian.dot(north)).normalized()
	return Basis(north.cross(meridian), north, meridian)


## The ephemeris's axes (z north) to the game's (y up), as `ScaledPlacement.to_game`.
static func to_game(kernel: Vector3) -> Vector3:
	return Vector3(kernel.x, kernel.z, -kernel.y)


## The direction to the star in the planet's own frame, the shaders' `sun_body`, from `to_sun` in game axes.
static func sun_in_body(to_sun: Vector3, frame: Basis) -> Vector3:
	return (frame.orthonormalized().transposed() * to_sun).normalized()


## Longitude east and latitude, rad, of a unit direction in the planet's frame: where the maps put it.
static func longitude_latitude(direction: Vector3) -> Vector2:
	return Vector2(atan2(direction.x, direction.z), asin(clampf(direction.y, -1.0, 1.0)))


## The surface shader's numbers that do not change from frame to frame.
func surface_uniforms() -> Dictionary:
	return {&"mesh_inflate": mesh_inflate(), &"wisp_tint": wisp_srgb}


## The haze shell's numbers that do not change from frame to frame.
func haze_uniforms() -> Dictionary:
	return {&"mesh_inflate": mesh_inflate() * shell_radius(), &"shell_radius": shell_radius(),
			&"scale_height": scale_height(), &"haze_tint": haze_srgb}


static func _colour8(raw: Variant, fallback: Color) -> Color:
	if not (raw is Array) or (raw as Array).size() < 3:
		return fallback
	return Color8(int(raw[0]), int(raw[1]), int(raw[2]))
