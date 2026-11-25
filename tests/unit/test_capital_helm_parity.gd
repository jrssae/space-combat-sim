extends GutTest
## The capital helm's parity recording (M10-T16, Q70): the helm moved from GDScript (`CapitalHelm`, M10-T07) into the native
## core (`capital_helm.rs`). Before the GDScript helm went, this file recorded what it commanded for seeded poses on four hulls
## (retros, none, a gravitic drive, the Omega's numbers) and for flips flown step by step (`tests/fixtures/parity/
## capital_helm.json`, recorded at d3e09c70); the native helm (`ScsSimCore.capital_helm_probe`) must give the same commands.

const FILE: String = "capital_helm"
const SEED: int = 16
const SINGLE_CASES: int = 60
const SEQUENCE_STEPS: int = 150
const DT: float = 1.0 / 60.0
## The helm's command matches the recording to this, per number (the two paths round the same maths in f32 and f64).
const TOLERANCE: float = 1e-5
const HARDPOINTS: Dictionary = {"center_of_mass": [0.0, 0.0, 0.0], "engines": [
	{"name": "r", "position": [20.0, 0.0, 150.0], "exhaust": [0.0, 0.0, 1.0]},
	{"name": "l", "position": [-20.0, 0.0, 150.0], "exhaust": [0.0, 0.0, 1.0]},
]}
## The hulls: name, propulsion, retro thrust, gravitic fraction, mass, inertia, main thrust, RCS force, RCS torque, rate max.
const HULLS: Array = [
	["retros", &"reaction", 5.0e6, 0.0, 1.0e7, Vector3(7.0e10, 7.0e10, 1.0e9), 1.0e7, Vector3(1.0e6, 1.0e6, 0.0),
			Vector3(7.0e8, 7.0e8, 1.0e7), Vector3(4.0, 4.0, 3.0)],
	["no_retros", &"reaction", 0.0, 0.0, 1.0e7, Vector3(7.0e10, 7.0e10, 1.0e9), 1.0e7, Vector3(1.0e6, 1.0e6, 0.0),
			Vector3(7.0e8, 7.0e8, 1.0e7), Vector3(4.0, 4.0, 3.0)],
	["gravitic", &"gravitic", 0.0, 0.5, 1.0e7, Vector3(7.0e10, 7.0e10, 1.0e9), 1.0e7, Vector3(1.0e6, 1.0e6, 0.0),
			Vector3(7.0e8, 7.0e8, 1.0e7), Vector3(4.0, 4.0, 3.0)],
	["omega", &"reaction", 1.575e8, 0.0, 1.05e9, Vector3(2.77e14, 2.91e14, 5.36e13), 3.15e8, Vector3(1.05e8, 1.05e8, 0.0),
			Vector3(5.0e11, 5.2e11, 9.6e10), Vector3(1.0, 1.0, 0.8)],
]


# The flight spec, layout and capability of hull `row` as `CapitalShip` builds them.
func _hull(row: Array) -> Array:
	var spec := ShipSpec.new()
	spec.propulsion = row[1]
	spec.pod_retro_thrust = row[2]
	spec.gravitic_fraction = row[3]
	spec.mass = row[4]
	spec.inertia = row[5]
	spec.pod_main_thrust = row[6]
	spec.rcs_force_max = row[7]
	spec.rcs_torque_max = row[8]
	spec.rate_max = row[9]
	var layout: ThrusterLayout = CapitalPropulsion.layout(HARDPOINTS)
	var flown: ShipSpec = CapitalPropulsion.flight_spec(spec, CapitalPropulsion.main_count(layout))
	return [flown, layout]


# One helm per hull: the numbers the native helm takes (`CapitalBrainSpec.helm_numbers`, as `CapitalShip` joins with).
func _make_helm(row: Array) -> Variant:
	var built: Array = _hull(row)
	return CapitalBrainSpec.helm_numbers(built[0], built[1])


# This tick's command and the flip state after it, as numbers: main l/r, retro l/r, strafe x/y, rot x/y/z, flipping.
func _command(helm: Variant, heading: Vector3, velocity: Vector3, flipping: bool, basis: Basis, current: Vector3) -> Array:
	var out: PackedFloat64Array = ScsSimCore.capital_helm_probe(helm, heading, velocity, flipping, basis, current)
	var values: Array = []
	for v: float in out:
		values.append(v)
	return values


func _random_basis(rng: RandomNumberGenerator) -> Basis:
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
	if axis.length_squared() < 1e-6:
		axis = Vector3.UP
	return Basis(axis.normalized(), rng.randf_range(-PI, PI))


func _random_vector(rng: RandomNumberGenerator, size: float) -> Vector3:
	return Vector3(rng.randf_range(-size, size), rng.randf_range(-size, size), rng.randf_range(-size, size))


# Seeded single commands on every hull: a pose, a heading (now and then none), the velocity held and the motion, a flip
# under way or not.
func _singles() -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for row: Array in HULLS:
		var helm: Variant = _make_helm(row)
		for i: int in SINGLE_CASES:
			var basis: Basis = _random_basis(rng)
			var heading: Vector3 = Vector3.ZERO if rng.randf() < 0.1 else _random_vector(rng, 1.0).normalized()
			var velocity: Vector3 = _random_vector(rng, 30.0)
			var current: Vector3 = velocity + _random_vector(rng, 25.0) if rng.randf() < 0.8 else velocity
			var flipping: bool = rng.randf() < 0.3
			out.append(_command(helm, heading, velocity, flipping, basis, current))
	return out


# Flips and turns flown step by step on a toy integration of the command (the helm keeps its own flip state): the
# commands of every step.
func _sequences() -> Array:
	var out: Array = []
	for row: Array in HULLS:
		var built: Array = _hull(row)
		var cap: ShipCapability = ShipCapability.from_spec(built[0], built[1])
		var helm: Variant = _make_helm(row)
		var basis := Basis.IDENTITY
		var current := Vector3(0.0, 0.0, -20.0)
		var flipping: bool = false
		var heading: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, 0.6)
		for step: int in SEQUENCE_STEPS:
			var got: Array = _command(helm, heading, Vector3.ZERO, flipping, basis, current)
			out.append(got)
			flipping = float(got[9]) > 0.5
			# The toy: the turn at its asked rate scaled up so a flip shows within the steps, the thrust as accelerations.
			var rot := Vector3(float(got[6]), float(got[7]), 0.0) * cap.rate_max_rad * 40.0 * DT
			basis = (basis * Basis.from_euler(Vector3(rot.x, -rot.y, 0.0))).orthonormalized()
			var thrust_b := Vector3(float(got[4]) * cap.a_rcs.x, float(got[5]) * cap.a_rcs.y,
					-float(got[0]) * cap.a_main + float(got[2]) * cap.a_retro)
			current += basis * thrust_b * 20.0 * DT
			# Below the helm's coast threshold the flight assist's own hold takes the rest, so a flip can end.
			if current.length() < 1.0:
				current *= 0.5
	return out


func _match_recording(label: String, got: Array, expected: Variant) -> void:
	assert_not_null(expected, "%s is recorded (%s.json)" % [label, FILE])
	if expected == null:
		return
	var stored: Array = expected
	assert_eq(got.size(), stored.size(), "%s: as many commands as recorded" % label)
	var worst: float = 0.0
	var first_bad: int = -1
	for i: int in mini(got.size(), stored.size()):
		var a: Array = got[i]
		var b: Array = stored[i]
		for k: int in a.size():
			var e: float = absf(float(a[k]) - float(b[k]))
			if e > worst:
				worst = e
			if e > TOLERANCE and first_bad < 0:
				first_bad = i
	assert_eq(first_bad, -1, "%s: every command within %s of the recording (worst %.9f, first off at %d)" % [label,
			TOLERANCE, worst, first_bad])


func test_the_native_helm_matches_the_recorded_gdscript_helm_command_for_command() -> void:
	var got: Array = _singles()
	var expected: Variant = await ParityFixture.expected(FILE, "singles", func() -> Array: return _singles())
	_match_recording("singles", got, expected)


func test_flips_flown_step_by_step_match_the_recorded_gdscript_helm() -> void:
	var got: Array = _sequences()
	var expected: Variant = await ParityFixture.expected(FILE, "sequences", func() -> Array: return _sequences())
	_match_recording("sequences", got, expected)
