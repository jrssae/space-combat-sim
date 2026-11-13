class_name VortexPassage
extends RefCounted
## One body flying a jump vortex's funnel (M6-T22): what `VortexTransits` keeps for it from the mouth to the ring or back.

enum Kind { ARRIVAL, DEPARTURE }

var kind: Kind = Kind.ARRIVAL
var body: RigidBody3D = null
var vortex: JumpVortex = null
var scaler: TransitScale = null
## Its radius across its line of flight and its bounding radius, m, at its whole size.
var lateral_radius_m: float = 0.0
var bounding_radius_m: float = 0.0
## Arriving: its offset across the mouth (the vortex's x and y, m), the velocity it leaves the funnel with (against the frame's
## rest), and whether it has come out of the ring yet (it waits through its vortex's opening flash).
var lateral: Vector2 = Vector2.ZERO
var exit_velocity_rel: Vector3 = Vector3.ZERO
var emerged: bool = false
## Its speed through the funnel, m/s, and the longest its passage may take before it is ended anyway, s.
var speed_mps: float = 0.0
var limit_s: float = 20.0
## Departing: called with the body once its nose touches the base.
var on_through: Callable = Callable()
## The AI driver held for the passage (null for the player's ship and a body without one), and what steers a departing one.
var driver: AiPilotDriver = null
var capability: ShipCapability = null
var age_s: float = 0.0
var tier_exempt_was: bool = false
## Bodies of the same funnel this one does not collide with while both pass.
var exempt: Array[RigidBody3D] = []
