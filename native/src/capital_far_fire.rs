// Far capitals fire (M10-T85): a real capital beyond the low-attention tier's radius is a tier row with no body, and its guns
// and launchers fire there as seeded rolls instead of bolts. Once a second (staggered by ship) each mount picks as it would
// near (its brain's order for the heavy weapons, the disguise, its arc, its own hull), counts the shots its own cycle gives
// since the last roll (bursts, its ship's rate of fire), and rolls each bolt's line against the target's hull: a big hull's
// surface, so a hit names its section, a fighter's share of its sphere. Missiles and torpedoes are rounds that arrive after
// their flight. The target's interceptors take a share of what comes at its hull. The hits land on the damage store in one
// batch (`capital_gun_rows`). The mounts' own timers carry over both ways, so a ship crossing the edge neither bursts nor
// pauses. Run on the main thread in mount order with no randomness but the seeded hash, so 1 and 6 threads roll alike.
// Engine-free (test_sim_core reads this file): rows in, plain numbers out, no statics.
use godot::builtin::{Basis, Vector3};

use crate::capital_gun_kernels::{self as ck, GunWorld, Mount, Owner, ROLE_PD, Scratch, Tally, is_capital};
use crate::rows::{Rows, seen_ix};
use crate::surface::{from_body, into_body, sweep};
use crate::tier_fire::roll;
use crate::turret_kernels as tk;
use crate::v3::{add, cross, dot, length, normalized, scale, sub, xform, xform_inv};

/// Rolls a ship's mounts are given apart by ship index, so a fleet's rolls spread over the second.
pub const STAGGER_TICKS: i64 = 7;
/// The share of the hostile shots headed for its hull a capital's batteries take when all of them work, a shot of toughness
/// `t` (a heavy bolt 2, a torpedo 3) the share to the power `t`: fitted to two Omegas broadside 2 km apart in play (980 of the
/// 1 113 bolts taken); missiles and torpedoes, which the batteries take first (Q81), by the same rule.
pub const PD_SHARE: f64 = 0.88;
/// What a target's unforeseen manoeuvres add to a bolt's miss while it flies, m/s^2: a fighter's (as the stand-ins' far
/// guns), a capital's.
pub const FIGHTER_DODGE_MPS2: f64 = 10.0;
pub const CAPITAL_DODGE_MPS2: f64 = 0.5;
/// A fighter is hit on this share of its bounding sphere (as the beams).
pub const SPHERE_FACTOR: f64 = 0.7;
/// A round's chance on a fighter: proportional navigation catches one it can out-turn, a long chase lets it slip away.
pub const ROUND_FIGHTER_HIT: f64 = 0.8;
pub const ROUND_FIGHTER_FALLOFF_M: f64 = 12000.0;
/// Time a far turret is given to lay itself on its target each roll, s (long enough to turn all the way).
const LAY_S: f64 = 1000.0;
/// Most shots a mount takes in one roll (a cycle shorter than a tick's share of the second never happens).
const MOST_SHOTS: u32 = 64;

/// A far shot that struck: its mount, the hull (`Damageable`) and body it struck, where (World), the point in the body's frame,
/// the surface volume (-1 for a sphere) and the hull points.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FarHit {
    pub mount: u32,
    pub shooter: i64,
    pub hull: i64,
    pub body: i64,
    pub point: Vector3,
    pub local: Vector3,
    pub volume: i32,
    pub damage: f64,
}

/// A mount that fired this roll, and what at (a disguised shooter that fires on its transponder's side gives itself away).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct FarShot {
    pub mount: u32,
    pub target: i64,
}

/// A far missile or torpedo in flight: who fired it (its row's flags then, for what its target perceives), at what, from
/// where, when it arrives, and its warhead's hull points and toughness.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Round {
    pub mount: u32,
    pub shooter: i64,
    pub shooter_ix: u32,
    pub shooter_flags: u32,
    pub target: i64,
    pub from: Vector3,
    pub arrive_tick: i64,
    pub damage: f64,
    pub toughness: u8,
    pub chance: f64,
    pub lane: i64,
}

/// Counts since the rows were made (readouts).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct FarTally {
    pub rolls: i64,
    pub bolts: i64,
    pub rounds: i64,
    pub hits: i64,
    pub rounds_down: i64,
    pub bolts_down: i64,
    pub rounds_lost: i64,
}

/// The tick: sim time, the sim clock's tick, its ticks a second, and the seed the rolls hash from.
#[derive(Clone, Copy, Debug)]
pub struct Clock {
    pub now_s: f64,
    pub tick: i64,
    pub ticks_per_s: i64,
    pub seed: u64,
}

/// The far fire's state between ticks: when each ship (by owner) last rolled (NaN: not far), the rounds in flight, and each
/// ship's interceptors (working, built) this tick.
#[derive(Clone, Debug, Default)]
pub struct Far {
    pub since: Vec<f64>,
    pub rounds: Vec<Round>,
    pub tally: FarTally,
    pd: Vec<(i64, u32, u32)>,
    due: Vec<Option<f64>>,
}

impl Far {
    /// Owner `o` leaves (`capital_gun_kernels::remove_owner`): the others keep their place.
    pub fn remove_owner(&mut self, o: usize) {
        if o < self.since.len() {
            self.since.remove(o);
        }
    }

    // The chance ship `body`'s batteries take a shot whose share at full strength is `share`: less as its batteries are lost.
    fn take_chance(&self, body: i64, share: f64) -> f64 {
        self.pd.iter().find(|p| p.0 == body).map_or(0.0, |p| share * f64::from(p.1) / f64::from(p.2.max(1)))
    }
}

/// One tick of the far fire. `world.owner_rows` names each owner's row only while it is a live far row (-1 otherwise). The
/// rounds due land first, then every ship whose roll falls on this tick fires the shots its mounts' cycles gave since its
/// last. Appends the hits and the mounts that fired.
#[allow(clippy::too_many_arguments)]
pub fn step<F: Fn(i64) -> Option<usize>>(
    far: &mut Far,
    mounts: &mut [Mount],
    owners: &[Owner],
    owner_of: &[u32],
    world: &GunWorld<'_, F>,
    clock: &Clock,
    warheads: &[f64; 3],
    scratch: &mut Scratch,
    tally: &mut Tally,
    hits: &mut Vec<FarHit>,
    shots: &mut Vec<FarShot>,
) {
    let per_s = clock.ticks_per_s.max(1);
    far.since.resize(owners.len(), f64::NAN);
    far.due.clear();
    let mut any = false;
    for (o, since) in far.since.iter_mut().enumerate() {
        let far_now = world.owner_rows.get(o).is_some_and(|&r| r >= 0);
        if !far_now {
            *since = f64::NAN;
            far.due.push(None);
            continue;
        }
        if since.is_nan() {
            *since = clock.now_s; // just gone far: its mounts' timers stand where the near step left them
            far.due.push(None);
            continue;
        }
        if (clock.tick + o as i64 * STAGGER_TICKS).rem_euclid(per_s) != 0 {
            far.due.push(None);
            continue;
        }
        far.due.push(Some(*since));
        *since = clock.now_s;
        far.tally.rolls += 1;
        any = true;
    }
    if !any && far.rounds.is_empty() {
        return;
    }
    // Every ship's interceptors, working and built.
    far.pd.clear();
    for m in mounts.iter().filter(|m| m.spec.role == ROLE_PD) {
        let working = u32::from(m.works && m.rate > 0.0);
        match far.pd.iter_mut().find(|p| p.0 == m.owner) {
            Some(p) => {
                p.1 += working;
                p.2 += 1;
            }
            None => far.pd.push((m.owner, working, 1)),
        }
    }
    land_rounds(far, world, clock, hits);
    if !any {
        return;
    }
    for (i, m) in mounts.iter_mut().enumerate() {
        if m.spec.role == ROLE_PD {
            continue;
        }
        let o = owner_of[i] as usize;
        let (Some(owner), Some(Some(from_s))) = (owners.get(o), far.due.get(o).copied()) else {
            continue;
        };
        let Some(r) = usize::try_from(world.owner_rows[o]).ok() else {
            continue;
        };
        roll_mount(far, m, i, owner, world, r, from_s, clock, warheads, scratch, tally, hits, shots);
    }
}

// One mount's roll on ship row `r`: its target kept or picked, the shots its cycle gave from `from_s` to now, each bolt's line
// rolled (or each round launched).
#[allow(clippy::too_many_arguments)]
fn roll_mount<F: Fn(i64) -> Option<usize>>(
    far: &mut Far,
    m: &mut Mount,
    i: usize,
    owner: &Owner,
    world: &GunWorld<'_, F>,
    r: usize,
    from_s: f64,
    clock: &Clock,
    warheads: &[f64; 3],
    scratch: &mut Scratch,
    tally: &mut Tally,
    hits: &mut Vec<FarHit>,
    shots: &mut Vec<FarShot>,
) {
    let now_s = clock.now_s;
    if !m.works || m.rate <= 0.0 {
        m.target = 0;
        m.burst_fired = 0;
        return;
    }
    let rows = world.rows;
    let basis = rows.bases[r];
    let origin = rows.positions[r];
    let pivot = add(origin, xform(&basis, m.local_at));
    if m.target != 0 && !ck::bears(m, owner, world, r, &basis, pivot, m.target, ck::PICK_REACH) {
        m.target = 0;
    }
    if let Some((target, aim_local)) = ck::choose(m, owner, world, r, &basis, pivot, scratch, tally) {
        m.target = target;
        m.aim_local = aim_local;
        tally.picks += 1;
    }
    let Some(j) = (m.target != 0).then(|| (world.row_of)(m.target)).flatten() else {
        ck::end_stalled_burst(m, now_s);
        return;
    };
    let aim = far_aim(rows, j, m.aim_local, pivot);
    let d = f64::from(length(sub(aim, pivot)));
    let capital = is_capital(rows, j);
    let reach = if m.spec.launcher { m.spec.reach_m() } else { m.spec.range_m };
    let in_reach = d - if capital || m.spec.launcher { rows.radii[j] } else { 0.0 } <= reach;
    // A fixed gun fires only once its helm has the target on its line (its own cone, not the wider one it holds in).
    let on_line = !m.fixed || in_aim_cone(m, &basis, sub(aim, pivot), d);
    let from = ck::line_from(m, pivot, normalized(xform(&basis, m.axis)));
    if !m.spec.launcher && in_reach && on_line && ck::own_hull_blocks(world, owner, from, aim) {
        tally.blocked += 1;
        m.target = 0;
        return;
    }
    if !in_reach || !on_line {
        ck::end_stalled_burst(m, now_s);
        return;
    }
    // A turret stays laid on its target, so back in play it fires without slewing round from where it last was.
    if !m.fixed && !m.spec.launcher {
        let frame = tk::Frame {
            pivot,
            up: normalized(xform(&basis, m.axis)),
            forward: normalized(xform(&basis, m.zero)),
            side: normalized(xform(&basis, cross(m.axis, m.zero))),
        };
        let gun = m.spec.gun();
        let laid = tk::aim(&frame, rows.velocities[r], m.azimuth, m.elevation, m.min_elevation, &gun, aim, ck::target_velocity(world, j), LAY_S);
        m.azimuth = laid.azimuth;
        m.elevation = laid.elevation;
    }
    // The shots its cycle gives since the last roll: none it was already owed before, so a long wait fires no burst.
    let mut t = if m.ready_at.is_finite() { m.ready_at.max(from_s) } else { from_s };
    let mut n: u32 = 0;
    while t <= now_s + 1e-9 && n < MOST_SHOTS {
        n += 1;
        let next = tk::next_ready(
            m.spec.cycle_s,
            m.spec.burst_shots,
            m.spec.burst_spacing_s,
            &mut m.burst_fired,
            &mut m.burst_started_s,
            t,
        );
        m.ready_at = t + (next - t) / m.rate;
        t = m.ready_at;
    }
    if n == 0 {
        return;
    }
    m.shots += i64::from(n);
    shots.push(FarShot { mount: i as u32, target: m.target });
    let barrels = m.spec.barrels.max(1);
    let target_body = rows.body_ids[j];
    if m.spec.launcher {
        let flight_s = (d - rows.radii[j]).max(0.0) / m.spec.speed_mps.max(1.0);
        let arrive = clock.tick + ((flight_s * clock.ticks_per_s as f64).ceil() as i64).max(1);
        let chance = if capital { 1.0 } else { round_fighter_chance(d) };
        let damage = m.spec.damage + warheads.get(usize::from(m.spec.warhead)).copied().unwrap_or(0.0);
        for k in 0..n * barrels {
            far.rounds.push(Round {
                mount: i as u32,
                shooter: m.owner,
                shooter_ix: rows.faction_ix[r],
                shooter_flags: rows.flags[r],
                target: target_body,
                from: pivot,
                arrive_tick: arrive,
                damage,
                toughness: m.spec.toughness,
                chance,
                lane: m.id.wrapping_mul(64).wrapping_add(i64::from(k)),
            });
            far.tally.rounds += 1;
        }
        return;
    }
    // A bolt misses by its spread (a cone), by the gate's allowance off the lead, and by the target's manoeuvres in its flight.
    let flight_s = d / m.spec.speed_mps.max(1.0);
    let accel = if capital { CAPITAL_DODGE_MPS2 } else { FIGHTER_DODGE_MPS2 };
    let dodge = 0.5 * accel * flight_s * flight_s;
    let allowance = if capital {
        (rows.radii[j] * ck::CAPITAL_AIM_SHARE).max(ck::CAPITAL_AIM_MIN_M)
    } else {
        rows.radii[j]
    };
    let gate = 0.5 * allowance;
    let sigma = (dodge * dodge + gate * gate).sqrt();
    let cone = d * m.spec.spread_rad.max(0.0);
    let target_ix = rows.faction_ix[j];
    let seen = rows.seen_ix(r, target_ix);
    let taken = if hostile(world, target_ix, seen) {
        far.take_chance(target_body, pd_share(m.spec.toughness))
    } else {
        0.0
    };
    for k in 0..n {
        for b in 0..barrels {
            far.tally.bolts += 1;
            let lane = m.id.wrapping_mul(8).wrapping_add(i64::from(b));
            let Some((point, local, volume)) = line_hit(rows, j, from, aim, cone, sigma, clock, lane, i64::from(k)) else {
                continue;
            };
            if taken > 0.0 && roll(clock.seed, clock.tick, lane, i64::from(k) * 4 + 1000) < taken {
                far.tally.bolts_down += 1;
                continue;
            }
            far.tally.hits += 1;
            hits.push(FarHit {
                mount: i as u32,
                shooter: m.owner,
                hull: rows.hull_ids[j],
                body: target_body,
                point,
                local,
                volume,
                damage: m.spec.damage,
            });
        }
    }
}

// The rounds that arrive this tick: lost with their target, taken by its interceptors, else struck where they meet its hull.
fn land_rounds<F: Fn(i64) -> Option<usize>>(
    far: &mut Far,
    world: &GunWorld<'_, F>,
    clock: &Clock,
    hits: &mut Vec<FarHit>,
) {
    if far.rounds.iter().all(|x| x.arrive_tick > clock.tick) {
        return;
    }
    let rows = world.rows;
    let rounds = std::mem::take(&mut far.rounds);
    let mut kept = Vec::with_capacity(rounds.len());
    for x in rounds {
        if x.arrive_tick > clock.tick {
            kept.push(x);
            continue;
        }
        let Some(j) = (world.row_of)(x.target) else {
            far.tally.rounds_lost += 1;
            continue;
        };
        let target_ix = rows.faction_ix[j];
        let seen = seen_ix(x.shooter_flags, x.shooter_ix, target_ix);
        if hostile(world, target_ix, seen) && roll(clock.seed, clock.tick, x.lane, 101) < far.take_chance(x.target, pd_share(x.toughness)) {
            far.tally.rounds_down += 1;
            continue;
        }
        if x.chance < 1.0 && roll(clock.seed, clock.tick, x.lane, 102) >= x.chance {
            far.tally.rounds_lost += 1;
            continue;
        }
        let aim = far_aim(rows, j, Vector3::ZERO, x.from);
        let Some((point, local, volume)) = line_hit(rows, j, x.from, aim, 0.0, 0.0, clock, x.lane, 0) else {
            far.tally.rounds_lost += 1;
            continue;
        };
        far.tally.hits += 1;
        hits.push(FarHit {
            mount: x.mount,
            shooter: x.shooter,
            hull: rows.hull_ids[j],
            body: x.target,
            point,
            local,
            volume,
            damage: x.damage,
        });
    }
    // Rounds launched while landing these (none) would follow the kept ones.
    kept.append(&mut far.rounds);
    far.rounds = kept;
}

/// Where a far shot from `from` aims on row `j`: the point its brain names (`aim_local`, its frame); else for a big hull where
/// the line to its centre meets its surface, or, when that line finds open space (an Omega's drum is a body of its own), the
/// centre of its largest volume; else its centre.
pub fn far_aim(rows: &Rows, j: usize, aim_local: Vector3, from: Vector3) -> Vector3 {
    if aim_local != Vector3::ZERO {
        return ck::aim_point(rows, j, aim_local);
    }
    let origin = rows.positions[j];
    let Some(s) = rows.surface(j) else {
        return origin;
    };
    let basis = &rows.bases[j];
    let a = into_body(basis, origin, from);
    let beyond = add(origin, scale(normalized(sub(origin, from)), (2.0 * rows.radii[j]) as f32));
    let b = into_body(basis, origin, beyond);
    if let Some((t, _)) = sweep(s, a, b, 0.0) {
        return from_body(basis, origin, [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]);
    }
    s.volumes
        .iter()
        .max_by(|x, y| x.reach.total_cmp(&y.reach))
        .map_or(origin, |v| from_body(basis, origin, v.centre))
}

/// The share of shots of `toughness` a capital's batteries take at full strength.
pub fn pd_share(toughness: u8) -> f64 {
    PD_SHARE.powi(i32::from(toughness.max(1)))
}

/// The chance a far round reaches a fighter `range_m` away.
pub fn round_fighter_chance(range_m: f64) -> f64 {
    (ROUND_FIGHTER_HIT * (1.0 - range_m / ROUND_FIGHTER_FALLOFF_M)).clamp(0.1, ROUND_FIGHTER_HIT)
}

fn hostile<F: Fn(i64) -> Option<usize>>(world: &GunWorld<'_, F>, observer: u32, seen: u32) -> bool {
    let (a, s, n) = (observer as usize, seen as usize, world.factions);
    a < n && s < n && world.hostile[a * n + s]
}

// Whether a World offset `rel` (length `d`) lies inside the cone the mount aims in.
fn in_aim_cone(m: &Mount, basis: &Basis, rel: Vector3, d: f64) -> bool {
    if d < 1e-6 {
        return true;
    }
    let along = f64::from(dot(xform_inv(basis, rel), m.axis)) / d;
    along.clamp(-1.0, 1.0).asin() >= m.min_elevation
}

/// Where one far bolt's line from `from` toward `aim` on row `j` meets its hull: the line thrown off by a uniform cone of
/// `cone_m` and a round Gaussian of `sigma_m` at the aim (seeded by `lane` and `k`), then met on the hull's surface when it
/// has one, else on a share of its sphere. The point (World), in the body's frame, and the surface volume (-1 for a sphere).
#[allow(clippy::too_many_arguments)]
pub fn line_hit(
    rows: &Rows,
    j: usize,
    from: Vector3,
    aim: Vector3,
    cone_m: f64,
    sigma_m: f64,
    clock: &Clock,
    lane: i64,
    k: i64,
) -> Option<(Vector3, Vector3, i32)> {
    let line = sub(aim, from);
    let d = f64::from(length(line));
    if d < 1e-3 {
        return None;
    }
    let dir = normalized(line);
    let helper = if dir.x.abs() < 0.9 { Vector3::new(1.0, 0.0, 0.0) } else { Vector3::new(0.0, 1.0, 0.0) };
    let p = normalized(cross(dir, helper));
    let q = cross(dir, p);
    let draw = |n: i64| roll(clock.seed, clock.tick, lane, k * 4 + n);
    let (u1, u2, u3, u4) = (draw(0), draw(1), draw(2), draw(3));
    let tau = std::f64::consts::TAU;
    let disc = cone_m * u1.sqrt();
    let gauss = sigma_m * (-2.0 * u3.max(1e-12).ln()).sqrt();
    let x = disc * (tau * u2).cos() + gauss * (tau * u4).cos();
    let y = disc * (tau * u2).sin() + gauss * (tau * u4).sin();
    let at = add(aim, add(scale(p, x as f32), scale(q, y as f32)));
    let radius = rows.radii[j];
    let beyond = add(from, scale(normalized(sub(at, from)), (d + 2.0 * radius + 10.0) as f32));
    let (basis, origin) = (&rows.bases[j], rows.positions[j]);
    if let Some(s) = rows.surface(j) {
        let a = into_body(basis, origin, from);
        let b = into_body(basis, origin, beyond);
        let (t, volume) = sweep(s, a, b, 0.0)?;
        let local = [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t];
        let point = from_body(basis, origin, local);
        return Some((point, Vector3::new(local[0] as f32, local[1] as f32, local[2] as f32), volume as i32));
    }
    // A fighter's sphere: where the line first enters it.
    let r = radius * SPHERE_FACTOR;
    let ray = normalized(sub(beyond, from));
    let to_c = sub(origin, from);
    let along = f64::from(dot(to_c, ray));
    let off_sq = f64::from(dot(to_c, to_c)) - along * along;
    if off_sq > r * r || along < 0.0 {
        return None;
    }
    let point = add(from, scale(ray, (along - (r * r - off_sq).sqrt()) as f32));
    let local = into_body(basis, origin, point);
    Some((point, Vector3::new(local[0] as f32, local[1] as f32, local[2] as f32), -1))
}

#[cfg(test)]
mod tests;
