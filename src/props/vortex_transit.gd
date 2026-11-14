class_name VortexTransit
extends RefCounted
## A ship's passage through a jump vortex (M6-T22, the maintainer's answers of 2026-11-13): it flies the funnel between the mouth
## and the black ring at its base, and is scaled at every depth to fit the funnel there. Pure: depths and sizes in, scales,
## speeds and places out, in the vortex's own frame (origin the mouth's centre, +Z down the funnel toward its base, x and y
## across the mouth, as `JumpVortex` lays it out).
##
## The scale law: the ship keeps its share of the funnel's width as the funnel narrows (so every ship shrinks with it, down to
## the ring's share of the mouth at the base), and it never takes more than `MARGIN` of the width (so a ship too big for the
## funnel, a capital at a gate, shrinks further: it fits inside the ring at the base). In front of the mouth it is whole; a ship
## too wide even for the mouth starts shrinking a little in front of it, so nothing jumps at the mouth.
##
## Arriving, a ship starts at the ring (its offset across the mouth shrunk by the ring's share) and flies straight out to its
## place in the mouth; departing, it flies down until its nose touches the base. Ship-made points are shallow (1.6 mouth radii),
## so the passage takes at least `MIN_TRANSIT_S` whatever the ship's speed, and at most `MAX_TRANSIT_S` for a ship at rest.

## The funnel's well, as the shader shapes it (`jump_vortex.gdshader`'s `well`): depth share = gaussian of the radius share.
const WELL: float = 0.55
## The black ring on the funnel's base, a share of the mouth's radius (the shader's `throat_radius`).
const RING_SHARE: float = 0.24
## A ship takes at most this share of the funnel's width at its depth.
const MARGIN: float = 0.8
## The passage between the ring and the mouth takes this long at least (a ship-made point's funnel unfolds in 2.5 s), and this
## long at most (a ship arriving at rest still comes out; a gate's 1 200 m at its 200 m/s arrival speed).
const MIN_TRANSIT_S: float = 2.5
const MAX_TRANSIT_S: float = 6.0
## An arriving ship comes out of the ring this far into its vortex's opening (after its opener's lead-in): the opening flash has
## faded and the funnel has unfolded about as far as the ring, so the ship's own flash shows and it stays inside the drawn funnel.
## Until then it waits on the base at this scale, as good as gone.
static var EMERGE_AFTER_S: float = VortexTiming.FLASH_S + VortexTiming.GROW_S / 3.0
const HELD_SCALE: float = 0.01
## An arriving ship smaller than this on screen (its bounding radius, px) is not flown through the funnel: nobody could see it
## shrink, so it comes out at its place as before (its flash still shows at the ring). Keeps a far wave of hundreds cheap.
const MIN_SEEN_PX: float = 2.0
## The white flash at the ring as a ship goes or comes: up fast, then out (seconds), its radius at the peak in ring radii.
const FLASH_RISE_S: float = 0.1
const FLASH_FALL_S: float = 0.5
const FLASH_RING_SIZE: float = 1.0


## How deep the funnel is at radius share `s` (0 the axis, 1 the rim), as a share of its depth: the shader's `profile_z`.
static func depth_share_at(s: float) -> float:
	var e: float = exp(-1.0 / (WELL * WELL))
	return (exp(-s * s / (WELL * WELL)) - e) / (1.0 - e)


## The funnel's radius share at depth share `z` (0 the mouth, 1 the base): the inverse of `depth_share_at`.
static func radius_share_at(z: float) -> float:
	var e: float = exp(-1.0 / (WELL * WELL))
	var g: float = clampf(z, 0.0, 1.0) * (1.0 - e) + e
	return clampf(WELL * sqrt(maxf(-log(g), 0.0)), 0.0, 1.0)


## The black ring's radius, m (across the mouth's half height).
static func ring_radius_m(fit: VortexFit) -> float:
	return RING_SHARE * fit.mouth_radius_m


## The room a ship has across the funnel at `depth_m` behind the mouth, m: the funnel's radius there (never under the ring's);
## in front of the mouth it opens out as fast as it comes forward, so a ship too wide for the mouth shrinks in smoothly.
static func inner_radius_m(fit: VortexFit, depth_m: float) -> float:
	if depth_m <= 0.0:
		return fit.mouth_radius_m - depth_m
	return maxf(radius_share_at(depth_m / fit.depth_m), RING_SHARE) * fit.mouth_radius_m


## The ship's scale at `depth_m` behind the mouth for a ship `ship_radius_m` across its line of flight (`lateral_radius`): its share
## of the funnel's width kept, at most `MARGIN` of it, never above 1.
static func scale_at(fit: VortexFit, depth_m: float, ship_radius_m: float) -> float:
	var inner: float = inner_radius_m(fit, depth_m)
	var share: float = minf(inner / fit.mouth_radius_m, 1.0)
	var fits: float = MARGIN * inner / maxf(ship_radius_m, 1e-3)
	return clampf(minf(share, fits), 1e-3, 1.0)


## The scale a ship has at the ring (where it flashes).
static func ring_scale(fit: VortexFit, ship_radius_m: float) -> float:
	return scale_at(fit, fit.depth_m, ship_radius_m)


## Where an arriving ship starts, in the vortex's frame: on the base, its offset across the mouth (`lateral`, m) shrunk to the ring.
static func arrival_start(fit: VortexFit, lateral: Vector2) -> Vector3:
	var at: Vector2 = clamp_lateral(fit, lateral) * RING_SHARE
	return Vector3(at.x, at.y, fit.depth_m)


## Where an arriving ship leaves the funnel, in the vortex's frame: its place in the mouth.
static func arrival_exit(fit: VortexFit, lateral: Vector2) -> Vector3:
	var at: Vector2 = clamp_lateral(fit, lateral)
	return Vector3(at.x, at.y, 0.0)


## An offset across the mouth kept inside the rim (a ship placed outside it comes out at its edge).
static func clamp_lateral(fit: VortexFit, lateral: Vector2) -> Vector2:
	var axes: Vector2 = fit.semi_axes() * 0.95
	var reach: float = (lateral / axes).length()
	return lateral / reach if reach > 1.0 else lateral


## The speed through the funnel over `path_m` for a ship whose own speed is `own_mps`: its own, held between the shortest and the
## longest passage.
static func transit_speed(path_m: float, own_mps: float) -> float:
	return clampf(own_mps, path_m / MAX_TRANSIT_S, path_m / MIN_TRANSIT_S)


## Whether a departing ship at `depth_m`, `nose_m` from its centre to its nose (scaled), touches the base.
static func reached_base(fit: VortexFit, depth_m: float, nose_m: float) -> bool:
	return depth_m + nose_m >= fit.depth_m


## The ship's radius across its line of flight (its local -Z), m, from the box that holds its hull in its own frame.
static func lateral_radius(bounds: AABB) -> float:
	var lo: Vector3 = bounds.position
	var hi: Vector3 = bounds.end
	return Vector2(maxf(absf(lo.x), absf(hi.x)), maxf(absf(lo.y), absf(hi.y))).length()


## The vortex's age at which an arriving ship comes out, for an opener's lead-in of `lead_s`.
static func emerge_age_s(lead_s: float) -> float:
	return lead_s + EMERGE_AFTER_S


## Whether a ship of `radius_m` at `distance_m` from the camera (`px_per_unit`, `VortexLod.px_per_unit`; 0 with no camera) is seen
## well enough to fly its passage.
static func worth_flying(radius_m: float, distance_m: float, px_per_unit: float) -> bool:
	return px_per_unit <= 0.0 or VortexLod.projected_radius_px(radius_m, distance_m, px_per_unit) >= MIN_SEEN_PX


## The flash's level `t` seconds after it starts, 0..1 (0 once it is out).
static func flash_level(t: float) -> float:
	if t < 0.0 or t >= FLASH_RISE_S + FLASH_FALL_S:
		return 0.0
	if t < FLASH_RISE_S:
		return t / FLASH_RISE_S
	return 1.0 - (t - FLASH_RISE_S) / FLASH_FALL_S


## The flash's radius at its peak for a vortex of `fit`, m.
static func flash_radius_m(fit: VortexFit) -> float:
	return FLASH_RING_SIZE * ring_radius_m(fit)
