extends GutTest
## The docking autopilot's roll match (M8-T31, maintainer 2026-11-19): the ship turns with the drum before it enters, its roll
## rate the drum's within a tolerance and its top square with the bay.

const SPIN: float = 0.148


func _cap() -> ShipCapability:
	var cap := ShipCapability.new()
	cap.rate_max_rad = Vector3(1.0, 1.0, 1.5)
	return cap


func test_the_roll_feeds_the_drums_turn_forward_and_squares_the_ship() -> void:
	var nose := Basis.looking_at(Vector3.BACK, Vector3.UP)  # flying along +z, into the bay
	var spin := Vector3(0.0, 0.0, SPIN)
	var square: Array[Vector3] = [Vector3.UP, Vector3.RIGHT, Vector3.DOWN, Vector3.LEFT]
	var fed: float = DockAutopilot.roll_with(nose, spin, square, _cap().rate_max_rad)
	var w_bz: float = (nose.transposed() * spin).z
	assert_almost_eq(fed, w_bz * FlightModel.AXIS_SIGN.z / 1.5, 1e-4, "square already: only the drum's turn, fed forward")
	assert_ne(fed, 0.0)
	var tilted: Basis = nose.rotated(Vector3.BACK, deg_to_rad(20.0))
	assert_ne(DockAutopilot.roll_with(tilted, spin, square, _cap().rate_max_rad), fed, "20 degrees off square: it rolls back")
	assert_eq(DockAutopilot.nearest_up(nose.rotated(Vector3.BACK, deg_to_rad(80.0)), square).snapped(Vector3.ONE * 1e-3).abs(),
			Vector3.RIGHT, "the nearest of the four ups, not always the top")


func test_it_turns_with_the_drum_only_at_its_rate_and_square() -> void:
	var nose := Basis.looking_at(Vector3.BACK, Vector3.UP)
	var spin := Vector3(0.0, 0.0, SPIN)
	var square: Array[Vector3] = [Vector3.UP, Vector3.RIGHT, Vector3.DOWN, Vector3.LEFT]
	assert_true(DockAutopilot.rolls_with(spin, nose, spin, square), "at the drum's rate, square")
	assert_true(DockAutopilot.rolls_with(spin * 1.1, nose, spin, square), "within the tolerance")
	assert_false(DockAutopilot.rolls_with(Vector3.ZERO, nose, spin, square), "not turning")
	assert_false(DockAutopilot.rolls_with(-spin, nose, spin, square), "turning the wrong way")
	assert_false(DockAutopilot.rolls_with(spin, nose.rotated(Vector3.BACK, deg_to_rad(10.0)), spin, square), "10 degrees off square")
