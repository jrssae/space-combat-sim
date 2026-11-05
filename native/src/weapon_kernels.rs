//! The weapon kernels (M4-T20, docs/architecture.md 17.13): a gun's target pick, aim step and fire gate, an interceptor's
//! pick, a capital's strike target, a missile's guidance and a mine's trigger and blast, over the core's rows, with no
//! engine type in this file. Each repeats its GDScript stand-in's arithmetic (32-bit vectors, 64-bit scalars, the engine's
//! order of operations), so both paths give the same bits. Every kernel is a pure function of the frozen rows and one
//! row's inputs: it writes only the outputs its caller passes, holds no statics and caches nothing between calls, so T18 can
//! run them per row across threads. `test_sim_core` reads this file and fails on any engine type.
#![allow(clippy::too_many_arguments)]
// `!(a > b)` is kept where the GDScript writes it: a NaN must fall the same way on both paths.
#![allow(clippy::neg_cmp_op_on_partial_ord)]

use std::f64::consts::PI;

use godot::builtin::{Basis, Vector3};

use crate::rows::{Bolts, FLAG_HULL_ACTIVE, FLAG_RIGID, Rows};

// `TurretStandin`'s constants.
const RANGE_M: f64 = 4000.0;
const INTERCEPT_RANGE_M: f64 = 1500.0;
const TURN_RATE_RAD_S: f64 = PI / 6.0;
const GATE_RAD: f64 = 1.5 * PI / 180.0;
const FIGHTER_RADIUS_MAX_M: f64 = 50.0;
const MUZZLE_SPEED_MPS: f64 = 1000.0;
const BOLT_LIFETIME_S: f64 = 4.2;
const MUZZLE_OFFSET_M: f32 = 4.0;
/// `TurretStandin.RETARGET_TICKS`.
pub const RETARGET_TICKS: i64 = 6;
/// `TurretStandin.SHOT_INTERVAL_S`: the gun's gate, one muzzle.
pub const SHOT_INTERVAL_S: f64 = 1.0;
// `PulseCannonGate.TIME_EPSILON_S`.
const TIME_EPSILON_S: f64 = 1e-6;
// `InterceptMath.LINEAR_EPSILON`.
const LINEAR_EPSILON: f64 = 1e-9;
/// `BeamStandin.RANGE_M`.
pub const BEAM_RANGE_M: f64 = 3000.0;
// `MissileStandin.RANGE_M`: a capital's strike reach.
const STRIKE_RANGE_M: f64 = 6000.0;
/// `StandinDirector.STRIKE_RETARGET_TICKS`.
pub const STRIKE_RETARGET_TICKS: i64 = 30;
// `MineStandin`'s constants.
const TRIGGER_RADIUS_M: f64 = 50.0;
const BLAST_RADIUS_M: f64 = 100.0;
/// `MineStandin.TRIGGER_TICKS`.
pub const TRIGGER_TICKS: i64 = 3;
// The mines' grid cell, m, and the room added round a hull's look so a mine the exact test takes is never missed.
const MINE_CELL_M: f64 = 200.0;
const PAD_REL: f64 = 1e-6;
const PAD_M: f64 = 1.0;
// The core's `KIND_*` values the kernels tell apart.
const KIND_MISSILE: u8 = 3;
const KIND_BEAM: u8 = 8;

/// A turret's role: a gun, an interceptor, or a beam emitter.
pub const ROLE_GUN: u8 = 0;
pub const ROLE_INTERCEPTOR: u8 = 1;
pub const ROLE_BEAM: u8 = 2;

/// Every turret of the bound capitals, in the director's order (capital by capital: guns, interceptors, beams), with the
/// state the GDScript keeps on each `TurretStandin`.
#[derive(Default)]
pub struct Turrets {
    pub capital: Vec<u32>,
    pub local: Vec<Vector3>,
    pub role: Vec<u8>,
    pub axis: Vec<Vector3>,
    pub target: Vec<i64>,
    pub aim_error: Vec<f64>,
    pub ready_at: Vec<f64>,
    pub shots: Vec<i64>,
    pub missile_shots: Vec<i64>,
}

/// The bound capitals in the director's order (a freed one keeps its place with body id 0) and their strike state: the
/// held target and the tick it was looked up (`known` false until the first lookup), and whose turn it is to launch.
#[derive(Default)]
pub struct Capitals {
    pub body_ids: Vec<i64>,
    pub strike_target: Vec<i64>,
    pub strike_tick: Vec<i64>,
    pub strike_known: Vec<bool>,
    pub turn: i64,
}

/// The mines: their offsets from the belt's node, layers (core faction indices), whether each is in play, and a grid of
/// the offsets built once when they are laid.
#[derive(Default)]
pub struct Mines {
    pub local: Vec<Vector3>,
    pub faction_ix: Vec<u32>,
    pub alive: Vec<bool>,
    pub cells: Vec<((i32, i32, i32), u32)>,
}

/// An interceptor's candidate: a projectile in reach and hostile, whether it is a missile, and its squared distance.
#[derive(Clone, Copy)]
pub struct Candidate {
    pub bolt: u32,
    pub missile: bool,
    pub d_sq: f64,
}

/// A gun's aim after one step: its new axis and how far off the lead point it is.
pub struct Aim {
    pub axis: Vector3,
    pub aim_error: f64,
}

/// A turret's place in the World frame: its capital's transform applied to its offset, as the engine composes a child's
/// global transform.
pub fn turret_at(basis: &Basis, origin: Vector3, local: Vector3) -> Vector3 {
    Vector3::new(
        dot(basis.rows[0], local) + origin.x,
        dot(basis.rows[1], local) + origin.y,
        dot(basis.rows[2], local) + origin.z,
    )
}

/// The rows a gun may pick from (the scan's ships of fighter size, never a rock or mine), in scan order.
pub fn fighter_rows(rows: &Rows, out: &mut Vec<u32>) {
    out.clear();
    for i in 0..rows.body_ids.len() {
        if !rows.is_static[i]
            && rows.flags[i] & FLAG_RIGID != 0
            && rows.radii[i] <= FIGHTER_RADIUS_MAX_M
        {
            out.push(i as u32);
        }
    }
}

/// `TurretStandin.retarget`: the nearest hostile fighter within reach of `at` among `fighters`, not `own_body`, as a body
/// id (0 for none). `hostile` is the capital's row of the hostility table; equal distances go to the earlier row.
pub fn retarget(
    rows: &Rows,
    fighters: &[u32],
    hostile: &[bool],
    own_body: i64,
    at: Vector3,
) -> i64 {
    let range_sq = RANGE_M * RANGE_M;
    let mut best_sq = range_sq;
    let mut best = 0;
    for &i in fighters {
        let j = i as usize;
        if rows.body_ids[j] == own_body || !flagged(hostile, rows.faction_ix[j]) {
            continue;
        }
        let d_sq = f64::from(dist_sq(rows.positions[j], at));
        if d_sq <= range_sq && d_sq < best_sq {
            best_sq = d_sq;
            best = rows.body_ids[j];
        }
    }
    best
}

/// Whether a gun at `at` still holds a target at `target_at` (within its reach).
pub fn in_reach(at: Vector3, target_at: Vector3) -> bool {
    f64::from(dist_sq(target_at, at)) <= RANGE_M * RANGE_M
}

/// `TurretStandin.step_gun`'s aim: the axis turned toward the lead point at the turn rate and the aim error after, or
/// `None` when there is no direction to aim along (the GDScript leaves the gun as it was).
pub fn aim_gun(
    at: Vector3,
    capital_velocity: Vector3,
    target_at: Vector3,
    target_velocity: Vector3,
    axis: Vector3,
    delta: f64,
) -> Option<Aim> {
    let (wanted, _) = solve(
        at,
        capital_velocity,
        target_at,
        target_velocity,
        MUZZLE_SPEED_MPS,
        BOLT_LIFETIME_S,
    );
    if f64::from(length_squared(wanted)) < 0.5 {
        return None;
    }
    let turned = turned_toward(axis, wanted, TURN_RATE_RAD_S * delta);
    Some(Aim {
        axis: turned,
        aim_error: f64::from(angle_to(turned, wanted)),
    })
}

/// Whether an aim error lets the gun fire (the gate's trigger).
pub fn on_target(aim_error: f64) -> bool {
    aim_error <= GATE_RAD
}

/// `PulseCannonGate.update` for one muzzle with no capacitor: whether it fires at `now`, and the next ready time.
pub fn gate(ready_at: f64, now: f64, held: bool, interval: f64) -> (bool, f64) {
    // The longest wait is the interval times the muzzles: one muzzle here.
    let ready = minf(ready_at, now + interval);
    if !held || now + TIME_EPSILON_S < ready {
        return (false, ready);
    }
    (true, now + interval)
}

/// Where a gun's bolt leaves and how fast: `TurretStandin.step_gun`'s launch.
pub fn muzzle(at: Vector3, capital_velocity: Vector3, axis: Vector3) -> (Vector3, Vector3) {
    (
        add(at, scale(axis, MUZZLE_OFFSET_M)),
        add(capital_velocity, scale(axis, MUZZLE_SPEED_MPS as f32)),
    )
}

/// How many projectiles fly that an interceptor could take (every kind but beams).
pub fn shots_in_flight(bolts: &Bolts) -> usize {
    bolts.kinds.iter().filter(|&&k| k != KIND_BEAM).count()
}

/// How many guided missiles fly.
pub fn missiles_in_flight(bolts: &Bolts) -> usize {
    bolts.kinds.iter().filter(|&&k| k == KIND_MISSILE).count()
}

/// An interceptor's candidates at `at`: every projectile but beams within its reach whose faction `hostile` marks (the
/// capital's row of the table), in bolt order.
pub fn intercept_candidates(
    bolts: &Bolts,
    hostile: &[bool],
    at: Vector3,
    out: &mut Vec<Candidate>,
) {
    out.clear();
    let reach_sq = INTERCEPT_RANGE_M * INTERCEPT_RANGE_M;
    for p in 0..bolts.ids.len() {
        if bolts.kinds[p] == KIND_BEAM || !flagged(hostile, bolts.faction_ix[p]) {
            continue;
        }
        let d_sq = f64::from(dist_sq(bolts.positions[p], at));
        if d_sq > reach_sq {
            continue;
        }
        out.push(Candidate {
            bolt: p as u32,
            missile: bolts.kinds[p] == KIND_MISSILE,
            d_sq,
        });
    }
}

/// `TurretStandin.step_interceptor`'s pick among `candidates` not yet `spent` this tick: the nearest missile, else the
/// nearest bolt; among equals the later one.
pub fn intercept_pick(candidates: &[Candidate], spent: &[bool]) -> Option<Candidate> {
    let mut best: Option<Candidate> = None;
    let mut best_sq = f64::INFINITY;
    let mut best_missile = false;
    for c in candidates {
        if spent[c.bolt as usize] {
            continue;
        }
        if (c.missile && !best_missile) || (c.missile == best_missile && c.d_sq <= best_sq) {
            best = Some(*c);
            best_sq = c.d_sq;
            best_missile = c.missile;
        }
    }
    best
}

/// `StandinDirector._nearest_hostile_fighter`: the nearest hostile hull of fighter size within a missile's reach of a
/// capital at `at`, among the rigid active hulls in `hull_rows`' order, as a body id (0 for none).
pub fn strike_target(rows: &Rows, hull_rows: &[u32], hostile: &[bool], at: Vector3) -> i64 {
    let mut best_sq = STRIKE_RANGE_M * STRIKE_RANGE_M;
    let mut best = 0;
    for &r in hull_rows {
        let j = r as usize;
        if rows.flags[j] & FLAG_RIGID == 0 || rows.radii[j] > FIGHTER_RADIUS_MAX_M {
            continue;
        }
        let d_sq = f64::from(dist_sq(rows.positions[j], at));
        if d_sq > best_sq {
            continue;
        }
        if flagged(hostile, rows.faction_ix[j]) {
            best_sq = d_sq;
            best = rows.body_ids[j];
        }
    }
    best
}

/// Whether a held strike target at `target_at` is still within a missile's reach of its capital at `at`.
pub fn in_strike_reach(target_at: Vector3, at: Vector3) -> bool {
    f64::from(dist_sq(target_at, at)) <= STRIKE_RANGE_M * STRIKE_RANGE_M
}

/// Whether a beam emitter at `at` reaches a target at `target_at`.
pub fn in_beam_reach(target_at: Vector3, at: Vector3) -> bool {
    f64::from(dist_sq(target_at, at)) <= BEAM_RANGE_M * BEAM_RANGE_M
}

/// `MissileStandin.steer`: proportional navigation for one tick, the velocity turned toward `nav_gain` times the line of
/// sight's turn by at most `max_turn_rate`, at the same speed; straight on once the target is behind or on top of it.
pub fn steer(
    position: Vector3,
    velocity: Vector3,
    target_position: Vector3,
    target_velocity: Vector3,
    nav_gain: f64,
    max_turn_rate: f64,
    delta: f64,
) -> Vector3 {
    let speed = f64::from(length(velocity));
    let line = sub(target_position, position);
    let range_sq = f64::from(length_squared(line));
    if speed < 1e-6 || range_sq < 1e-6 {
        return velocity;
    }
    let closing = sub(target_velocity, velocity);
    if f64::from(dot(line, closing)) >= 0.0 {
        return velocity;
    }
    let line_turn = div_s(cross(line, closing), range_sq as f32);
    let wanted = add(
        velocity,
        scale(
            scale(cross(line_turn, velocity), nav_gain as f32),
            delta as f32,
        ),
    );
    if f64::from(length_squared(wanted)) < 1e-12 {
        return velocity;
    }
    let turned = turned_toward(
        div_s(velocity, speed as f32),
        normalized(wanted),
        max_turn_rate * delta,
    );
    scale(turned, speed as f32)
}

/// The mines' grid over their offsets, sorted by cell then by mine.
pub fn mine_cells(local: &[Vector3]) -> Vec<((i32, i32, i32), u32)> {
    let mut cells: Vec<((i32, i32, i32), u32)> = local
        .iter()
        .enumerate()
        .map(|(i, p)| {
            let key = (
                cell_of(f64::from(p.x)),
                cell_of(f64::from(p.y)),
                cell_of(f64::from(p.z)),
            );
            (key, i as u32)
        })
        .collect();
    cells.sort_unstable();
    cells
}

/// `MineStandin.triggers` from one hull's side: the mines checking this tick (`phase`, the tick modulo the cadence) and
/// in play whose layer `hostile` marks (the hull's column of the table, by mine faction) and whose trigger the hull's
/// sphere (`hull_at`, `hull_reach`) comes inside, with the belt's node at `origin`. Appends them to `out`.
pub fn mine_hits(
    mines: &Mines,
    phase: usize,
    origin: Vector3,
    hull_at: Vector3,
    hull_reach: f64,
    hostile: &[bool],
    out: &mut Vec<u32>,
) {
    let reach = TRIGGER_RADIUS_M + hull_reach;
    let pad = reach.abs() * (1.0 + PAD_REL) + PAD_M;
    let rel = |h: f32, o: f32| f64::from(h) - f64::from(o);
    let (rx, ry, rz) = (
        rel(hull_at.x, origin.x),
        rel(hull_at.y, origin.y),
        rel(hull_at.z, origin.z),
    );
    if !(rx.is_finite() && ry.is_finite() && rz.is_finite() && pad.is_finite()) {
        return;
    }
    let (lx, ly, lz) = (cell_of(rx - pad), cell_of(ry - pad), cell_of(rz - pad));
    let (hx, hy, hz) = (cell_of(rx + pad), cell_of(ry + pad), cell_of(rz + pad));
    let cells = &mines.cells;
    for cx in lx..=hx {
        for cy in ly..=hy {
            let start = cells.partition_point(|e| e.0 < (cx, cy, lz));
            let end = cells.partition_point(|e| e.0 <= (cx, cy, hz));
            for e in &cells[start..end] {
                let i = e.1 as usize;
                if i % TRIGGER_TICKS as usize != phase
                    || !mines.alive[i]
                    || !flagged(hostile, mines.faction_ix[i])
                {
                    continue;
                }
                let at = add(origin, mines.local[i]);
                if f64::from(dist_sq(hull_at, at)) <= reach * reach {
                    out.push(e.1);
                }
            }
        }
    }
}

/// `MineStandin.blast`: the rigid active hulls (in `hull_rows`' order) whose spheres lie within the blast of a mine at
/// `at`, as rows, appended to `out`.
pub fn blast(rows: &Rows, hull_rows: &[u32], at: Vector3, out: &mut Vec<u32>) {
    for &r in hull_rows {
        let j = r as usize;
        if rows.flags[j] & FLAG_RIGID == 0 || rows.flags[j] & FLAG_HULL_ACTIVE == 0 {
            continue;
        }
        let reach = BLAST_RADIUS_M + rows.radii[j];
        if f64::from(dist_sq(rows.positions[j], at)) <= reach * reach {
            out.push(r);
        }
    }
}

/// `InterceptMath.solve`'s aim: the unit direction to fire along and whether a meeting exists within `max_time`; without
/// one, the line of sight (zero on top of the shooter).
pub fn solve(
    shooter_pos: Vector3,
    shooter_vel: Vector3,
    target_pos: Vector3,
    target_vel: Vector3,
    bolt_speed: f64,
    max_time: f64,
) -> (Vector3, bool) {
    let rx = f64::from(target_pos.x) - f64::from(shooter_pos.x);
    let ry = f64::from(target_pos.y) - f64::from(shooter_pos.y);
    let rz = f64::from(target_pos.z) - f64::from(shooter_pos.z);
    let ux = f64::from(target_vel.x) - f64::from(shooter_vel.x);
    let uy = f64::from(target_vel.y) - f64::from(shooter_vel.y);
    let uz = f64::from(target_vel.z) - f64::from(shooter_vel.z);
    let rr = rx * rx + ry * ry + rz * rz;
    let t = meeting_time(
        rr,
        rx * ux + ry * uy + rz * uz,
        ux * ux + uy * uy + uz * uz,
        bolt_speed,
    );
    if !(t > 0.0 && t <= max_time) {
        if rr > 0.0 {
            let length = rr.sqrt();
            return (
                Vector3::new(
                    (rx / length) as f32,
                    (ry / length) as f32,
                    (rz / length) as f32,
                ),
                false,
            );
        }
        return (Vector3::new(0.0, 0.0, 0.0), false);
    }
    let st = bolt_speed * t;
    let dx = (rx + ux * t) / st;
    let dy = (ry + uy * t) / st;
    let dz = (rz + uz * t) / st;
    let length = (dx * dx + dy * dy + dz * dz).sqrt();
    (
        Vector3::new(
            (dx / length) as f32,
            (dy / length) as f32,
            (dz / length) as f32,
        ),
        true,
    )
}

/// `TurretStandin.turned_toward`: `from` turned toward `wanted` by at most `max_angle`, both unit vectors.
pub fn turned_toward(from: Vector3, wanted: Vector3, max_angle: f64) -> Vector3 {
    let angle = f64::from(angle_to(from, wanted));
    if angle <= max_angle {
        return wanted;
    }
    let mut turn_axis = cross(from, wanted);
    if f64::from(length_squared(turn_axis)) < 1e-12 {
        let up = Vector3::new(0.0, 1.0, 0.0);
        let other = if f64::from(dot(from, up)).abs() < 0.9 {
            up
        } else {
            Vector3::new(1.0, 0.0, 0.0)
        };
        turn_axis = cross(from, other);
    }
    normalized(rotated(from, normalized(turn_axis), max_angle as f32))
}

/// `Vector3.angle_to`, in 32 bits as the engine computes it.
pub fn angle_to(a: Vector3, b: Vector3) -> f32 {
    length(cross(a, b)).atan2(dot(a, b))
}

// `InterceptMath._meeting_time`: the smallest positive root of (uu - s²) t² + 2 ru t + rr = 0, or -1.
fn meeting_time(rr: f64, ru: f64, uu: f64, bolt_speed: f64) -> f64 {
    if !(bolt_speed > 0.0) || !(rr > 0.0) {
        return -1.0;
    }
    let qa = uu - bolt_speed * bolt_speed;
    let qb = 2.0 * ru;
    if qa.abs() <= LINEAR_EPSILON * bolt_speed * bolt_speed {
        return if qb < 0.0 { -rr / qb } else { -1.0 };
    }
    let disc = qb * qb - 4.0 * qa * rr;
    if !(disc >= 0.0) {
        return -1.0;
    }
    let root = disc.sqrt();
    let q = -0.5 * (if qb >= 0.0 { qb + root } else { qb - root });
    if q == 0.0 {
        return -1.0;
    }
    let mut best = -1.0;
    for candidate in [q / qa, rr / q] {
        if candidate > 0.0 && (best < 0.0 || candidate < best) {
            best = candidate;
        }
    }
    best
}

// Whether faction `index` is flagged in `row`; a row too short says no.
fn flagged(row: &[bool], index: u32) -> bool {
    row.get(index as usize).copied().unwrap_or(false)
}

// The mines' grid cell holding coordinate `v`.
fn cell_of(v: f64) -> i32 {
    (v / MINE_CELL_M).floor() as i32
}

// `Vector3.rotated(axis, angle)`: the engine's axis-angle basis applied to `v`, in 32 bits.
fn rotated(v: Vector3, axis: Vector3, angle: f32) -> Vector3 {
    let (x, y, z) = (axis.x, axis.y, axis.z);
    let sq = Vector3::new(x * x, y * y, z * z);
    let cosine = angle.cos();
    let r00 = sq.x + cosine * (1.0 - sq.x);
    let r11 = sq.y + cosine * (1.0 - sq.y);
    let r22 = sq.z + cosine * (1.0 - sq.z);
    let sine = angle.sin();
    let t = 1.0 - cosine;
    let (xyzt, zyxs) = (x * y * t, z * sine);
    let (r01, r10) = (xyzt - zyxs, xyzt + zyxs);
    let (xyzt, zyxs) = (x * z * t, y * sine);
    let (r02, r20) = (xyzt + zyxs, xyzt - zyxs);
    let (xyzt, zyxs) = (y * z * t, x * sine);
    let (r12, r21) = (xyzt - zyxs, xyzt + zyxs);
    Vector3::new(
        dot(Vector3::new(r00, r01, r02), v),
        dot(Vector3::new(r10, r11, r12), v),
        dot(Vector3::new(r20, r21, r22), v),
    )
}

// Godot's Vector3 maths in 32 bits, in the engine's order of operations.
fn add(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x + b.x, a.y + b.y, a.z + b.z)
}

fn sub(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(a.x - b.x, a.y - b.y, a.z - b.z)
}

fn scale(a: Vector3, s: f32) -> Vector3 {
    Vector3::new(a.x * s, a.y * s, a.z * s)
}

fn div_s(a: Vector3, s: f32) -> Vector3 {
    Vector3::new(a.x / s, a.y / s, a.z / s)
}

fn dot(a: Vector3, b: Vector3) -> f32 {
    a.x * b.x + a.y * b.y + a.z * b.z
}

fn cross(a: Vector3, b: Vector3) -> Vector3 {
    Vector3::new(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    )
}

fn length_squared(a: Vector3) -> f32 {
    let x2 = a.x * a.x;
    let y2 = a.y * a.y;
    let z2 = a.z * a.z;
    x2 + y2 + z2
}

fn length(a: Vector3) -> f32 {
    length_squared(a).sqrt()
}

fn normalized(a: Vector3) -> Vector3 {
    let length_sq = length_squared(a);
    if length_sq == 0.0 {
        return Vector3::new(0.0, 0.0, 0.0);
    }
    let l = length_sq.sqrt();
    Vector3::new(a.x / l, a.y / l, a.z / l)
}

// `a.distance_squared_to(b)`.
fn dist_sq(a: Vector3, b: Vector3) -> f32 {
    length_squared(sub(b, a))
}

// Godot's `minf`: `a < b ? a : b`.
fn minf(a: f64, b: f64) -> f64 {
    if a < b { a } else { b }
}
