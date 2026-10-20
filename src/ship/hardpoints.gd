class_name Hardpoints
extends RefCounted
## A ship's `hardpoints.json` (architecture §9.1, schema in docs/assets-starfury.md): the centre of mass, cockpit
## camera, chase anchor, gun muzzles and collision primitives, parsed into Godot types. Pure: reads a file, text or
## Dictionary and never touches the scene tree. Body frame, metres, relative to the body origin (which the generator
## puts on the splat centroid, so this frame is also the rendered frame).
##
## The pod nozzles are the flight model's business: `thruster_layout()` hands the same parsed document to
## `ThrusterLayout`, so the file is read once.
##
## A malformed input is not fatal: `valid` is false and `error` says why (no `push_error` here, so tests can feed bad
## input quietly); the Ship decides whether to warn.

## Collision primitive kinds.
const TYPE_BOX: String = "box"
const TYPE_CAPSULE: String = "capsule"

## False when the input could not be read; `error` explains.
var valid: bool = false
var error: String = ""
## The parsed document, for `ThrusterLayout` and for fields this class does not model (`rcs[]`, pod radii).
var raw: Dictionary = {}
## Body-frame centre of mass (RigidBody3D `center_of_mass` with `CENTER_OF_MASS_MODE_CUSTOM`).
var center_of_mass: Vector3 = Vector3.ZERO
## Pilot eye point: origin at `cockpit_camera.position`, -Z along `forward`, +Y along `up` (a Camera3D looks down -Z).
var cockpit_camera: Transform3D = Transform3D.IDENTITY
## Ship-local chase camera offset (behind and above), handed to `CameraRig.setup`.
var chase_anchor: Vector3 = Vector3.ZERO
## One entry per gun barrel tip, in file order: `name` (String), `position` (Vector3), `direction` (unit Vector3),
## `transform` (Transform3D: origin at the tip, -Z along `direction`).
var muzzles: Array[Dictionary] = []
## One entry per collision primitive, in file order: `name` (String), `type` (`box` or `capsule`), `shape` (a new
## BoxShape3D or CapsuleShape3D) and `transform` (Transform3D: the primitive's `basis` and `position`; for a capsule
## also the turn that lays Godot's capsule axis, local Y, along the named `axis`).
var collision: Array[Dictionary] = []
## Break-up chunks (optional; M2-T04), one entry per group in file order: `name` (String), `ply` and `obj` (file names in the
## asset directory), `offset` (Vector3: the chunk's centroid in the body frame) and `splats` (int).
var chunks: Array[Dictionary] = []


static func load_file(path: String) -> Hardpoints:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failed("cannot open %s (error %d); run scripts/gen_assets.sh" % [path, FileAccess.get_open_error()])
	return from_json_text(file.get_as_text())


static func from_json_text(text: String) -> Hardpoints:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failed("hardpoints are not valid JSON (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
	if not (json.data is Dictionary):
		return _failed("hardpoints root is not an object")
	return from_dict(json.data as Dictionary)


static func from_dict(data: Dictionary) -> Hardpoints:
	var hp := Hardpoints.new()
	hp.raw = data
	hp.error = hp._parse(data)
	hp.valid = hp.error.is_empty()
	return hp


## The pod nozzles of this document as the flight model sees them (lever arms about `center_of_mass`). Check the
## result's `valid` too: the pods are validated there, not here.
func thruster_layout() -> ThrusterLayout:
	if not valid:
		var broken := ThrusterLayout.new()
		broken.error = error
		return broken
	return ThrusterLayout.from_dict(raw, center_of_mass)


## Muzzle names in file order.
func muzzle_names() -> PackedStringArray:
	var names := PackedStringArray()
	for muzzle: Dictionary in muzzles:
		names.append(muzzle["name"])
	return names


## The rotation that lays a Godot capsule (axis along local +Y) along local `axis` ("x", "y" or "z").
static func capsule_axis_basis(axis: String) -> Basis:
	match axis:
		"x":
			return Basis(Vector3.BACK, -PI / 2.0)  # +Y -> +X
		"z":
			return Basis(Vector3.RIGHT, PI / 2.0)  # +Y -> +Z
	return Basis.IDENTITY


## A basis whose -Z looks along `forward` with +Y towards `up`. When `up` is zero or parallel to `forward` it falls
## back to +Y (or +Z for a vertical `forward`); a zero `forward` gives the identity.
static func look_basis(forward: Vector3, up: Vector3 = Vector3.UP) -> Basis:
	if forward.is_zero_approx():
		return Basis.IDENTITY
	var f: Vector3 = forward.normalized()
	var u: Vector3 = up if not up.is_zero_approx() else Vector3.UP
	if absf(f.dot(u.normalized())) > 0.999:
		u = Vector3.BACK if absf(f.dot(Vector3.UP)) > 0.999 else Vector3.UP
	return Basis.looking_at(f, u)


# Fills the fields from `data`; returns "" or the first problem found.
func _parse(data: Dictionary) -> String:
	if not _is_vec3(data.get("center_of_mass")):
		return "hardpoints have no center_of_mass [x, y, z]"
	center_of_mass = _to_vec3(data["center_of_mass"])

	var camera: Variant = data.get("cockpit_camera")
	if not (camera is Dictionary) or not _is_vec3((camera as Dictionary).get("position")):
		return "hardpoints have no cockpit_camera.position"
	var camera_dict: Dictionary = camera
	var forward: Vector3 = _vec3_or(camera_dict.get("forward"), Vector3.FORWARD)
	var up: Vector3 = _vec3_or(camera_dict.get("up"), Vector3.UP)
	cockpit_camera = Transform3D(look_basis(forward, up), _to_vec3(camera_dict["position"]))

	var chase: Variant = data.get("chase_anchor")
	if not (chase is Dictionary) or not _is_vec3((chase as Dictionary).get("position")):
		return "hardpoints have no chase_anchor.position"
	chase_anchor = _to_vec3((chase as Dictionary)["position"])

	var muzzle_list: Variant = data.get("muzzles")
	if not (muzzle_list is Array):
		return "hardpoints have no muzzles[]"
	for value: Variant in muzzle_list as Array:
		var problem: String = _parse_muzzle(value)
		if not problem.is_empty():
			return problem

	var collision_list: Variant = data.get("collision")
	if not (collision_list is Array):
		return "hardpoints have no collision[]"
	for value: Variant in collision_list as Array:
		var problem: String = _parse_collision(value)
		if not problem.is_empty():
			return problem

	var chunk_list: Variant = data.get("chunks", [])
	if not (chunk_list is Array):
		return "hardpoints chunks must be an array"
	for value: Variant in chunk_list as Array:
		var problem: String = _parse_chunk(value)
		if not problem.is_empty():
			return problem
	return ""


func _parse_chunk(value: Variant) -> String:
	var index: int = chunks.size()
	if not (value is Dictionary):
		return "chunk %d is not an object" % index
	var entry: Dictionary = value
	if not (entry.get("name") is String) or not (entry.get("ply") is String) or not (entry.get("obj") is String):
		return "chunk %d needs string name, ply and obj" % index
	if not _is_vec3(entry.get("offset")):
		return "chunk %d needs offset [x, y, z]" % index
	chunks.append({
		"name": String(entry["name"]),
		"ply": String(entry["ply"]),
		"obj": String(entry["obj"]),
		"offset": _to_vec3(entry["offset"]),
		"splats": int(_number_or(entry.get("splats"), 0.0)),
	})
	return ""


func _parse_muzzle(value: Variant) -> String:
	var index: int = muzzles.size()
	if not (value is Dictionary) or not _is_vec3((value as Dictionary).get("position")):
		return "muzzle %d needs position [x, y, z]" % index
	var entry: Dictionary = value
	var direction: Vector3 = _vec3_or(entry.get("direction"), Vector3.FORWARD)
	if direction.is_zero_approx():
		return "muzzle %d has a zero direction" % index
	direction = direction.normalized()
	var position: Vector3 = _to_vec3(entry["position"])
	muzzles.append({
		"name": str(entry.get("name", "muzzle_%d" % index)),
		"position": position,
		"direction": direction,
		"transform": Transform3D(look_basis(direction), position),
	})
	return ""


func _parse_collision(value: Variant) -> String:
	var index: int = collision.size()
	if not (value is Dictionary):
		return "collision %d is not an object" % index
	var entry: Dictionary = value
	var label: String = str(entry.get("name", "collision_%d" % index))
	if not _is_vec3(entry.get("position")):
		return "collision %s needs position [x, y, z]" % label
	var basis: Basis = Basis.IDENTITY
	if entry.has("basis"):
		var parsed: Variant = _parse_basis(entry["basis"])
		if parsed == null:
			return "collision %s basis must be {x, y, z} columns of a rotation" % label
		basis = parsed
	var shape: Shape3D
	var type: String = str(entry.get("type", ""))
	match type:
		TYPE_BOX:
			var size: Variant = entry.get("size")
			if not _is_vec3(size) or not _positive(_to_vec3(size)):
				return "collision %s box needs a positive size [x, y, z]" % label
			var box := BoxShape3D.new()
			box.size = _to_vec3(size)
			shape = box
		TYPE_CAPSULE:
			var radius: float = _number_or(entry.get("radius"), 0.0)
			var height: float = _number_or(entry.get("height"), 0.0)
			var axis: String = str(entry.get("axis", ""))
			if radius <= 0.0 or height < 2.0 * radius:
				return "collision %s capsule needs radius > 0 and height >= 2 * radius" % label
			if axis not in ["x", "y", "z"]:
				return "collision %s capsule needs axis x, y or z" % label
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			capsule.height = height  # total length, caps included (Godot's meaning too)
			shape = capsule
			basis = basis * capsule_axis_basis(axis)
		_:
			return "collision %s has type '%s', expected box or capsule" % [label, type]
	collision.append({
		"name": label,
		"type": type,
		"shape": shape,
		"transform": Transform3D(basis, _to_vec3(entry["position"])),
	})
	return ""


# `{"x": [...], "y": [...], "z": [...]}` columns -> an orthonormal proper rotation, or null. The generator rounds to
# 5 decimals, so the columns are re-orthonormalised: Jolt warns about scaled shapes otherwise.
static func _parse_basis(value: Variant) -> Variant:
	if not (value is Dictionary):
		return null
	var columns: Dictionary = value
	for key: String in ["x", "y", "z"]:
		if not _is_vec3(columns.get(key)):
			return null
	var basis := Basis(_to_vec3(columns["x"]), _to_vec3(columns["y"]), _to_vec3(columns["z"]))
	if basis.determinant() < 0.5:
		return null  # degenerate or a reflection
	return basis.orthonormalized()


static func _failed(message: String) -> Hardpoints:
	var hp := Hardpoints.new()
	hp.error = message
	return hp


static func _positive(v: Vector3) -> bool:
	return v.x > 0.0 and v.y > 0.0 and v.z > 0.0


static func _number_or(value: Variant, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback


static func _vec3_or(value: Variant, fallback: Vector3) -> Vector3:
	return _to_vec3(value) if _is_vec3(value) else fallback


static func _is_vec3(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	for part: Variant in value as Array:
		if not (part is float or part is int):
			return false
	return true


static func _to_vec3(value: Variant) -> Vector3:
	var parts: Array = value
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
