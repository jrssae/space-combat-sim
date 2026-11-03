class_name FlightBatch
extends Node
## Flies every batched ship's tick in one native call (M4-T10, N4; architecture §17.9). Stub: the GDScript side lands
## with the step itself; until then no ship takes the native path.

## The native class that flies the batch when the library is loaded and `perf_native` is on.
const NATIVE_CLASS: StringName = &"ScsFlightStep"
const NODE_NAME: StringName = &"FlightBatch"

## Per ship in a step: command scalars (the four nozzle groups' levels, `main_right, main_left, retro_right, retro_left`),
## vectors (strafe, rot, track_dir_b, track_rate_b, face_dir_b, env_accel world) and flags (brake, autotrack, assist_on,
## has_propellant).
const CMD_SCALARS: int = 4
const CMD_VECTORS: int = 6
const CMD_FLAGS: int = 4
## Per ship when the caller supplies the state: basis rows 0 to 2, linear velocity, angular velocity (world).
const STATE_VECTORS: int = 5
## Per ship out: vectors by `Out`, scalars by `OutScalar`.
const OUT_VECTORS: int = 10
const OUT_SCALARS: int = 12
enum Out { FORCE, TORQUE, POD_FORCE, POD_TORQUE, RCS_FORCE, RCS_TORQUE, RCS_FORCE_LEVEL, RCS_TORQUE_LEVEL, RATE_TARGET, VELOCITY }
enum OutScalar { R_MAIN, L_MAIN, R_RETRO, L_RETRO, TRIM, POD_YAW_CMD, MASS_FLOW, FACE_ERROR, BRAKING, FACING, TRACKING,
		PROPELLANT_EMPTY }

## Rows stepped in the last tick, in row order (empty when the batch did not run).
var rows: Array[Ship] = []
## The physics frame of the last step.
var tick: int = -1


## The batch under `world`, made on first ask; null without a world.
static func attach(_world: Node) -> FlightBatch:
	return null


## Registers `spec` and `layout` with a native step for the body `rid` and returns the slot, or -1.
static func register_slot(_step: Object, _rid: RID, _spec: ShipSpec, _layout: ThrusterLayout) -> int:
	return -1


## Packs one ship's command for a step at `row` of the command arrays (sized by the caller).
static func pack_command(cmd: FlightCommand, env_accel: Vector3, assist_on: bool, has_propellant: bool,
		scalars: PackedFloat64Array, vectors: PackedVector3Array, flags: PackedByteArray, row: int) -> void:
	var s: int = row * CMD_SCALARS
	scalars[s] = cmd.main_right
	scalars[s + 1] = cmd.main_left
	scalars[s + 2] = cmd.retro_right
	scalars[s + 3] = cmd.retro_left
	var v: int = row * CMD_VECTORS
	vectors[v] = Vector3(cmd.strafe.x, cmd.strafe.y, 0.0)
	vectors[v + 1] = cmd.rot
	vectors[v + 2] = cmd.track_dir_b
	vectors[v + 3] = cmd.track_rate_b
	vectors[v + 4] = cmd.face_dir_b
	vectors[v + 5] = env_accel
	var f: int = row * CMD_FLAGS
	flags[f] = 1 if cmd.brake else 0
	flags[f + 1] = 1 if cmd.autotrack else 0
	flags[f + 2] = 1 if assist_on else 0
	flags[f + 3] = 1 if has_propellant else 0


## The assist's smoothed pod-yaw command as the native step holds it for `ship` (0 when the ship has no slot).
func assist_state(_ship: Ship) -> float:
	return 0.0


## Which path flew the last tick: `native` when the batch stepped any ship, else `gdscript`.
func path() -> StringName:
	return &"native" if not rows.is_empty() else &"gdscript"
