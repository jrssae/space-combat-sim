// The core's shell around the capital ships' helms and brains (M10-T16, Q70): the table GDScript fills per ship and per
// event, the helm stepped every tick on the main thread (`capital_helm_commands`), the launch's copy for the AI job and the
// join's answers, applied to the entries whose stamp they were thought for. Every engine type stays here; the maths is
// `capital_helm` and `capital_brain`, engine-free.
use std::sync::Arc;

use godot::prelude::*;

use crate::brain_maths::Capability;
use crate::capital_brain::{
    Answer, BrainMount, BrainPoint, CapitalJob, CapitalSpec, Doctrine, EVENT_ORDER, EVENT_THREAT, EVENT_WITHDRAW, EXIT_FOUND, EXIT_NONE,
    EXIT_UNKNOWN, Entry, MODE_AUTO, MODE_HELD, Memory, RunTuning, STATE_NAMES, Status, Tuning,
};
use crate::capital_helm::{self as ch, Helm, HelmSpec};
use crate::sim_core::ScsSimCore;

/// Numbers per mount in `capital_add`'s `mounts`: place (3), axis (3), cone half angle (deg), dps, range (m), shape, role,
/// works; per part in `points`: place (3), kind, works, half extents (3).
pub const MOUNT_LEN: usize = 12;
pub const POINT_LEN: usize = 8;
/// `capital_add`'s `helm`: gravitic, retros, a_main, a_retro, a_rcs x and y, rate max (3), alpha max (3); `brain`: hull
/// points, class value, threat and value weights, cripple, carrier.
pub const HELM_LEN: usize = 12;
pub const BRAIN_LEN: usize = 6;
/// `capital_set_tuning`'s numbers, in `Tuning`'s field order, the fighters' runs (`RunTuning`) last.
pub const TUNING_LEN: usize = 18;
/// `FlightBatch`'s command layout per ship.
const CMD_SCALARS: usize = 4;
const CMD_VECTORS: usize = 6;
const CMD_FLAGS: usize = 4;

// One capital in the table: the brain's entry, its helm, the order its weapons hold and what GDScript is yet to hear.
struct Row {
    entry: Entry,
    order: i64,
    order_aim: Option<Vector3>,
    changes: u8,
}

/// The capitals' helms and brains in the core.
#[derive(Default)]
pub struct CapitalTable {
    rows: Vec<Row>,
    tuning: Tuning,
    relations: Vec<u8>,
    stride: usize,
    next_stamp: u32,
    answers_applied: i64,
    answers_stale: i64,
    // The capital thinks' cost so far: jobs that thought, thinks, and their time, ns (readouts).
    think_jobs: i64,
    thinks: i64,
    think_ns: u64,
    // The helm's cost so far: calls, ships stepped, and their time, ns (readouts).
    helm_calls: i64,
    helm_ships: i64,
    helm_ns: u64,
}

impl CapitalTable {
    fn index_of(&self, body: i64) -> Option<usize> {
        self.rows.iter().position(|r| r.entry.spec.body == body)
    }

    fn new_stamp(&mut self) -> u32 {
        self.next_stamp = self.next_stamp.wrapping_add(1).max(1);
        self.next_stamp
    }

    /// Every velocity the core holds loses `dv` (a velocity rebase, M6-T05): the helms' too.
    pub fn boost(&mut self, dv: Vector3) {
        for r in &mut self.rows {
            r.entry.helm.velocity = crate::v3::sub(r.entry.helm.velocity, dv);
        }
    }
}

impl ScsSimCore {
    /// The launch's copy for the AI job: every capital as it stands, the relations, the tuning, the rest and the tick.
    pub(crate) fn capital_snapshot_into(&mut self, job: &mut CapitalJob) {
        let t = &self.capitals;
        job.entries.clear();
        job.entries.extend(t.rows.iter().map(|r| r.entry.clone()));
        job.relations.clone_from(&t.relations);
        job.stride = t.stride;
        job.tuning = t.tuning;
        job.rest = self.frame_rest().velocity;
        job.answers.clear();
        job.raiders_ix = self.factions.iter().position(|f| *f == "raiders").map(|i| i as u32);
    }

    /// The far capitals' helms (M10-T16): each low-attention tier row a capital's helm steers takes this tick's command from
    /// its helm, flown by the tier like a fighter's, and its brain keeps its beat. Called before the tier's step.
    pub(crate) fn capital_tier_helms(&mut self) {
        let ScsSimCore { tier, capitals, .. } = self;
        for i in 0..tier.len() {
            if !tier.helmed[i] || tier.hulk[i] {
                continue;
            }
            let Some(k) = capitals.index_of(tier.body_ids[i]) else {
                continue;
            };
            let row = &mut capitals.rows[k];
            row.entry.age += 1;
            let c = ch::command(&row.entry.spec.helm, &mut row.entry.helm, &tier.bases[i], tier.velocities[i]);
            tier.commands[i].cmd = [
                c.main_left,
                c.main_right,
                c.retro_left,
                c.retro_right,
                f64::from(c.strafe_x),
                f64::from(c.strafe_y),
                f64::from(c.rot.x),
                f64::from(c.rot.y),
                f64::from(c.rot.z),
                f64::from(u8::from(c.brake)),
            ];
        }
    }

    /// A joined job's answers: each lands on its capital when the entry is still the one it was thought for.
    pub(crate) fn take_capital_answers(&mut self, job: &CapitalJob) {
        let t = &mut self.capitals;
        if !job.answers.is_empty() {
            t.think_jobs += 1;
            t.thinks += job.answers.len() as i64;
            t.think_ns += job.think_ns;
        }
        for a in &job.answers {
            let Some(i) = t.index_of(a.body).filter(|&i| t.rows[i].entry.stamp == a.stamp) else {
                t.answers_stale += 1;
                continue;
            };
            t.answers_applied += 1;
            apply(&mut t.rows[i], a);
        }
    }
}

// One answer onto its row: the memory, the helm (only when the brain steers), the order and the events for GDScript.
fn apply(row: &mut Row, a: &Answer) {
    let bearings = std::mem::take(&mut row.entry.memory.bearings);
    row.entry.memory = a.memory.clone();
    if row.entry.memory.bearings.is_empty() {
        row.entry.memory.bearings = bearings;
    }
    if row.entry.status.mode == MODE_AUTO
        && let Some(course) = a.helm
    {
        row.entry.helm.heading = course.heading;
        row.entry.helm.velocity = course.velocity;
        row.entry.helm.up = course.up;
    }
    if row.order != a.order || row.order_aim != a.order_aim {
        row.order = a.order;
        row.order_aim = a.order_aim;
        row.changes |= EVENT_ORDER;
    }
    row.changes |= a.events & (EVENT_WITHDRAW | EVENT_THREAT);
}

fn v3(p: &[f64], k: usize) -> Vector3 {
    Vector3::new(p[k] as f32, p[k + 1] as f32, p[k + 2] as f32)
}

#[godot_api(secondary)]
impl ScsSimCore {
    /// The numbers every capital brain shares (`TUNING_LEN`, `capitals.json`'s `capital_brain`).
    #[func]
    fn capital_set_tuning(&mut self, n: PackedFloat64Array) -> bool {
        let n = n.as_slice();
        if n.len() != TUNING_LEN {
            godot_error!("ScsSimCore.capital_set_tuning: {} numbers, {TUNING_LEN} wanted", n.len());
            return false;
        }
        self.capitals.tuning = Tuning {
            think_hz: n[0],
            engage_share: n[1],
            approach_mps: n[2],
            arrive_s: n[3],
            sensor_m: n[4],
            screen_min_m: n[5],
            screen_max_m: n[6],
            withdraw_hull: n[7],
            withdraw_reactor: n[8],
            outgunned_ratio: n[9],
            keep_bonus: n[10],
            attitude_margin: n[11],
            launch_m: n[12],
            runs: RunTuning {
                fire_from_m: n[13],
                fire_to_m: n[14],
                open_m: n[15],
                replan_s: n[16],
                regroup_m: n[17],
            },
        };
        true
    }

    /// The brains' relations, row-major by the core's faction indices (1 hostile, 2 friendly, 0 neutral), `count` square.
    #[func]
    fn capital_set_hostility(&mut self, count: i64, matrix: PackedByteArray) -> bool {
        let n = usize::try_from(count).unwrap_or(0);
        if matrix.len() != n * n {
            godot_error!("ScsSimCore.capital_set_hostility: {} entries for {n} factions", matrix.len());
            return false;
        }
        self.capitals.stride = n;
        self.capitals.relations = matrix.as_slice().to_vec();
        true
    }

    /// Capital `body` joins (again: its spec is replaced, its memory and helm kept): its helm (`HELM_LEN`), its worth and
    /// doctrine (`BRAIN_LEN`), its mounts (`MOUNT_LEN` each) and subsystem points (`POINT_LEN` each). Returns its stamp (0
    /// when the numbers are short).
    #[func]
    fn capital_add(
        &mut self,
        body: i64,
        helm: PackedFloat64Array,
        brain: PackedFloat64Array,
        mounts: PackedFloat64Array,
        points: PackedFloat64Array,
    ) -> i64 {
        let (h, b, m, p) = (helm.as_slice(), brain.as_slice(), mounts.as_slice(), points.as_slice());
        if h.len() != HELM_LEN || b.len() != BRAIN_LEN || m.len() % MOUNT_LEN != 0 || p.len() % POINT_LEN != 0 {
            godot_error!("ScsSimCore.capital_add: the numbers are short for body {body}");
            return 0;
        }
        let spec = CapitalSpec {
            body,
            helm: HelmSpec {
                gravitic: h[0] != 0.0,
                retros: h[1] != 0.0,
                cap: Capability {
                    a_main: h[2],
                    a_retro: h[3],
                    a_rcs_x: h[4],
                    a_rcs_y: h[5],
                    rate_max: v3(h, 6),
                    alpha_max: v3(h, 9),
                },
            },
            hull_max: b[0],
            value: b[1],
            doctrine: Doctrine {
                threat_w: b[2],
                value_w: b[3],
                cripple: b[4] != 0.0,
            },
            carrier: b[5] != 0.0,
            mounts: m
                .as_chunks::<MOUNT_LEN>()
                .0
                .iter()
                .map(|c| BrainMount {
                    at: v3(c, 0),
                    axis: crate::v3::normalized(v3(c, 3)),
                    cos_half: c[6].to_radians().cos() as f32,
                    dps: c[7],
                    range_m: c[8],
                    kind: c[9] as u8,
                    role: c[10] as u8,
                    works: c[11] != 0.0,
                })
                .collect(),
            points: p
                .as_chunks::<POINT_LEN>()
                .0
                .iter()
                .map(|c| BrainPoint {
                    at: v3(c, 0),
                    kind: c[3] as u8,
                    works: c[4] != 0.0,
                    half: v3(c, 5),
                })
                .collect(),
        };
        let stamp = self.capitals.new_stamp();
        let t = &mut self.capitals;
        match t.index_of(body) {
            Some(i) => {
                let row = &mut t.rows[i];
                row.entry.stamp = stamp;
                row.entry.spec = Arc::new(spec);
                row.entry.memory.bearings.clear();
            }
            None => {
                // Its place in the stagger: how many capitals were there before it (the same in every run).
                let ordinal = t.rows.len() as i64;
                t.rows.push(Row {
                    entry: Entry {
                        stamp,
                        ordinal,
                        age: 0,
                        spec: Arc::new(spec),
                        status: Status::default(),
                        memory: Memory::default(),
                        helm: Helm {
                            level: true,
                            ..Default::default()
                        },
                    },
                    order: 0,
                    order_aim: None,
                    changes: 0,
                });
            }
        }
        i64::from(stamp)
    }

    /// Capital `body` leaves; an answer still out for it is dropped at the join.
    #[func]
    fn capital_remove(&mut self, body: i64) {
        if let Some(i) = self.capitals.index_of(body) {
            self.capitals.rows.remove(i);
        }
    }

    #[func]
    fn capital_count(&self) -> i64 {
        self.capitals.rows.len() as i64
    }

    /// Orders for `body`'s helm: its bow toward `heading` (World; zero holds it) and `velocity` held (World frame). From now
    /// its brain no longer steers (Hold) until `capital_release`.
    #[func]
    fn capital_set_course(&mut self, body: i64, heading: Vector3, velocity: Vector3) {
        if let Some(i) = self.capitals.index_of(body) {
            let row = &mut self.capitals.rows[i];
            row.entry.status.mode = MODE_HELD;
            row.entry.helm.up = Vector3::ZERO;
            row.entry.helm.heading = if crate::v3::length_squared(heading) > 1e-12 {
                crate::v3::normalized(heading)
            } else {
                Vector3::ZERO
            };
            row.entry.helm.velocity = velocity;
        }
    }

    /// The helm's velocity alone, its heading and mode kept (a ship back from the tier with its cruise).
    #[func]
    fn capital_set_helm_velocity(&mut self, body: i64, velocity: Vector3) {
        if let Some(i) = self.capitals.index_of(body) {
            self.capitals.rows[i].entry.helm.velocity = velocity;
        }
    }

    /// Capital `body`'s tier row is steered live by its helm from now on (M10-T16), flown with tier type `type_ix` (its
    /// thrusters, `tier_register_type`) and its assist on. False when it has no tier row or the type is unknown.
    #[func]
    fn capital_tier_helm(&mut self, body: i64, type_ix: i64) -> bool {
        let (Some(i), Ok(ty)) = (self.tier.index_of(body), u32::try_from(type_ix)) else {
            return false;
        };
        if ty as usize >= self.tier_types.len() || self.capitals.index_of(body).is_none() {
            return false;
        }
        self.tier.type_ix[i] = ty;
        self.tier.helmed[i] = true;
        self.tier.assist_on[i] = true;
        true
    }

    /// `body`'s brain steers again.
    #[func]
    fn capital_release(&mut self, body: i64) {
        if let Some(i) = self.capitals.index_of(body) {
            self.capitals.rows[i].entry.status.mode = MODE_AUTO;
        }
    }

    /// What changed for `body` (per event): the reactor's share, its live and total main engines, the charge it escorts
    /// (0 none).
    #[func]
    fn capital_set_status(&mut self, body: i64, reactor: f64, engines_live: i64, engines_total: i64, charge: i64) {
        if let Some(i) = self.capitals.index_of(body) {
            let s = &mut self.capitals.rows[i].entry.status;
            s.reactor = reactor;
            s.engines_live = engines_live.max(0) as u32;
            s.engines_total = engines_total.max(0) as u32;
            s.charge = charge;
        }
    }

    /// Whether `body`'s hangar is launching (M10-T17): its brain holds its course meanwhile.
    #[func]
    fn capital_set_launching(&mut self, body: i64, launching: bool) {
        if let Some(i) = self.capitals.index_of(body) {
            self.capitals.rows[i].entry.status.launching = launching;
        }
    }

    /// Which of `body`'s mounts and points still work, one byte each in `capital_add`'s order.
    #[func]
    fn capital_set_works(&mut self, body: i64, mounts: PackedByteArray, points: PackedByteArray) {
        let Some(i) = self.capitals.index_of(body) else {
            return;
        };
        let spec = Arc::make_mut(&mut self.capitals.rows[i].entry.spec);
        for (m, &w) in spec.mounts.iter_mut().zip(mounts.as_slice()) {
            m.works = w != 0;
        }
        for (p, &w) in spec.points.iter_mut().zip(points.as_slice()) {
            p.works = w != 0;
        }
    }

    /// The withdraw's exit for `body`: `kind` 1 found (at universe `x, y, z`), 2 none (it fights on), 0 not asked yet.
    #[func]
    fn capital_set_exit(&mut self, body: i64, kind: i64, x: f64, y: f64, z: f64) {
        if let Some(i) = self.capitals.index_of(body) {
            let row = &mut self.capitals.rows[i];
            row.entry.status.exit = match kind {
                1 => EXIT_FOUND,
                2 => EXIT_NONE,
                _ => EXIT_UNKNOWN,
            };
            row.entry.status.exit_at = [x, y, z];
            if kind == 0 {
                row.entry.memory.withdraw_asked = false;
            }
        }
    }

    /// This tick's helm commands for `bodies`, `states` holding each ship's basis columns and velocity (4 vectors, World):
    /// `[scalars, vectors, flags]` in the flight batch's command layout (the assist and propellant on), and each helm's
    /// velocity (what `cruise_velocity` mirrors). A body with no helm gets an empty command.
    #[func]
    fn capital_helm_commands(&mut self, bodies: PackedInt64Array, states: PackedVector3Array) -> VarArray {
        let started = std::time::Instant::now();
        let (b, s) = (bodies.as_slice(), states.as_slice());
        let n = b.len().min(s.len() / 4);
        let mut scalars = PackedFloat64Array::new();
        let mut vectors = PackedVector3Array::new();
        let mut flags = PackedByteArray::new();
        let mut velocities = PackedVector3Array::new();
        scalars.resize(n * CMD_SCALARS);
        vectors.resize(n * CMD_VECTORS);
        flags.resize(n * CMD_FLAGS);
        velocities.resize(n);
        {
            let (sc, ve, fl, vel) =
                (scalars.as_mut_slice(), vectors.as_mut_slice(), flags.as_mut_slice(), velocities.as_mut_slice());
            for k in 0..n {
                fl[k * CMD_FLAGS + 2] = 1;
                fl[k * CMD_FLAGS + 3] = 1;
                let Some(i) = self.capitals.index_of(b[k]) else {
                    continue;
                };
                let row = &mut self.capitals.rows[i];
                row.entry.age += 1;
                let basis = Basis::from_cols(s[4 * k], s[4 * k + 1], s[4 * k + 2]);
                let cmd = ch::command(&row.entry.spec.helm, &mut row.entry.helm, &basis, s[4 * k + 3]);
                sc[k * CMD_SCALARS] = cmd.main_right;
                sc[k * CMD_SCALARS + 1] = cmd.main_left;
                sc[k * CMD_SCALARS + 2] = cmd.retro_right;
                sc[k * CMD_SCALARS + 3] = cmd.retro_left;
                ve[k * CMD_VECTORS] = Vector3::new(cmd.strafe_x, cmd.strafe_y, 0.0);
                ve[k * CMD_VECTORS + 1] = cmd.rot;
                fl[k * CMD_FLAGS] = u8::from(cmd.brake);
                vel[k] = row.entry.helm.velocity;
            }
        }
        let mut out = VarArray::new();
        out.push(&scalars.to_variant());
        out.push(&vectors.to_variant());
        out.push(&flags.to_variant());
        out.push(&velocities.to_variant());
        let t = &mut self.capitals;
        t.helm_calls += 1;
        t.helm_ships += n as i64;
        t.helm_ns += started.elapsed().as_nanos() as u64;
        out
    }

    /// `body`'s helm: `[heading, velocity, flipping, gravitic]`, empty without one.
    #[func]
    fn capital_helm_state(&self, body: i64) -> VarArray {
        let mut out = VarArray::new();
        if let Some(i) = self.capitals.index_of(body) {
            let row = &self.capitals.rows[i];
            out.push(&row.entry.helm.heading.to_variant());
            out.push(&row.entry.helm.velocity.to_variant());
            out.push(&row.entry.helm.flipping.to_variant());
            out.push(&row.entry.spec.helm.gravitic.to_variant());
        }
        out
    }

    /// A helm command for a hull of `helm` numbers (`HELM_LEN`) told `heading` and `velocity`, mid-flip or not, at `basis`
    /// moving at `current`: main l/r, retro l/r, strafe x/y, rot x/y/z, flipping after (the parity test's probe).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn capital_helm_probe(
        helm: PackedFloat64Array,
        heading: Vector3,
        velocity: Vector3,
        flipping: bool,
        basis: Basis,
        current: Vector3,
    ) -> PackedFloat64Array {
        let h = helm.as_slice();
        if h.len() != HELM_LEN {
            return PackedFloat64Array::new();
        }
        let spec = HelmSpec {
            gravitic: h[0] != 0.0,
            retros: h[1] != 0.0,
            cap: Capability {
                a_main: h[2],
                a_retro: h[3],
                a_rcs_x: h[4],
                a_rcs_y: h[5],
                rate_max: v3(h, 6),
                alpha_max: v3(h, 9),
            },
        };
        let mut state = Helm {
            heading,
            velocity,
            up: Vector3::ZERO,
            level: false,
            flipping,
        };
        let c = ch::command(&spec, &mut state, &basis, current);
        PackedFloat64Array::from(
            [
                c.main_left,
                c.main_right,
                c.retro_left,
                c.retro_right,
                f64::from(c.strafe_x),
                f64::from(c.strafe_y),
                f64::from(c.rot.x),
                f64::from(c.rot.y),
                f64::from(c.rot.z),
                if state.flipping { 1.0 } else { 0.0 },
            ]
            .as_slice(),
        )
    }

    /// `body`'s brain as the console and tests read it: `[state, target body, aim (or null), attitude, thinks, mode, exit,
    /// withdraw asked, order body, hostile fighters and warships within its launch reach, launching]`; empty without one.
    #[func]
    fn capital_brain_state(&self, body: i64) -> VarArray {
        let mut out = VarArray::new();
        if let Some(i) = self.capitals.index_of(body) {
            let row = &self.capitals.rows[i];
            let m = &row.entry.memory;
            out.push(&GString::from(STATE_NAMES[usize::from(m.state).min(STATE_NAMES.len() - 1)]).to_variant());
            out.push(&m.target.to_variant());
            out.push(&m.aim.map_or(Variant::nil(), |a| a.to_variant()));
            out.push(&i64::from(m.attitude).to_variant());
            out.push(&m.thinks.to_variant());
            out.push(&i64::from(row.entry.status.mode == MODE_HELD).to_variant());
            out.push(&i64::from(row.entry.status.exit).to_variant());
            out.push(&m.withdraw_asked.to_variant());
            out.push(&row.order.to_variant());
            out.push(&i64::from(m.threat_fighters).to_variant());
            out.push(&i64::from(m.threat_warships).to_variant());
            out.push(&row.entry.status.launching.to_variant());
        }
        out
    }

    /// What GDScript is yet to hear since the last call: `[bodies, order targets, aims, flags, threat fighters, threat
    /// warships]`, one entry per capital with a change (flags: 1 its order changed, 2 it has an aim point, 4 it wants an exit
    /// to withdraw through, 8 a carrier's count of hostiles within its launch reach changed, M10-T17).
    #[func]
    fn capital_take_changes(&mut self) -> VarArray {
        let mut bodies = PackedInt64Array::new();
        let mut targets = PackedInt64Array::new();
        let mut aims = PackedVector3Array::new();
        let mut flags = PackedByteArray::new();
        let mut fighters = PackedInt32Array::new();
        let mut warships = PackedInt32Array::new();
        for row in &mut self.capitals.rows {
            if row.changes == 0 {
                continue;
            }
            bodies.push(row.entry.spec.body);
            targets.push(row.order);
            aims.push(row.order_aim.unwrap_or(Vector3::ZERO));
            let mut f = 0u8;
            if row.changes & EVENT_ORDER != 0 {
                f |= 1;
            }
            if row.order_aim.is_some() {
                f |= 2;
            }
            if row.changes & EVENT_WITHDRAW != 0 {
                f |= 4;
            }
            if row.changes & EVENT_THREAT != 0 {
                f |= 8;
            }
            flags.push(f);
            fighters.push(row.entry.memory.threat_fighters as i32);
            warships.push(row.entry.memory.threat_warships as i32);
            row.changes = 0;
        }
        let mut out = VarArray::new();
        out.push(&bodies.to_variant());
        out.push(&targets.to_variant());
        out.push(&aims.to_variant());
        out.push(&flags.to_variant());
        out.push(&fighters.to_variant());
        out.push(&warships.to_variant());
        out
    }

    /// Readouts so far: answers applied, answers dropped as stale, jobs that thought, thinks, their time (ns), helm calls,
    /// helms stepped, their time (ns, the packing included).
    #[func]
    fn capital_readouts(&self) -> PackedInt64Array {
        let t = &self.capitals;
        PackedInt64Array::from(
            [
                t.answers_applied,
                t.answers_stale,
                t.think_jobs,
                t.thinks,
                t.think_ns as i64,
                t.helm_calls,
                t.helm_ships,
                t.helm_ns as i64,
            ]
            .as_slice(),
        )
    }

    /// A digest of every capital's brain and helm (state, target's row, aim, attitude, heading, velocity, flip, order's row),
    /// for the threads test.
    #[func]
    fn capital_digest(&self) -> i64 {
        let mut h: u64 = 0xcbf2_9ce4_8422_2325;
        let mut word = |w: u64| {
            for b in w.to_le_bytes() {
                h ^= u64::from(b);
                h = h.wrapping_mul(0x0000_0100_0000_01b3);
            }
        };
        for row in &self.capitals.rows {
            let m = &row.entry.memory;
            word(u64::from(m.state));
            word(self.row_of_id(m.target) as u64);
            word(self.row_of_id(row.order) as u64);
            for v in [m.aim.unwrap_or(Vector3::ZERO), row.entry.helm.heading, row.entry.helm.velocity] {
                for c in [v.x, v.y, v.z] {
                    word(u64::from(c.to_bits()));
                }
            }
            word(u64::from(m.attitude));
            word(u64::from(row.entry.helm.flipping));
            word(m.thinks as u64);
            word(u64::from(m.threat_fighters) | (u64::from(m.threat_warships) << 32));
        }
        h as i64
    }
}
