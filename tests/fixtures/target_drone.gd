class_name TargetDrone
extends RigidBody3D
## Test fixture (M2-T03): a ship stand-in for the hit tests. A Newtonian body (architecture §5.4) with a `Damageable`
## built from `hardpoints_drone.json` (a capsule of radius 1 m along z, 6 m long, and a 4 x 0.4 x 2 m box), faction
## raiders by default, and a settable `velocity` that is re-applied every physics tick so it crosses a bolt's path at a
## known speed.

const HARDPOINTS_PATH: String = "res://tests/fixtures/hardpoints_drone.json"

var velocity: Vector3 = Vector3.ZERO
var faction: StringName = Factions.RAIDERS
var hull_max: float = 1.0e6
var damageable: Damageable = null


func _init() -> void:
	gravity_scale = 0.0
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	continuous_cd = false


func _ready() -> void:
	var hardpoints: Hardpoints = Hardpoints.load_file(HARDPOINTS_PATH)
	assert(hardpoints.valid, "drone hardpoints: %s" % hardpoints.error)
	damageable = Damageable.new()
	damageable.name = "Damageable"
	add_child(damageable)
	damageable.setup(hardpoints.collision, hull_max, faction)
	linear_velocity = velocity


func _physics_process(_delta: float) -> void:
	linear_velocity = velocity
