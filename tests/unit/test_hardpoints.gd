extends GutTest
## Hardpoints: `hardpoints.json` parsed into Godot types (architecture §9.1, schema in docs/assets-starfury.md).
## Uses the static fixture, never the generated assets.

const FIXTURE: String = "res://tests/fixtures/hardpoints_nominal.json"
const EPS: float = 1e-5

var hp: Hardpoints
var fixture: Dictionary


func before_each() -> void:
	hp = Hardpoints.load_file(FIXTURE)
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	fixture = JSON.parse_string(file.get_as_text()) as Dictionary


func _tol(eps: float = EPS) -> Vector3:
	return Vector3(eps, eps, eps)


## The fixture with one top-level key replaced (or removed when `value` is null).
func _variant(key: String, value: Variant) -> Hardpoints:
	var data: Dictionary = fixture.duplicate(true)
	if value == null:
		data.erase(key)
	else:
		data[key] = value
	return Hardpoints.from_dict(data)


## The fixture with collision entry `index` changed by `edit` (a Dictionary merged over it).
func _collision_variant(index: int, edit: Dictionary, erase: String = "") -> Hardpoints:
	var data: Dictionary = fixture.duplicate(true)
	var entry: Dictionary = (data["collision"] as Array)[index]
	entry.merge(edit, true)
	if not erase.is_empty():
		entry.erase(erase)
	return Hardpoints.from_dict(data)


func test_fixture_loads() -> void:
	assert_true(hp.valid, hp.error)
	assert_eq(hp.error, "")
	assert_almost_eq(hp.center_of_mass, Vector3(0.0, 0.0, 0.06728), _tol())
	assert_eq(hp.raw, fixture, "the parsed document is kept for ThrusterLayout and visuals")


func test_cockpit_camera_looks_forward_with_up_up() -> void:
	assert_almost_eq(hp.cockpit_camera.origin, Vector3(0.0, 0.95889, -3.21172), _tol())
	assert_almost_eq(-hp.cockpit_camera.basis.z, Vector3(0.0, 0.0, -1.0), _tol(), "-Z along forward")
	assert_almost_eq(hp.cockpit_camera.basis.y, Vector3(0.0, 1.0, 0.0), _tol(), "+Y along up")
	assert_true(hp.cockpit_camera.basis.is_equal_approx(Basis.IDENTITY), "the nominal eye looks straight ahead")


func test_chase_anchor() -> void:
	assert_almost_eq(hp.chase_anchor, Vector3(0.0, 2.5, 9.0), _tol())


func test_muzzles_in_file_order() -> void:
	assert_eq(hp.muzzles.size(), 2)
	assert_eq(hp.muzzle_names(), PackedStringArray(["left", "right"]))
	assert_almost_eq(hp.muzzles[0]["position"] as Vector3, Vector3(-0.6, -0.74349, -6.47572), _tol())
	assert_almost_eq(hp.muzzles[1]["position"] as Vector3, Vector3(0.6, -0.74349, -6.47572), _tol())
	for muzzle: Dictionary in hp.muzzles:
		var xform: Transform3D = muzzle["transform"]
		assert_eq(xform.origin, muzzle["position"] as Vector3, "%s: origin at the tip" % muzzle["name"])
		assert_almost_eq(-xform.basis.z, muzzle["direction"] as Vector3, _tol(), "%s: -Z down the barrel" % muzzle["name"])


func test_collision_primitives() -> void:
	assert_eq(hp.collision.size(), 9)
	var names: PackedStringArray = []
	for entry: Dictionary in hp.collision:
		names.append(entry["name"])
	assert_eq(names, PackedStringArray(["fuselage", "pod_ur", "pod_lr", "pod_ul", "pod_ll",
			"strut_ur", "strut_lr", "strut_ul", "strut_ll"]))
	var fuselage: Dictionary = hp.collision[0]
	assert_eq(fuselage["type"], Hardpoints.TYPE_BOX)
	assert_true(fuselage["shape"] is BoxShape3D)
	assert_almost_eq((fuselage["shape"] as BoxShape3D).size, Vector3(1.6, 1.4, 7.5), _tol())
	assert_almost_eq((fuselage["transform"] as Transform3D).origin, Vector3(0.0, 0.01526, -1.82572), _tol())
	assert_true((fuselage["transform"] as Transform3D).basis.is_equal_approx(Basis.IDENTITY))


func test_capsules_lie_along_their_named_axis() -> void:
	var pod: Dictionary = hp.collision[1]
	assert_eq(pod["type"], Hardpoints.TYPE_CAPSULE)
	var capsule := pod["shape"] as CapsuleShape3D
	assert_not_null(capsule)
	assert_almost_eq(capsule.radius, 0.55, EPS)
	assert_almost_eq(capsule.height, 3.2, EPS, "total length, caps included")
	var xform: Transform3D = pod["transform"]
	assert_almost_eq(xform.basis.y, Vector3(0.0, 0.0, 1.0), _tol(), "Godot's capsule axis (local Y) along Z")
	assert_almost_eq(xform.origin, Vector3(3.18198, 3.18198, 1.12428), _tol())
	# pod_lr has a basis turned 180 deg about Z: its axis is still Z.
	var lower: Transform3D = (hp.collision[2] as Dictionary)["transform"]
	assert_almost_eq(lower.basis.y, Vector3(0.0, 0.0, 1.0), _tol())
	assert_almost_eq(lower.basis.x, Vector3(-1.0, 0.0, 0.0), _tol())


func test_strut_bases_are_rotations_from_rounded_columns() -> void:
	var strut: Dictionary = hp.collision[5]
	assert_eq(strut["name"], "strut_ur")
	var basis: Basis = (strut["transform"] as Transform3D).basis
	assert_almost_eq(basis.x, Vector3(0.70711, 0.70711, 0.0), _tol(1e-4), "column x")
	assert_almost_eq(basis.y, Vector3(-0.70711, 0.70711, 0.0), _tol(1e-4), "column y")
	assert_almost_eq(basis.determinant(), 1.0, 1e-6, "re-orthonormalised (5-decimal input)")
	assert_almost_eq(basis.x.length(), 1.0, 1e-6)


func test_capsule_axis_basis_maps_y_to_the_axis() -> void:
	assert_almost_eq(Hardpoints.capsule_axis_basis("x") * Vector3.UP, Vector3.RIGHT, _tol())
	assert_almost_eq(Hardpoints.capsule_axis_basis("y") * Vector3.UP, Vector3.UP, _tol())
	assert_almost_eq(Hardpoints.capsule_axis_basis("z") * Vector3.UP, Vector3.BACK, _tol())
	for axis: String in ["x", "y", "z"]:
		assert_almost_eq(Hardpoints.capsule_axis_basis(axis).determinant(), 1.0, 1e-6, "%s: a rotation" % axis)


func test_look_basis() -> void:
	assert_true(Hardpoints.look_basis(Vector3.FORWARD).is_equal_approx(Basis.IDENTITY))
	var right: Basis = Hardpoints.look_basis(Vector3.RIGHT)
	assert_almost_eq(-right.z, Vector3.RIGHT, _tol())
	assert_almost_eq(right.y, Vector3.UP, _tol())
	var down: Basis = Hardpoints.look_basis(Vector3.DOWN)
	assert_almost_eq(-down.z, Vector3.DOWN, _tol(), "vertical forward still works")
	assert_almost_eq(down.determinant(), 1.0, 1e-6)
	assert_true(Hardpoints.look_basis(Vector3.ZERO).is_equal_approx(Basis.IDENTITY), "degenerate input")


func test_thruster_layout_matches_the_direct_parse() -> void:
	var layout: ThrusterLayout = hp.thruster_layout()
	var direct: ThrusterLayout = ThrusterLayout.load_file(FIXTURE)
	assert_true(layout.valid, layout.error)
	assert_eq(layout.center_of_mass, direct.center_of_mass)
	assert_eq(layout.nozzle_names, direct.nozzle_names)
	assert_eq(layout.nozzle_positions, direct.nozzle_positions)
	assert_eq(layout.nozzle_exhausts, direct.nozzle_exhausts)
	assert_eq(layout.rcs_nozzles.size(), direct.rcs_nozzles.size())


func test_invalid_hardpoints_give_an_invalid_layout() -> void:
	var broken: Hardpoints = _variant("center_of_mass", null)
	assert_false(broken.valid)
	var layout: ThrusterLayout = broken.thruster_layout()
	assert_false(layout.valid)
	assert_eq(layout.error, broken.error)


func test_missing_file_and_bad_json() -> void:
	var missing: Hardpoints = Hardpoints.load_file("res://tests/fixtures/no_such_hardpoints.json")
	assert_false(missing.valid)
	assert_string_contains(missing.error, "gen_assets.sh")
	var bad: Hardpoints = Hardpoints.from_json_text("{\"center_of_mass\": [0, 0")
	assert_false(bad.valid)
	assert_string_contains(bad.error, "not valid JSON")
	var not_object: Hardpoints = Hardpoints.from_json_text("[1, 2, 3]")
	assert_false(not_object.valid)
	assert_string_contains(not_object.error, "not an object")


func test_required_top_level_fields() -> void:
	var cases: Dictionary = {
		"center_of_mass": "center_of_mass",
		"cockpit_camera": "cockpit_camera",
		"chase_anchor": "chase_anchor",
		"muzzles": "muzzles",
		"collision": "collision",
	}
	for key: String in cases:
		var broken: Hardpoints = _variant(key, null)
		assert_false(broken.valid, "%s missing" % key)
		assert_string_contains(broken.error, cases[key])
	assert_false(_variant("center_of_mass", [0, 0]).valid, "CoM needs three numbers")
	assert_false(_variant("cockpit_camera", {"forward": [0, 0, -1]}).valid, "camera needs a position")
	assert_false(_variant("muzzles", [{"name": "x"}]).valid, "muzzle needs a position")
	assert_false(_variant("muzzles", [{"position": [0, 0, 0], "direction": [0, 0, 0]}]).valid, "zero direction")


func test_optional_fields_take_defaults() -> void:
	var cam: Hardpoints = _variant("cockpit_camera", {"position": [0, 1, -2]})
	assert_true(cam.valid, cam.error)
	assert_true(cam.cockpit_camera.basis.is_equal_approx(Basis.IDENTITY), "forward -Z, up +Y by default")
	var muzzle: Hardpoints = _variant("muzzles", [{"position": [0, 0, -5]}])
	assert_true(muzzle.valid, muzzle.error)
	assert_eq(muzzle.muzzles[0]["name"], "muzzle_0")
	assert_eq(muzzle.muzzles[0]["direction"], Vector3.FORWARD)
	var no_basis: Hardpoints = _collision_variant(0, {}, "basis")
	assert_true(no_basis.valid, no_basis.error)
	assert_true((no_basis.collision[0]["transform"] as Transform3D).basis.is_equal_approx(Basis.IDENTITY))
	var no_muzzles: Hardpoints = _variant("muzzles", [])
	assert_true(no_muzzles.valid, "an unarmed ship is fine")


func test_bad_collision_primitives_are_rejected() -> void:
	assert_string_contains(_collision_variant(0, {"type": "sphere"}).error, "expected box or capsule")
	assert_string_contains(_collision_variant(0, {"size": [1, 0, 1]}).error, "positive size")
	assert_string_contains(_collision_variant(0, {}, "position").error, "needs position")
	assert_string_contains(_collision_variant(1, {}, "axis").error, "axis x, y or z")
	assert_string_contains(_collision_variant(1, {"axis": "w"}).error, "axis x, y or z")
	assert_string_contains(_collision_variant(1, {"height": 1.0}).error, "height >= 2 * radius")
	assert_string_contains(_collision_variant(1, {"radius": 0}).error, "radius > 0")
	var mirrored: Dictionary = {"basis": {"x": [-1, 0, 0], "y": [0, 1, 0], "z": [0, 0, 1]}}
	assert_string_contains(_collision_variant(0, mirrored).error, "columns of a rotation")  # a reflection
	var flat: Dictionary = {"basis": {"x": [1, 0, 0], "y": [1, 0, 0], "z": [0, 0, 1]}}
	assert_string_contains(_collision_variant(0, flat).error, "columns of a rotation")  # degenerate
	assert_false(_collision_variant(0, {"basis": "identity"}).valid)
