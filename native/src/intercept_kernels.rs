//! Interceptor batteries (M7-T41, M10-T13): the one battery model the station grid and the capitals share, with no engine type
//! in this file (`test_sim_core` reads it and fails on one).
//!
//! - **Incoming fire.** A battery looks at hostile missiles and bolts within its reach whose path meets a hull it guards within
//!   `INTERCEPT_HORIZON_S` (`gather`; who is hostile and which hulls are guarded are the caller's: the grid guards every big
//!   hull by true faction, a capital its own hull and friendly big hulls by what it perceives). Beams, mines, blasts and other
//!   batteries' pulses are never candidates.
//! - **The choice** (`choose_by`): a missile or torpedo before any bolt, then the caller's class (a capital's own hull before
//!   its friends'), then the shot that hits soonest; among equals the lower bolt row.
//! - **The shot** (`fire_battery`): the next ready barrel laid on the lead from its own muzzle, a seeded spread, so a pulse can
//!   miss. A shot already covered by enough pulses on their way (`PulseCover`) is left to them.
//! - **Toughness** (Q81): a shot takes as many pulses as its `hits_left`; each pulse that meets it takes one off, and it is gone
//!   at 0 (`pulse_hits_by`). Cover lets that many pulses fly at it.
#![allow(clippy::too_many_arguments)]

use std::collections::{HashMap, HashSet};

use godot::builtin::{Basis, Vector3};

use crate::brain_maths::solve;
use crate::rows::{Bolts, Rows, Surface};
use crate::surface;
use crate::sweep_cells::CellGrid;
use crate::turret_kernels::{self as tk, Gun};
use crate::v3::{add, dist_sq, dot, length, normalized, scale, sub};

/// Projectile kinds as the core packs them (`sim_core::KIND_NAMES`).
pub const KIND_MISSILE: u8 = 3;
pub const KIND_BOLT: u8 = 7;
/// A battery's pulse (M7-T41): it flies like a bolt but meets only hostile missiles and bolts, never a hull.
pub const KIND_INTERCEPT: u8 = 9;
/// The most barrels a battery has.
pub const MAX_BARRELS: usize = 4;
/// The most pulses a shot can take (Q81's toughness 1 to 3, with room for one more).
pub const MAX_TOUGHNESS: usize = 4;
/// A pulse still in flight covers its target until this long after the meeting its lead predicted, s; past it the pulse missed
/// and the target may be shot at again.
pub const COVER_SLACK_S: f64 = 0.1;
const TIME_EPSILON_S: f64 = 1e-6;
/// How often at most a battery's barrel is laid again on the lead from its muzzle, and the muzzle's move that ends it
/// (1 mm, squared).
const LAY_PASSES: usize = 6;
const LAY_SETTLED_M2: f64 = 1e-6;
/// How far ahead an interceptor follows a projectile's straight path to the hull, s (its own life when shorter).
pub const INTERCEPT_HORIZON_S: f64 = 6.0;
/// A bolt not yet swept against the guarded hulls this tick, in a cache of hull times.
pub const NOT_SWEPT: f64 = f64::NAN;

/// A projectile a battery may take: its bolt row, whether it is a missile and how soon its path meets a guarded hull, s.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Incoming {
    pub bolt: u32,
    pub missile: bool,
    pub hit_in_s: f64,
}

/// Whether bolt `p` is a shot a battery could take at all: a missile or a bolt (never a beam, a mine or a pulse), not spent.
pub fn is_shot(bolts: &Bolts, p: usize) -> bool {
    let kind = bolts.kinds[p];
    (kind == KIND_MISSILE || kind == KIND_BOLT) && !bolts.spent[p]
}

/// How soon bolt `p`'s straight path meets one of `guarded`'s hulls (rows with a surface), s, and which (followed for its
/// life, at most `INTERCEPT_HORIZON_S`); none when it meets none. The path is taken relative to each hull's motion.
pub fn first_hull_hit(rows: &Rows, guarded: &[usize], bolts: &Bolts, p: usize, now_s: f64) -> Option<(f64, usize)> {
    first_hull_hit_within(rows, guarded, &[], bolts, p, now_s)
}

/// How far a big hull's volumes reach from its row's origin, m: a path that passes further off cannot meet it.
pub fn hull_bound(s: &Surface) -> f64 {
    s.volumes.iter().fold(0.0, |far, v| {
        let c = (v.centre[0] * v.centre[0] + v.centre[1] * v.centre[1] + v.centre[2] * v.centre[2]).sqrt();
        far.max(c + v.reach)
    })
}

/// `first_hull_hit` with each guarded hull's `hull_bound` (in `guarded`'s order; none to sweep every hull): a path passing
/// further off a hull than its bound skips the volume sweep, which would find nothing there (a capital's hull has hundreds).
pub fn first_hull_hit_within(
    rows: &Rows,
    guarded: &[usize],
    bounds: &[f64],
    bolts: &Bolts,
    p: usize,
    now_s: f64,
) -> Option<(f64, usize)> {
    let life = bolts.expires_at[p] - now_s;
    let horizon = if life.is_finite() && life > 0.0 { life.min(INTERCEPT_HORIZON_S) } else { INTERCEPT_HORIZON_S };
    let start = bolts.positions[p];
    let mut best: Option<(f64, usize)> = None;
    for (k, &j) in guarded.iter().enumerate() {
        let Some(s) = rows.surface(j) else {
            continue;
        };
        let (basis, origin): (&Basis, Vector3) = (&rows.bases[j], rows.positions[j]);
        let relative = sub(bolts.velocities[p], rows.velocities[j]);
        let end = add(start, scale(relative, horizon as f32));
        if let Some(&bound) = bounds.get(k)
            && segment_distance(start, end, origin) > bound + 1.8 * bolts.radii[p] + 1.0
        {
            continue;
        }
        let a = surface::into_body(basis, origin, start);
        let b = surface::into_body(basis, origin, end);
        if let Some((t, _)) = surface::sweep(s, a, b, bolts.radii[p]) {
            let when = t * horizon;
            if best.is_none_or(|(w, _)| when < w) {
                best = Some((when, j));
            }
        }
    }
    best
}

// The distance from `p` to the segment `a`-`b`, m.
fn segment_distance(a: Vector3, b: Vector3, p: Vector3) -> f64 {
    let (ax, ay, az) = (f64::from(a.x), f64::from(a.y), f64::from(a.z));
    let (dx, dy, dz) = (f64::from(b.x) - ax, f64::from(b.y) - ay, f64::from(b.z) - az);
    let (px, py, pz) = (f64::from(p.x) - ax, f64::from(p.y) - ay, f64::from(p.z) - az);
    let len_sq = dx * dx + dy * dy + dz * dz;
    let t = if len_sq < 1e-12 { 0.0 } else { ((px * dx + py * dy + pz * dz) / len_sq).clamp(0.0, 1.0) };
    let (ex, ey, ez) = (px - dx * t, py - dy * t, pz - dz * t);
    (ex * ex + ey * ey + ez * ez).sqrt()
}

/// `first_hull_hit`'s time alone.
pub fn time_to_hull(rows: &Rows, guarded: &[usize], bolts: &Bolts, p: usize, now_s: f64) -> Option<f64> {
    first_hull_hit(rows, guarded, bolts, p, now_s).map(|(t, _)| t)
}

/// A battery's incoming fire at `pivot` within `reach_m` among bolt rows `candidates` (in the order given): each shot `hostile`
/// accepts whose `hull_time` (s; infinite for none) is finite. The caller keeps the hull times, so each bolt is swept once a
/// tick per guarded set, not once per battery.
pub fn gather<I, H, T>(bolts: &Bolts, candidates: I, pivot: Vector3, reach_m: f64, mut hostile: H, mut hull_time: T, out: &mut Vec<Incoming>)
where
    I: IntoIterator<Item = usize>,
    H: FnMut(usize) -> bool,
    T: FnMut(usize) -> f64,
{
    out.clear();
    let reach_sq = reach_m * reach_m;
    for p in candidates {
        if !hostile(p) || f64::from(dist_sq(bolts.positions[p], pivot)) > reach_sq {
            continue;
        }
        let when = hull_time(p);
        if when.is_finite() {
            out.push(Incoming {
                bolt: p as u32,
                missile: bolts.kinds[p] == KIND_MISSILE,
                hit_in_s: when,
            });
        }
    }
}

/// The battery's order among `candidates`: a missile before any bolt, then the lower `class` (the caller's: 0 for all on the
/// grid; a capital's own hull before its friends'), then the one that hits soonest; among equals the earlier candidate. `ok`
/// is asked only of one that would beat the best so far, so the costly tests (the line past a hull) stay rare.
pub fn choose_by<C, F>(candidates: &[Incoming], class: C, mut ok: F) -> Option<Incoming>
where
    C: Fn(&Incoming) -> u8,
    F: FnMut(&Incoming) -> bool,
{
    let mut best: Option<(Incoming, u8)> = None;
    for c in candidates {
        let k = class(c);
        let better = match best {
            None => true,
            Some((b, bk)) => {
                (c.missile && !b.missile) || (c.missile == b.missile && (k < bk || (k == bk && c.hit_in_s < b.hit_in_s)))
            }
        };
        if better && ok(c) {
            best = Some((*c, k));
        }
    }
    best.map(|(c, _)| c)
}

/// An interceptor battery's barrels (M7-T41): the trunnion in the yaw frame and each muzzle in the pitch frame (metres, as
/// `TurretMount`'s Yaw and Pitch nodes hold them), each barrel's recharge, when each is ready and which fires next. They fire
/// in turn: the battery's own interval spaces the shots, and a barrel fires again only once recharged.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Battery {
    pub trunnion: Vector3,
    pub muzzles: [Vector3; MAX_BARRELS],
    pub count: usize,
    pub recharge_s: f64,
    pub ready_at: [f64; MAX_BARRELS],
    pub next: usize,
}

impl Battery {
    /// One barrel `barrel_m` down the axis from the pivot, recharging as the gun's interval: a battery with no model data.
    pub fn single(barrel_m: f64, recharge_s: f64) -> Self {
        Self::with(Vector3::ZERO, &[Vector3::new(0.0, 0.0, -barrel_m as f32)], recharge_s)
    }

    /// `barrels` barrels side by side `barrel_m` down the axis (a capital's battery, whose model gives no muzzles), each
    /// recharging in the time all of them take to fire once at `interval_s`.
    pub fn row(barrels: usize, barrel_m: f64, interval_s: f64) -> Self {
        let n = barrels.clamp(1, MAX_BARRELS);
        let mut muzzles = [Vector3::ZERO; MAX_BARRELS];
        for (k, m) in muzzles.iter_mut().enumerate().take(n) {
            let across = (k as f32 - 0.5 * (n as f32 - 1.0)) * 0.6;
            *m = Vector3::new(across, 0.0, -barrel_m as f32);
        }
        Self::with(Vector3::ZERO, &muzzles[..n], interval_s * n as f64)
    }

    /// Barrels at `muzzles` (at most `MAX_BARRELS`; none gives one at the trunnion), every one ready.
    pub fn with(trunnion: Vector3, muzzles: &[Vector3], recharge_s: f64) -> Self {
        let mut at = [Vector3::ZERO; MAX_BARRELS];
        let count = muzzles.len().clamp(1, MAX_BARRELS);
        for (k, m) in muzzles.iter().take(MAX_BARRELS).enumerate() {
            at[k] = *m;
        }
        Self {
            trunnion,
            muzzles: at,
            count,
            recharge_s: recharge_s.max(0.0),
            ready_at: [f64::NEG_INFINITY; MAX_BARRELS],
            next: 0,
        }
    }

    /// Whether the barrel next in turn has recharged at `now_s`.
    pub fn barrel_ready(&self, now_s: f64) -> bool {
        now_s + TIME_EPSILON_S >= self.ready_at[self.next]
    }

    /// Fires the barrel next in turn at `now_s` and returns it.
    pub fn fire(&mut self, now_s: f64) -> usize {
        let b = self.next;
        self.ready_at[b] = now_s + self.recharge_s;
        self.next = (b + 1) % self.count;
        b
    }
}

/// Where a muzzle is in the World: the mount turned to `azimuth` round its up and lifted to `elevation`, as `TurretMount` turns
/// its Yaw and Pitch nodes, `trunnion` in the yaw frame and `muzzle` in the pitch frame (Godot axes: -z down the barrel).
pub fn muzzle_point(f: &tk::Frame, azimuth: f64, elevation: f64, trunnion: Vector3, muzzle: Vector3) -> Vector3 {
    let (se, ce) = elevation.sin_cos();
    let (sa, ca) = azimuth.sin_cos();
    let (mx, my, mz) = (f64::from(muzzle.x), f64::from(muzzle.y), f64::from(muzzle.z));
    let (px, py, pz) = (mx, my * ce - mz * se, my * se + mz * ce);
    let (lx, ly, lz) = (f64::from(trunnion.x) + px, f64::from(trunnion.y) + py, f64::from(trunnion.z) + pz);
    let (yx, yy, yz) = (lx * ca + lz * sa, ly, -lx * sa + lz * ca);
    // The mount's Godot basis: x opposite the frame's side, y its up, z opposite its forward.
    let along = add(scale(f.side, -yx as f32), add(scale(f.up, yy as f32), scale(f.forward, -yz as f32)));
    add(f.pivot, along)
}

/// A battery's shot (M7-T41): where the pulse leaves, its line, its flight time to the meeting, and the angles the mount shows.
pub struct BatteryShot {
    pub muzzle: Vector3,
    pub aim: Vector3,
    pub flight_s: f64,
    pub azimuth: f64,
    pub elevation: f64,
}

/// The barrel a battery fires: the arc's floor, the azimuth the mount holds now, the trunnion in the yaw frame and the muzzle in
/// the pitch frame.
pub struct Barrel {
    pub min_elevation: f64,
    pub azimuth: f64,
    pub trunnion: Vector3,
    pub muzzle: Vector3,
}

/// The azimuth and elevation that bring a barrel's line through `point` (M8-T10): a barrel beside or over the trunnion needs a
/// little more or less turn and lift than the trunnion's own line. Turning cannot bring a barrel onto a point nearer the
/// mount's axis than the barrel stands beside it (a target right overhead), so the mount keeps its azimuth there. The
/// elevation stays inside the arc.
pub fn lay_on(f: &tk::Frame, b: &Barrel, point: Vector3) -> (f64, f64) {
    let rel = sub(point, f.pivot);
    let (along, across) = (f64::from(dot(rel, f.forward)), f64::from(dot(rel, f.side)));
    let beside = f64::from(b.trunnion.x) + f64::from(b.muzzle.x);
    let flat = along.hypot(across);
    let azimuth = if flat > beside.abs() {
        let turned = across.atan2(along) + (beside / flat).asin();
        turned - std::f64::consts::TAU * (turned / std::f64::consts::TAU).round()
    } else {
        b.azimuth
    };
    let (sa, ca) = azimuth.sin_cos();
    // The point as the trunnion sees it in the plane the barrels lift in.
    let ahead = along * ca + across * sa + f64::from(b.trunnion.z);
    let above = f64::from(dot(rel, f.up)) - f64::from(b.trunnion.y);
    let over = f64::from(b.muzzle.y);
    let reach = ahead.hypot(above);
    let less = if reach > over.abs() { (over / reach).asin() } else { 0.0 };
    (azimuth, (above.atan2(ahead) - less).clamp(b.min_elevation, std::f64::consts::FRAC_PI_2))
}

/// A battery's shot at a projectile: the pulse leaves the tip of the barrel as it is drawn and, wherever the mount can turn
/// that far, along that barrel, however close the target (M8-T10). The barrel is laid through the meeting the trunnion's lead
/// gives, the pulse led from the muzzle that puts, and the barrel laid again until the muzzle settles; the pulse's line is
/// always the lead from where it starts. A lead is its line and flight time at `pulse_speed`; `lead_from` leads from a point
/// (none without a solution).
pub fn battery_shot(
    f: &tk::Frame,
    b: &Barrel,
    pulse_speed: f64,
    trunnion_lead: (Vector3, f64),
    lead_from: impl Fn(Vector3) -> Option<(Vector3, f64)>,
) -> BatteryShot {
    let lay = |from: Vector3, (aim, flight_s): (Vector3, f64)| {
        let (az, el) = lay_on(f, b, add(from, scale(aim, (pulse_speed * flight_s) as f32)));
        (az, el, muzzle_point(f, az, el, b.trunnion, b.muzzle))
    };
    let mut lead = trunnion_lead;
    let (mut azimuth, mut elevation, mut at) = lay(muzzle_point(f, b.azimuth, 0.0, b.trunnion, Vector3::ZERO), lead);
    let mut settled = false;
    for _ in 0..LAY_PASSES {
        let Some(from_muzzle) = lead_from(at) else {
            settled = true;
            break;
        };
        lead = from_muzzle;
        let was = at;
        (azimuth, elevation, at) = lay(was, lead);
        if f64::from(dist_sq(at, was)) < LAY_SETTLED_M2 {
            settled = true;
            break;
        }
    }
    if !settled && let Some(from_muzzle) = lead_from(at) {
        lead = from_muzzle;
    }
    BatteryShot {
        muzzle: at,
        aim: lead.0,
        flight_s: lead.1,
        azimuth,
        elevation,
    }
}

/// The pulses on their way to each shot this tick: the earliest few meetings their leads expect, so a shot that needs `n`
/// pulses (its hits left) is covered once `n` of them get there before it hits.
#[derive(Default)]
pub struct PulseCover {
    by_target: HashMap<i64, [f64; MAX_TOUGHNESS]>,
}

impl PulseCover {
    pub fn clear(&mut self) {
        self.by_target.clear();
    }

    /// A pulse on its way to shot `target` expects to meet it at `meet_at`.
    pub fn add(&mut self, target: i64, meet_at: f64) {
        let meets = self.by_target.entry(target).or_insert([f64::INFINITY; MAX_TOUGHNESS]);
        // Keep the earliest few, in order.
        let mut at = meet_at;
        for m in meets.iter_mut() {
            if at < *m {
                std::mem::swap(&mut at, m);
            }
        }
    }

    /// Whether `hits_left` pulses on their way meet shot `target` by `by_s`: then it needs no more.
    pub fn covered(&self, target: i64, hits_left: u8, by_s: f64) -> bool {
        let need = usize::from(hits_left.max(1)).min(MAX_TOUGHNESS);
        let key = &target;
        self.by_target.get(key).is_some_and(|meets| meets[need - 1] <= by_s)
    }
}

/// A battery's pulse in flight: the battery that fired it (the caller's index or id), the shot it was fired at and when its
/// lead said it would meet it.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Pulse {
    pub battery: i64,
    pub target: i64,
    pub meet_at: f64,
}

/// One owner's pulses in flight by bolt id, and this tick's cover from them.
#[derive(Default)]
pub struct PulseBook {
    pub pulses: HashMap<i64, Pulse>,
    pub cover: PulseCover,
    live: HashSet<i64>,
}

impl PulseBook {
    /// The pulses still flying and the cover they give at `now_s` (M7-T41). A pulse past its meeting by `COVER_SLACK_S`
    /// missed: its target is free to be shot at again. Records of pulses gone are dropped.
    pub fn refresh(&mut self, bolts: &Bolts, now_s: f64) {
        self.cover.clear();
        self.live.clear();
        for p in 0..bolts.owned.min(bolts.ids.len()) {
            if bolts.kinds[p] != KIND_INTERCEPT || bolts.spent[p] {
                continue;
            }
            let id = &bolts.ids[p];
            self.live.insert(*id);
            if let Some(info) = self.pulses.get(id)
                && now_s <= info.meet_at + COVER_SLACK_S
            {
                self.cover.add(info.target, info.meet_at);
            }
        }
        let live = &self.live;
        self.pulses.retain(|id, _| live.contains(id));
    }

    /// Whether bolt `id` is one of this owner's pulses.
    pub fn owns(&self, id: i64) -> bool {
        self.pulses.contains_key(&id)
    }
}

/// One battery as `fire_battery` reads it: its frame, the arc's floor, the angles it holds now, its barrels, its gun, its
/// velocity at the pivot and the lane its spread is hashed in.
pub struct BatteryAt<'a> {
    pub frame: tk::Frame,
    pub min_elevation: f64,
    pub azimuth: f64,
    pub elevation: f64,
    pub battery: &'a mut Battery,
    pub gun: &'a Gun,
    pub velocity: Vector3,
    pub lane: i64,
}

/// A pulse a battery fired: its barrel, where it leaves and how fast, the shot it was fired at (row and id), when its lead
/// says they meet, and the angles the mount now shows.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Fired {
    pub barrel: usize,
    pub muzzle: Vector3,
    pub velocity: Vector3,
    pub target_row: usize,
    pub target: i64,
    pub meet_at: f64,
    pub azimuth: f64,
    pub elevation: f64,
}

/// One battery's shot this tick (its barrel ready), at the best of `candidates` it can take (`choose_by` with `class`): inside
/// its arc, not covered by enough pulses on their way (`cover`, the shot's hits left less those `taken` this tick), one its
/// pulse can catch, and with its line clear (`line_clear` from the line's start to the shot). The pulse leaves the barrel's
/// muzzle on a lead course from there, thrown off by a spread hashed from `lane` and the tick; the battery's barrel is spent
/// and `cover` and `taken` count the pulse. None when nothing qualifies.
pub fn fire_battery<C, L>(
    b: &mut BatteryAt<'_>,
    bolts: &Bolts,
    candidates: &[Incoming],
    cover: &mut PulseCover,
    taken: &mut [u8],
    class: C,
    mut line_clear: L,
    now_s: f64,
    delta: f64,
    tick: i64,
) -> Option<Fired>
where
    C: Fn(&Incoming) -> u8,
    L: FnMut(Vector3, Vector3) -> bool,
{
    let f = &b.frame;
    let gun = b.gun;
    let mount_velocity = b.velocity;
    let trunnion = muzzle_point(f, b.azimuth, b.elevation, b.battery.trunnion, Vector3::ZERO);
    // A pulse does not move on its launch tick: it is led to where the target will be when it starts to fly.
    let lead_from = |from: Vector3, p: usize| {
        let ahead = add(bolts.positions[p], scale(bolts.velocities[p], delta as f32));
        solve(from, mount_velocity, ahead, bolts.velocities[p], gun.muzzle_speed, gun.lifetime_s)
    };
    let from = tk::line_start(f);
    let pick = choose_by(candidates, class, |c| {
        let p = c.bolt as usize;
        let hits = bolts.hits_left_of(p);
        if taken.get(p).copied().unwrap_or(0) >= hits {
            return false;
        }
        let at = bolts.positions[p];
        let (_, elevation) = tk::angles_of(f, normalized(sub(at, f.pivot)));
        elevation >= b.min_elevation
            && !cover.covered(bolts.ids[p], hits, now_s + c.hit_in_s)
            && lead_from(trunnion, p).ok
            && line_clear(from, at)
    })?;
    let p = pick.bolt as usize;
    if let Some(t) = taken.get_mut(p) {
        *t = t.saturating_add(1);
    }
    let barrel = b.battery.fire(now_s);
    let shot = battery_shot(
        f,
        &Barrel {
            min_elevation: b.min_elevation,
            azimuth: b.azimuth,
            trunnion: b.battery.trunnion,
            muzzle: b.battery.muzzles[barrel],
        },
        gun.muzzle_speed,
        {
            let lead = lead_from(trunnion, p);
            (lead.aim_dir, lead.t)
        },
        |from| Some(lead_from(from, p)).filter(|l| l.ok).map(|l| (l.aim_dir, l.t)),
    );
    let direction = tk::spread(shot.aim, gun.spread_rad, b.lane, tick);
    let meet_at = now_s + delta + shot.flight_s;
    cover.add(bolts.ids[p], meet_at);
    Some(Fired {
        barrel,
        muzzle: shot.muzzle,
        velocity: add(mount_velocity, scale(direction, gun.muzzle_speed as f32)),
        target_row: p,
        target: bolts.ids[p],
        meet_at,
        azimuth: shot.azimuth,
        elevation: shot.elevation,
    })
}

/// When along the tick two spheres moving in straight lines first touch, as a share of the tick (0 to 1): `a` from `a_start`
/// by `a_step`, `b` likewise, their radii summed `reach`; none when they stay apart.
pub fn first_touch(a_start: Vector3, a_step: Vector3, b_start: Vector3, b_step: Vector3, reach: f64) -> Option<f64> {
    let d = sub(a_start, b_start);
    let v = sub(a_step, b_step);
    let (dx, dy, dz) = (f64::from(d.x), f64::from(d.y), f64::from(d.z));
    let (vx, vy, vz) = (f64::from(v.x), f64::from(v.y), f64::from(v.z));
    let c = dx * dx + dy * dy + dz * dz - reach * reach;
    if c <= 0.0 {
        return Some(0.0);
    }
    let a = vx * vx + vy * vy + vz * vz;
    let b = dx * vx + dy * vy + dz * vz;
    if a <= 0.0 || b >= 0.0 {
        return None;
    }
    let disc = b * b - a * c;
    if disc < 0.0 {
        return None;
    }
    let t = (-b - disc.sqrt()) / a;
    (t <= 1.0).then_some(t.max(0.0))
}

/// A pulse that met a shot this tick: both bolt rows, where along the tick (0 to 1), and whether that was the shot's last hit.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PulseHit {
    pub pulse: u32,
    pub target: u32,
    pub t: f64,
    pub downed: bool,
}

/// The pulse sweep's reused buffers.
#[derive(Default)]
pub struct PulseScratch {
    targets: Vec<u32>,
    mids: Vec<Vector3>,
    reach: Vec<f64>,
    candidates: Vec<u32>,
    left: Vec<u8>,
    pub cells: CellGrid,
}

/// This tick's pulse hits (M7-T41, Q81), in pulse row order: each live pulse `mine` accepts takes the first live shot that
/// `hostile(pulse, shot)` accepts and its swept sphere touches along the bolts' last move (the earliest touch; among equals the
/// lower row). A shot takes as many pulses as it has hits left; the one that takes its last downs it. The shots are placed in
/// the hit broad phase's cells, so a pulse tests only those near it.
pub fn pulse_hits_by<M, H>(bolts: &Bolts, mine: M, hostile: H, scratch: &mut PulseScratch, out: &mut Vec<PulseHit>)
where
    M: Fn(usize) -> bool,
    H: Fn(usize, usize) -> bool,
{
    out.clear();
    let n = bolts.ids.len();
    let live_pulse = |p: usize| bolts.kinds[p] == KIND_INTERCEPT && !bolts.spent[p] && mine(p);
    if !(0..n).any(live_pulse) {
        return;
    }
    let s = scratch;
    s.targets.clear();
    s.mids.clear();
    s.reach.clear();
    s.left.clear();
    for p in 0..n {
        if !is_shot(bolts, p) {
            continue;
        }
        let step = bolts.last_steps[p];
        s.targets.push(p as u32);
        s.mids.push(sub(bolts.positions[p], scale(step, 0.5)));
        s.reach.push(f64::from(length(step)) * 0.5 + bolts.radii[p]);
        s.left.push(bolts.hits_left_of(p));
    }
    if s.targets.is_empty() {
        return;
    }
    s.cells.place(&s.mids, &s.reach);
    for p in 0..n {
        if !live_pulse(p) {
            continue;
        }
        let step = bolts.last_steps[p];
        let start = sub(bolts.positions[p], step);
        let mid = sub(bolts.positions[p], scale(step, 0.5));
        s.cells.look(mid, f64::from(length(step)) * 0.5 + bolts.radii[p], &mut s.candidates);
        let mut best: Option<(f64, usize)> = None;
        for &j in &s.candidates {
            let j = j as usize;
            let q = s.targets[j] as usize;
            if s.left[j] == 0 || !hostile(p, q) {
                continue;
            }
            let q_step = bolts.last_steps[q];
            let q_start = sub(bolts.positions[q], q_step);
            let Some(t) = first_touch(start, step, q_start, q_step, bolts.radii[p] + bolts.radii[q]) else {
                continue;
            };
            if best.is_none_or(|(bt, bj)| t < bt || (t == bt && j < bj)) {
                best = Some((t, j));
            }
        }
        if let Some((t, j)) = best {
            s.left[j] -= 1;
            out.push(PulseHit {
                pulse: p as u32,
                target: s.targets[j],
                t,
                downed: s.left[j] == 0,
            });
        }
    }
}

/// Where pulse hit `h` met its shot (along the pulse's last move).
pub fn meeting_point(bolts: &Bolts, h: &PulseHit) -> Vector3 {
    let p = h.pulse as usize;
    let step = bolts.last_steps[p];
    add(sub(bolts.positions[p], step), scale(step, h.t as f32))
}

/// Lands this tick's pulse hits on the bolts: every pulse spent, each shot one hit fewer, and spent once it has none left.
pub fn apply_hits(bolts: &mut Bolts, hits: &[PulseHit]) {
    for h in hits {
        let (p, q) = (h.pulse as usize, h.target as usize);
        bolts.spent[p] = true;
        let left = bolts.hits_left_of(q).saturating_sub(1);
        bolts.set_hits_left(q, left);
        if h.downed || left == 0 {
            bolts.spent[q] = true;
        }
    }
}

#[cfg(test)]
mod tests;
