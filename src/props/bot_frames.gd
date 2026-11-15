class_name BotFrames
extends RefCounted
## The moving frames the maintenance crew flies in (M7-T35), shared by every bot and refreshed by the fleet each physics tick:
## the drum's angle and turn rate about its pivot, and where the jumpgate stands in the station's frame. Pure: a test sets the
## numbers itself.

## The drum's pivot in the station's frame, its angle about +Z now, rad, and its turn rate, rad/s (0 when held still).
var pivot: Vector3 = Vector3.ZERO
var drum_angle: float = 0.0
var spin_rate: float = 0.0
## The jumpgate in the station's frame; `has_gate` false when the scene has none.
var gate: Transform3D = Transform3D.IDENTITY
var has_gate: bool = false
## Where on the drum's turn a bot gets on and off, rad about +Z (-90 degrees: under the drum, clear of the spine above it).
var hold_angle: float = -PI * 0.5


## A point given in `frame` (a drum point in its landing plane, turned by `psi`) in the station's frame.
func to_station(point: Vector3, frame: BotTrip.Frame, psi: float = 0.0) -> Vector3:
	match frame:
		BotTrip.Frame.DRUM:
			return pivot + Basis(Vector3.BACK, drum_angle + psi) * point
		BotTrip.Frame.GATE:
			return gate * point
	return point


## A direction given in `frame`, in the station's frame.
func dir_to_station(dir: Vector3, frame: BotTrip.Frame, psi: float = 0.0) -> Vector3:
	match frame:
		BotTrip.Frame.DRUM:
			return Basis(Vector3.BACK, drum_angle + psi) * dir
		BotTrip.Frame.GATE:
			return gate.basis * dir
	return dir


## A station point in the drum's own frame (the frame its hull is drawn in).
func station_to_drum(point: Vector3) -> Vector3:
	return Basis(Vector3.BACK, drum_angle).inverse() * (point - pivot)


## The station point at `radius`, station `z`, at angle `phi` about the drum's axis.
func on_circle(radius: float, z: float, phi: float) -> Vector3:
	return Vector3(pivot.x + radius * cos(phi), pivot.y + radius * sin(phi), z)
