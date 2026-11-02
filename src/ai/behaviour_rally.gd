class_name BehaviourRally
extends AiBehaviour
## Back to the wing's fight (architecture §16 D34, M3-T10): a wing ship with nothing it may attack in sight flies to the
## nearest engaged wingmate (one with a target selected), seen or heard through broadcast (`Perception.broadcasts`, allies
## 100 km). So a fight that spread past the 5 km near scan comes together instead of a wingmate fighting alone. It flies to
## a wingmate, never a far hostile: behaviours do not chase far contacts on their own (Q21).
##
## Score: `SCORE` (above idle, below formation's 0.25, so only a leader or a leaderless member rallies) while the orders
## allow no attack on anything in sight and an engaged wingmate is beyond `ARRIVE_M`; else 0. `WingDirector` gives it to a
## wing's AI ships and keeps `AiContext.wing_ids` current.

const SCORE: float = 0.2
const ARRIVE_M: float = 1500.0
const EXTRA_MPS: float = 100.0
const FACE_DV_MPS: float = 20.0

var closure_mps: float = 200.0

var _to: Contact = null


func _init(profile: AiProfile = null) -> void:
	id = &"rally"
	if profile != null:
		closure_mps = profile.cruise_mps + EXTRA_MPS


func score(ctx: AiContext) -> float:
	_to = null
	if ctx.wing_ids.is_empty() or ctx.has_attackable():
		return 0.0
	var p: Perception = ctx.perception
	# Nearest engaged wingmate beyond ARRIVE_M.
	var nearest: float = INF
	for list: Array[Contact] in [p.contacts, p.broadcasts]:
		for c: Contact in list:
			if c.target_id > 0 and ctx.wing_ids.has(c.id):
				var d2: float = c.position.distance_squared_to(p.position)
				if d2 > ARRIVE_M * ARRIVE_M and d2 < nearest:
					nearest = d2
					_to = c
	return SCORE if _to != null else 0.0


func think(ctx: AiContext, _dt: float) -> PilotCommand:
	var p: Perception = ctx.perception
	var cmd := PilotCommand.new()
	if _to == null:
		return cmd
	var los: Vector3 = _to.position - p.position
	var v_des: Vector3 = _to.velocity + los.normalized() * closure_mps
	var dv: Vector3 = v_des - p.velocity
	cmd.flight.rot = PilotSteering.face(p.basis, dv if dv.length() > FACE_DV_MPS else los, p.capability.rate_max_rad)
	seek_velocity(cmd.flight, p, v_des)
	return cmd


func describe() -> Dictionary:
	return {"state": "to %s" % _to.name if _to != null else "none"}
