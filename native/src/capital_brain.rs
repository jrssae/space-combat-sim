//! The `capital` brain (M10-T16, D12.10, Q16, Q17, Q70): what a capital ship does in a fight, thought at 5 Hz staggered in
//! the AI job one tick behind (on the job's frozen rows), its answers applied at the join against the entry's stamp. The helm
//! it steers (`capital_helm`) runs every tick on the main thread; the brain only moves its heading and velocity.
//!
//! - **States.** Approach a hostile capital until 0.7 x its main weapon's range; Engage: hold that range with the attitude
//!   that brings the most mount dps to bear (`attitude`); Screen: an escort holds 0.8 to 1.2 km off its charge; Withdraw at
//!   hull under 30 %, reactor under 50 % or every main engine lost (GDScript finds the exit: its own point, a friendly point,
//!   a gate; none and it fights on); Hold on orders (the helm is the caller's); Launch (M10-T17): a carrier holds its course
//!   while its hangar launches, and counts the hostiles within reach for it (`launch`).
//! - **Targets** (`targets`): `threat x value / time_to_kill` with the faction's doctrine weights; anti-capital mounts take
//!   it, with a subsystem to aim at when outgunned or when a withdrawing target is to be crippled.
//!
//! Engine-free (the guard in test_sim_core reads this file): plain rows and numbers in, plain numbers out. No randomness:
//! the same frozen rows give the same answers on any thread.
use std::sync::Arc;

use godot::builtin::{Basis, Vector3};

use crate::capital_helm::{Helm, HelmSpec};
use crate::rows::{FLAG_DISABLED, FLAG_HULK, FLAG_SHELTERED, Rows, seen_ix};
use crate::v3::{add, clampf, dist_sq, distance, div_s, length, scale, sub};

mod aim;
pub mod attitude;
mod launch;
mod targets;


/// The brain's states (`STATE_NAMES`). Launch (M10-T17): a carrier whose hangar is launching holds its course.
pub const STATE_IDLE: u8 = 0;
pub const STATE_APPROACH: u8 = 1;
pub const STATE_ENGAGE: u8 = 2;
pub const STATE_SCREEN: u8 = 3;
pub const STATE_WITHDRAW: u8 = 4;
pub const STATE_HOLD: u8 = 5;
pub const STATE_LAUNCH: u8 = 6;
pub const STATE_NAMES: [&str; 7] = ["idle", "approach", "engage", "screen", "withdraw", "hold", "launch"];

/// Who steers: the brain, or the caller's orders (`set_course`, the console, a mission).
pub const MODE_AUTO: u8 = 0;
pub const MODE_HELD: u8 = 1;

/// A mount's shape (`BrainMount.kind`) and role (`role`, as the gun rows number them: af, dual, ac, pd). The turret and fixed
/// shapes are GDScript's numbering (`CapitalBrainSpec`); the brain weighs them by their cones alone.
#[allow(dead_code)]
pub const MOUNT_TURRET: u8 = 0;
#[allow(dead_code)]
pub const MOUNT_FIXED: u8 = 1;
pub const MOUNT_LAUNCHER: u8 = 2;
pub const MOUNT_BEAM: u8 = 3;
#[allow(dead_code)] // GDScript's number for an interceptor; the brain reads its role
pub const MOUNT_PD: u8 = 4;
pub const ROLE_AF: u8 = 0;
pub const ROLE_DUAL: u8 = 1;
pub const ROLE_AC: u8 = 2;
pub const ROLE_PD: u8 = 3;

/// A part's kind (`BrainPoint.kind`): an engine's nozzle, a bay's mouth, the vital sections (reactor, bridge, magazine) and
/// every other section of the hull.
pub const POINT_ENGINE: u8 = 0;
pub const POINT_BAY: u8 = 1;
pub const POINT_REACTOR: u8 = 2;
pub const POINT_BRIDGE: u8 = 3;
pub const POINT_MAGAZINE: u8 = 4;
pub const POINT_SECTION: u8 = 5;

/// What the withdraw's exit search found (`Status.exit`): not asked yet, an exit to fly to, or none (it fights on).
pub const EXIT_UNKNOWN: u8 = 0;
pub const EXIT_FOUND: u8 = 1;
pub const EXIT_NONE: u8 = 2;

/// An answer's events for GDScript (`Answer.events`): its order changed, it wants an exit to withdraw through.
pub const EVENT_ORDER: u8 = 1;
pub const EVENT_WITHDRAW: u8 = 2;
/// A carrier's count of hostiles within its launch reach changed (M10-T17).
pub const EVENT_THREAT: u8 = 4;

// `BodyKind.CAPITAL`.
const KIND_CAPITAL: u8 = 1;
// A row with a surface of its own is a big hull (`ROLE_SURFACE`, the station's frame and drum, every capital).
const ROLE_SURFACE: u8 = 2;

/// A weapon mount as the brain weighs it, in its hull's frame (rotating pieces at rest): where it sits, the axis its cone
/// is round and that cone's half angle's cosine, its nominal dps and reach, its shape and role, and whether it works.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BrainMount {
    pub at: Vector3,
    pub axis: Vector3,
    pub cos_half: f32,
    pub dps: f64,
    pub range_m: f64,
    pub kind: u8,
    pub role: u8,
    pub works: bool,
}

impl BrainMount {
    /// Whether it counts against a capital: anything but an interceptor, and only while it works.
    pub fn fights(&self) -> bool {
        self.works && self.role != ROLE_PD && self.dps > 0.0
    }
}

/// A part the brain or an attacker aims at, in its hull's frame: its place, kind, whether it still stands, and the half
/// extents of the box it fills (a section's box; a nozzle's or mouth's size).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct BrainPoint {
    pub at: Vector3,
    pub kind: u8,
    pub works: bool,
    pub half: Vector3,
}

/// The faction's doctrine (`capitals.json`, `capital_brain.doctrine`): how much threat and value weigh in a target's score,
/// and whether it cripples a withdrawing target's engines (the Centauri, the Drazi).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Doctrine {
    pub threat_w: f64,
    pub value_w: f64,
    pub cripple: bool,
}

impl Default for Doctrine {
    fn default() -> Self {
        Doctrine {
            threat_w: 1.0,
            value_w: 1.0,
            cripple: false,
        }
    }
}

/// The numbers every capital brain shares (`capitals.json`, `capital_brain`).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Tuning {
    /// Thinks a second (5): each capital on its own beat.
    pub think_hz: f64,
    /// Engage holds this share of the main weapon's range (0.7).
    pub engage_share: f64,
    /// How fast it closes or opens, m/s, and over how long it meets a range error, s.
    pub approach_mps: f64,
    pub arrive_s: f64,
    /// How far it looks for targets, m.
    pub sensor_m: f64,
    /// An escort's band off its charge, m (0.8 to 1.2 km).
    pub screen_min_m: f64,
    pub screen_max_m: f64,
    /// Withdraw below these hull and reactor shares.
    pub withdraw_hull: f64,
    pub withdraw_reactor: f64,
    /// Outgunned when the target's dps is over this times its own: its heavy weapons go for the mounts bearing on it.
    pub outgunned_ratio: f64,
    /// A held target's score is worth this much more, so a near tie does not swap targets.
    pub keep_bonus: f64,
    /// A new attitude must bring this much more dps to bear than the held one.
    pub attitude_margin: f64,
    /// A carrier counts the hostiles within this for its hangar, m (15 km, M10-T17).
    pub launch_m: f64,
    /// The fighters' attack runs on a capital (`RunTuning`).
    pub runs: RunTuning,
}

/// The fighters' attack runs on a capital (`capitals.json`, `capital_brain.fighter_runs`): they fire from `fire_from_m` down
/// to `fire_to_m` off the point they aim at, open to `open_m` off the hull, re-plan the way in every `replan_s` and regroup
/// `regroup_m` off it once their squadron aborts.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RunTuning {
    pub fire_from_m: f64,
    pub fire_to_m: f64,
    pub open_m: f64,
    pub replan_s: f64,
    pub regroup_m: f64,
}

impl Default for RunTuning {
    fn default() -> Self {
        RunTuning {
            fire_from_m: 1500.0,
            fire_to_m: 400.0,
            open_m: 3000.0,
            replan_s: 2.0,
            regroup_m: 5000.0,
        }
    }
}

impl Default for Tuning {
    fn default() -> Self {
        Tuning {
            think_hz: 5.0,
            engage_share: 0.7,
            approach_mps: 40.0,
            arrive_s: 30.0,
            sensor_m: 30000.0,
            screen_min_m: 800.0,
            screen_max_m: 1200.0,
            withdraw_hull: 0.3,
            withdraw_reactor: 0.5,
            outgunned_ratio: 1.5,
            keep_bonus: 1.25,
            attitude_margin: 1.1,
            launch_m: 15000.0,
            runs: RunTuning::default(),
        }
    }
}

/// A capital as its brain knows it, set once when it joins (its mounts' and points' `works` change per event).
#[derive(Clone, Debug, Default)]
pub struct CapitalSpec {
    pub body: i64,
    pub helm: HelmSpec,
    pub hull_max: f64,
    /// Its class's worth as a target (a cruiser 1, a dreadnought 4).
    pub value: f64,
    pub doctrine: Doctrine,
    /// It has bays: it counts threats for its hangar and holds its course while launching (M10-T17).
    pub carrier: bool,
    pub mounts: Vec<BrainMount>,
    pub points: Vec<BrainPoint>,
}

impl CapitalSpec {
    /// Its live anti-capital dps (every working mount but the interceptors).
    pub fn dps(&self) -> f64 {
        self.mounts.iter().filter(|m| m.fights()).map(|m| m.dps).sum()
    }

    /// The reach of its main weapon: the range whose guns and beams give the most dps (anti-fighter guns and guided rounds
    /// left out: a missile's reach is no range to hold); 3 km without.
    pub fn main_range_m(&self) -> f64 {
        let main = |m: &&BrainMount| m.fights() && m.role != ROLE_AF && m.kind != MOUNT_LAUNCHER;
        let mut best = (0.0, 3000.0);
        for m in self.mounts.iter().filter(main) {
            let total: f64 = self
                .mounts
                .iter()
                .filter(main)
                .filter(|o| o.range_m == m.range_m)
                .map(|o| o.dps)
                .sum();
            if total > best.0 || (total == best.0 && m.range_m > best.1) {
                best = (total, m.range_m);
            }
        }
        best.1
    }
}

/// What changes per event: the reactor's share, the engines left, who steers, the charge it escorts (0 none) and the
/// withdraw's exit (`EXIT_*`, its place in universe coordinates).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Status {
    pub reactor: f64,
    pub engines_live: u32,
    pub engines_total: u32,
    pub mode: u8,
    pub charge: i64,
    pub exit: u8,
    pub exit_at: [f64; 3],
    /// Its hangar is launching (M10-T17): it holds its course.
    pub launching: bool,
}

impl Default for Status {
    fn default() -> Self {
        Status {
            reactor: 1.0,
            engines_live: 0,
            engines_total: 0,
            mode: MODE_AUTO,
            charge: 0,
            exit: EXIT_UNKNOWN,
            exit_at: [0.0; 3],
            launching: false,
        }
    }
}

/// What the brain keeps between thinks.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Memory {
    pub state: u8,
    /// The body it fights (0 none) and the point its heavy weapons aim at there (none: the centre).
    pub target: i64,
    pub aim: Option<Vector3>,
    /// The attitude it holds toward its target: an index of `DIRECTIONS` in its own frame.
    pub attitude: u8,
    /// Its mounts' bearings, one bit per direction (`attitude::bearings`), worked out at its first think with a surface.
    pub bearings: Vec<u32>,
    /// It asked for a withdraw's exit already.
    pub withdraw_asked: bool,
    pub thinks: i64,
    /// The age of its last think, so a second job in the same tick (a single think) does not think it again.
    pub thought_at: i64,
    /// The course it held before its fight (heading, velocity against the World's rest), taken up again once it has no target.
    pub cruise: Option<(Vector3, Vector3)>,
    /// A carrier's hostile fighters and warships within its launch reach at its last think (M10-T17).
    pub threat_fighters: u32,
    pub threat_warships: u32,
}

/// The helm's course a think gives: the bow's heading, the velocity held (World frame) and the way the top should face (zero:
/// the roll left alone).
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Course {
    pub heading: Vector3,
    pub velocity: Vector3,
    pub up: Vector3,
}

impl Course {
    fn bow(heading: Vector3, velocity: Vector3) -> Course {
        Course {
            heading,
            velocity,
            up: Vector3::ZERO,
        }
    }
}

/// One capital in the job: its stamp, spec, status, memory and the place in the stagger.
#[derive(Clone, Debug, Default)]
pub struct Entry {
    pub stamp: u32,
    pub ordinal: i64,
    /// Ticks its helm has flown since it joined: the beat its thinks keep (the same in every run, whatever the core's clock).
    pub age: i64,
    pub spec: Arc<CapitalSpec>,
    pub status: Status,
    pub memory: Memory,
    /// Its helm as the launch found it (the main thread steps it every tick).
    pub helm: Helm,
}

/// A think's answer: what the join writes back to the entry whose stamp it still is.
#[derive(Clone, Debug, PartialEq)]
pub struct Answer {
    pub body: i64,
    pub stamp: u32,
    pub memory: Memory,
    /// The helm's course; none on orders (`MODE_HELD`) or with nothing to steer.
    pub helm: Option<Course>,
    pub order: i64,
    pub order_aim: Option<Vector3>,
    pub events: u8,
}

/// The brains' part of a job (M10-T16): every capital as the launch found it, the relations by the core's faction indices
/// (1 hostile, 2 friendly, 0 neutral; `stride` square), the World's rest velocity the job's rows had taken off, and the
/// answers.
#[derive(Clone, Debug, Default)]
pub struct CapitalJob {
    pub entries: Vec<Entry>,
    pub relations: Vec<u8>,
    pub stride: usize,
    pub tuning: Tuning,
    pub rest: Vector3,
    pub answers: Vec<Answer>,
    /// The raiders' faction index, which never attacks a warship (D12.10); none while the core has not seen them.
    pub raiders_ix: Option<u32>,
    /// How long the job's capital thinks took, ns (a readout the shell writes; the kernel never reads a clock).
    pub think_ns: u64,
}

impl CapitalJob {
    pub fn clear(&mut self) {
        self.entries.clear();
        self.answers.clear();
    }

    /// The entry of body `body`, by a search of the few capitals.
    pub fn entry_of(&self, body: i64) -> Option<&Entry> {
        self.entries.iter().find(|e| e.spec.body == body)
    }

    // Whether an observer of faction `own` sees row `j` as hostile.
    fn hostile(&self, rows: &Rows, own: u32, j: usize) -> bool {
        let seen = seen_ix(rows.flags[j], rows.faction_ix[j], own);
        let (o, s) = (own as usize, seen as usize);
        o < self.stride && s < self.stride && self.relations[o * self.stride + s] == 1
    }
}

/// Whether row `j` is a big hull worth a capital's heavy weapons: a capital, or a station's own hull (not a rotor, which is
/// named by its hull).
pub fn is_warship_row(rows: &Rows, j: usize) -> bool {
    if rows.is_civilian(j) {
        return false;
    }
    if rows.kinds.get(j).copied() == Some(KIND_CAPITAL) {
        return true;
    }
    rows.role(j) == ROLE_SURFACE && rows.surface(j).is_some_and(|s| s.named_by == 0)
}

/// Thinks every capital whose beat this tick is, in entry order, and leaves the answers in `job.answers`. `row_of` is the
/// row a kernel may read for a body (-1 none); `origin` the World's place in universe coordinates.
pub fn think_all<F: Fn(i64) -> i64>(job: &mut CapitalJob, rows: &Rows, row_of: F, origin: [f64; 3]) {
    job.answers.clear();
    let period = (60.0 / job.tuning.think_hz.max(0.1)).round().max(1.0) as i64;
    for k in 0..job.entries.len() {
        let e = &job.entries[k];
        if (e.age + e.ordinal).rem_euclid(period) != 0 || (e.memory.thinks > 0 && e.memory.thought_at == e.age) {
            continue;
        }
        let Ok(r) = usize::try_from(row_of(e.spec.body)) else {
            continue; // out of the rows (parked, pooled, a tier row): it keeps its last answer
        };
        if r >= rows.positions.len() {
            continue;
        }
        let answer = think_one(job, k, rows, &row_of, r, origin, period as f64 / 60.0);
        job.answers.push(answer);
    }
}

// One capital's think: the state, the target and the helm's course.
fn think_one<F: Fn(i64) -> i64>(
    job: &CapitalJob,
    k: usize,
    rows: &Rows,
    row_of: &F,
    r: usize,
    origin: [f64; 3],
    _dt: f64,
) -> Answer {
    let e = &job.entries[k];
    let spec = &e.spec;
    let t = &job.tuning;
    let mut memory = e.memory.clone();
    memory.thinks += 1;
    memory.thought_at = e.age;
    let mut answer = Answer {
        body: spec.body,
        stamp: e.stamp,
        memory: Memory::default(),
        helm: None,
        order: 0,
        order_aim: None,
        events: 0,
    };
    // A hulk thinks nothing and gives no orders: its weapons are dead and its helm is gone (D12.7).
    if rows.flags[r] & (FLAG_DISABLED | FLAG_HULK) != 0 || rows.hull_fraction[r] == 0.0 {
        memory.state = STATE_IDLE;
        memory.target = 0;
        memory.aim = None;
        memory.threat_fighters = 0;
        memory.threat_warships = 0;
        answer.events = order_events(&e.memory, &memory) | threat_events(&e.memory, &memory);
        answer.memory = memory;
        return answer;
    }
    if memory.bearings.is_empty() && let Some(surface) = rows.surface(r) {
        memory.bearings = attitude::bearings(spec, Some(surface));
    }
    let own_ix = rows.faction_ix[r];
    (memory.threat_fighters, memory.threat_warships) = launch::threats(job, spec, rows, row_of, r, own_ix);
    let pick = targets::choose(job, spec, &memory, rows, row_of, r, own_ix);
    memory.target = pick.map_or(0, |p| p.body);
    memory.aim = pick.and_then(|p| p.aim);
    let position = rows.positions[r];
    let basis = rows.bases[r];
    let own_v = add(rows.velocities[r], job.rest);
    // The state: orders first, then a withdraw, an escort's screen, a fight, else it holds its course.
    let wants_out = withdraw_due(&e.status, rows.hull_fraction[r], t);
    let can_leave = e.status.exit != EXIT_NONE;
    memory.state = if e.status.mode == MODE_HELD {
        STATE_HOLD
    } else if wants_out && can_leave {
        STATE_WITHDRAW
    } else if e.status.charge != 0 && usize::try_from(row_of(e.status.charge)).is_ok_and(|c| c < rows.positions.len()) {
        STATE_SCREEN
    } else if let Some(p) = pick {
        let hold = t.engage_share * spec.main_range_m();
        let near = if e.memory.state == STATE_ENGAGE { 1.3 } else { 1.15 };
        if p.range_m > hold * near {
            STATE_APPROACH
        } else {
            STATE_ENGAGE
        }
    } else {
        STATE_IDLE
    };
    // A carrier launching holds its course (not while it withdraws, screens or holds on orders).
    if spec.carrier && e.status.launching && matches!(memory.state, STATE_IDLE | STATE_APPROACH | STATE_ENGAGE) {
        memory.state = STATE_LAUNCH;
    }
    if memory.state == STATE_WITHDRAW && !memory.withdraw_asked {
        memory.withdraw_asked = true;
        answer.events |= EVENT_WITHDRAW;
    }
    let target_row = pick.map(|p| p.row);
    let attitude = target_row.map(|j| {
        attitude::choose(spec, &memory, &basis, sub(rows.positions[j], position), memory.attitude, t)
    });
    if let Some((index, _, _)) = attitude {
        memory.attitude = index;
    }
    // Into a fight it remembers its course, and out of it takes it up again.
    let fighting = !matches!(memory.state, STATE_IDLE | STATE_HOLD);
    if fighting && memory.cruise.is_none() {
        memory.cruise = Some((e.helm.heading, sub(e.helm.velocity, job.rest)));
    }
    // The helm's course in the World frame (the rows' velocities are against the World's rest).
    answer.helm = match memory.state {
        STATE_HOLD => None,
        STATE_LAUNCH => Some(Course::bow(attitude::nose(&basis), own_v)),
        STATE_WITHDRAW if e.status.exit == EXIT_FOUND => {
            let goal = Vector3::new(
                (e.status.exit_at[0] - origin[0]) as f32,
                (e.status.exit_at[1] - origin[1]) as f32,
                (e.status.exit_at[2] - origin[2]) as f32,
            );
            let way = sub(goal, position);
            let d = f64::from(length(way));
            let dir = if d > 1.0 { div_s(way, d as f32) } else { attitude::nose(&basis) };
            let speed = clampf(d / t.arrive_s, 0.0, t.approach_mps);
            Some(Course::bow(dir, add(job.rest, scale(dir, speed as f32))))
        }
        STATE_WITHDRAW => Some(Course::bow(attitude::nose(&basis), own_v)), // its exit is being found: it holds its course
        STATE_SCREEN => Some(screen_course(job, e, rows, row_of, r, target_row, &basis, t)),
        STATE_APPROACH | STATE_ENGAGE => {
            let j = target_row.unwrap_or(r);
            let way = sub(rows.positions[j], position);
            let d = f64::from(length(way)).max(1e-3);
            let dir = div_s(way, d as f32);
            let hold = t.engage_share * spec.main_range_m();
            let closing = if memory.state == STATE_APPROACH {
                t.approach_mps
            } else {
                clampf((d - hold) / t.arrive_s, -t.approach_mps, t.approach_mps)
            };
            let velocity = add(add(rows.velocities[j], job.rest), scale(dir, closing as f32));
            match (memory.state, attitude) {
                (STATE_ENGAGE, Some((_, heading, up))) => Some(Course { heading, velocity, up }),
                _ => Some(Course::bow(dir, velocity)),
            }
        }
        // Idle: back on the course it had before the fight, else the helm keeps what it had.
        _ => memory.cruise.take().map(|(heading, v)| Course::bow(heading, add(job.rest, v))),
    };
    // Its heavy weapons take the target (none: they pick their own, fighters included, Q77).
    answer.order = memory.target;
    answer.order_aim = memory.aim;
    answer.events |= order_events(&e.memory, &memory);
    answer.events |= threat_events(&e.memory, &memory);
    answer.memory = memory;
    answer
}

// Whether a carrier's threat count changed between two thinks' memories.
fn threat_events(before: &Memory, after: &Memory) -> u8 {
    if before.threat_fighters != after.threat_fighters || before.threat_warships != after.threat_warships {
        EVENT_THREAT
    } else {
        0
    }
}

// Whether the order changed between two thinks' memories.
fn order_events(before: &Memory, after: &Memory) -> u8 {
    if before.target != after.target || before.aim != after.aim {
        EVENT_ORDER
    } else {
        0
    }
}

/// Whether a capital should withdraw (D12.10): hull under its share, reactor under its share, or every main engine lost.
pub fn withdraw_due(status: &Status, hull: f64, t: &Tuning) -> bool {
    (hull >= 0.0 && hull < t.withdraw_hull)
        || status.reactor < t.withdraw_reactor
        || (status.engines_total > 0 && status.engines_live == 0)
}

// An escort's course: within the band off its charge, on the side of the threat (else ahead of it), matching its motion;
// the bow brought to bear on a target in reach, else along the charge's.
#[allow(clippy::too_many_arguments)]
fn screen_course<F: Fn(i64) -> i64>(
    job: &CapitalJob,
    e: &Entry,
    rows: &Rows,
    row_of: &F,
    r: usize,
    target_row: Option<usize>,
    basis: &Basis,
    t: &Tuning,
) -> Course {
    let c = row_of(e.status.charge) as usize;
    let charge_at = rows.positions[c];
    let side = match target_row {
        Some(j) => attitude::unit_or(sub(rows.positions[j], charge_at), attitude::nose(&rows.bases[c])),
        None => attitude::nose(&rows.bases[c]),
    };
    let reach = 0.5 * (t.screen_min_m + t.screen_max_m) + rows.radii[c] + rows.radii[r];
    let post = add(charge_at, scale(side, reach as f32));
    let way = sub(post, rows.positions[r]);
    let d = f64::from(length(way));
    let off = distance(rows.positions[r], charge_at) as f64 - rows.radii[c] - rows.radii[r];
    let inside_band = off >= t.screen_min_m && off <= t.screen_max_m && d < 0.5 * (t.screen_max_m - t.screen_min_m) + 200.0;
    let closing = if inside_band { 0.0 } else { clampf(d / t.arrive_s, 0.0, t.approach_mps) };
    let dir = attitude::unit_or(way, attitude::nose(basis));
    let velocity = add(add(rows.velocities[c], job.rest), scale(dir, closing as f32));
    match target_row {
        Some(j) => {
            let memory = &e.memory;
            let (_, heading, up) = attitude::choose(&e.spec, memory, basis, sub(rows.positions[j], rows.positions[r]), memory.attitude, t);
            Course { heading, velocity, up }
        }
        None => Course::bow(attitude::nose(&rows.bases[c]), velocity),
    }
}

// Rows a capital ignores entirely: static rows, mines, sheltered ships, the dead.
fn ignored(rows: &Rows, j: usize) -> bool {
    rows.is_static[j] || rows.flags[j] & FLAG_SHELTERED != 0 || rows.hull_fraction[j] == 0.0
}

// How far apart two rows are, squared, in 32 bits as the rows hold them.
fn range_sq(rows: &Rows, a: usize, b: usize) -> f32 {
    dist_sq(rows.positions[a], rows.positions[b])
}

#[cfg(test)]
mod tests;
