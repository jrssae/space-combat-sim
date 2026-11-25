// A fighter's attack runs on a capital ship (M10-T16, D12.10): it sets up out where the capital's arcs cover least (its
// beams weighed most), re-planned every couple of seconds; runs in on a subsystem (a mount covering the approach, then the
// interceptors, the engines, the bays), firing from 1 500 m down to 400 m; breaks off across the nearest beam's arc; opens to
// 3 km; and sets up again. A squadron that lost half its ships (`capital_abort`) regroups 5 km off instead. The gun run
// itself is the attack's own (`AttackBrainState`), held to the run's ranges.
use godot::builtin::Vector3;

use crate::brain_maths::{self, FlightCmd, Pcg, hash_seed};
use crate::capital_brain::attitude::DIRECTIONS;
use crate::capital_brain::{
    BrainMount, CapitalSpec, MOUNT_BEAM, MOUNT_LAUNCHER, POINT_BAY, POINT_ENGINE, ROLE_AC, ROLE_AF, ROLE_DUAL, ROLE_PD,
    RunTuning,
};
use crate::surface;
use crate::v3::{add, cross, dist_sq, dot, length, normalized, scale, sub, xform, xform_inv};

use super::{AttackBrainState, Ship, Tick, Wish, detour, seek_velocity};

/// The legs of a run (`LEG_NAMES`).
pub const LEG_SETUP: u8 = 0;
pub const LEG_INBOUND: u8 = 1;
pub const LEG_BREAK: u8 = 2;
pub const LEG_OPEN: u8 = 3;
pub const LEG_REGROUP: u8 = 4;
pub const LEG_NAMES: [&str; 5] = ["setup", "inbound", "break", "open", "regroup"];

/// `BodyKind.CAPITAL`.
pub const KIND_CAPITAL: u8 = 1;

// How much a mount's arc counts against an approach through it: a beam most, then the anti-fighter guns.
fn coverage_weight(m: &BrainMount) -> f64 {
    if !m.works || m.role == ROLE_PD {
        return 0.0;
    }
    match (m.kind, m.role) {
        (MOUNT_BEAM, _) => 3.0,
        (_, ROLE_AF) => 1.5,
        (_, ROLE_DUAL) => 1.0,
        (MOUNT_LAUNCHER, _) => 0.5,
        (_, ROLE_AC) => 0.5,
        _ => 0.5,
    }
}

// The set-up point is reached within this, m; the run turns in from up to this far off the planned line, rad (cos).
const SETUP_REACHED_M: f64 = 500.0;
const ON_LINE_COS: f32 = 0.9;
// The share of the arcs' weight a way round costs, and of a random tie-break per run, so a squadron spreads its runs.
const TRAVEL_COST: f64 = 0.15;
const JITTER: f64 = 0.1;
// The slowest a set-up or regroup closes on its point, m/s, and over how long it meets the distance, s.
const SETUP_MIN_MPS: f64 = 20.0;
const ARRIVE_S: f64 = 3.0;

/// One fighter's runs on its capital target.
pub struct CapitalRun {
    pub leg: u8,
    target_id: i64,
    plan_s: f64,
    leg_s: f64,
    /// The way in, in the capital's frame (unit), and the point aimed at there.
    pub dir_local: Vector3,
    pub aim_local: Option<Vector3>,
    break_dir: Vector3,
    pub runs: i64,
    seed: i64,
    rng: Pcg,
    pub goal: Vector3,
    pub firing: bool,
    pub last_range_m: f64,
}

impl CapitalRun {
    pub fn new(seed: i64) -> Self {
        CapitalRun {
            leg: LEG_SETUP,
            target_id: 0,
            plan_s: 0.0,
            leg_s: 0.0,
            dir_local: Vector3::new(0.0, 0.0, -1.0),
            aim_local: None,
            break_dir: Vector3::ZERO,
            runs: 0,
            seed,
            rng: Pcg::seeded(hash_seed(seed, "capital runs")),
            goal: Vector3::ZERO,
            firing: false,
            last_range_m: f64::INFINITY,
        }
    }

    /// A new target, or the brain's reset: the run starts over from its set-up, planned at once.
    pub fn restart(&mut self, target_id: i64) {
        self.leg = LEG_SETUP;
        self.target_id = target_id;
        self.plan_s = f64::INFINITY;
        self.leg_s = 0.0;
        self.runs = 0;
        self.rng = Pcg::seeded(hash_seed(self.seed, "capital runs"));
        self.firing = false;
        self.last_range_m = f64::INFINITY;
    }

    /// One think of the run on capital `spec` at row `t` (its marker `target_id`): the flight into `cmd`; whether the trigger
    /// is held. `abort`: the squadron lost half its ships, so it regroups off the capital and holds its fire.
    #[allow(clippy::too_many_arguments)]
    pub fn engage(
        &mut self,
        tick: &Tick,
        ship: &Ship,
        gun: &mut AttackBrainState,
        spec: &CapitalSpec,
        t: usize,
        target_id: i64,
        runs: &RunTuning,
        abort: bool,
        dt: f64,
        cmd: &mut FlightCmd,
        wish: &mut Wish,
    ) -> bool {
        if target_id != self.target_id {
            self.restart(target_id);
        }
        self.firing = false;
        self.plan_s += dt;
        self.leg_s += dt;
        let rows = tick.rows;
        let (centre, basis, radius) = (rows.positions[t], rows.bases[t], rows.radii[t]);
        let p = &tick.p;
        let from_centre = sub(p.position, centre);
        let range_m = f64::from(length(from_centre));
        self.last_range_m = range_m;
        let target_v = rows.velocities[t];
        let out_dir = if range_m > 1e-3 { normalized(from_centre) } else { Vector3::new(0.0, 1.0, 0.0) };
        if abort {
            self.enter(LEG_REGROUP);
        } else if self.leg == LEG_REGROUP {
            self.enter(LEG_OPEN);
        }
        if self.leg == LEG_SETUP && self.plan_s >= runs.replan_s {
            self.plan(spec, xform_inv(&basis, out_dir));
        }
        match self.leg {
            LEG_SETUP => {
                let world_dir = normalized(xform(&basis, self.dir_local));
                let setup_m = runs.open_m + radius;
                self.goal = add(centre, scale(world_dir, setup_m as f32));
                let to_goal = sub(self.goal, p.position);
                let d = f64::from(length(to_goal));
                let on_line = dot(out_dir, world_dir) > ON_LINE_COS && range_m < setup_m + SETUP_REACHED_M;
                if d < SETUP_REACHED_M || on_line {
                    self.enter(LEG_INBOUND);
                } else {
                    self.fly_to(tick, ship, self.goal, target_v, d, gun.tactics.closing_far_mps, cmd, wish);
                    return false;
                }
            }
            LEG_REGROUP => {
                self.goal = add(centre, scale(out_dir, (runs.regroup_m + radius) as f32));
                let d = f64::from(length(sub(self.goal, p.position)));
                self.fly_to(tick, ship, self.goal, target_v, d, gun.tactics.closing_far_mps, cmd, wish);
                return false;
            }
            _ => {}
        }
        let aim_point = match self.aim_local {
            Some(local) => add(centre, xform(&basis, local)),
            None => surface::nearest_of_row(rows, t, p.position).map_or(centre, |(at, _)| at),
        };
        let gap = f64::from(length(sub(aim_point, p.position)));
        match self.leg {
            LEG_INBOUND => {
                if gap < runs.fire_to_m {
                    self.enter_break(tick, spec, t, aim_point);
                } else {
                    // The attack's own gun run on the point, held to the run's ranges: it fires inside `fire_from_m` and
                    // breaks at `fire_to_m`.
                    if gun.state != AttackBrainState::APPROACH {
                        gun.restart();
                    }
                    let held = gun.tactics;
                    gun.tactics.fire_range_m = held.fire_range_m.max(runs.fire_from_m);
                    gun.tactics.break_range_m = runs.fire_to_m;
                    gun.tactics.max_time_on_target_s = f64::INFINITY;
                    let v_point = tick.velocity_at(t, aim_point);
                    self.goal = aim_point;
                    self.firing = gun.engage(tick, ship, target_id, aim_point, v_point, 0.0, dt, cmd, wish);
                    gun.tactics = held;
                    if gun.state != AttackBrainState::APPROACH {
                        self.enter_break(tick, spec, t, aim_point);
                    }
                    return self.firing;
                }
            }
            LEG_BREAK => {
                if self.leg_s >= gun.tactics.break_duration_s.max(1.0) || gap > runs.fire_from_m {
                    self.enter(LEG_OPEN);
                }
            }
            LEG_OPEN if range_m > runs.open_m + radius => {
                self.runs += 1;
                self.enter(LEG_SETUP);
                self.plan_s = f64::INFINITY;
            }
            _ => {}
        }
        let away = if self.leg == LEG_BREAK { self.break_dir } else { out_dir };
        let speed = if self.leg == LEG_BREAK { gun.tactics.break_speed_mps } else { gun.tactics.closing_far_mps };
        self.goal = add(p.position, scale(away, 1000.0));
        let v_des = add(target_v, scale(away, speed as f32));
        let dv = sub(v_des, p.velocity);
        let face = if f64::from(length(dv)) > 1.0 { normalized(dv) } else { p.forward };
        cmd.rot = brain_maths::face(&p.basis, face, ship.capability.rate_max, brain_maths::K_FACE);
        seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
        false
    }

    fn enter(&mut self, leg: u8) {
        if self.leg != leg {
            self.leg = leg;
            self.leg_s = 0.0;
        }
    }

    // Across the line of sight, away from the side the nearest working beam sits on (out of its arc the soonest); a seeded
    // side when it has none.
    fn enter_break(&mut self, tick: &Tick, spec: &CapitalSpec, t: usize, aim_point: Vector3) {
        let rows = tick.rows;
        let p = &tick.p;
        let los = normalized(sub(aim_point, p.position));
        let (centre, basis) = (rows.positions[t], rows.bases[t]);
        let beam = spec
            .mounts
            .iter()
            .filter(|m| m.works && m.kind == MOUNT_BEAM)
            .map(|m| add(centre, xform(&basis, m.at)))
            .min_by(|a, b| dist_sq(*a, p.position).total_cmp(&dist_sq(*b, p.position)));
        let side = match beam {
            Some(at) => sub(p.position, at),
            None => {
                let up = if dot(los, Vector3::new(0.0, 1.0, 0.0)).abs() < 0.95 {
                    Vector3::new(0.0, 1.0, 0.0)
                } else {
                    Vector3::new(1.0, 0.0, 0.0)
                };
                let s = if self.rng.randf() < 0.5 { 1.0 } else { -1.0 };
                scale(cross(los, up), s)
            }
        };
        let across = sub(side, scale(los, dot(side, los)));
        self.break_dir = if length(across) > 1e-3 { normalized(across) } else { normalized(cross(los, Vector3::new(0.0, 1.0, 0.0))) };
        self.enter(LEG_BREAK);
    }

    // The way in least covered by the capital's arcs, a little for the way round from `bearing` (the fighter's own bearing
    // from the capital, its frame), and a seeded share per run; then the point to run at on that side.
    fn plan(&mut self, spec: &CapitalSpec, bearing: Vector3) {
        self.plan_s = 0.0;
        let total: f64 = spec.mounts.iter().map(coverage_weight).sum::<f64>().max(1.0);
        let mut best: Option<(f64, usize)> = None;
        for (k, d) in DIRECTIONS.iter().enumerate() {
            let covered: f64 = spec
                .mounts
                .iter()
                .filter(|m| dot(*d, m.axis) >= m.cos_half)
                .map(coverage_weight)
                .sum();
            let way = 0.5 * (1.0 - f64::from(dot(*d, bearing)));
            let cost = covered + total * (TRAVEL_COST * way + JITTER * f64::from(self.rng.randf()));
            if best.is_none_or(|(c, _)| cost < c) {
                best = Some((cost, k));
            }
        }
        self.dir_local = DIRECTIONS[best.map_or(0, |(_, k)| k)];
        self.aim_local = aim_on(spec, self.dir_local);
    }

    pub fn leg_name(&self) -> &'static str {
        LEG_NAMES[usize::from(self.leg).min(LEG_NAMES.len() - 1)]
    }
}

/// The point a run in along `dir` (the capital's frame) aims at: a working mount whose arc covers the way in, the strongest
/// nearest the way; else an interceptor on that side; else an engine; else a bay; else none (the nearest skin).
pub fn aim_on(spec: &CapitalSpec, dir: Vector3) -> Option<Vector3> {
    let near_side = |at: Vector3| dot(normalized(at), dir) > 0.0;
    let along = |at: Vector3| -f64::from(dot(at, dir));
    let covering = spec
        .mounts
        .iter()
        .filter(|m| m.works && m.role != ROLE_PD && dot(dir, m.axis) >= m.cos_half && near_side(m.at))
        .min_by(|a, b| (-coverage_weight(a), along(a.at)).partial_cmp(&(-coverage_weight(b), along(b.at))).unwrap_or(std::cmp::Ordering::Equal));
    if let Some(m) = covering {
        return Some(m.at);
    }
    let pd = spec
        .mounts
        .iter()
        .filter(|m| m.works && m.role == ROLE_PD && near_side(m.at))
        .min_by(|a, b| along(a.at).total_cmp(&along(b.at)));
    if let Some(m) = pd {
        return Some(m.at);
    }
    for kind in [POINT_ENGINE, POINT_BAY] {
        let found = spec
            .points
            .iter()
            .filter(|p| p.works && p.kind == kind)
            .min_by(|a, b| along(a.at).total_cmp(&along(b.at)));
        if let Some(p) = found {
            return Some(p.at);
        }
    }
    None
}

impl CapitalRun {
    // Flies toward `goal` (World) as fast as it can still meet it, round any big hull in the way.
    #[allow(clippy::too_many_arguments)]
    fn fly_to(
        &self,
        tick: &Tick,
        ship: &Ship,
        goal: Vector3,
        target_v: Vector3,
        d: f64,
        max_mps: f64,
        cmd: &mut FlightCmd,
        wish: &mut Wish,
    ) {
        let p = &tick.p;
        let speed = (d / ARRIVE_S).clamp(SETUP_MIN_MPS, max_mps.max(SETUP_MIN_MPS));
        let way = if d > 1e-3 { normalized(sub(goal, p.position)) } else { p.forward };
        let v_des = detour(tick, ship, goal, speed).unwrap_or_else(|| add(target_v, scale(way, speed as f32)));
        let dv = sub(v_des, p.velocity);
        let face = if f64::from(length(dv)) > 1.0 { normalized(dv) } else { way };
        cmd.rot = brain_maths::face(&p.basis, face, ship.capability.rate_max, brain_maths::K_FACE);
        seek_velocity(cmd, p, &ship.capability, v_des, false, wish);
    }
}
