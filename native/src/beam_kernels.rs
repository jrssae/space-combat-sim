// Capital beams as rows (M10-T12, D12.9): every beam emitter of every capital in play is a row with no node per shot. A pulsed
// beam lands once on the first hull on its line; a sustained one stays on for a few seconds and lands each tick on the first
// hull under its line while its emitter sweeps after the target. Each emitter charges, fires and cools on sim time, keeps to
// its mount's arc and picks targets by what its ship perceives (the renegades' disguise). Run once a tick on the main thread
// over the rows of the tick's sync, in emitter order, so 1 and 6 threads land the same beams. Engine-free (test_sim_core
// reads this file): rows in, plain numbers out, no statics.
use godot::builtin::{Basis, Vector3};

use crate::rows::{FLAG_DISABLED, FLAG_HULK, FLAG_HULL_ACTIVE, FLAG_SHELTERED, FLAG_TIER, Rows};
use crate::surface::{into_body, sweep};
use crate::v3::{add, cross, dist_sq, dot, length, normalized, scale, sub, xform, xform_inv};

/// A pulsed beam: one tick, the first hull on the line.
pub const PULSED: u8 = 1;
/// A sustained beam: on for `on_s`, each tick to the first hull under the line, sweeping.
pub const SUSTAINED: u8 = 2;

/// Where an emitter is in its cycle.
pub const READY: u8 = 0;
pub const CHARGING: u8 = 1;
pub const FIRING: u8 = 2;
pub const COOLING: u8 = 3;

/// The target kinds a beam takes (the core's entity kinds): ships and capitals.
const KIND_SHIP: u8 = 0;
const KIND_CAPITAL: u8 = 1;
/// A fighter's line is measured against this share of its bounding sphere (hulls are thinner than their spheres; as
/// the far fire's shot model).
pub const SPHERE_FACTOR: f64 = 0.7;
/// The least angle off the target an emitter fires within, rad (half a degree; a big hull's own size widens it).
const GATE_MIN_RAD: f64 = 0.5 * std::f64::consts::PI / 180.0;
/// An emitter with no target looks for one this many ticks apart, staggered by its index, so a fleet's idle beams do not
/// all walk the rows in the same tick.
pub const PICK_EVERY: u32 = 15;
/// A phase ends when this little is left, so a timer counted down in ticks ends on the tick it should (not one later for a
/// rounding error).
const TIMER_EPS: f64 = 1e-9;

/// One weapon's numbers, from its `WeaponSpec` (the hull's `damage_scale` already in `damage` and `dps`).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct BeamSpec {
    pub kind: u8,
    /// A pulse's hull points.
    pub damage: f64,
    /// A sustained beam's hull points a second while on.
    pub dps: f64,
    pub on_s: f64,
    /// From one shot's start to the next's, s.
    pub cycle_s: f64,
    pub charge_s: f64,
    pub range_m: f64,
    /// How fast the emitter turns its beam, rad/s (its traverse, and a sustained beam's sweep).
    pub turn_rad_s: f64,
}

/// One emitter: its ship, where it sits and looks in the ship's frame, its arc, its weapon, and its state.
#[derive(Clone, Debug, PartialEq)]
pub struct Beam {
    /// The ship's body id.
    pub owner: i64,
    pub local_at: Vector3,
    pub local_fwd: Vector3,
    /// The cosine of the arc's half angle.
    pub arc_cos: f64,
    pub spec: BeamSpec,
    /// Its mount works (alive, its section standing, the ship neither disabled nor destroyed).
    pub works: bool,
    /// Its ship's rate of fire, 0 to 1 (half on last orders with the bridge lost).
    pub rate: f64,
    pub phase: u8,
    /// Seconds left in the phase.
    pub timer: f64,
    /// The body it holds, 0 none.
    pub target: i64,
    /// Where its beam points, a unit vector in the ship's frame.
    pub aim: Vector3,
    /// Ticks until it looks for a target again.
    pub pick_wait: u32,
}

impl Beam {
    pub fn new(
        owner: i64,
        local_at: Vector3,
        local_fwd: Vector3,
        arc_half_rad: f64,
        spec: BeamSpec,
    ) -> Beam {
        let fwd = normalized(local_fwd);
        Beam {
            owner,
            local_at,
            local_fwd: fwd,
            arc_cos: arc_half_rad.clamp(0.0, std::f64::consts::PI).cos(),
            spec,
            works: true,
            rate: 1.0,
            phase: READY,
            timer: 0.0,
            target: 0,
            aim: fwd,
            pick_wait: 0,
        }
    }
}

/// A ship's own bodies (its hull and its rotating sections), which its beams pass through, and the target its brain gives.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Owner {
    pub body: i64,
    pub bodies: Vec<i64>,
    pub order: i64,
}

/// A beam landed this tick: the emitter, the hull row, where, the surface volume it entered (-1 for a sphere), and the
/// hull points.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BeamHit {
    pub beam: u32,
    pub row: u32,
    pub point: Vector3,
    pub volume: i32,
    pub damage: f64,
}

/// A beam to draw this tick: the emitter, its phase, the line's ends (World), and whether it ends on a hull.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BeamDraw {
    pub beam: u32,
    pub phase: u8,
    pub from: Vector3,
    pub to: Vector3,
    pub hit: bool,
}

/// What a step reads beside the rows: the hull rows in the sweep's order, each owner's row (-1: not in the rows this tick),
/// the hostility table by the core's faction indices (`factions` square), and how to find a body's row.
pub struct BeamWorld<'a, F: Fn(i64) -> Option<usize>> {
    pub rows: &'a Rows,
    pub hull_rows: &'a [u32],
    pub owner_rows: &'a [i32],
    pub hostile: &'a [bool],
    pub factions: usize,
    pub row_of: F,
}

/// One tick of every emitter, in order: phases on by `dt`, targets kept or picked, beams turned and fired. Appends the
/// hits and the lines to draw.
pub fn step<F: Fn(i64) -> Option<usize>>(
    beams: &mut [Beam],
    owners: &[Owner],
    owner_of: &[u32],
    world: &BeamWorld<'_, F>,
    dt: f64,
    hits: &mut Vec<BeamHit>,
    draws: &mut Vec<BeamDraw>,
) {
    for (i, b) in beams.iter_mut().enumerate() {
        let o = owner_of[i] as usize;
        let Some(owner) = owners.get(o) else {
            continue;
        };
        let Some(r) = usize::try_from(world.owner_rows[o]).ok() else {
            continue; // out of the rows this tick (parked, pooled): it holds its state
        };
        if !b.works || b.rate <= 0.0 {
            if b.phase == FIRING || b.phase == CHARGING {
                b.phase = COOLING;
                b.timer = b.spec.cycle_s;
            }
            continue;
        }
        let basis = world.rows.bases[r];
        let origin = world.rows.positions[r];
        let from = add(origin, xform(&basis, b.local_at));
        if b.target != 0 && !bears(b, owner, world, r, &basis, from, b.target) {
            b.target = 0;
        }
        if b.phase == READY && b.target == 0 {
            b.target = choose(b, owner, world, r, &basis, from);
        } else if b.phase == READY && holds_disabled(world, b.target) {
            // A disabled hull it holds gives way to anything live before each shot (M10-T14 review): a ready emitter charges
            // at once, so this looks every time, not on the pick beat.
            b.pick_wait = 0;
            let better = choose(b, owner, world, r, &basis, from);
            if better != 0 {
                b.target = better;
            }
        }
        // A sustained beam that lost its target holds its line for the rest of its time on; an idle emitter rests forward.
        let rest = if b.phase == FIRING {
            b.aim
        } else {
            b.local_fwd
        };
        let wanted = target_dir(world, &basis, from, b.target).unwrap_or(rest);
        b.aim = turned(b.aim, wanted, b.spec.turn_rad_s * dt);
        match b.phase {
            COOLING => {
                b.timer -= dt * b.rate;
                if b.timer <= TIMER_EPS {
                    b.phase = READY;
                    b.timer = 0.0;
                }
            }
            READY => {
                if b.target != 0 && on_target(world, &basis, from, b) {
                    b.phase = CHARGING;
                    b.timer = b.spec.charge_s;
                }
            }
            CHARGING => {
                if b.target == 0 {
                    b.phase = READY;
                } else {
                    b.timer -= dt;
                    draws.push(BeamDraw {
                        beam: i as u32,
                        phase: CHARGING,
                        from,
                        to: from,
                        hit: false,
                    });
                    if b.timer <= TIMER_EPS {
                        if b.spec.kind == SUSTAINED {
                            b.phase = FIRING;
                            b.timer = b.spec.on_s;
                        } else {
                            fire(b, i, owner, world, &basis, from, b.spec.damage, hits, draws);
                            b.phase = COOLING;
                            b.timer = b.spec.cycle_s;
                        }
                    }
                }
            }
            FIRING => {
                fire(
                    b,
                    i,
                    owner,
                    world,
                    &basis,
                    from,
                    b.spec.dps * dt,
                    hits,
                    draws,
                );
                b.timer -= dt;
                if b.timer <= TIMER_EPS {
                    b.phase = COOLING;
                    b.timer = (b.spec.cycle_s - b.spec.on_s).max(0.0);
                }
            }
            _ => b.phase = READY,
        }
    }
}

// The beam along its aim this tick: the first hull on the line takes `damage`; the line is drawn to it or to full range.
#[allow(clippy::too_many_arguments)]
fn fire<F: Fn(i64) -> Option<usize>>(
    b: &Beam,
    i: usize,
    owner: &Owner,
    world: &BeamWorld<'_, F>,
    basis: &Basis,
    from: Vector3,
    damage: f64,
    hits: &mut Vec<BeamHit>,
    draws: &mut Vec<BeamDraw>,
) {
    let dir = normalized(xform(basis, b.aim));
    let found = first_hull(
        world.rows,
        world.hull_rows,
        &owner.bodies,
        from,
        dir,
        b.spec.range_m,
    );
    let to = match found {
        Some((row, t, volume)) => {
            let point = add(from, scale(dir, t as f32));
            hits.push(BeamHit {
                beam: i as u32,
                row,
                point,
                volume,
                damage,
            });
            point
        }
        None => add(from, scale(dir, b.spec.range_m as f32)),
    };
    draws.push(BeamDraw {
        beam: i as u32,
        phase: if b.spec.kind == SUSTAINED {
            FIRING
        } else {
            COOLING
        },
        from,
        to,
        hit: found.is_some(),
    });
}

/// The first hull of `hull_rows` the line from `from` along unit `dir` meets within `range_m`, skipping `own` bodies: its
/// row, how far along, and the surface volume entered (-1 for a sphere). A big hull is met on its surface, any other on a
/// share of its bounding sphere. Ties go to the earlier row.
pub fn first_hull(
    rows: &Rows,
    hull_rows: &[u32],
    own: &[i64],
    from: Vector3,
    dir: Vector3,
    range_m: f64,
) -> Option<(u32, f64, i32)> {
    let mut best: Option<(u32, f64, i32)> = None;
    let mut best_t = range_m;
    for &r in hull_rows {
        let j = r as usize;
        if j >= rows.positions.len() || !can_block(rows, j) || own.contains(&rows.body_ids[j]) {
            continue;
        }
        let rel = sub(rows.positions[j], from);
        let along = f64::from(dot(rel, dir));
        let radius = rows.radii[j];
        if along + radius < 0.0 || along - radius > best_t {
            continue;
        }
        let off = f64::from(length(sub(rel, scale(dir, along as f32))));
        if off > radius {
            continue;
        }
        let met = if let Some(s) = rows.surface(j) {
            // Only the stretch of the line inside the hull's bounding sphere can meet its volumes.
            let (t0, t1) = ((along - radius).max(0.0), (along + radius).min(best_t));
            let (basis, origin) = (&rows.bases[j], rows.positions[j]);
            let (a, b) = (
                add(from, scale(dir, t0 as f32)),
                add(from, scale(dir, t1 as f32)),
            );
            sweep(
                s,
                into_body(basis, origin, a),
                into_body(basis, origin, b),
                0.0,
            )
            .map(|(f, k)| (t0 + f * (t1 - t0), k as i32))
        } else {
            sphere_entry(along, off, radius * SPHERE_FACTOR).map(|t| (t, -1))
        };
        if let Some((t, volume)) = met
            && t < best_t
        {
            best_t = t;
            best = Some((r, t, volume));
        }
    }
    best
}

// Where a line first enters a sphere whose centre lies `along` the line and `off` from it, or none when it misses or the
// sphere is wholly behind; 0 when the line starts inside.
fn sphere_entry(along: f64, off: f64, radius: f64) -> Option<f64> {
    if off > radius {
        return None;
    }
    let half = (radius * radius - off * off).sqrt();
    if along + half < 0.0 {
        return None;
    }
    Some((along - half).max(0.0))
}

// Whether a beam stops on row `j`: a hull in play or a tier row, not a mine, not sheltered in a station.
fn can_block(rows: &Rows, j: usize) -> bool {
    let flags = rows.flags[j];
    flags & FLAG_SHELTERED == 0
        && (flags & FLAG_TIER != 0 || flags & FLAG_HULL_ACTIVE != 0)
        && !rows.is_mine[j]
}

// Whether emitter `b` of the ship at row `r` can hold body `target`: a live hostile ship or capital its ship perceives as
// hostile, within range and inside the mount's arc.
fn bears<F: Fn(i64) -> Option<usize>>(
    b: &Beam,
    owner: &Owner,
    world: &BeamWorld<'_, F>,
    r: usize,
    basis: &Basis,
    from: Vector3,
    target: i64,
) -> bool {
    (world.row_of)(target).is_some_and(|j| takes(b, owner, world, r, basis, from, j))
}

// Whether row `j` is a target for emitter `b` (see `bears`).
fn takes<F: Fn(i64) -> Option<usize>>(
    b: &Beam,
    owner: &Owner,
    world: &BeamWorld<'_, F>,
    r: usize,
    basis: &Basis,
    from: Vector3,
    j: usize,
) -> bool {
    let rows = world.rows;
    if j >= rows.positions.len()
        || !can_block(rows, j)
        || rows.flags[j] & FLAG_HULK != 0
        || rows.is_static[j]
    {
        return false;
    }
    let kind = rows.kinds[j];
    if (kind != KIND_SHIP && kind != KIND_CAPITAL) || owner.bodies.contains(&rows.body_ids[j]) {
        return false;
    }
    // Only a ship with a target marker is a target (its row's id is the marker's, not the body's): a hull-only piece, such
    // as a capital's rotating section, is not, though it still stops a line.
    if rows.ids[j] == rows.body_ids[j] {
        return false;
    }
    if !hostile(
        world,
        rows.faction_ix[r],
        rows.seen_ix(j, rows.faction_ix[r]),
    ) {
        return false;
    }
    let rel = sub(rows.positions[j], from);
    let d = f64::from(length(rel));
    if d - rows.radii[j] > b.spec.range_m {
        return false;
    }
    d < 1e-6 || f64::from(dot(normalized(xform_inv(basis, rel)), b.local_fwd)) >= b.arc_cos
}

fn hostile<F: Fn(i64) -> Option<usize>>(
    world: &BeamWorld<'_, F>,
    observer: u32,
    seen: u32,
) -> bool {
    let (a, s, n) = (observer as usize, seen as usize, world.factions);
    a < n && s < n && world.hostile[a * n + s]
}

// The target emitter `b` takes when it has none: its brain's order when that bears, else (on its staggered pick tick) the
// nearest live capital it can hold, else the nearest live ship, else a disabled hull. 0: none; it looks again `PICK_EVERY` ticks later.
fn choose<F: Fn(i64) -> Option<usize>>(
    b: &mut Beam,
    owner: &Owner,
    world: &BeamWorld<'_, F>,
    r: usize,
    basis: &Basis,
    from: Vector3,
) -> i64 {
    if owner.order != 0 && bears(b, owner, world, r, basis, from, owner.order) {
        return owner.order;
    }
    if b.pick_wait > 0 {
        b.pick_wait -= 1;
        return 0;
    }
    b.pick_wait = PICK_EVERY - 1;
    let rows = world.rows;
    // A disabled hull last (M10-T14 review), then capitals before ships, nearest first.
    let mut best: Option<((bool, bool), f32, usize)> = None;
    for &h in world.hull_rows {
        let j = h as usize;
        if !takes(b, owner, world, r, basis, from, j) {
            continue;
        }
        let small = (rows.flags[j] & FLAG_DISABLED != 0, rows.kinds[j] != KIND_CAPITAL);
        let d = dist_sq(rows.positions[j], from);
        if best.is_none_or(|(bs, bd, _)| (small, d) < (bs, bd)) {
            best = Some((small, d, j));
        }
    }
    best.map_or(0, |(_, _, j)| rows.body_ids[j])
}

// Whether body `target` is a disabled hull (`FLAG_DISABLED`).
fn holds_disabled<F: Fn(i64) -> Option<usize>>(world: &BeamWorld<'_, F>, target: i64) -> bool {
    target != 0 && (world.row_of)(target).is_some_and(|j| world.rows.flags[j] & FLAG_DISABLED != 0)
}

// The way to body `target` from `from`, in the ship's frame (unit), or none.
fn target_dir<F: Fn(i64) -> Option<usize>>(
    world: &BeamWorld<'_, F>,
    basis: &Basis,
    from: Vector3,
    target: i64,
) -> Option<Vector3> {
    if target == 0 {
        return None;
    }
    let j = (world.row_of)(target)?;
    let rel = sub(world.rows.positions[j], from);
    if dot(rel, rel) < 1e-6 {
        return None;
    }
    Some(normalized(xform_inv(basis, rel)))
}

// Whether emitter `b`'s aim lies within its gate of its target: half a degree, or the angle half the target's size subtends.
fn on_target<F: Fn(i64) -> Option<usize>>(
    world: &BeamWorld<'_, F>,
    basis: &Basis,
    from: Vector3,
    b: &Beam,
) -> bool {
    let Some(j) = (world.row_of)(b.target) else {
        return false;
    };
    let rel = sub(world.rows.positions[j], from);
    let d = f64::from(length(rel)).max(1e-6);
    let gate = GATE_MIN_RAD.max((0.5 * world.rows.radii[j] * SPHERE_FACTOR / d).atan());
    let want = normalized(xform_inv(basis, rel));
    f64::from(dot(b.aim, want)).clamp(-1.0, 1.0).acos() <= gate
}

/// Unit `from` turned toward unit `to` by at most `max_rad`.
pub fn turned(from: Vector3, to: Vector3, max_rad: f64) -> Vector3 {
    let c = f64::from(dot(from, to)).clamp(-1.0, 1.0);
    let angle = c.acos();
    if angle <= max_rad.max(0.0) || angle < 1e-9 {
        return to;
    }
    let mut axis = cross(from, to);
    if length(axis) < 1e-9 {
        // Opposite: any axis across `from`.
        axis = cross(from, Vector3::new(0.0, 1.0, 0.0));
        if length(axis) < 1e-6 {
            axis = cross(from, Vector3::new(1.0, 0.0, 0.0));
        }
    }
    let axis = normalized(axis);
    let (s, k) = (max_rad.sin() as f32, max_rad.cos() as f32);
    // Rodrigues' turn of `from` about an axis across it.
    normalized(add(scale(from, k), scale(cross(axis, from), s)))
}

#[cfg(test)]
mod tests;
